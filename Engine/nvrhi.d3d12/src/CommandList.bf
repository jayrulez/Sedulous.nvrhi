using Win32.Graphics.Direct3D12;
using System.Collections;
using System;
using nvrhi.d3dcommon;
using nvrhi.rt;
namespace nvrhi.d3d12;

class CommandList : RefCounter<nvrhi.d3d12.ICommandList>
{
	// Internal interface functions

	public this(nvrhi.d3d12.Device device, Context* context, DeviceResources resources, CommandListParameters @params)
	{
		m_Context = context;
		m_Resources = resources;
		m_Device = device;
		m_Queue = device.getQueue(@params.queueType);
		m_UploadManager = new .(context, m_Queue, @params.uploadChunkSize, 0, false);
		m_DxrScratchManager = new .(context, m_Queue, @params.scratchChunkSize, (.)@params.scratchMaxMemory, true);
		m_StateTracker = new .(context.messageCallback);
		m_Desc = @params;
	}

	public ~this(){
	}

	public CommandListInstance executed(Queue pQueue)
	{
		CommandListInstance instance = m_Instance;
		instance.fence = pQueue.fence;
		instance.submittedInstance = pQueue.lastSubmittedInstance;
		m_Instance = null;

		m_ActiveCommandList.lastSubmittedInstance = pQueue.lastSubmittedInstance;
		m_CommandListPool.Add(m_ActiveCommandList);
		m_ActiveCommandList = null;

		for (var it in instance.referencedStagingTextures)
		{
			it.lastUseFence = pQueue.fence;
			it.lastUseFenceValue = instance.submittedInstance;
		}

		for (var it in instance.referencedStagingBuffers)
		{
			it.lastUseFence = pQueue.fence;
			it.lastUseFenceValue = instance.submittedInstance;
		}

		for (var it in instance.referencedTimerQueries)
		{
			it.started = true;
			it.resolved = false;
			it.fence = pQueue.fence;
			it.fenceCounter = instance.submittedInstance;
		}

		m_StateTracker.commandListSubmitted();

		uint64 submittedVersion = MakeVersion(instance.submittedInstance, m_Desc.queueType, true);
		m_UploadManager.submitChunks(m_RecordingVersion, submittedVersion);
		m_DxrScratchManager.submitChunks(m_RecordingVersion, submittedVersion);
		m_RecordingVersion = 0;

		return instance;
	}

	public void requireTextureState(ITexture _texture, TextureSubresourceSet subresources, ResourceStates state)
	{
		Texture texture = checked_cast<Texture, ITexture>(_texture);

		m_StateTracker.requireTextureState(texture, subresources, state);
	}

	public void requireBufferState(IBuffer _buffer, ResourceStates state)
	{
		Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

		m_StateTracker.requireBufferState(buffer, state);
	}
	public ID3D12CommandList* getD3D12CommandList() { return m_ActiveCommandList.commandList; }

	// IResource implementation

	public override NativeObject getNativeObject(ObjectType objectType)
	{
		switch (objectType)
		{
		case ObjectType.D3D12_GraphicsCommandList:
			if (m_ActiveCommandList != null)
				return NativeObject(m_ActiveCommandList.commandList);
			else
				return null;

		case ObjectType.D3D12_CommandAllocator:
			if (m_ActiveCommandList != null)
				return NativeObject(m_ActiveCommandList.allocator);
			else
				return null;

		case ObjectType.Nvrhi_D3D12_CommandList:
			return NativeObject(Internal.UnsafeCastToPtr(this));

		default:
			return null;
		}
	}

	// ICommandList implementation

	public override void open()
	{
		uint64 completedInstance = m_Queue.updateLastCompletedInstance();

		InternalCommandList chunk = null;

		if (!m_CommandListPool.IsEmpty)
		{
			chunk = m_CommandListPool.Front;

			if (chunk.lastSubmittedInstance <= completedInstance)
			{
				chunk.allocator.Reset();
				chunk.commandList.Reset(chunk.allocator, null);
				m_CommandListPool.PopFront();
			}
			else
			{
				chunk = null;
			}
		}

		if (chunk == null)
		{
			chunk = createInternalCommandList();
		}

		m_ActiveCommandList = chunk;

		m_Instance = new CommandListInstance();
		m_Instance.commandAllocator = m_ActiveCommandList.allocator;
		m_Instance.commandList = m_ActiveCommandList.commandList;
		m_Instance.commandQueue = m_Desc.queueType;

		m_RecordingVersion = MakeVersion(m_Queue.recordingInstance++, m_Desc.queueType, false);
	}
	public override void close()
	{
		m_StateTracker.keepBufferInitialStates();
		m_StateTracker.keepTextureInitialStates();
		commitBarriers();

#if NVRHI_WITH_RTXMU
		if (!m_Instance.rtxmuBuildIds.IsEmpty)
		{
			m_Context.rtxMemUtil.PopulateCompactionSizeCopiesCommandList(m_ActiveCommandList.commandList4, m_Instance.rtxmuBuildIds);
		}
#endif

		m_ActiveCommandList.commandList.Close();

		clearStateCache();

		m_CurrentUploadBuffer = null;
		m_VolatileConstantBufferAddresses.Clear();
		m_ShaderTableStates.Clear();
	}
	public override void clearState()
	{
		m_ActiveCommandList.commandList.ClearState(null);

#if NVRHI_D3D12_WITH_NVAPI
		if (m_CurrentGraphicsStateValid && m_CurrentSinglePassStereoState.enabled)
		{
			NvAPI_Status Status = NvAPI_D3D12_SetSinglePassStereoMode(m_ActiveCommandList.commandList, 
				1, 0, false);

			if (Status != NVAPI_OK)
			{
				m_Context.error("NvAPI_D3D12_SetSinglePassStereoMode call failed");
			}
		}
#endif

		clearStateCache();

		commitDescriptorHeaps();
	}

	public override void clearTextureFloat(ITexture _t, TextureSubresourceSet subresources, Color clearColor)
	{
		var subresources;
		Texture t = checked_cast<Texture, ITexture>(_t);

#if DEBUG
		readonly ref FormatInfo formatInfo = ref getFormatInfo(t.desc.format);
		Runtime.Assert(!formatInfo.hasDepth && !formatInfo.hasStencil);
		Runtime.Assert(t.desc.isUAV || t.desc.isRenderTarget);
#endif

		subresources = subresources.resolve(t.desc, false);

		m_Instance.referencedResources.Add(t);

		if (t.desc.isRenderTarget)
		{
			if (m_EnableAutomaticBarriers)
			{
				requireTextureState(t, subresources, ResourceStates.RenderTarget);
			}
			commitBarriers();

			for (MipLevel mipLevel = subresources.baseMipLevel; mipLevel < subresources.baseMipLevel + subresources.numMipLevels; mipLevel++)
			{
				D3D12_CPU_DESCRIPTOR_HANDLE RTV = .() { ptr = t.getNativeView(ObjectType.D3D12_RenderTargetViewDescriptor, Format.UNKNOWN, subresources, TextureDimension.Unknown).integer };

				float[4] color = .(clearColor.r, clearColor.g, clearColor.b, clearColor.a);

				m_ActiveCommandList.commandList.ClearRenderTargetView(
					RTV,
					&color,
					0, null);
			}
		}
		else
		{
			if (m_EnableAutomaticBarriers)
			{
				requireTextureState(t, subresources, ResourceStates.UnorderedAccess);
			}
			commitBarriers();

			for (MipLevel mipLevel = subresources.baseMipLevel; mipLevel < subresources.baseMipLevel + subresources.numMipLevels; mipLevel++)
			{
				DescriptorIndex index = t.getClearMipLevelUAV(mipLevel);

				Runtime.Assert(index != c_InvalidDescriptorIndex);

				float[4] color = .(clearColor.r, clearColor.g, clearColor.b, clearColor.a);

				m_ActiveCommandList.commandList.ClearUnorderedAccessViewFloat(
					m_Resources.shaderResourceViewHeap.getGpuHandle(index),
					m_Resources.shaderResourceViewHeap.getCpuHandle(index),
					t.resource, &color, 0, null);
			}
		}
	}
	public override void clearDepthStencilTexture(ITexture _t, TextureSubresourceSet subresources, bool clearDepth, float depth, bool clearStencil, uint8 stencil)
	{
		var subresources;
		if (!clearDepth && !clearStencil)
		{
			return;
		}

		Texture t = checked_cast<Texture, ITexture>(_t);

#if DEBUG
		readonly ref FormatInfo formatInfo = ref getFormatInfo(t.desc.format);
		Runtime.Assert(t.desc.isRenderTarget);
		Runtime.Assert(formatInfo.hasDepth || formatInfo.hasStencil);
#endif

		subresources = subresources.resolve(t.desc, false);

		m_Instance.referencedResources.Add(t);

		if (m_EnableAutomaticBarriers)
		{
			requireTextureState(t, subresources, ResourceStates.DepthWrite);
		}
		commitBarriers();

		D3D12_CLEAR_FLAGS clearFlags = D3D12_CLEAR_FLAGS.D3D12_CLEAR_FLAG_DEPTH | D3D12_CLEAR_FLAGS.D3D12_CLEAR_FLAG_STENCIL;
		if (!clearDepth)
		{
			clearFlags = D3D12_CLEAR_FLAGS.D3D12_CLEAR_FLAG_STENCIL;
		}
		else if (!clearStencil)
		{
			clearFlags = D3D12_CLEAR_FLAGS.D3D12_CLEAR_FLAG_DEPTH;
		}

		for (MipLevel mipLevel = subresources.baseMipLevel; mipLevel < subresources.baseMipLevel + subresources.numMipLevels; mipLevel++)
		{
			D3D12_CPU_DESCRIPTOR_HANDLE DSV = .() { ptr = t.getNativeView(ObjectType.D3D12_DepthStencilViewDescriptor, Format.UNKNOWN, subresources, TextureDimension.Unknown).integer };

			m_ActiveCommandList.commandList.ClearDepthStencilView(
				DSV,
				clearFlags,
				depth, stencil,
				0, null);
		}
	}
	public override void clearTextureUInt(ITexture _t, TextureSubresourceSet subresources, uint32 clearColor)
	{
		var subresources;
		Texture t = checked_cast<Texture, ITexture>(_t);

#if DEBUG
		readonly ref FormatInfo formatInfo = ref getFormatInfo(t.desc.format);
		Runtime.Assert(!formatInfo.hasDepth && !formatInfo.hasStencil);
		Runtime.Assert(t.desc.isUAV || t.desc.isRenderTarget);
#endif
		subresources = subresources.resolve(t.desc, false);

		uint32[4] clearValues = .(clearColor, clearColor, clearColor, clearColor);

		m_Instance.referencedResources.Add(t);

		if (t.desc.isUAV)
		{
			if (m_EnableAutomaticBarriers)
			{
				requireTextureState(t, subresources, ResourceStates.UnorderedAccess);
			}
			commitBarriers();

			for (MipLevel mipLevel = subresources.baseMipLevel; mipLevel < subresources.baseMipLevel + subresources.numMipLevels; mipLevel++)
			{
				DescriptorIndex index = t.getClearMipLevelUAV(mipLevel);

				Runtime.Assert(index != c_InvalidDescriptorIndex);

				m_ActiveCommandList.commandList.ClearUnorderedAccessViewUint(
					m_Resources.shaderResourceViewHeap.getGpuHandle(index),
					m_Resources.shaderResourceViewHeap.getCpuHandle(index),
					t.resource, &clearValues, 0, null);
			}
		}
		else if (t.desc.isRenderTarget)
		{
			if (m_EnableAutomaticBarriers)
			{
				requireTextureState(t, subresources, ResourceStates.RenderTarget);
			}
			commitBarriers();

			for (MipLevel mipLevel = subresources.baseMipLevel; mipLevel < subresources.baseMipLevel + subresources.numMipLevels; mipLevel++)
			{
				D3D12_CPU_DESCRIPTOR_HANDLE RTV = .() { ptr = t.getNativeView(ObjectType.D3D12_RenderTargetViewDescriptor, Format.UNKNOWN, subresources, TextureDimension.Unknown).integer };

				float[4] floatColor = .((float)clearColor, (float)clearColor, (float)clearColor, (float)clearColor);
				m_ActiveCommandList.commandList.ClearRenderTargetView(RTV, &floatColor, 0, null);
			}
		}
	}

	public override void copyTexture(ITexture _dst, TextureSlice dstSlice,
		ITexture _src, TextureSlice srcSlice)
	{
		Texture dst = checked_cast<Texture, ITexture>(_dst);
		Texture src = checked_cast<Texture, ITexture>(_src);

		var resolvedDstSlice = dstSlice.resolve(dst.desc);
		var resolvedSrcSlice = srcSlice.resolve(src.desc);

		Runtime.Assert(resolvedDstSlice.width == resolvedSrcSlice.width);
		Runtime.Assert(resolvedDstSlice.height == resolvedSrcSlice.height);

		UINT dstSubresource = calcSubresource(resolvedDstSlice.mipLevel, resolvedDstSlice.arraySlice, 0, dst.desc.mipLevels, dst.desc.arraySize);
		UINT srcSubresource = calcSubresource(resolvedSrcSlice.mipLevel, resolvedSrcSlice.arraySlice, 0, src.desc.mipLevels, src.desc.arraySize);

		D3D12_TEXTURE_COPY_LOCATION dstLocation = .();
		dstLocation.pResource = dst.resource;
		dstLocation.Type = D3D12_TEXTURE_COPY_TYPE.D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
		dstLocation.SubresourceIndex = dstSubresource;

		D3D12_TEXTURE_COPY_LOCATION srcLocation = .();
		srcLocation.pResource = src.resource;
		srcLocation.Type = D3D12_TEXTURE_COPY_TYPE.D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
		srcLocation.SubresourceIndex = srcSubresource;

		D3D12_BOX srcBox = .();
		srcBox.left = resolvedSrcSlice.x;
		srcBox.top = resolvedSrcSlice.y;
		srcBox.front = resolvedSrcSlice.z;
		srcBox.right = resolvedSrcSlice.x + resolvedSrcSlice.width;
		srcBox.bottom = resolvedSrcSlice.y + resolvedSrcSlice.height;
		srcBox.back = resolvedSrcSlice.z + resolvedSrcSlice.depth;

		if (m_EnableAutomaticBarriers)
		{
			requireTextureState(dst, TextureSubresourceSet(resolvedDstSlice.mipLevel, 1, resolvedDstSlice.arraySlice, 1), ResourceStates.CopyDest);
			requireTextureState(src, TextureSubresourceSet(resolvedSrcSlice.mipLevel, 1, resolvedSrcSlice.arraySlice, 1), ResourceStates.CopySource);
		}
		commitBarriers();

		m_Instance.referencedResources.Add(dst);
		m_Instance.referencedResources.Add(src);

		m_ActiveCommandList.commandList.CopyTextureRegion(&dstLocation,
			resolvedDstSlice.x,
			resolvedDstSlice.y,
			resolvedDstSlice.z,
			&srcLocation,
			&srcBox);
	}
	public override void copyTexture(IStagingTexture _dst, TextureSlice dstSlice, ITexture _src, TextureSlice srcSlice)
	{
		Texture src = checked_cast<Texture, ITexture>(_src);
		StagingTexture dst = checked_cast<StagingTexture, IStagingTexture>(_dst);

		var resolvedDstSlice = dstSlice.resolve(dst.desc);
		var resolvedSrcSlice = srcSlice.resolve(src.desc);

		UINT srcSubresource = calcSubresource(resolvedSrcSlice.mipLevel, resolvedSrcSlice.arraySlice, 0, src.desc.mipLevels, src.desc.arraySize);

		if (m_EnableAutomaticBarriers)
		{
			requireTextureState(src, TextureSubresourceSet(resolvedSrcSlice.mipLevel, 1, resolvedSrcSlice.arraySlice, 1), ResourceStates.CopySource);
			requireBufferState(dst.buffer, ResourceStates.CopyDest);
		}
		commitBarriers();

		m_Instance.referencedResources.Add(src);
		m_Instance.referencedStagingTextures.Add(dst);

		var dstRegion = dst.getSliceRegion(m_Context.device, resolvedDstSlice);

		D3D12_TEXTURE_COPY_LOCATION dstLocation = .();
		dstLocation.pResource = dst.buffer.resource;
		dstLocation.Type = D3D12_TEXTURE_COPY_TYPE.D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
		dstLocation.PlacedFootprint = dstRegion.footprint;

		D3D12_TEXTURE_COPY_LOCATION srcLocation = .();
		srcLocation.pResource = src.resource;
		srcLocation.Type = D3D12_TEXTURE_COPY_TYPE.D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
		srcLocation.SubresourceIndex = srcSubresource;

		D3D12_BOX srcBox = .();
		srcBox.left = resolvedSrcSlice.x;
		srcBox.top = resolvedSrcSlice.y;
		srcBox.front = resolvedSrcSlice.z;
		srcBox.right = resolvedSrcSlice.x + resolvedSrcSlice.width;
		srcBox.bottom = resolvedSrcSlice.y + resolvedSrcSlice.height;
		srcBox.back = resolvedSrcSlice.z + resolvedSrcSlice.depth;

		m_ActiveCommandList.commandList.CopyTextureRegion(&dstLocation, resolvedDstSlice.x, resolvedDstSlice.y, resolvedDstSlice.z,
			&srcLocation, &srcBox);
	}
	public override void copyTexture(ITexture _dst, TextureSlice dstSlice, IStagingTexture _src, TextureSlice srcSlice)
	{
		StagingTexture src = checked_cast<StagingTexture, IStagingTexture>(_src);
		Texture dst = checked_cast<Texture, ITexture>(_dst);

		var resolvedDstSlice = dstSlice.resolve(dst.desc);
		var resolvedSrcSlice = srcSlice.resolve(src.desc);

		UINT dstSubresource = calcSubresource(resolvedDstSlice.mipLevel, resolvedDstSlice.arraySlice, 0, dst.desc.mipLevels, dst.desc.arraySize);

		if (m_EnableAutomaticBarriers)
		{
			requireTextureState(dst, TextureSubresourceSet(resolvedDstSlice.mipLevel, 1, resolvedDstSlice.arraySlice, 1), ResourceStates.CopyDest);
			requireBufferState(src.buffer, ResourceStates.CopySource);
		}
		commitBarriers();

		m_Instance.referencedResources.Add(dst);
		m_Instance.referencedStagingTextures.Add(src);

		var srcRegion = src.getSliceRegion(m_Context.device, resolvedSrcSlice);

		D3D12_TEXTURE_COPY_LOCATION dstLocation = .();
		dstLocation.pResource = dst.resource;
		dstLocation.Type = D3D12_TEXTURE_COPY_TYPE.D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
		dstLocation.SubresourceIndex = dstSubresource;

		D3D12_TEXTURE_COPY_LOCATION srcLocation = .();
		srcLocation.pResource = src.buffer.resource;
		srcLocation.Type = D3D12_TEXTURE_COPY_TYPE.D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
		srcLocation.PlacedFootprint = srcRegion.footprint;

		D3D12_BOX srcBox = .();
		srcBox.left = resolvedSrcSlice.x;
		srcBox.top = resolvedSrcSlice.y;
		srcBox.front = resolvedSrcSlice.z;
		srcBox.right = resolvedSrcSlice.x + resolvedSrcSlice.width;
		srcBox.bottom = resolvedSrcSlice.y + resolvedSrcSlice.height;
		srcBox.back = resolvedSrcSlice.z + resolvedSrcSlice.depth;

		m_ActiveCommandList.commandList.CopyTextureRegion(&dstLocation, resolvedDstSlice.x, resolvedDstSlice.y, resolvedDstSlice.z,
			&srcLocation, &srcBox);
	}
	public override void writeTexture(ITexture _dest, uint32 arraySlice, uint32 mipLevel, void* data, int rowPitch, int depthPitch)
	{
		Texture dest = checked_cast<Texture, ITexture>(_dest);

		if (m_EnableAutomaticBarriers)
		{
			requireTextureState(dest, TextureSubresourceSet(mipLevel, 1, arraySlice, 1), ResourceStates.CopyDest);
		}
		commitBarriers();

		uint32 subresource = calcSubresource(mipLevel, arraySlice, 0, dest.desc.mipLevels, dest.desc.arraySize);

		D3D12_RESOURCE_DESC resourceDesc = dest.resource.GetDesc();
		D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint = .();
		uint32 numRows = 0;
		uint64 rowSizeInBytes = 0;
		uint64 totalBytes = 0;

		m_Context.device.GetCopyableFootprints(&resourceDesc, subresource, 1, 0, &footprint, &numRows, &rowSizeInBytes, &totalBytes);

		void* cpuVA = null;
		ID3D12Resource* uploadBuffer = null;
		int offsetInUploadBuffer = 0;
		if (!m_UploadManager.suballocateBuffer(totalBytes, null, &uploadBuffer, &offsetInUploadBuffer, &cpuVA, null,
			m_RecordingVersion, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT))
		{
			m_Context.error("Couldn't suballocate an upload buffer");
			return;
		}
		footprint.Offset = uint64(offsetInUploadBuffer);

		Runtime.Assert(numRows <= footprint.Footprint.Height);

		for (uint32 depthSlice = 0; depthSlice < footprint.Footprint.Depth; depthSlice++)
		{
			for (uint32 row = 0; row < numRows; row++)
			{
				void* destAddress = (char8*)cpuVA + footprint.Footprint.RowPitch * (row + depthSlice * numRows);
				readonly void* srcAddress = (char8*)data + rowPitch * row + depthPitch * depthSlice;
				Internal.MemCpy(destAddress, srcAddress, Math.Min(rowPitch, (int)rowSizeInBytes));
			}
		}

		D3D12_TEXTURE_COPY_LOCATION destCopyLocation;
		destCopyLocation.Type = D3D12_TEXTURE_COPY_TYPE.D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
		destCopyLocation.SubresourceIndex = subresource;
		destCopyLocation.pResource = dest.resource;

		D3D12_TEXTURE_COPY_LOCATION srcCopyLocation;
		srcCopyLocation.Type = D3D12_TEXTURE_COPY_TYPE.D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
		srcCopyLocation.PlacedFootprint = footprint;
		srcCopyLocation.pResource = uploadBuffer;

		m_Instance.referencedResources.Add(dest);

		if (uploadBuffer != m_CurrentUploadBuffer)
		{
			m_Instance.referencedNativeResources.Add(*uploadBuffer);
			m_CurrentUploadBuffer = uploadBuffer;
		}

		m_ActiveCommandList.commandList.CopyTextureRegion(&destCopyLocation, 0, 0, 0, &srcCopyLocation, null);
	}
	public override void resolveTexture(ITexture _dest, TextureSubresourceSet dstSubresources, ITexture _src, TextureSubresourceSet srcSubresources)
	{
		Texture dest = checked_cast<Texture, ITexture>(_dest);
		Texture src = checked_cast<Texture, ITexture>(_src);

		TextureSubresourceSet dstSR = dstSubresources.resolve(dest.desc, false);
		TextureSubresourceSet srcSR = srcSubresources.resolve(src.desc, false);

		if (dstSR.numArraySlices != srcSR.numArraySlices || dstSR.numMipLevels != srcSR.numMipLevels)
			// let the validation layer handle the messages
			return;

		if (m_EnableAutomaticBarriers)
		{
			requireTextureState(_dest, dstSubresources, ResourceStates.ResolveDest);
			requireTextureState(_src, srcSubresources, ResourceStates.ResolveSource);
		}
		commitBarriers();

		readonly ref DxgiFormatMapping formatMapping = ref getDxgiFormatMapping(dest.desc.format);

		for (int32 plane = 0; plane < dest.planeCount; plane++)
		{
			for (ArraySlice arrayIndex = 0; arrayIndex < dstSR.numArraySlices; arrayIndex++)
			{
				for (MipLevel mipLevel = 0; mipLevel < dstSR.numMipLevels; mipLevel++)
				{
					uint32 dstSubresource = calcSubresource(mipLevel + dstSR.baseMipLevel, arrayIndex + dstSR.baseArraySlice, (.)plane, dest.desc.mipLevels, dest.desc.arraySize);
					uint32 srcSubresource = calcSubresource(mipLevel + srcSR.baseMipLevel, arrayIndex + srcSR.baseArraySlice, (.)plane, src.desc.mipLevels, src.desc.arraySize);
					m_ActiveCommandList.commandList.ResolveSubresource(dest.resource, dstSubresource, src.resource, srcSubresource, formatMapping.rtvFormat);
				}
			}
		}
	}

	public override void writeBuffer(IBuffer _b, void* data, int dataSize, uint64 destOffsetBytes)
	{
		Buffer buffer = checked_cast<Buffer, IBuffer>(_b);

		void* cpuVA = null;
		D3D12_GPU_VIRTUAL_ADDRESS gpuVA = .();
		ID3D12Resource* uploadBuffer = null;
		int offsetInUploadBuffer = 0;
		if (!m_UploadManager.suballocateBuffer((.)dataSize, null, &uploadBuffer, &offsetInUploadBuffer, &cpuVA, &gpuVA,
			m_RecordingVersion, D3D12_CONSTANT_BUFFER_DATA_PLACEMENT_ALIGNMENT))
		{
			m_Context.error("Couldn't suballocate an upload buffer");
			return;
		}

		if (uploadBuffer != m_CurrentUploadBuffer)
		{
			m_Instance.referencedNativeResources.Add(*uploadBuffer);
			m_CurrentUploadBuffer = uploadBuffer;
		}

		Internal.MemCpy(cpuVA, data, dataSize);

		if (buffer.desc.isVolatile)
		{
			m_VolatileConstantBufferAddresses[buffer] = gpuVA;
			m_AnyVolatileBufferWrites = true;
		}
		else
		{
			if (m_EnableAutomaticBarriers)
			{
				requireBufferState(buffer, ResourceStates.CopyDest);
			}
			commitBarriers();

			m_Instance.referencedResources.Add(buffer);

			m_ActiveCommandList.commandList.CopyBufferRegion(buffer.resource, destOffsetBytes, uploadBuffer, (.)offsetInUploadBuffer, (.)dataSize);
		}
	}
	public override void clearBufferUInt(IBuffer _b, uint32 clearValue)
	{
		Buffer b = checked_cast<Buffer, IBuffer>(_b);

		if (!b.desc.canHaveUAVs)
		{
			String message = scope $"Cannot clear buffer {utils.DebugNameToString(b.desc.debugName)} because it was created with canHaveUAVs = false";
			m_Context.error(message);
			return;
		}

		if (m_EnableAutomaticBarriers)
		{
			requireBufferState(b, ResourceStates.UnorderedAccess);
		}
		commitBarriers();

		DescriptorIndex clearUAV = b.getClearUAV();
		Runtime.Assert(clearUAV != c_InvalidDescriptorIndex);

		m_Instance.referencedResources.Add(b);

		uint32[4] values = .(clearValue, clearValue, clearValue, clearValue);
		m_ActiveCommandList.commandList.ClearUnorderedAccessViewUint(
			m_Resources.shaderResourceViewHeap.getGpuHandle(clearUAV),
			m_Resources.shaderResourceViewHeap.getCpuHandle(clearUAV),
			b.resource, &values, 0, null);
	}
	public override void copyBuffer(IBuffer _dest, uint64 destOffsetBytes, IBuffer _src, uint64 srcOffsetBytes, uint64 dataSizeBytes)
	{
		Buffer dest = checked_cast<Buffer, IBuffer>(_dest);
		Buffer src = checked_cast<Buffer, IBuffer>(_src);

		if (m_EnableAutomaticBarriers)
		{
			requireBufferState(dest, ResourceStates.CopyDest);
			requireBufferState(src, ResourceStates.CopySource);
		}
		commitBarriers();

		if (src.desc.cpuAccess != CpuAccessMode.None)
			m_Instance.referencedStagingBuffers.Add(src);
		else
			m_Instance.referencedResources.Add(src);

		if (dest.desc.cpuAccess != CpuAccessMode.None)
			m_Instance.referencedStagingBuffers.Add(dest);
		else
			m_Instance.referencedResources.Add(dest);

		m_ActiveCommandList.commandList.CopyBufferRegion(dest.resource, destOffsetBytes, src.resource, srcOffsetBytes, dataSizeBytes);
	}

	public override void setPushConstants(void* data, int byteSize)
	{
		RootSignature rootsig = null;
		bool isGraphics = false;

		if (m_CurrentGraphicsStateValid && m_CurrentGraphicsState.pipeline != null)
		{
			GraphicsPipeline pso = checked_cast<GraphicsPipeline, IGraphicsPipeline>(m_CurrentGraphicsState.pipeline);
			rootsig = pso.rootSignature;
			isGraphics = true;
		}
		else if (m_CurrentComputeStateValid && m_CurrentComputeState.pipeline != null)
		{
			ComputePipeline pso = checked_cast<ComputePipeline, IComputePipeline>(m_CurrentComputeState.pipeline);
			rootsig = pso.rootSignature;
			isGraphics = false;
		}
		else if (m_CurrentRayTracingStateValid && m_CurrentRayTracingState.shaderTable != null)
		{
			RayTracingPipeline pso = checked_cast<RayTracingPipeline, IPipeline>(m_CurrentRayTracingState.shaderTable.getPipeline());
			rootsig = pso.globalRootSignature;
			isGraphics = false;
		}
		else if (m_CurrentMeshletStateValid && m_CurrentMeshletState.pipeline != null)
		{
			MeshletPipeline pso = checked_cast<MeshletPipeline, IMeshletPipeline>(m_CurrentMeshletState.pipeline);
			rootsig = pso.rootSignature;
			isGraphics = true;
		}

		if (rootsig  == null || rootsig.pushConstantByteSize == 0)
			return;

		Runtime.Assert(byteSize == rootsig.pushConstantByteSize); // the validation error handles the error message

		if (isGraphics)
			m_ActiveCommandList.commandList.SetGraphicsRoot32BitConstants(rootsig.rootParameterPushConstants, UINT(byteSize / 4), data, 0);
		else
			m_ActiveCommandList.commandList.SetComputeRoot32BitConstants(rootsig.rootParameterPushConstants, UINT(byteSize / 4), data, 0);
	}

	public override void setGraphicsState(GraphicsState state)
	{
		var state;
		GraphicsPipeline pso = checked_cast<GraphicsPipeline, IGraphicsPipeline>(state.pipeline);
		Framebuffer framebuffer = checked_cast<Framebuffer, IFramebuffer>(state.framebuffer);

		readonly bool updateFramebuffer = !m_CurrentGraphicsStateValid || m_CurrentGraphicsState.framebuffer != state.framebuffer;
		readonly bool updateRootSignature = !m_CurrentGraphicsStateValid || m_CurrentGraphicsState.pipeline == null ||
			checked_cast<GraphicsPipeline, IGraphicsPipeline>(m_CurrentGraphicsState.pipeline).rootSignature != pso.rootSignature;

		readonly bool updatePipeline = !m_CurrentGraphicsStateValid || m_CurrentGraphicsState.pipeline != state.pipeline;
		readonly bool updateIndirectParams = !m_CurrentGraphicsStateValid || m_CurrentGraphicsState.indirectParams != state.indirectParams;

		readonly bool updateViewports = !m_CurrentGraphicsStateValid ||
			arraysAreDifferent(m_CurrentGraphicsState.viewport.viewports, state.viewport.viewports) ||
			arraysAreDifferent(m_CurrentGraphicsState.viewport.scissorRects, state.viewport.scissorRects);

		readonly bool updateBlendFactor = !m_CurrentGraphicsStateValid || m_CurrentGraphicsState.blendConstantColor != state.blendConstantColor;

		readonly bool updateIndexBuffer = !m_CurrentGraphicsStateValid || m_CurrentGraphicsState.indexBuffer != state.indexBuffer;
		readonly bool updateVertexBuffers = !m_CurrentGraphicsStateValid || arraysAreDifferent(m_CurrentGraphicsState.vertexBuffers, state.vertexBuffers);

		readonly bool updateShadingRate = !m_CurrentGraphicsStateValid || m_CurrentGraphicsState.shadingRateState != state.shadingRateState;

		uint32 bindingUpdateMask = 0;
		if (!m_CurrentGraphicsStateValid || updateRootSignature)
			bindingUpdateMask = ~0u;

		if (commitDescriptorHeaps())
			bindingUpdateMask = ~0u;

		if (bindingUpdateMask == 0)
			bindingUpdateMask = arrayDifferenceMask(m_CurrentGraphicsState.bindings, state.bindings);

		if (updatePipeline)
		{
			bindGraphicsPipeline(pso, updateRootSignature);
			m_Instance.referencedResources.Add(pso);
		}

		if (pso.requiresBlendFactor && updateBlendFactor)
		{
			m_ActiveCommandList.commandList.OMSetBlendFactor(&state.blendConstantColor.r);
		}

		if (updateFramebuffer)
		{
			bindFramebuffer(framebuffer);
			m_Instance.referencedResources.Add(framebuffer);
		}

		setGraphicsBindings(state.bindings, bindingUpdateMask, state.indirectParams, updateIndirectParams, pso.rootSignature);

		if (updateIndexBuffer)
		{
			D3D12_INDEX_BUFFER_VIEW IBV = .();

			if (state.indexBuffer.buffer != null)
			{
				Buffer buffer = checked_cast<Buffer, IBuffer>(state.indexBuffer.buffer);

				if (m_EnableAutomaticBarriers)
				{
					requireBufferState(buffer, ResourceStates.IndexBuffer);
				}

				IBV.Format = getDxgiFormatMapping(state.indexBuffer.format).srvFormat;
				IBV.SizeInBytes = (UINT)(buffer.desc.byteSize - state.indexBuffer.offset);
				IBV.BufferLocation = buffer.gpuVA + state.indexBuffer.offset;

				m_Instance.referencedResources.Add(state.indexBuffer.buffer);
			}

			m_ActiveCommandList.commandList.IASetIndexBuffer(&IBV);
		}

		if (updateVertexBuffers)
		{
			D3D12_VERTEX_BUFFER_VIEW[16] VBVs = .InitAll;

			InputLayout inputLayout = checked_cast<InputLayout, IInputLayout>(pso.desc.inputLayout?.Get<IInputLayout>());

			for (int i = 0; i < state.vertexBuffers.Count; i++)
			{
				readonly /*ref*/ VertexBufferBinding binding = /*ref*/ state.vertexBuffers[i];

				Buffer buffer = checked_cast<Buffer, IBuffer>(binding.buffer);

				if (m_EnableAutomaticBarriers)
				{
					requireBufferState(buffer, ResourceStates.VertexBuffer);
				}

				VBVs[binding.slot].StrideInBytes = inputLayout.elementStrides[binding.slot];
				VBVs[binding.slot].SizeInBytes = (UINT)(Math.Min(buffer.desc.byteSize - binding.offset, (uint64)uint64.MaxValue));
				VBVs[binding.slot].BufferLocation = buffer.gpuVA + binding.offset;

				m_Instance.referencedResources.Add(buffer);
			}

			uint32 numVertexBuffers = uint32(state.vertexBuffers.Count);
			if (m_CurrentGraphicsStateValid)
				numVertexBuffers = Math.Max(numVertexBuffers, uint32(m_CurrentGraphicsState.vertexBuffers.Count));

			for (uint32 i = 0; i < numVertexBuffers; i++)
			{
				m_ActiveCommandList.commandList.IASetVertexBuffers(i, 1, VBVs[i].BufferLocation != 0 ? &VBVs[i] : null);
			}
		}

		if (updateShadingRate || updateFramebuffer)
		{
			var framebufferDesc = framebuffer.getDesc();
			bool shouldEnableVariableRateShading = framebufferDesc.shadingRateAttachment.valid() && state.shadingRateState.enabled;
			bool variableRateShadingCurrentlyEnabled = m_CurrentGraphicsStateValid
				&& m_CurrentGraphicsState.framebuffer.getDesc().shadingRateAttachment.valid() && m_CurrentGraphicsState.shadingRateState.enabled;

			if (shouldEnableVariableRateShading)
			{
				setTextureState(framebufferDesc.shadingRateAttachment.texture, nvrhi.TextureSubresourceSet(0, 1, 0, 1), nvrhi.ResourceStates.ShadingRateSurface);
				Texture texture = checked_cast<Texture, ITexture>(framebufferDesc.shadingRateAttachment.texture);
				m_ActiveCommandList.commandList6.RSSetShadingRateImage(texture.resource);
			}
			else if (variableRateShadingCurrentlyEnabled)
			{
				// shading rate attachment is not enabled in framebuffer, or VRS is turned off, so unbind VRS image
				m_ActiveCommandList.commandList6.RSSetShadingRateImage(null);
			}
		}

		if (updateShadingRate)
		{
			if (state.shadingRateState.enabled)
			{
				Compiler.Assert(D3D12_RS_SET_SHADING_RATE_COMBINER_COUNT == 2);
				D3D12_SHADING_RATE_COMBINER[D3D12_RS_SET_SHADING_RATE_COMBINER_COUNT] combiners = .();
				combiners[0] = convertShadingRateCombiner(state.shadingRateState.pipelinePrimitiveCombiner);
				combiners[1] = convertShadingRateCombiner(state.shadingRateState.imageCombiner);
				m_ActiveCommandList.commandList6.RSSetShadingRate(convertPixelShadingRate(state.shadingRateState.shadingRate), &combiners);
			}
			else if (m_CurrentGraphicsStateValid && m_CurrentGraphicsState.shadingRateState.enabled)
			{
				// only call if the old state had VRS enabled and we need to disable it
				m_ActiveCommandList.commandList6.RSSetShadingRate(D3D12_SHADING_RATE.D3D12_SHADING_RATE_1X1, null);
			}
		}

		commitBarriers();

		if (updateViewports)
		{
			DX12_ViewportState vpState = convertViewportState(pso.desc.renderState.rasterState, framebuffer.framebufferInfo, state.viewport);

			if (vpState.numViewports > 0)
			{
				m_ActiveCommandList.commandList.RSSetViewports(vpState.numViewports, &vpState.viewports);
			}

			if (vpState.numScissorRects > 0)
			{
				m_ActiveCommandList.commandList.RSSetScissorRects(vpState.numScissorRects, &vpState.scissorRects);
			}
		}

#if NVRHI_D3D12_WITH_NVAPI
		bool updateSPS = m_CurrentSinglePassStereoState != pso.desc.renderState.singlePassStereo;

		if (updateSPS)
		{
			const SinglePassStereoState& spsState = pso.desc.renderState.singlePassStereo;

			NvAPI_Status Status = NvAPI_D3D12_SetSinglePassStereoMode(m_ActiveCommandList.commandList, spsState.enabled ? 2 : 1, spsState.renderTargetIndexOffset, spsState.independentViewportMask);

			if (Status != NVAPI_OK)
			{
				m_Context.error("NvAPI_D3D12_SetSinglePassStereoMode call failed");
			}

			m_CurrentSinglePassStereoState = spsState;
		}
#endif

		m_CurrentGraphicsStateValid = true;
		m_CurrentComputeStateValid = false;
		m_CurrentMeshletStateValid = false;
		m_CurrentRayTracingStateValid = false;
		m_CurrentGraphicsState = state;
	}
	public override void draw(DrawArguments args)
	{
		updateGraphicsVolatileBuffers();

		m_ActiveCommandList.commandList.DrawInstanced(args.vertexCount, args.instanceCount, args.startVertexLocation, args.startInstanceLocation);
	}
	public override void drawIndexed(DrawArguments args)
	{
		updateGraphicsVolatileBuffers();

		m_ActiveCommandList.commandList.DrawIndexedInstanced(args.vertexCount, args.instanceCount, args.startIndexLocation, (.)args.startVertexLocation, args.startInstanceLocation);
	}
	public override void drawIndirect(uint32 offsetBytes)
	{
		Buffer indirectParams = checked_cast<Buffer, IBuffer>(m_CurrentGraphicsState.indirectParams);
		Runtime.Assert(indirectParams != null); // validation layer handles this

		updateGraphicsVolatileBuffers();

		m_ActiveCommandList.commandList.ExecuteIndirect(m_Context.drawIndirectSignature, 1, indirectParams.resource, offsetBytes, null, 0);
	}

	public override void setComputeState(ComputeState state)
	{
		ComputePipeline pso = checked_cast<ComputePipeline, IComputePipeline>(state.pipeline);

		readonly bool updateRootSignature = !m_CurrentComputeStateValid || m_CurrentComputeState.pipeline == null ||
			checked_cast<ComputePipeline, IComputePipeline>(m_CurrentComputeState.pipeline).rootSignature != pso.rootSignature;

		bool updatePipeline = !m_CurrentComputeStateValid || m_CurrentComputeState.pipeline != state.pipeline;
		bool updateIndirectParams = !m_CurrentComputeStateValid || m_CurrentComputeState.indirectParams != state.indirectParams;

		uint32 bindingUpdateMask = 0;
		if (!m_CurrentComputeStateValid || updateRootSignature)
			bindingUpdateMask = ~0u;

		if (commitDescriptorHeaps())
			bindingUpdateMask = ~0u;

		if (bindingUpdateMask == 0)
			bindingUpdateMask = arrayDifferenceMask(m_CurrentComputeState.bindings, state.bindings);

		if (updateRootSignature)
		{
			m_ActiveCommandList.commandList.SetComputeRootSignature(pso.rootSignature.handle);
		}

		if (updatePipeline)
		{
			m_ActiveCommandList.commandList.SetPipelineState(pso.pipelineState);

			m_Instance.referencedResources.Add(pso);
		}

		setComputeBindings(state.bindings, bindingUpdateMask, state.indirectParams, updateIndirectParams, pso.rootSignature);

		unbindShadingRateState();

		m_CurrentGraphicsStateValid = false;
		m_CurrentComputeStateValid = true;
		m_CurrentMeshletStateValid = false;
		m_CurrentRayTracingStateValid = false;
		m_CurrentComputeState = state;

		commitBarriers();
	}
	public override void dispatch(uint32 groupsX, uint32 groupsY = 1, uint32 groupsZ = 1)
	{
		updateComputeVolatileBuffers();

		m_ActiveCommandList.commandList.Dispatch(groupsX, groupsY, groupsZ);
	}
	public override void dispatchIndirect(uint32 offsetBytes)
	{
		Buffer indirectParams = checked_cast<Buffer, IBuffer>(m_CurrentComputeState.indirectParams);
		Runtime.Assert(indirectParams != null); // validation layer handles this

		updateComputeVolatileBuffers();

		m_ActiveCommandList.commandList.ExecuteIndirect(m_Context.dispatchIndirectSignature, 1, indirectParams.resource, offsetBytes, null, 0);
	}

	public override void setMeshletState(MeshletState state)
	{
		var state;
		MeshletPipeline pso = checked_cast<MeshletPipeline, IMeshletPipeline>(state.pipeline);
		Framebuffer framebuffer = checked_cast<Framebuffer, IFramebuffer>(state.framebuffer);

		unbindShadingRateState();

		readonly bool updateFramebuffer = !m_CurrentMeshletStateValid || m_CurrentMeshletState.framebuffer != state.framebuffer;
		readonly bool updateRootSignature = !m_CurrentMeshletStateValid || m_CurrentMeshletState.pipeline == null ||
			checked_cast<MeshletPipeline, IMeshletPipeline>(m_CurrentMeshletState.pipeline).rootSignature != pso.rootSignature;

		readonly bool updatePipeline = !m_CurrentMeshletStateValid || m_CurrentMeshletState.pipeline != state.pipeline;
		readonly bool updateIndirectParams = !m_CurrentMeshletStateValid || m_CurrentMeshletState.indirectParams != state.indirectParams;

		readonly bool updateViewports = !m_CurrentMeshletStateValid ||
			arraysAreDifferent(m_CurrentMeshletState.viewport.viewports, state.viewport.viewports) ||
			arraysAreDifferent(m_CurrentMeshletState.viewport.scissorRects, state.viewport.scissorRects);

		readonly bool updateBlendFactor = !m_CurrentGraphicsStateValid || m_CurrentGraphicsState.blendConstantColor != state.blendConstantColor;

		uint32 bindingUpdateMask = 0;
		if (!m_CurrentMeshletStateValid || updateRootSignature)
			bindingUpdateMask = ~0u;

		if (commitDescriptorHeaps())
			bindingUpdateMask = ~0u;

		if (bindingUpdateMask == 0)
			bindingUpdateMask = arrayDifferenceMask(m_CurrentMeshletState.bindings, state.bindings);

		if (updatePipeline)
		{
			bindMeshletPipeline(pso, updateRootSignature);
			m_Instance.referencedResources.Add(pso);
		}

		if (pso.requiresBlendFactor && updateBlendFactor)
		{
			m_ActiveCommandList.commandList.OMSetBlendFactor(&state.blendConstantColor.r);
		}

		if (updateFramebuffer)
		{
			bindFramebuffer(framebuffer);
			m_Instance.referencedResources.Add(framebuffer);
		}

		setGraphicsBindings(state.bindings, bindingUpdateMask, state.indirectParams, updateIndirectParams, pso.rootSignature);

		commitBarriers();

		if (updateViewports)
		{
			DX12_ViewportState vpState = convertViewportState(pso.desc.renderState.rasterState, framebuffer.framebufferInfo, state.viewport);

			if (vpState.numViewports > 0)
			{
				Runtime.Assert(pso.viewportState.numViewports == 0);
				m_ActiveCommandList.commandList.RSSetViewports(vpState.numViewports, &vpState.viewports);
			}

			if (vpState.numScissorRects > 0)
			{
				Runtime.Assert(pso.viewportState.numScissorRects == 0);
				m_ActiveCommandList.commandList.RSSetScissorRects(vpState.numScissorRects, &vpState.scissorRects);
			}
		}

		m_CurrentGraphicsStateValid = false;
		m_CurrentComputeStateValid = false;
		m_CurrentMeshletStateValid = true;
		m_CurrentRayTracingStateValid = false;
		m_CurrentMeshletState = state;
	}
	public override void dispatchMesh(uint32 groupsX, uint32 groupsY = 1, uint32 groupsZ = 1)
	{
		updateGraphicsVolatileBuffers();

		m_ActiveCommandList.commandList6.DispatchMesh(groupsX, groupsY, groupsZ);
	}

	public override void setRayTracingState(nvrhi.rt.State state)
	{
		ShaderTable shaderTable = checked_cast<ShaderTable, IShaderTable>(state.shaderTable);
		RayTracingPipeline pso = shaderTable.pipeline;

		ShaderTableState shaderTableState = getShaderTableStateTracking(shaderTable);

		bool rebuildShaderTable = shaderTableState.committedVersion != shaderTable.version ||
			shaderTableState.descriptorHeapSRV != m_Resources.shaderResourceViewHeap.getShaderVisibleHeap() ||
			shaderTableState.descriptorHeapSamplers != m_Resources.samplerHeap.getShaderVisibleHeap();

		if (rebuildShaderTable)
		{
			uint32 entrySize = pso.getShaderTableEntrySize();
			uint32 sbtSize = shaderTable.getNumEntries() * entrySize;

			char8* cpuVA = null;
			D3D12_GPU_VIRTUAL_ADDRESS gpuVA = .();
			if (!m_UploadManager.suballocateBuffer(sbtSize, null, null, null,
				(void**)&cpuVA, &gpuVA, m_RecordingVersion, D3D12_RAYTRACING_SHADER_TABLE_BYTE_ALIGNMENT))
			{
				m_Context.error("Couldn't suballocate an upload buffer");
				return;
			}

			uint32 entryIndex = 0;

			delegate void(ShaderTable.Entry entry)  writeEntry = scope [=entrySize, &cpuVA, &gpuVA, &entryIndex, &] (entry) =>
				{
					Internal.MemCpy(cpuVA, entry.pShaderIdentifier, D3D12_SHADER_IDENTIFIER_SIZE_IN_BYTES);

					if (entry.localBindings != null)
					{
						d3d12.BindingSet bindingSet = checked_cast<d3d12.BindingSet, IBindingSet>(entry.localBindings?.Get<IBindingSet>());
						d3d12.BindingLayout layout = bindingSet.layout;

						if (layout.descriptorTableSizeSamplers > 0)
						{
							var pTable = (D3D12_GPU_DESCRIPTOR_HANDLE*)(cpuVA + D3D12_SHADER_IDENTIFIER_SIZE_IN_BYTES + layout.rootParameterSamplers * sizeof(D3D12_GPU_DESCRIPTOR_HANDLE));
							*pTable = m_Resources.samplerHeap.getGpuHandle(bindingSet.descriptorTableSamplers);
						}

						if (layout.descriptorTableSizeSRVetc > 0)
						{
							var pTable = (D3D12_GPU_DESCRIPTOR_HANDLE*)(cpuVA + D3D12_SHADER_IDENTIFIER_SIZE_IN_BYTES + layout.rootParameterSRVetc * sizeof(D3D12_GPU_DESCRIPTOR_HANDLE));
							*pTable = m_Resources.shaderResourceViewHeap.getGpuHandle(bindingSet.descriptorTableSRVetc);
						}

						if (!layout.rootParametersVolatileCB.IsEmpty)
						{
							m_Context.error("Cannot use Volatile CBs in a shader binding table");
							return;
						}
					}

					cpuVA += entrySize;
					gpuVA += entrySize;
					entryIndex += 1;
				};

			ref D3D12_DISPATCH_RAYS_DESC drd = ref shaderTableState.dispatchRaysTemplate;
			Internal.MemCpy(&drd, null, sizeof(D3D12_DISPATCH_RAYS_DESC));

			drd.RayGenerationShaderRecord.StartAddress = gpuVA;
			drd.RayGenerationShaderRecord.SizeInBytes = entrySize;
			writeEntry(shaderTable.rayGenerationShader);

			if (!shaderTable.missShaders.IsEmpty)
			{
				drd.MissShaderTable.StartAddress = gpuVA;
				drd.MissShaderTable.StrideInBytes = (shaderTable.missShaders.Count == 1) ? 0 : entrySize;
				drd.MissShaderTable.SizeInBytes = uint32(shaderTable.missShaders.Count) * entrySize;

				for (var entry in ref shaderTable.missShaders)
					writeEntry(entry);
			}

			if (!shaderTable.hitGroups.IsEmpty)
			{
				drd.HitGroupTable.StartAddress = gpuVA;
				drd.HitGroupTable.StrideInBytes = (shaderTable.hitGroups.Count == 1) ? 0 : entrySize;
				drd.HitGroupTable.SizeInBytes = uint32(shaderTable.hitGroups.Count) * entrySize;

				for (var entry in ref shaderTable.hitGroups)
					writeEntry(entry);
			}

			if (!shaderTable.callableShaders.IsEmpty)
			{
				drd.CallableShaderTable.StartAddress = gpuVA;
				drd.CallableShaderTable.StrideInBytes = (shaderTable.callableShaders.Count == 1) ? 0 : entrySize;
				drd.CallableShaderTable.SizeInBytes = uint32(shaderTable.callableShaders.Count) * entrySize;

				for (var entry in ref shaderTable.callableShaders)
					writeEntry(entry);
			}

			shaderTableState.committedVersion = shaderTable.version;
			shaderTableState.descriptorHeapSRV = m_Resources.shaderResourceViewHeap.getShaderVisibleHeap();
			shaderTableState.descriptorHeapSamplers = m_Resources.samplerHeap.getShaderVisibleHeap();

			// AddRef the shaderTable only on the first use / build because build happens at least once per CL anyway
			m_Instance.referencedResources.Add(shaderTable);
		}

		readonly bool updateRootSignature = !m_CurrentRayTracingStateValid || m_CurrentRayTracingState.shaderTable == null ||
			checked_cast<ShaderTable, IShaderTable>(m_CurrentRayTracingState.shaderTable).pipeline.globalRootSignature != pso.globalRootSignature;

		bool updatePipeline = !m_CurrentRayTracingStateValid || m_CurrentRayTracingState.shaderTable.getPipeline() != pso;

		uint32 bindingUpdateMask = 0;
		if (!m_CurrentRayTracingStateValid || updateRootSignature)
			bindingUpdateMask = ~0u;

		if (commitDescriptorHeaps())
			bindingUpdateMask = ~0u;

		if (bindingUpdateMask == 0)
			bindingUpdateMask = arrayDifferenceMask(m_CurrentRayTracingState.bindings, state.bindings);

		if (updateRootSignature)
		{
			m_ActiveCommandList.commandList4.SetComputeRootSignature(pso.globalRootSignature.handle);
		}

		if (updatePipeline)
		{
			m_ActiveCommandList.commandList4.SetPipelineState1(pso.pipelineState);

			m_Instance.referencedResources.Add(pso);
		}

		setComputeBindings(state.bindings, bindingUpdateMask, null, false, pso.globalRootSignature);

		unbindShadingRateState();

		m_CurrentComputeStateValid = false;
		m_CurrentGraphicsStateValid = false;
		m_CurrentRayTracingStateValid = true;
		m_CurrentRayTracingState = state;

		commitBarriers();
	}
	public override void dispatchRays(nvrhi.rt.DispatchRaysArguments args)
	{
		updateComputeVolatileBuffers();

		if (!m_CurrentRayTracingStateValid)
		{
			m_Context.error("setRayTracingState must be called before dispatchRays");
			return;
		}

		ShaderTableState shaderTableState = getShaderTableStateTracking(m_CurrentRayTracingState.shaderTable);

		D3D12_DISPATCH_RAYS_DESC desc = shaderTableState.dispatchRaysTemplate;
		desc.Width = args.width;
		desc.Height = args.height;
		desc.Depth = args.depth;

		m_ActiveCommandList.commandList4.DispatchRays(&desc);
	}

	public override void buildBottomLevelAccelStruct(nvrhi.rt.IAccelStruct _as, nvrhi.rt.GeometryDesc* pGeometries, int numGeometries, nvrhi.rt.AccelStructBuildFlags buildFlags)
	{
		AccelStruct @as = checked_cast<AccelStruct, IAccelStruct>(_as);

		readonly bool performUpdate = (buildFlags & nvrhi.rt.AccelStructBuildFlags.PerformUpdate) != 0;
		if (performUpdate)
		{
			Runtime.Assert(@as.allowUpdate);
		}

		List<D3D12_RAYTRACING_GEOMETRY_DESC> d3dGeometryDescs = scope .();
		d3dGeometryDescs.Resize(numGeometries);

		for (uint32 i = 0; i < numGeometries; i++)
		{
			/*readonly*/ var geometryDesc = ref pGeometries[i];
			var d3dGeometryDesc = ref d3dGeometryDescs[i];

			fillD3dGeometryDesc(ref d3dGeometryDesc, geometryDesc);

			if (geometryDesc.useTransform)
			{
				void* cpuVA = null;
				D3D12_GPU_VIRTUAL_ADDRESS gpuVA = 0;
				if (!m_UploadManager.suballocateBuffer(sizeof(nvrhi.rt.AffineTransform), null, null, null,
					&cpuVA, &gpuVA, m_RecordingVersion, D3D12_CONSTANT_BUFFER_DATA_PLACEMENT_ALIGNMENT))
				{
					m_Context.error("Couldn't suballocate an upload buffer");
					return;
				}

				Internal.MemCpy(cpuVA, &geometryDesc.transform, sizeof(nvrhi.rt.AffineTransform));

				d3dGeometryDesc.Triangles.Transform3x4 = gpuVA;
			}

			if (geometryDesc.geometryType == nvrhi.rt.GeometryType.Triangles)
			{
				readonly var triangles = /*ref*/ geometryDesc.geometryData.triangles;

				if (m_EnableAutomaticBarriers)
				{
					requireBufferState(triangles.indexBuffer, ResourceStates.AccelStructBuildInput);
					requireBufferState(triangles.vertexBuffer, ResourceStates.AccelStructBuildInput);
				}

				m_Instance.referencedResources.Add(triangles.indexBuffer);
				m_Instance.referencedResources.Add(triangles.vertexBuffer);
			}
			else
			{
				readonly var aabbs = geometryDesc.geometryData.aabbs;

				if (m_EnableAutomaticBarriers)
				{
					requireBufferState(aabbs.buffer, ResourceStates.AccelStructBuildInput);
				}

				m_Instance.referencedResources.Add(aabbs.buffer);
			}
		}

		commitBarriers();

		D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS ASInputs;
		ASInputs.Type = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE.D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL;
		ASInputs.DescsLayout = D3D12_ELEMENTS_LAYOUT.D3D12_ELEMENTS_LAYOUT_ARRAY;
		ASInputs.pGeometryDescs = d3dGeometryDescs.Ptr;
		ASInputs.NumDescs = UINT(d3dGeometryDescs.Count);
		ASInputs.Flags = (D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAGS)buildFlags;
		if (@as.allowUpdate)
			ASInputs.Flags |= D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAGS.D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_ALLOW_UPDATE;

#if NVRHI_WITH_RTXMU
		List<uint64> accelStructsToBuild;
		List<D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS> buildInputs;
		buildInputs.push_back(ASInputs);

		if(as.rtxmuId == ~0ull)
		{
			m_Context.rtxMemUtil.PopulateBuildCommandList(m_ActiveCommandList.commandList4.Get(),
														   buildInputs.data(),
														   buildInputs.size(),
														   accelStructsToBuild);

			as.rtxmuId = accelStructsToBuild[0];

			as.rtxmuGpuVA = m_Context.rtxMemUtil.GetAccelStructGPUVA(as.rtxmuId);

			m_Instance.rtxmuBuildIds.push_back(as.rtxmuId);

		}
		else
		{
			List<uint64> buildsToUpdate(1, as.rtxmuId);

			m_Context.rtxMemUtil.PopulateUpdateCommandList(m_ActiveCommandList.commandList4.Get(),
															buildInputs.data(),
															uint32(buildInputs.size()),
															buildsToUpdate);
		}
#else
		D3D12_RAYTRACING_ACCELERATION_STRUCTURE_PREBUILD_INFO ASPreBuildInfo = .();
		m_Context.device5.GetRaytracingAccelerationStructurePrebuildInfo(&ASInputs, &ASPreBuildInfo);

		if (ASPreBuildInfo.ResultDataMaxSizeInBytes > @as.dataBuffer.desc.byteSize)
		{
			String message = scope $"BLAS {utils.DebugNameToString(@as.desc.debugName)} build requires at least {ASPreBuildInfo.ResultDataMaxSizeInBytes} bytes in the data buffer, while the allocated buffer is only {@as.dataBuffer.desc.byteSize} bytes";

			m_Context.error(message);
			return;
		}

		uint64 scratchSize = performUpdate
			? ASPreBuildInfo.UpdateScratchDataSizeInBytes
			: ASPreBuildInfo.ScratchDataSizeInBytes;

		D3D12_GPU_VIRTUAL_ADDRESS scratchGpuVA = 0;
		if (!m_DxrScratchManager.suballocateBuffer(scratchSize, m_ActiveCommandList.commandList, null, null, null,
			&scratchGpuVA, m_RecordingVersion, D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BYTE_ALIGNMENT))
		{
			String message = scope $"Couldn't suballocate a scratch buffer for BLAS {nvrhi.utils.DebugNameToString(@as.desc.debugName)} build. The build requires {scratchSize} bytes of scratch space.";

			m_Context.error(message);
			return;
		}

		D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_DESC buildDesc = .();
		buildDesc.Inputs = ASInputs;
		buildDesc.ScratchAccelerationStructureData = scratchGpuVA;
		buildDesc.DestAccelerationStructureData = @as.dataBuffer.gpuVA;
		buildDesc.SourceAccelerationStructureData = performUpdate ? @as.dataBuffer.gpuVA : 0;

		if (m_EnableAutomaticBarriers)
		{
			requireBufferState(@as.dataBuffer, nvrhi.ResourceStates.AccelStructWrite);
		}
		commitBarriers();

		m_ActiveCommandList.commandList4.BuildRaytracingAccelerationStructure(&buildDesc, 0, null);

#endif

		if (@as.desc.trackLiveness)
			m_Instance.referencedResources.Add(@as);
	}
	public override void compactBottomLevelAccelStructs()
	{
#if NVRHI_WITH_RTXMU

		if (!m_Resources.asBuildsCompleted.IsEmpty)
		{
			std.lock_guard lockGuard(m_Resources.asListMutex);

			if (!m_Resources.asBuildsCompleted.IsEmpty)
			{
				m_Context.rtxMemUtil.PopulateCompactionCommandList(m_ActiveCommandList.commandList4.Get(), m_Resources.asBuildsCompleted);

				m_Instance.rtxmuCompactionIds.insert(m_Instance.rtxmuCompactionIds.end(), m_Resources.asBuildsCompleted.begin(), m_Resources.asBuildsCompleted.end());

				m_Resources.asBuildsCompleted.clear();
			}
		}
#endif
	}
	public override void buildTopLevelAccelStruct(nvrhi.rt.IAccelStruct _as, nvrhi.rt.InstanceDesc* pInstances, int numInstances, nvrhi.rt.AccelStructBuildFlags buildFlags)
	{
		AccelStruct @as = checked_cast<AccelStruct, IAccelStruct>(_as);

		@as.bottomLevelASes.Clear();

		// Keep the dxrInstances array in the AS object to avoid reallocating it on the next update
		@as.dxrInstances.Resize(numInstances);

		// Construct the instance array in a local vector first and then copy it over
		// because doing it in GPU memory over PCIe is much slower.
		for (uint32 i = 0; i < numInstances; i++)
		{
			/*readonly*/ ref nvrhi.rt.InstanceDesc instance = ref pInstances[i];
			ref D3D12_RAYTRACING_INSTANCE_DESC dxrInstance = ref @as.dxrInstances[i];

			AccelStruct blas = checked_cast<AccelStruct, IAccelStruct>(instance.bottomLevelAS);

			if (blas.desc.trackLiveness)
				@as.bottomLevelASes.Add(blas);

			Compiler.Assert(sizeof(decltype(dxrInstance)) == sizeof(decltype(instance)));
			Internal.MemCpy(&dxrInstance, &instance, sizeof(decltype(instance)));

#if NVRHI_WITH_RTXMU
			dxrInstance.AccelerationStructure = m_Context.rtxMemUtil.GetAccelStructGPUVA(blas.rtxmuId);
#else
			dxrInstance.AccelerationStructure = blas.dataBuffer.gpuVA;
#endif

#if !NVRHI_WITH_RTXMU
			if (m_EnableAutomaticBarriers)
			{
				requireBufferState(blas.dataBuffer, nvrhi.ResourceStates.AccelStructBuildBlas);
			}
#endif
		}

#if NVRHI_WITH_RTXMU
		m_Context.rtxMemUtil.PopulateUAVBarriersCommandList(m_ActiveCommandList.commandList4, m_Instance.rtxmuBuildIds);
#endif

		// Copy the instance array to the GPU
		D3D12_RAYTRACING_INSTANCE_DESC* cpuVA = null;
		D3D12_GPU_VIRTUAL_ADDRESS gpuVA = 0;
		int uploadSize = sizeof(D3D12_RAYTRACING_INSTANCE_DESC) * @as.dxrInstances.Count;
		if (!m_UploadManager.suballocateBuffer((.)uploadSize, null, null, null, (void**)&cpuVA, &gpuVA,
			m_RecordingVersion, D3D12_CONSTANT_BUFFER_DATA_PLACEMENT_ALIGNMENT))
		{
			m_Context.error("Couldn't suballocate an upload buffer");
			return;
		}

		Internal.MemCpy(cpuVA, @as.dxrInstances.Ptr, sizeof(D3D12_RAYTRACING_INSTANCE_DESC) * @as.dxrInstances.Count);

		if (m_EnableAutomaticBarriers)
		{
			requireBufferState(@as.dataBuffer, nvrhi.ResourceStates.AccelStructWrite);
		}
		commitBarriers();

		buildTopLevelAccelStructInternal(@as, gpuVA, numInstances, buildFlags);

		if (@as.desc.trackLiveness)
			m_Instance.referencedResources.Add(@as);
	}
	public override void buildTopLevelAccelStructFromBuffer(nvrhi.rt.IAccelStruct _as, nvrhi.IBuffer instanceBuffer, uint64 instanceBufferOffset, int numInstances, nvrhi.rt.AccelStructBuildFlags buildFlags)
	{
		AccelStruct @as = checked_cast<AccelStruct, IAccelStruct>(_as);

		@as.bottomLevelASes.Clear();
		@as.dxrInstances.Clear();

		if (m_EnableAutomaticBarriers)
		{
			requireBufferState(@as.dataBuffer, nvrhi.ResourceStates.AccelStructWrite);
			requireBufferState(instanceBuffer, nvrhi.ResourceStates.AccelStructBuildInput);
		}
		commitBarriers();

		buildTopLevelAccelStructInternal(@as, getBufferGpuVA(instanceBuffer) + instanceBufferOffset, numInstances, buildFlags);

		if (@as.desc.trackLiveness)
			m_Instance.referencedResources.Add(@as);
	}

	public override void beginTimerQuery(ITimerQuery _query)
	{
		TimerQuery query = checked_cast<TimerQuery, ITimerQuery>(_query);

		m_Instance.referencedTimerQueries.Add(query);

		m_ActiveCommandList.commandList.EndQuery(m_Context.timerQueryHeap, D3D12_QUERY_TYPE.D3D12_QUERY_TYPE_TIMESTAMP, query.beginQueryIndex);

		// two timestamps within the same command list are always reliably comparable, so we avoid kicking off here
		// (note: we don't call SetStablePowerState anymore)
	}
	public override void endTimerQuery(ITimerQuery _query)
	{
		TimerQuery query = checked_cast<TimerQuery, ITimerQuery>(_query);

		m_Instance.referencedTimerQueries.Add(query);

		m_ActiveCommandList.commandList.EndQuery(m_Context.timerQueryHeap, D3D12_QUERY_TYPE.D3D12_QUERY_TYPE_TIMESTAMP, query.endQueryIndex);

		m_ActiveCommandList.commandList.ResolveQueryData(m_Context.timerQueryHeap,
			D3D12_QUERY_TYPE.D3D12_QUERY_TYPE_TIMESTAMP,
			query.beginQueryIndex,
			2,
			m_Context.timerQueryResolveBuffer.resource,
			query.beginQueryIndex * 8);
	}

	public override void beginMarker(char8* name)
	{
		//PIXBeginEvent(m_ActiveCommandList.commandList, 0, name); // todo
	}
	public override void endMarker()
	{
		//PIXEndEvent(m_ActiveCommandList.commandList); // todo
	}

	public override void setEnableAutomaticBarriers(bool enable)
	{
		m_EnableAutomaticBarriers = enable;
	}
	public override void setResourceStatesForBindingSet(IBindingSet _bindingSet)
	{
		if (_bindingSet.getDesc() == null)
			return; // is bindless

		BindingSet bindingSet = checked_cast<BindingSet, IBindingSet>(_bindingSet);

		for (var bindingIndex in bindingSet.bindingsThatNeedTransitions)
		{
			readonly ref BindingSetItem binding = ref  bindingSet.desc.bindings[bindingIndex];

			switch (binding.type) // NOLINT(clang-diagnostic-switch-enum)
			{
			case ResourceType.Texture_SRV:
				requireTextureState(checked_cast<ITexture, IResource>(binding.resourceHandle), binding.subresources, ResourceStates.ShaderResource);
				break;

			case ResourceType.Texture_UAV:
				requireTextureState(checked_cast<ITexture, IResource>(binding.resourceHandle), binding.subresources, ResourceStates.UnorderedAccess);
				break;

			case ResourceType.TypedBuffer_SRV: fallthrough;
			case ResourceType.StructuredBuffer_SRV: fallthrough;
			case ResourceType.RawBuffer_SRV:
				requireBufferState(checked_cast<IBuffer, IResource>(binding.resourceHandle), ResourceStates.ShaderResource);
				break;

			case ResourceType.TypedBuffer_UAV: fallthrough;
			case ResourceType.StructuredBuffer_UAV: fallthrough;
			case ResourceType.RawBuffer_UAV:
				requireBufferState(checked_cast<IBuffer, IResource>(binding.resourceHandle), ResourceStates.UnorderedAccess);
				break;

			case ResourceType.ConstantBuffer:
				requireBufferState(checked_cast<IBuffer, IResource>(binding.resourceHandle), ResourceStates.ConstantBuffer);
				break;

			case ResourceType.RayTracingAccelStruct:
				requireBufferState(checked_cast<AccelStruct, IResource>(binding.resourceHandle).dataBuffer, ResourceStates.AccelStructRead);
				break;

			default:
				// do nothing
				break;
			}
		}
	}

	public override void setEnableUavBarriersForTexture(ITexture _texture, bool enableBarriers)
	{
		Texture texture = checked_cast<Texture, ITexture>(_texture);

		m_StateTracker.setEnableUavBarriersForTexture(texture, enableBarriers);
	}

	public override void setEnableUavBarriersForBuffer(IBuffer _buffer, bool enableBarriers)
	{
		Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

		m_StateTracker.setEnableUavBarriersForBuffer(buffer, enableBarriers);
	}

	public override void beginTrackingTextureState(ITexture _texture, TextureSubresourceSet subresources, ResourceStates stateBits)
	{
		Texture texture = checked_cast<Texture, ITexture>(_texture);

		m_StateTracker.beginTrackingTextureState(texture, subresources, stateBits);
	}
	public override void beginTrackingBufferState(IBuffer _buffer, ResourceStates stateBits)
	{
		Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

		m_StateTracker.beginTrackingBufferState(buffer, stateBits);
	}

	public override void setTextureState(ITexture _texture, TextureSubresourceSet subresources, ResourceStates stateBits)
	{
		Texture texture = checked_cast<Texture, ITexture>(_texture);

		m_StateTracker.endTrackingTextureState(texture, subresources, stateBits, false);
	}
	public override void setBufferState(IBuffer _buffer, ResourceStates stateBits)
	{
		Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

		m_StateTracker.endTrackingBufferState(buffer, stateBits, false);
	}
	public override void setAccelStructState(nvrhi.rt.IAccelStruct _as, ResourceStates stateBits)
	{
		AccelStruct @as = checked_cast<AccelStruct, IAccelStruct>(_as);

		if (@as.dataBuffer != null)
			m_StateTracker.endTrackingBufferState(@as.dataBuffer, stateBits, false);
	}

	public override void setPermanentTextureState(ITexture _texture, ResourceStates stateBits)
	{
		Texture texture = checked_cast<Texture, ITexture>(_texture);

		m_StateTracker.endTrackingTextureState(texture, AllSubresources, stateBits, true);
	}
	public override void setPermanentBufferState(IBuffer _buffer, ResourceStates stateBits)
	{
		Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

		m_StateTracker.endTrackingBufferState(buffer, stateBits, true);
	}

	public override void commitBarriers()
	{
		readonly var textureBarriers = m_StateTracker.getTextureBarriers();
		readonly var bufferBarriers = m_StateTracker.getBufferBarriers();
		readonly int barrierCount = textureBarriers.Count + bufferBarriers.Count;
		if (barrierCount == 0)
			return;

		// Allocate vector space for the barriers assuming 1:1 translation.
		// For partial transitions on multi-plane textures, original barriers may translate
		// into more than 1 barrier each, but that's relatively rare.
		m_D3DBarriers.Clear();
		m_D3DBarriers.Reserve(barrierCount);

		// Convert the texture barriers into D3D equivalents
		for (readonly var barrier in textureBarriers)
		{
			readonly Texture texture = (Texture)(barrier.texture);

			D3D12_RESOURCE_BARRIER d3dbarrier = .();
			readonly D3D12_RESOURCE_STATES stateBefore = convertResourceStates(barrier.stateBefore);
			readonly D3D12_RESOURCE_STATES stateAfter = convertResourceStates(barrier.stateAfter);
			if (stateBefore != stateAfter)
			{
				d3dbarrier.Type = D3D12_RESOURCE_BARRIER_TYPE.D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
				d3dbarrier.Transition.StateBefore = stateBefore;
				d3dbarrier.Transition.StateAfter = stateAfter;
				d3dbarrier.Transition.pResource = texture.resource;
				if (barrier.entireTexture)
				{
					d3dbarrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
					m_D3DBarriers.Add(d3dbarrier);
				}
				else
				{
					for (uint8 plane = 0; plane < texture.planeCount; plane++)
					{
						d3dbarrier.Transition.Subresource = calcSubresource(barrier.mipLevel, barrier.arraySlice, plane, texture.desc.mipLevels, texture.desc.arraySize);
						m_D3DBarriers.Add(d3dbarrier);
					}
				}
			}
			else if (stateAfter & D3D12_RESOURCE_STATES.D3D12_RESOURCE_STATE_UNORDERED_ACCESS != 0)
			{
				d3dbarrier.Type = D3D12_RESOURCE_BARRIER_TYPE.D3D12_RESOURCE_BARRIER_TYPE_UAV;
				d3dbarrier.UAV.pResource = texture.resource;
				m_D3DBarriers.Add(d3dbarrier);
			}
		}

		// Convert the buffer barriers into D3D equivalents
		for (readonly var barrier in bufferBarriers)
		{
			readonly Buffer buffer = (Buffer)(barrier.buffer);

			D3D12_RESOURCE_BARRIER d3dbarrier = .();
			readonly D3D12_RESOURCE_STATES stateBefore = convertResourceStates(barrier.stateBefore);
			readonly D3D12_RESOURCE_STATES stateAfter = convertResourceStates(barrier.stateAfter);
			if (stateBefore != stateAfter &&
				(stateBefore & D3D12_RESOURCE_STATES.D3D12_RESOURCE_STATE_RAYTRACING_ACCELERATION_STRUCTURE) == 0 &&
				(stateAfter & D3D12_RESOURCE_STATES.D3D12_RESOURCE_STATE_RAYTRACING_ACCELERATION_STRUCTURE) == 0)
			{
				d3dbarrier.Type = D3D12_RESOURCE_BARRIER_TYPE.D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
				d3dbarrier.Transition.StateBefore = stateBefore;
				d3dbarrier.Transition.StateAfter = stateAfter;
				d3dbarrier.Transition.pResource = buffer.resource;
				d3dbarrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
				m_D3DBarriers.Add(d3dbarrier);
			}
			else if ((barrier.stateBefore == ResourceStates.AccelStructWrite && (barrier.stateAfter & (ResourceStates.AccelStructRead | ResourceStates.AccelStructBuildBlas)) != 0) ||
				(barrier.stateAfter == ResourceStates.AccelStructWrite && (barrier.stateBefore & (ResourceStates.AccelStructRead | ResourceStates.AccelStructBuildBlas)) != 0) ||
				(stateAfter & D3D12_RESOURCE_STATES.D3D12_RESOURCE_STATE_UNORDERED_ACCESS) != 0)
			{
				d3dbarrier.Type = D3D12_RESOURCE_BARRIER_TYPE.D3D12_RESOURCE_BARRIER_TYPE_UAV;
				d3dbarrier.UAV.pResource = buffer.resource;
				m_D3DBarriers.Add(d3dbarrier);
			}
		}

		Runtime.Assert(!m_D3DBarriers.IsEmpty); // otherwise there's an early-out in the beginning of this function

		m_ActiveCommandList.commandList.ResourceBarrier(uint32(m_D3DBarriers.Count), m_D3DBarriers.Ptr);

		m_StateTracker.clearBarriers();
	}

	public override ResourceStates getTextureSubresourceState(ITexture _texture, ArraySlice arraySlice, MipLevel mipLevel)
	{
		Texture texture = checked_cast<Texture, ITexture>(_texture);

		return m_StateTracker.getTextureSubresourceState(texture, arraySlice, mipLevel);
	}
	public override ResourceStates getBufferState(IBuffer _buffer)
	{
		Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

		return m_StateTracker.getBufferState(buffer);
	}

	public override nvrhi.IDevice getDevice()
	{
		return m_Device;
	}
	public override readonly ref CommandListParameters getDesc() { return ref m_Desc; }

	// D3D12 specific methods

	public override bool allocateUploadBuffer(int size, void** pCpuAddress, D3D12_GPU_VIRTUAL_ADDRESS* pGpuAddress)
	{
		return m_UploadManager.suballocateBuffer((.)size, null, null, null, pCpuAddress, pGpuAddress,
			m_RecordingVersion, D3D12_CONSTANT_BUFFER_DATA_PLACEMENT_ALIGNMENT);
	}
	public bool allocateDxrScratchBuffer(int size, void** pCpuAddress, D3D12_GPU_VIRTUAL_ADDRESS* pGpuAddress)
	{
		return m_DxrScratchManager.suballocateBuffer((.)size, m_ActiveCommandList.commandList, null, null, pCpuAddress, pGpuAddress,
			m_RecordingVersion, D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BYTE_ALIGNMENT);
	}
	public override bool commitDescriptorHeaps()
	{
		ID3D12DescriptorHeap* heapSRVetc = m_Resources.shaderResourceViewHeap.getShaderVisibleHeap();
		ID3D12DescriptorHeap* heapSamplers = m_Resources.samplerHeap.getShaderVisibleHeap();

		if (heapSRVetc != m_CurrentHeapSRVetc || heapSamplers != m_CurrentHeapSamplers)
		{
			ID3D12DescriptorHeap*[2] heaps = .(heapSRVetc, heapSamplers);
			m_ActiveCommandList.commandList.SetDescriptorHeaps(2, &heaps);

			m_CurrentHeapSRVetc = heapSRVetc;
			m_CurrentHeapSamplers = heapSamplers;

			m_Instance.referencedNativeResources.Add(*heapSRVetc);
			m_Instance.referencedNativeResources.Add(*heapSamplers);

			return true;
		}

		return false;
	}

	public override D3D12_GPU_VIRTUAL_ADDRESS getBufferGpuVA(IBuffer _buffer)
	{
		if (_buffer == null)
			return 0;

		Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

		if (buffer.desc.isVolatile)
		{
			return m_VolatileConstantBufferAddresses[buffer];
		}

		return buffer.gpuVA;
	}

	public override void updateGraphicsVolatileBuffers()
	{
		// If there are some volatile buffers bound, and they have been written into since the last draw or setGraphicsState, patch their views
		if (!m_AnyVolatileBufferWrites)
			return;

		for (ref VolatileConstantBufferBinding parameter in ref m_CurrentGraphicsVolatileCBs)
		{
			D3D12_GPU_VIRTUAL_ADDRESS currentGpuVA = m_VolatileConstantBufferAddresses[parameter.buffer];

			if (currentGpuVA != parameter.address)
			{
				m_ActiveCommandList.commandList.SetGraphicsRootConstantBufferView(parameter.bindingPoint, currentGpuVA);

				parameter.address = currentGpuVA;
			}
		}

		m_AnyVolatileBufferWrites = false;
	}
	public override void updateComputeVolatileBuffers()
	{
		// If there are some volatile buffers bound, and they have been written into since the last dispatch or setComputeState, patch their views
		if (!m_AnyVolatileBufferWrites)
			return;

		for (ref VolatileConstantBufferBinding parameter in ref m_CurrentComputeVolatileCBs)
		{
			readonly D3D12_GPU_VIRTUAL_ADDRESS currentGpuVA = m_VolatileConstantBufferAddresses[parameter.buffer];

			if (currentGpuVA != parameter.address)
			{
				m_ActiveCommandList.commandList.SetComputeRootConstantBufferView(parameter.bindingPoint, currentGpuVA);

				parameter.address = currentGpuVA;
			}
		}

		m_AnyVolatileBufferWrites = false;
	}
	public void setComputeBindings(
		BindingSetVector bindings, uint32 bindingUpdateMask,
		IBuffer indirectParams, bool updateIndirectParams,
		RootSignature rootSignature)
	{
		if (bindingUpdateMask > 0)
		{
			StaticVector<VolatileConstantBufferBinding, const c_MaxVolatileConstantBuffers> newVolatileCBs = .();

			for (uint32 bindingSetIndex = 0; bindingSetIndex < uint32(bindings.Count); bindingSetIndex++)
			{
				IBindingSet _bindingSet = bindings[bindingSetIndex];

				if (_bindingSet == null)
					continue;

				readonly bool updateThisSet = (bindingUpdateMask & (1 << bindingSetIndex)) != 0;

				readonly (BindingLayoutHandle layout, RootParameterIndex index) layoutAndOffset = rootSignature.pipelineLayouts[bindingSetIndex];
				RootParameterIndex rootParameterOffset = layoutAndOffset.index;

				if (_bindingSet.getDesc() != null)
				{
					Runtime.Assert(layoutAndOffset.layout == _bindingSet.getLayout()); // validation layer handles this

					BindingSet bindingSet = checked_cast<BindingSet, IBindingSet>(_bindingSet);

					// Bind the volatile constant buffers
					for (int volatileCbIndex = 0; volatileCbIndex < bindingSet.rootParametersVolatileCB.Count; volatileCbIndex++)
					{
						readonly var parameter = bindingSet.rootParametersVolatileCB[volatileCbIndex];
						RootParameterIndex rootParameterIndex = rootParameterOffset + parameter.index;

						if (parameter.buffer != null)
						{
							Buffer buffer = checked_cast<Buffer, IBuffer>(parameter.buffer);

							if (buffer.desc.isVolatile)
							{
								D3D12_GPU_VIRTUAL_ADDRESS volatileData = m_VolatileConstantBufferAddresses[buffer];

								if (volatileData == 0)
								{
									String message = scope $"Attempted use of a volatile constant buffer {utils.DebugNameToString(buffer.desc.debugName)} before it was written into";
									m_Context.error(message);

									continue;
								}

								if (updateThisSet || volatileData != m_CurrentGraphicsVolatileCBs[newVolatileCBs.Count].address)
								{
									m_ActiveCommandList.commandList.SetComputeRootConstantBufferView(rootParameterIndex, volatileData);
								}

								newVolatileCBs.PushBack(VolatileConstantBufferBinding() { bindingPoint = rootParameterIndex, buffer = buffer, address = volatileData });
							}
							else if (updateThisSet)
							{
								Runtime.Assert(buffer.gpuVA != 0);

								m_ActiveCommandList.commandList.SetComputeRootConstantBufferView(rootParameterIndex, buffer.gpuVA);
							}
						}
						else if (updateThisSet)
						{
							// This can only happen as a result of an improperly built binding set. 
							// Such binding set should fail to create.
							m_ActiveCommandList.commandList.SetComputeRootConstantBufferView(rootParameterIndex, 0);
						}
					}

					if (updateThisSet)
					{
						if (bindingSet.descriptorTableValidSamplers)
						{
							m_ActiveCommandList.commandList.SetComputeRootDescriptorTable(
								rootParameterOffset + bindingSet.rootParameterIndexSamplers,
								m_Resources.samplerHeap.getGpuHandle(bindingSet.descriptorTableSamplers));
						}

						if (bindingSet.descriptorTableValidSRVetc)
						{
							m_ActiveCommandList.commandList.SetComputeRootDescriptorTable(
								rootParameterOffset + bindingSet.rootParameterIndexSRVetc,
								m_Resources.shaderResourceViewHeap.getGpuHandle(bindingSet.descriptorTableSRVetc));
						}

						if (bindingSet.desc.trackLiveness)
							m_Instance.referencedResources.Add(bindingSet);
					}

					if (m_EnableAutomaticBarriers && (updateThisSet || bindingSet.hasUavBindings)) // UAV bindings may place UAV barriers on the same binding set
					{
						setResourceStatesForBindingSet(bindingSet);
					}
				}
				else
				{
					DescriptorTable descriptorTable = checked_cast<DescriptorTable, IBindingSet>(_bindingSet);

					m_ActiveCommandList.commandList.SetComputeRootDescriptorTable(rootParameterOffset, m_Resources.shaderResourceViewHeap.getGpuHandle(descriptorTable.firstDescriptor));
				}
			}

			m_CurrentComputeVolatileCBs = newVolatileCBs;
		}

		if (indirectParams != null && updateIndirectParams)
		{
			if (m_EnableAutomaticBarriers)
			{
				requireBufferState(indirectParams, ResourceStates.IndirectArgument);
			}
			m_Instance.referencedResources.Add(indirectParams);
		}

		uint32 bindingMask = (1 << uint32(bindings.Count)) - 1;
		if ((bindingUpdateMask & bindingMask) == bindingMask)
		{
			// Only reset this flag when this function has gone over all the binging sets
			m_AnyVolatileBufferWrites = false;
		}
	}
	public void setGraphicsBindings(
		BindingSetVector bindings, uint32 bindingUpdateMask,
		IBuffer indirectParams, bool updateIndirectParams,
		RootSignature rootSignature)
	{
		if (bindingUpdateMask > 0)
		{
			StaticVector<VolatileConstantBufferBinding, const c_MaxVolatileConstantBuffers> newVolatileCBs = .();

			for (uint32 bindingSetIndex = 0; bindingSetIndex < uint32(bindings.Count); bindingSetIndex++)
			{
				IBindingSet _bindingSet = bindings[bindingSetIndex];

				if (_bindingSet == null)
					continue;

				readonly bool updateThisSet = (bindingUpdateMask & (1 << bindingSetIndex)) != 0;

				readonly (BindingLayoutHandle layout, RootParameterIndex index) layoutAndOffset = rootSignature.pipelineLayouts[bindingSetIndex];
				RootParameterIndex rootParameterOffset = layoutAndOffset.index;

				if (_bindingSet.getDesc() != null)
				{
					Runtime.Assert(layoutAndOffset.layout == _bindingSet.getLayout()); // validation layer handles this

					BindingSet bindingSet = checked_cast<BindingSet, IBindingSet>(_bindingSet);

					// Bind the volatile constant buffers
					for (int volatileCbIndex = 0; volatileCbIndex < bindingSet.rootParametersVolatileCB.Count; volatileCbIndex++)
					{
						readonly var parameter = bindingSet.rootParametersVolatileCB[volatileCbIndex];
						RootParameterIndex rootParameterIndex = rootParameterOffset + parameter.index;

						if (parameter.buffer != null)
						{
							Buffer buffer = checked_cast<Buffer, IBuffer>(parameter.buffer);

							if (buffer.desc.isVolatile)
							{
								readonly D3D12_GPU_VIRTUAL_ADDRESS volatileData = m_VolatileConstantBufferAddresses[buffer];

								if (volatileData == 0)
								{
									String message = scope $"Attempted use of a volatile constant buffer {utils.DebugNameToString(buffer.desc.debugName)} before it was written into";
									m_Context.error(message);

									continue;
								}

								if (updateThisSet || volatileData != m_CurrentGraphicsVolatileCBs[newVolatileCBs.Count].address)
								{
									m_ActiveCommandList.commandList.SetGraphicsRootConstantBufferView(rootParameterIndex, volatileData);
								}

								newVolatileCBs.PushBack(VolatileConstantBufferBinding() { bindingPoint = rootParameterIndex, buffer = buffer, address = volatileData });
							}
							else if (updateThisSet)
							{
								Runtime.Assert(buffer.gpuVA != 0);

								m_ActiveCommandList.commandList.SetGraphicsRootConstantBufferView(rootParameterIndex, buffer.gpuVA);
							}
						}
						else if (updateThisSet)
						{
							// This can only happen as a result of an improperly built binding set. 
							// Such binding set should fail to create.
							m_ActiveCommandList.commandList.SetGraphicsRootConstantBufferView(rootParameterIndex, 0);
						}
					}

					if (updateThisSet)
					{
						if (bindingSet.descriptorTableValidSamplers)
						{
							m_ActiveCommandList.commandList.SetGraphicsRootDescriptorTable(
								rootParameterOffset + bindingSet.rootParameterIndexSamplers,
								m_Resources.samplerHeap.getGpuHandle(bindingSet.descriptorTableSamplers));
						}

						if (bindingSet.descriptorTableValidSRVetc)
						{
							m_ActiveCommandList.commandList.SetGraphicsRootDescriptorTable(
								rootParameterOffset + bindingSet.rootParameterIndexSRVetc,
								m_Resources.shaderResourceViewHeap.getGpuHandle(bindingSet.descriptorTableSRVetc));
						}

						if (bindingSet.desc.trackLiveness)
							m_Instance.referencedResources.Add(bindingSet);
					}

					if (m_EnableAutomaticBarriers && (updateThisSet || bindingSet.hasUavBindings)) // UAV bindings may place UAV barriers on the same binding set
					{
						setResourceStatesForBindingSet(bindingSet);
					}
				}
				else if (updateThisSet)
				{
					DescriptorTable descriptorTable = checked_cast<DescriptorTable, IBindingSet>(_bindingSet);

					m_ActiveCommandList.commandList.SetGraphicsRootDescriptorTable(rootParameterOffset, m_Resources.shaderResourceViewHeap.getGpuHandle(descriptorTable.firstDescriptor));
				}
			}

			m_CurrentGraphicsVolatileCBs = newVolatileCBs;
		}

		if (indirectParams != null && updateIndirectParams)
		{
			if (m_EnableAutomaticBarriers)
			{
				requireBufferState(indirectParams, ResourceStates.IndirectArgument);
			}
			m_Instance.referencedResources.Add(indirectParams);
		}

		uint32 bindingMask = (1 << uint32(bindings.Count)) - 1;
		if ((bindingUpdateMask & bindingMask) == bindingMask)
		{
			// Only reset this flag when this function has gone over all the binging sets
			m_AnyVolatileBufferWrites = false;
		}
	}

	private Context* m_Context;
	private DeviceResources m_Resources;

	private struct VolatileConstantBufferBinding
	{
		public uint32 bindingPoint; // RootParameterIndex
		public Buffer buffer;
		public D3D12_GPU_VIRTUAL_ADDRESS address;
	}

	private nvrhi.d3d12.IDevice m_Device;
	private Queue m_Queue;
	private UploadManager m_UploadManager ~ delete _;
	private UploadManager m_DxrScratchManager ~ delete _;
	private CommandListResourceStateTracker m_StateTracker ~ delete _;
	private bool m_EnableAutomaticBarriers = true;

	private CommandListParameters m_Desc;

	private InternalCommandList m_ActiveCommandList ~ delete _;
	private Queue<InternalCommandList> m_CommandListPool = new .() ~ {
		for(var item in _){
			delete item;
		}
		delete _;
	};
	private CommandListInstance m_Instance ~ delete _;
	private uint64 m_RecordingVersion = 0;

	// Cache for user-provided state

	private GraphicsState m_CurrentGraphicsState;
	private ComputeState m_CurrentComputeState;
	private MeshletState m_CurrentMeshletState;
	private nvrhi.rt.State m_CurrentRayTracingState;
	private bool m_CurrentGraphicsStateValid = false;
	private bool m_CurrentComputeStateValid = false;
	private bool m_CurrentMeshletStateValid = false;
	private bool m_CurrentRayTracingStateValid = false;

	// Cache for internal state

	private ID3D12DescriptorHeap* m_CurrentHeapSRVetc = null;
	private ID3D12DescriptorHeap* m_CurrentHeapSamplers = null;
	private ID3D12Resource* m_CurrentUploadBuffer = null;
	private SinglePassStereoState m_CurrentSinglePassStereoState;

	private Dictionary<IBuffer, D3D12_GPU_VIRTUAL_ADDRESS> m_VolatileConstantBufferAddresses = new .() ~ delete _;
	private bool m_AnyVolatileBufferWrites = false;

	private List<D3D12_RESOURCE_BARRIER> m_D3DBarriers = new .() ~ delete _; // Used locally in commitBarriers, member to avoid re-allocations

	// Bound volatile buffer state. Saves currently bound volatile buffers and their current GPU VAs.
	// Necessary to patch the bound VAs when a buffer is updated between setGraphicsState and draw, or between draws.

	private StaticVector<VolatileConstantBufferBinding, const c_MaxVolatileConstantBuffers> m_CurrentGraphicsVolatileCBs = .();
	private StaticVector<VolatileConstantBufferBinding, const c_MaxVolatileConstantBuffers> m_CurrentComputeVolatileCBs = .();

	private Dictionary<nvrhi.rt.IShaderTable, ShaderTableState> m_ShaderTableStates = new .() ~ delete _;
	private ShaderTableState getShaderTableStateTracking(nvrhi.rt.IShaderTable shaderTable)
	{
		if (m_ShaderTableStates.ContainsKey(shaderTable))
		{
			return m_ShaderTableStates[shaderTable];
		}

		ShaderTableState trackingRef = new ShaderTableState();

		ShaderTableState tracking = trackingRef;
		m_ShaderTableStates.Add(shaderTable, trackingRef);

		return tracking;
	}

	private void clearStateCache()
	{
		m_AnyVolatileBufferWrites = false;
		m_CurrentGraphicsStateValid = false;
		m_CurrentComputeStateValid = false;
		m_CurrentMeshletStateValid = false;
		m_CurrentRayTracingStateValid = false;
		m_CurrentHeapSRVetc = null;
		m_CurrentHeapSamplers = null;
		m_CurrentGraphicsVolatileCBs.Resize(0);
		m_CurrentComputeVolatileCBs.Resize(0);
		m_CurrentSinglePassStereoState = SinglePassStereoState();
	}

	private void bindGraphicsPipeline(GraphicsPipeline pso, bool updateRootSignature)
	{
		readonly var pipelineDesc = pso.desc;

		if (updateRootSignature)
		{
			m_ActiveCommandList.commandList.SetGraphicsRootSignature(pso.rootSignature.handle);
		}

		m_ActiveCommandList.commandList.SetPipelineState(pso.pipelineState);

		m_ActiveCommandList.commandList.IASetPrimitiveTopology(convertPrimitiveType(pipelineDesc.primType, pipelineDesc.patchControlPoints));

		if (pipelineDesc.renderState.depthStencilState.stencilEnable)
		{
			m_ActiveCommandList.commandList.OMSetStencilRef(pipelineDesc.renderState.depthStencilState.stencilRefValue);
		}
	}
	private void bindMeshletPipeline(MeshletPipeline pso, bool updateRootSignature)
	{
		readonly var state = pso.desc;

		ID3D12GraphicsCommandList* commandList = m_ActiveCommandList.commandList;

		if (updateRootSignature)
		{
			commandList.SetGraphicsRootSignature(pso.rootSignature.handle);
		}

		commandList.SetPipelineState(pso.pipelineState);

		commandList.IASetPrimitiveTopology(convertPrimitiveType(state.primType, 0));

		if (pso.viewportState.numViewports > 0)
		{
			commandList.RSSetViewports(pso.viewportState.numViewports, &pso.viewportState.viewports);
		}

		if (pso.viewportState.numScissorRects != 0)
		{
			commandList.RSSetScissorRects(pso.viewportState.numViewports, &pso.viewportState.scissorRects);
		}

		if (state.renderState.depthStencilState.stencilEnable)
		{
			commandList.OMSetStencilRef(state.renderState.depthStencilState.stencilRefValue);
		}
	}
	private void bindFramebuffer(Framebuffer fb)
	{
		if (m_EnableAutomaticBarriers)
		{
			setResourceStatesForFramebuffer(fb);
		}

		StaticVector<D3D12_CPU_DESCRIPTOR_HANDLE, 16> RTVs = .();
		for (uint32 rtIndex = 0; rtIndex < fb.RTVs.Count; rtIndex++)
		{
			RTVs.PushBack(m_Resources.renderTargetViewHeap.getCpuHandle(fb.RTVs[rtIndex]));
		}

		D3D12_CPU_DESCRIPTOR_HANDLE DSV = .();
		if (fb.desc.depthAttachment.valid())
			DSV = m_Resources.depthStencilViewHeap.getCpuHandle(fb.DSV);

		m_ActiveCommandList.commandList.OMSetRenderTargets(UINT(RTVs.Count), RTVs.Ptr, 0, fb.desc.depthAttachment.valid() ? &DSV : null);
	}
	private void unbindShadingRateState()
	{
		if (m_CurrentGraphicsStateValid && m_CurrentGraphicsState.shadingRateState.enabled)
		{
			m_ActiveCommandList.commandList6.RSSetShadingRateImage(null);
			m_ActiveCommandList.commandList6.RSSetShadingRate(D3D12_SHADING_RATE.D3D12_SHADING_RATE_1X1, null);
			m_CurrentGraphicsState.shadingRateState.enabled = false;
			m_CurrentGraphicsState.framebuffer = null;
		}
	}

	private InternalCommandList createInternalCommandList()
	{
		var commandList = new InternalCommandList();

		D3D12_COMMAND_LIST_TYPE d3dCommandListType = default;
		switch (m_Desc.queueType)
		{
		case CommandQueue.Graphics:
			d3dCommandListType = D3D12_COMMAND_LIST_TYPE.D3D12_COMMAND_LIST_TYPE_DIRECT;
			break;
		case CommandQueue.Compute:
			d3dCommandListType = D3D12_COMMAND_LIST_TYPE.D3D12_COMMAND_LIST_TYPE_COMPUTE;
			break;
		case CommandQueue.Copy:
			d3dCommandListType = D3D12_COMMAND_LIST_TYPE.D3D12_COMMAND_LIST_TYPE_COPY;
			break;

		case CommandQueue.Count: fallthrough;
		default:
			nvrhi.utils.InvalidEnum();
			return null;
		}

		m_Context.device.CreateCommandAllocator(d3dCommandListType, ID3D12CommandAllocator.IID, (void**)&commandList.allocator);
		m_Context.device.CreateCommandList(0, d3dCommandListType, commandList.allocator, null, ID3D12GraphicsCommandList.IID, (void**)&commandList.commandList);

		commandList.commandList.QueryInterface(ID3D12GraphicsCommandList4.IID, (void**)(&commandList.commandList4));
		commandList.commandList.QueryInterface(ID3D12GraphicsCommandList6.IID, (void**)(&commandList.commandList6));

		return commandList;
	}

	private void buildTopLevelAccelStructInternal(AccelStruct @as, D3D12_GPU_VIRTUAL_ADDRESS instanceData, int numInstances, nvrhi.rt.AccelStructBuildFlags buildFlags)
	{
		readonly bool performUpdate = (buildFlags & rt.AccelStructBuildFlags.PerformUpdate) != 0;

		if (performUpdate)
		{
			Runtime.Assert(@as.allowUpdate);
			Runtime.Assert(@as.dxrInstances.Count == numInstances); // DXR doesn't allow updating to a different instance count
		}

		D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS ASInputs;
		ASInputs.Type = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE.D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL;
		ASInputs.DescsLayout = D3D12_ELEMENTS_LAYOUT.D3D12_ELEMENTS_LAYOUT_ARRAY;
		ASInputs.InstanceDescs = instanceData;
		ASInputs.NumDescs = UINT(numInstances);
		ASInputs.Flags = (D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAGS)buildFlags;
		if (@as.allowUpdate)
			ASInputs.Flags |= D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAGS.D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_ALLOW_UPDATE;

		D3D12_RAYTRACING_ACCELERATION_STRUCTURE_PREBUILD_INFO ASPreBuildInfo = .();
		m_Context.device5.GetRaytracingAccelerationStructurePrebuildInfo(&ASInputs, &ASPreBuildInfo);

		if (ASPreBuildInfo.ResultDataMaxSizeInBytes > @as.dataBuffer.desc.byteSize)
		{
			String message = scope $"TLAS {utils.DebugNameToString(@as.desc.debugName)} build requires at least {ASPreBuildInfo.ResultDataMaxSizeInBytes} bytes in the data buffer, while the allocated buffer is only {@as.dataBuffer.desc.byteSize} bytes";

			m_Context.error(message);
			return;
		}

		uint64 scratchSize = performUpdate
			? ASPreBuildInfo.UpdateScratchDataSizeInBytes
			: ASPreBuildInfo.ScratchDataSizeInBytes;

		D3D12_GPU_VIRTUAL_ADDRESS scratchGpuVA = 0;
		if (!m_DxrScratchManager.suballocateBuffer(scratchSize, m_ActiveCommandList.commandList, null, null, null,
			&scratchGpuVA, m_RecordingVersion, D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BYTE_ALIGNMENT))
		{
			String message = scope $"Couldn't suballocate a scratch buffer for TLAS {utils.DebugNameToString(@as.desc.debugName)} build. The build requires {scratchSize} bytes of scratch space.";

			m_Context.error(message);
			return;
		}

		D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_DESC buildDesc = .();
		buildDesc.Inputs = ASInputs;
		buildDesc.ScratchAccelerationStructureData = scratchGpuVA;
		buildDesc.DestAccelerationStructureData = @as.dataBuffer.gpuVA;
		buildDesc.SourceAccelerationStructureData = performUpdate ? @as.dataBuffer.gpuVA : 0;

		m_ActiveCommandList.commandList4.BuildRaytracingAccelerationStructure(&buildDesc, 0, null);
	}
}