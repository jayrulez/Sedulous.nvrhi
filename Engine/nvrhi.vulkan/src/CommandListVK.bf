using Bulkan;
using System;
using System.Collections;
using static Bulkan.VulkanNative;
using nvrhi.rt;
namespace nvrhi.vulkan
{
	class CommandListVK :  RefCounter<ICommandList>
	{
		// Internal backend methods

		public this(DeviceVK device, VulkanContext* context, CommandListParameters parameters)
		{
			m_Device = device;
			m_Context = context;
			m_CommandListParameters = parameters;
			m_StateTracker = new .(context.messageCallback);
			m_UploadManager = new UploadManager(device, (.)parameters.uploadChunkSize, 0, false);
			m_ScratchManager = new UploadManager(device, (.)parameters.scratchChunkSize, (.)parameters.scratchMaxMemory, true);
		}

		public ~this()
		{
			delete m_ScratchManager;
			delete m_UploadManager;
			delete m_StateTracker;
		}

		public void executed(QueueVK queue, uint64 submissionID)
		{
			Runtime.Assert(m_CurrentCmdBuf != null);

			m_CurrentCmdBuf.submissionID = submissionID;

			readonly CommandQueue queueID = queue.getQueueID();
			readonly uint64 recordingID = m_CurrentCmdBuf.recordingID;

			m_CurrentCmdBuf = null;

			submitVolatileBuffers(recordingID, submissionID);

			m_StateTracker.commandListSubmitted();

			m_UploadManager.submitChunks(
				MakeVersion(recordingID, queueID, false),
				MakeVersion(submissionID, queueID, true));

			m_ScratchManager.submitChunks(
				MakeVersion(recordingID, queueID, false),
				MakeVersion(submissionID, queueID, true));

			m_VolatileBufferStates.Clear();
		}

		// IResource implementation

		public override NativeObject getNativeObject(ObjectType objectType)
		{
			switch (objectType)
			{
			case ObjectType.VK_CommandBuffer:
				return NativeObject(m_CurrentCmdBuf.cmdBuf);
			default:
				return null;
			}
		}

		// ICommandList implementation

		public override void open()
		{
			m_CurrentCmdBuf = m_Device.getQueue(m_CommandListParameters.queueType).getOrCreateCommandBuffer();

			var beginInfo = VkCommandBufferBeginInfo()
				.setFlags(VkCommandBufferUsageFlags.eOneTimeSubmitBit);

			VkResult result = vkBeginCommandBuffer(m_CurrentCmdBuf.cmdBuf, &beginInfo);
			ASSERT_VK_OK!(result);
			m_CurrentCmdBuf.referencedResources.Add(this); // prevent deletion of e.g. UploadManager

			clearState();
		}

		public override void close()
		{
			endRenderPass();

			m_StateTracker.keepBufferInitialStates();
			m_StateTracker.keepTextureInitialStates();
			commitBarriers();

#if NVRHI_WITH_RTXMU
			if (!m_CurrentCmdBuf.rtxmuBuildIdsIsEmpty)
			{
				m_Context.rtxMemUtil.PopulateCompactionSizeCopiesCommandList(m_CurrentCmdBuf.cmdBuf, m_CurrentCmdBuf.rtxmuBuildIds);
			}
#endif

			/*VkResult result =*/ vkEndCommandBuffer(m_CurrentCmdBuf.cmdBuf);
			/*ASSERT_VK_OK!(result);*/

			clearState();

			flushVolatileBufferWrites();
		}

		public override void clearState()
		{
			endRenderPass();

			m_CurrentPipelineLayout = .Null;
			m_CurrentPipelineShaderStages = .None;

			m_CurrentGraphicsState = .();
			m_CurrentComputeState = .();
			m_CurrentMeshletState = .();
			m_CurrentRayTracingState = .();
			m_CurrentShaderTablePointers = ShaderTableState();

			m_AnyVolatileBufferWrites = false;

			// TODO: add real context clearing code here
		}

		public override void clearTextureFloat(ITexture texture, TextureSubresourceSet subresources, Color clearColor)
		{
			var clearValue = VkClearColorValue()
				.setFloat32(.(clearColor.r, clearColor.g, clearColor.b, clearColor.a));

			clearTexture(texture, subresources, clearValue);
		}

		public override void clearDepthStencilTexture(ITexture _texture, TextureSubresourceSet subresources, bool clearDepth, float depth, bool clearStencil, uint8 stencil)
		{
			var subresources;
			endRenderPass();

			if (!clearDepth && !clearStencil)
			{
				return;
			}

			TextureVK texture = checked_cast<TextureVK, ITexture>(_texture);
			Runtime.Assert(texture != null);
			Runtime.Assert(m_CurrentCmdBuf != null);

			subresources = subresources.resolve(texture.desc, false);

			if (m_EnableAutomaticBarriers)
			{
				requireTextureState(texture, subresources, ResourceStates.CopyDest);
			}
			commitBarriers();

			VkImageAspectFlags aspectFlags = VkImageAspectFlags();

			if (clearDepth)
				aspectFlags |= VkImageAspectFlags.eDepthBit;

			if (clearStencil)
				aspectFlags |= VkImageAspectFlags.eStencilBit;

			VkImageSubresourceRange subresourceRange = VkImageSubresourceRange()
				.setAspectMask(aspectFlags)
				.setBaseArrayLayer(subresources.baseArraySlice)
				.setLayerCount(subresources.numArraySlices)
				.setBaseMipLevel(subresources.baseMipLevel)
				.setLevelCount(subresources.numMipLevels);

			var clearValue = VkClearDepthStencilValue() { depth = depth, stencil = uint32(stencil) };
			vkCmdClearDepthStencilImage(m_CurrentCmdBuf.cmdBuf, texture.image,
				VkImageLayout.eTransferDstOptimal,
				&clearValue,
				1, &subresourceRange);
		}

		public override void clearTextureUInt(ITexture texture, TextureSubresourceSet subresources, uint32 clearColor)
		{
			int32 clearColorInt = int32(clearColor);

			var clearValue = VkClearColorValue()
				.setUint32(.(clearColor, clearColor, clearColor, clearColor))
				.setInt32(.(clearColorInt, clearColorInt, clearColorInt, clearColorInt));

			clearTexture(texture, subresources, clearValue);
		}

		public override void copyTexture(ITexture _dst, TextureSlice dstSlice, IStagingTexture _src, TextureSlice srcSlice)
		{
			StagingTextureVK src = checked_cast<StagingTextureVK, IStagingTexture>(_src);
			TextureVK dst = checked_cast<TextureVK, ITexture>(_dst);

			var resolvedDstSlice = dstSlice.resolve(dst.desc);
			var resolvedSrcSlice = srcSlice.resolve(src.desc);

			VkExtent3D dstMipSize = dst.imageInfo.extent;
			dstMipSize.width = Math.Max(dstMipSize.width >> resolvedDstSlice.mipLevel, 1u);
			dstMipSize.height = Math.Max(dstMipSize.height >> resolvedDstSlice.mipLevel, 1u);

			var srcRegion = src.getSliceRegion(resolvedSrcSlice.mipLevel, resolvedSrcSlice.arraySlice, resolvedSrcSlice.z);

			Runtime.Assert((srcRegion.offset & 0x3) == 0); // per vulkan spec
			Runtime.Assert(srcRegion.size > 0);

			TextureSubresourceSet dstSubresource = TextureSubresourceSet(
				resolvedDstSlice.mipLevel, 1,
				resolvedDstSlice.arraySlice, 1
				);

			VkOffset3D dstOffset = .() { x = (.)resolvedDstSlice.x, y = (.)resolvedDstSlice.y, z = (.)resolvedDstSlice.z };

			var imageCopy = VkBufferImageCopy()
				.setBufferOffset((.)srcRegion.offset)
				.setBufferRowLength(resolvedSrcSlice.width)
				.setBufferImageHeight(resolvedSrcSlice.height)
				.setImageSubresource(VkImageSubresourceLayers()
				.setAspectMask(guessImageAspectFlags(dst.imageInfo.format))
				.setMipLevel(resolvedDstSlice.mipLevel)
				.setBaseArrayLayer(resolvedDstSlice.arraySlice)
				.setLayerCount(1))
				.setImageOffset(dstOffset)
				.setImageExtent(dstMipSize);

			Runtime.Assert(m_CurrentCmdBuf != null);

			if (m_EnableAutomaticBarriers)
			{
				requireBufferState(src.buffer, ResourceStates.CopySource);
				requireTextureState(dst, dstSubresource, ResourceStates.CopyDest);
			}
			commitBarriers();

			m_CurrentCmdBuf.referencedResources.Add(src);
			m_CurrentCmdBuf.referencedResources.Add(dst);
			m_CurrentCmdBuf.referencedStagingBuffers.Add(src.buffer);

			vkCmdCopyBufferToImage(m_CurrentCmdBuf.cmdBuf, src.buffer.buffer,
				dst.image, VkImageLayout.eTransferDstOptimal,
				1, &imageCopy);
		}

		public override void copyTexture(IStagingTexture _dst, TextureSlice dstSlice, ITexture _src, TextureSlice srcSlice)
		{
			TextureVK src = checked_cast<TextureVK, ITexture>(_src);
			StagingTextureVK dst = checked_cast<StagingTextureVK, IStagingTexture>(_dst);

			var resolvedDstSlice = dstSlice.resolve(dst.desc);
			var resolvedSrcSlice = srcSlice.resolve(src.desc);

			Runtime.Assert(resolvedDstSlice.depth == 1);

			VkExtent3D srcMipSize = src.imageInfo.extent;
			srcMipSize.width = Math.Max(srcMipSize.width >> resolvedDstSlice.mipLevel, 1u);
			srcMipSize.height = Math.Max(srcMipSize.height >> resolvedDstSlice.mipLevel, 1u);

			var dstRegion = dst.getSliceRegion(resolvedDstSlice.mipLevel, resolvedDstSlice.arraySlice, resolvedDstSlice.z);
			Runtime.Assert((dstRegion.offset % 0x3) == 0); // per Vulkan spec

			TextureSubresourceSet srcSubresource = TextureSubresourceSet(
				resolvedSrcSlice.mipLevel, 1,
				resolvedSrcSlice.arraySlice, 1
				);

			var imageCopy = VkBufferImageCopy()
				.setBufferOffset((.)dstRegion.offset)
				.setBufferRowLength(resolvedDstSlice.width)
				.setBufferImageHeight(resolvedDstSlice.height)
				.setImageSubresource(VkImageSubresourceLayers()
				.setAspectMask(guessImageAspectFlags(src.imageInfo.format))
				.setMipLevel(resolvedSrcSlice.mipLevel)
				.setBaseArrayLayer(resolvedSrcSlice.arraySlice)
				.setLayerCount(1))
				.setImageOffset(VkOffset3D() { x = (.)resolvedSrcSlice.x, y = (.)resolvedSrcSlice.y, z = (.)resolvedSrcSlice.z })
				.setImageExtent(srcMipSize);

			Runtime.Assert(m_CurrentCmdBuf != null);

			if (m_EnableAutomaticBarriers)
			{
				requireBufferState(dst.buffer, ResourceStates.CopyDest);
				requireTextureState(src, srcSubresource, ResourceStates.CopySource);
			}
			commitBarriers();

			m_CurrentCmdBuf.referencedResources.Add(src);
			m_CurrentCmdBuf.referencedResources.Add(dst);
			m_CurrentCmdBuf.referencedStagingBuffers.Add(dst.buffer);

			vkCmdCopyImageToBuffer(m_CurrentCmdBuf.cmdBuf, src.image, VkImageLayout.eTransferSrcOptimal,
				dst.buffer.buffer, 1, &imageCopy);
		}

		public override void copyTexture(ITexture _dst, TextureSlice dstSlice,
			ITexture _src, TextureSlice srcSlice)
		{
			TextureVK dst = checked_cast<TextureVK, ITexture>(_dst);
			TextureVK src = checked_cast<TextureVK, ITexture>(_src);

			var resolvedDstSlice = dstSlice.resolve(dst.desc);
			var resolvedSrcSlice = srcSlice.resolve(src.desc);

			Runtime.Assert(m_CurrentCmdBuf != null);

			m_CurrentCmdBuf.referencedResources.Add(dst);
			m_CurrentCmdBuf.referencedResources.Add(src);

			TextureSubresourceSet srcSubresource = TextureSubresourceSet(
				resolvedSrcSlice.mipLevel, 1,
				resolvedSrcSlice.arraySlice, 1
				);

			/*readonly ref*/ var srcSubresourceView = ref src.getSubresourceView(srcSubresource, TextureDimension.Unknown);

			TextureSubresourceSet dstSubresource = TextureSubresourceSet(
				resolvedDstSlice.mipLevel, 1,
				resolvedDstSlice.arraySlice, 1
				);

			/*readonly ref*/ var dstSubresourceView = ref dst.getSubresourceView(dstSubresource, TextureDimension.Unknown);

			var imageCopy = VkImageCopy()
				.setSrcSubresource(VkImageSubresourceLayers()
				.setAspectMask(srcSubresourceView.subresourceRange.aspectMask)
				.setMipLevel(srcSubresource.baseMipLevel)
				.setBaseArrayLayer(srcSubresource.baseArraySlice)
				.setLayerCount(srcSubresource.numArraySlices))
				.setSrcOffset(VkOffset3D() { x = (.)resolvedSrcSlice.x, y = (.)resolvedSrcSlice.y, z = (.)resolvedSrcSlice.z })
				.setDstSubresource(VkImageSubresourceLayers()
				.setAspectMask(dstSubresourceView.subresourceRange.aspectMask)
				.setMipLevel(dstSubresource.baseMipLevel)
				.setBaseArrayLayer(dstSubresource.baseArraySlice)
				.setLayerCount(dstSubresource.numArraySlices))
				.setDstOffset(VkOffset3D() { x = (.)resolvedDstSlice.x, y = (.)resolvedDstSlice.y, z = (.)resolvedDstSlice.z })
				.setExtent(VkExtent3D() { width = resolvedDstSlice.width, height = resolvedDstSlice.height, depth = resolvedDstSlice.depth });


			if (m_EnableAutomaticBarriers)
			{
				requireTextureState(src, TextureSubresourceSet(resolvedSrcSlice.mipLevel, 1, resolvedSrcSlice.arraySlice, 1), ResourceStates.CopySource);
				requireTextureState(dst, TextureSubresourceSet(resolvedDstSlice.mipLevel, 1, resolvedDstSlice.arraySlice, 1), ResourceStates.CopyDest);
			}
			commitBarriers();

			vkCmdCopyImage(m_CurrentCmdBuf.cmdBuf, src.image, VkImageLayout.eTransferSrcOptimal,
				dst.image, VkImageLayout.eTransferDstOptimal,
				1, &imageCopy);
		}

		public override void writeTexture(ITexture _dest, uint32 arraySlice, uint32 mipLevel, void* data, int rowPitch, int depthPitch)
		{
			endRenderPass();

			TextureVK dest = checked_cast<TextureVK, ITexture>(_dest);

			TextureDesc desc = dest.getDesc();

			uint32 mipWidth = 0, mipHeight = 0, mipDepth = 0;
			computeMipLevelInformation(desc, mipLevel, &mipWidth, &mipHeight, &mipDepth);

			readonly ref FormatInfo formatInfo = ref getFormatInfo(desc.format);
			uint32 deviceNumCols = (mipWidth + formatInfo.blockSize - 1) / formatInfo.blockSize;
			uint32 deviceNumRows = (mipHeight + formatInfo.blockSize - 1) / formatInfo.blockSize;
			uint32 deviceRowPitch = deviceNumCols * formatInfo.bytesPerBlock;
			uint32 deviceMemSize = deviceRowPitch * deviceNumRows * mipDepth;

			BufferVK uploadBuffer = null;
			uint64 uploadOffset = 0;
			void* uploadCpuVA = null;
			m_UploadManager.suballocateBuffer(
				deviceMemSize,
				&uploadBuffer,
				&uploadOffset,
				&uploadCpuVA,
				MakeVersion(m_CurrentCmdBuf.recordingID, m_CommandListParameters.queueType, false));

			int minRowPitch = Math.Min(int(deviceRowPitch), rowPitch);
			uint8* mappedPtr = (uint8*)uploadCpuVA;
			for (uint32 slice = 0; slice < mipDepth; slice++)
			{
				/*readonly*/ uint8* sourcePtr = (uint8*)data + depthPitch * slice;
				for (uint32 row = 0; row < deviceNumRows; row++)
				{
					Internal.MemCpy(mappedPtr, sourcePtr, minRowPitch);
					mappedPtr += deviceRowPitch;
					sourcePtr += rowPitch;
				}
			}

			var imageCopy = VkBufferImageCopy()
				.setBufferOffset(uploadOffset)
				.setBufferRowLength(deviceNumCols * formatInfo.blockSize)
				.setBufferImageHeight(deviceNumRows * formatInfo.blockSize)
				.setImageSubresource(VkImageSubresourceLayers()
				.setAspectMask(guessImageAspectFlags(dest.imageInfo.format))
				.setMipLevel(mipLevel)
				.setBaseArrayLayer(arraySlice)
				.setLayerCount(1))
				.setImageExtent(VkExtent3D().setWidth(mipWidth).setHeight(mipHeight).setDepth(mipDepth));

			Runtime.Assert(m_CurrentCmdBuf != null);

			if (m_EnableAutomaticBarriers)
			{
				requireTextureState(dest, TextureSubresourceSet(mipLevel, 1, arraySlice, 1), ResourceStates.CopyDest);
			}
			commitBarriers();

			m_CurrentCmdBuf.referencedResources.Add(dest);

			vkCmdCopyBufferToImage(m_CurrentCmdBuf.cmdBuf, uploadBuffer.buffer,
				dest.image, VkImageLayout.eTransferDstOptimal,
				1, &imageCopy);
		}

		public override void resolveTexture(ITexture _dest, TextureSubresourceSet dstSubresources, ITexture _src, TextureSubresourceSet srcSubresources)
		{
			endRenderPass();

			TextureVK dest = checked_cast<TextureVK, ITexture>(_dest);
			TextureVK src = checked_cast<TextureVK, ITexture>(_src);

			TextureSubresourceSet dstSR = dstSubresources.resolve(dest.desc, false);
			TextureSubresourceSet srcSR = srcSubresources.resolve(src.desc, false);

			if (dstSR.numArraySlices != srcSR.numArraySlices || dstSR.numMipLevels != srcSR.numMipLevels)
				// let the validation layer handle the messages
				return;

			Runtime.Assert(m_CurrentCmdBuf != null);

			List<VkImageResolve> regions = scope .();

			for (MipLevel mipLevel = 0; mipLevel < dstSR.numMipLevels; mipLevel++)
			{
				VkImageSubresourceLayers dstLayers = .() { aspectMask = VkImageAspectFlags.eColorBit, mipLevel = mipLevel + dstSR.baseMipLevel, baseArrayLayer = dstSR.baseArraySlice, layerCount = dstSR.numArraySlices };
				VkImageSubresourceLayers srcLayers = .() { aspectMask = VkImageAspectFlags.eColorBit, mipLevel = mipLevel + srcSR.baseMipLevel, baseArrayLayer = srcSR.baseArraySlice, layerCount = srcSR.numArraySlices };

				regions.Add(VkImageResolve()
					.setSrcSubresource(srcLayers)
					.setDstSubresource(dstLayers)
					.setExtent(VkExtent3D()
					{
						width = dest.desc.width >> dstLayers.mipLevel,
						height = dest.desc.height >> dstLayers.mipLevel,
						depth = dest.desc.depth >> dstLayers.mipLevel
					}));
			}

			if (m_EnableAutomaticBarriers)
			{
				requireTextureState(src, srcSR, ResourceStates.ResolveSource);
				requireTextureState(dest, dstSR, ResourceStates.ResolveDest);
			}
			commitBarriers();

			vkCmdResolveImage(m_CurrentCmdBuf.cmdBuf, src.image, VkImageLayout.eTransferSrcOptimal, dest.image, VkImageLayout.eTransferDstOptimal, (.)regions.Count, regions.Ptr);
		}

		public override void writeBuffer(IBuffer _buffer, void* data, int dataSize, uint64 destOffsetBytes)
		{
			BufferVK buffer = checked_cast<BufferVK, IBuffer>(_buffer);

			Runtime.Assert(dataSize <= (.)buffer.desc.byteSize);

			Runtime.Assert(m_CurrentCmdBuf != null);

			endRenderPass();

			m_CurrentCmdBuf.referencedResources.Add(buffer);

			if (buffer.desc.isVolatile)
			{
				Runtime.Assert(destOffsetBytes == 0);

				writeVolatileBuffer(buffer, data, dataSize);

				return;
			}

			const int commandBufferWriteLimit = 65536;

			if (dataSize <= commandBufferWriteLimit)
			{
				if (m_EnableAutomaticBarriers)
				{
					requireBufferState(buffer, ResourceStates.CopyDest);
				}
				commitBarriers();

				int64 remaining = dataSize;
				char8* @base = (char8*)data;
				while (remaining > 0)
				{
					// vulkan allows <= 64kb transfers via VkCmdUpdateBuffer
					int64 thisGulpSize = Math.Min(remaining, int64(commandBufferWriteLimit));

					// we bloat the read size here past the incoming buffer since the transfer must be a multiple of 4; the extra garbage should never be used anywhere
					thisGulpSize += thisGulpSize % 4;
					vkCmdUpdateBuffer(m_CurrentCmdBuf.cmdBuf, buffer.buffer, ((.)destOffsetBytes + (.)dataSize - (.)remaining), (.)thisGulpSize, &@base[dataSize - remaining]);
					remaining -= thisGulpSize;
				}
			}
			else
			{
				if (buffer.desc.cpuAccess != CpuAccessMode.Write)
				{
					// use the upload manager
					BufferVK uploadBuffer = null;
					uint64 uploadOffset = 0;
					void* uploadCpuVA = null;
					m_UploadManager.suballocateBuffer((.)dataSize, &uploadBuffer, &uploadOffset, &uploadCpuVA, MakeVersion(m_CurrentCmdBuf.recordingID, m_CommandListParameters.queueType, false));

					Internal.MemCpy(uploadCpuVA, data, dataSize);

					copyBuffer(buffer, destOffsetBytes, uploadBuffer, uploadOffset, (.)dataSize);
				}
				else
				{
					m_Context.error("Using writeBuffer on mappable buffers is invalid");
				}
			}
		}

		public override void clearBufferUInt(IBuffer b, uint32 clearValue)
		{
			BufferVK vkbuf = checked_cast<BufferVK, IBuffer>(b);

			Runtime.Assert(m_CurrentCmdBuf != null);

			endRenderPass();

			if (m_EnableAutomaticBarriers)
			{
				requireBufferState(vkbuf, ResourceStates.CopyDest);
			}
			commitBarriers();

			vkCmdFillBuffer(m_CurrentCmdBuf.cmdBuf, vkbuf.buffer, 0, vkbuf.desc.byteSize, clearValue);
			m_CurrentCmdBuf.referencedResources.Add(b);
		}

		public override void copyBuffer(IBuffer _dest, uint64 destOffsetBytes,
			IBuffer _src, uint64 srcOffsetBytes,
			uint64 dataSizeBytes)
		{
			BufferVK dest = checked_cast<BufferVK, IBuffer>(_dest);
			BufferVK src = checked_cast<BufferVK, IBuffer>(_src);

			Runtime.Assert(destOffsetBytes + dataSizeBytes <= dest.desc.byteSize);
			Runtime.Assert(srcOffsetBytes + dataSizeBytes <= src.desc.byteSize);

			Runtime.Assert(m_CurrentCmdBuf != null);

			if (dest.desc.cpuAccess != CpuAccessMode.None)
				m_CurrentCmdBuf.referencedStagingBuffers.Add(dest);
			else
				m_CurrentCmdBuf.referencedResources.Add(dest);

			if (src.desc.cpuAccess != CpuAccessMode.None)
				m_CurrentCmdBuf.referencedStagingBuffers.Add(src);
			else
				m_CurrentCmdBuf.referencedResources.Add(src);

			if (m_EnableAutomaticBarriers)
			{
				requireBufferState(src, ResourceStates.CopySource);
				requireBufferState(dest, ResourceStates.CopyDest);
			}
			commitBarriers();

			var copyRegion = VkBufferCopy()
				.setSize(dataSizeBytes)
				.setSrcOffset(srcOffsetBytes)
				.setDstOffset(destOffsetBytes);

			vkCmdCopyBuffer(m_CurrentCmdBuf.cmdBuf, src.buffer, dest.buffer, 1, &copyRegion);
		}

		public override void setPushConstants(void* data, int byteSize)
		{
			Runtime.Assert(m_CurrentCmdBuf != null);

			vkCmdPushConstants(m_CurrentCmdBuf.cmdBuf, m_CurrentPipelineLayout, m_CurrentPipelineShaderStages, 0, uint32(byteSize), data);
		}

		public override void setGraphicsState(GraphicsState state)
		{
			Runtime.Assert(m_CurrentCmdBuf != null);

			GraphicsPipelineVK pso = checked_cast<GraphicsPipelineVK, IGraphicsPipeline>(state.pipeline);
			FramebufferVK fb = checked_cast<FramebufferVK, IFramebuffer>(state.framebuffer);

			if (m_EnableAutomaticBarriers)
			{
				trackResourcesAndBarriers(state);
			}

			bool anyBarriers = this.anyBarriers();
			bool updatePipeline = false;

			if (m_CurrentGraphicsState.pipeline != state.pipeline)
			{
				vkCmdBindPipeline(m_CurrentCmdBuf.cmdBuf, VkPipelineBindPoint.eGraphics, pso.pipeline);

				m_CurrentCmdBuf.referencedResources.Add(state.pipeline);
				updatePipeline = true;
			}

			if (m_CurrentGraphicsState.framebuffer != state.framebuffer || anyBarriers /* because barriers cannot be set inside a renderpass */)
			{
				endRenderPass();
			}

			var desc = state.framebuffer.getDesc();
			if (desc.shadingRateAttachment.valid())
			{
				setTextureState(desc.shadingRateAttachment.texture, nvrhi.TextureSubresourceSet(0, 1, 0, 1), nvrhi.ResourceStates.ShadingRateSurface);
			}

			commitBarriers();

			if (m_CurrentGraphicsState.framebuffer == null)
			{
				var beginInfo = VkRenderPassBeginInfo()
					.setRenderPass(fb.renderPass)
					.setFramebuffer(fb.framebuffer)
					.setRenderArea(VkRect2D()
					.setOffset(VkOffset2D(0, 0))
					.setExtent(VkExtent2D(fb.framebufferInfo.width, fb.framebufferInfo.height)))
					.setClearValueCount(0);

				vkCmdBeginRenderPass(m_CurrentCmdBuf.cmdBuf, &beginInfo,
					VkSubpassContents.eInline);

				m_CurrentCmdBuf.referencedResources.Add(state.framebuffer);
			}

			m_CurrentPipelineLayout = pso.pipelineLayout;
			m_CurrentPipelineShaderStages = convertShaderTypeToShaderStageFlagBits(pso.shaderMask);

			if (arraysAreDifferent(m_CurrentComputeState.bindings, state.bindings) || m_AnyVolatileBufferWrites)
			{
				bindBindingSets(VkPipelineBindPoint.eGraphics, pso.pipelineLayout, state.bindings);
			}

			if (!state.viewport.viewports.IsEmpty && arraysAreDifferent(state.viewport.viewports, m_CurrentGraphicsState.viewport.viewports))
			{
				nvrhi.StaticVector<VkViewport, const c_MaxViewports> viewports = .();
				for ( /*readonly ref*/var vp in ref state.viewport.viewports)
				{
					viewports.PushBack(VKViewportWithDXCoords(vp));
				}

				vkCmdSetViewport(m_CurrentCmdBuf.cmdBuf, 0, uint32(viewports.Count), viewports.Ptr);
			}

			if (!state.viewport.scissorRects.IsEmpty && arraysAreDifferent(state.viewport.scissorRects, m_CurrentGraphicsState.viewport.scissorRects))
			{
				nvrhi.StaticVector<VkRect2D, const c_MaxViewports> scissors = .();
				for ( /*readonly ref*/var sc in ref state.viewport.scissorRects)
				{
					scissors.PushBack(VkRect2D(VkOffset2D(sc.minX, sc.minY),
						VkExtent2D(Math.Abs(sc.maxX - sc.minX), Math.Abs(sc.maxY - sc.minY))));
				}

				vkCmdSetScissor(m_CurrentCmdBuf.cmdBuf, 0, uint32(scissors.Count), scissors.Ptr);
			}

			if (pso.usesBlendConstants && (updatePipeline || m_CurrentGraphicsState.blendConstantColor != state.blendConstantColor))
			{
				vkCmdSetBlendConstants(m_CurrentCmdBuf.cmdBuf, .(state.blendConstantColor.r, state.blendConstantColor.g, state.blendConstantColor.b, state.blendConstantColor.a));
			}

			if (state.indexBuffer.buffer != null && m_CurrentGraphicsState.indexBuffer != state.indexBuffer)
			{
				vkCmdBindIndexBuffer(m_CurrentCmdBuf.cmdBuf, checked_cast<BufferVK, IBuffer>(state.indexBuffer.buffer).buffer,
					state.indexBuffer.offset, state.indexBuffer.format == Format.R16_UINT ?
					VkIndexType.eUint16 : VkIndexType.eUint32);

				m_CurrentCmdBuf.referencedResources.Add(state.indexBuffer.buffer);
			}

			if (!state.vertexBuffers.IsEmpty && arraysAreDifferent(state.vertexBuffers, m_CurrentGraphicsState.vertexBuffers))
			{
				StaticVector<VkBuffer, const c_MaxVertexAttributes> vertexBuffers = .();
				StaticVector<uint64, const c_MaxVertexAttributes> vertexBufferOffsets = .();

				for ( /*readonly ref*/var vb in ref state.vertexBuffers)
				{
					vertexBuffers.PushBack(checked_cast<BufferVK, IBuffer>(vb.buffer).buffer);
					vertexBufferOffsets.PushBack(vb.offset);

					m_CurrentCmdBuf.referencedResources.Add(vb.buffer);
				}

				vkCmdBindVertexBuffers(m_CurrentCmdBuf.cmdBuf, 0, uint32(vertexBuffers.Count), vertexBuffers.Ptr, vertexBufferOffsets.Ptr);
			}

			if (state.indirectParams != null)
			{
				m_CurrentCmdBuf.referencedResources.Add(state.indirectParams);
			}

			if (state.shadingRateState.enabled)
			{
				VkFragmentShadingRateCombinerOpKHR[2] combiners = .(convertShadingRateCombiner(state.shadingRateState.pipelinePrimitiveCombiner), convertShadingRateCombiner(state.shadingRateState.imageCombiner));
				VkExtent2D shadingRate = convertFragmentShadingRate(state.shadingRateState.shadingRate);
				vkCmdSetFragmentShadingRateKHR(m_CurrentCmdBuf.cmdBuf, &shadingRate, combiners);
			}

			m_CurrentGraphicsState = state;
			m_CurrentComputeState = ComputeState();
			m_CurrentMeshletState = MeshletState();
			m_CurrentRayTracingState = nvrhi.rt.State();
			m_AnyVolatileBufferWrites = false;
		}

		public override void draw(DrawArguments args)
		{
			Runtime.Assert(m_CurrentCmdBuf != null);

			updateGraphicsVolatileBuffers();

			vkCmdDraw(m_CurrentCmdBuf.cmdBuf, args.vertexCount,
				args.instanceCount,
				args.startVertexLocation,
				args.startInstanceLocation);
		}

		public override void drawIndexed(DrawArguments args)
		{
			Runtime.Assert(m_CurrentCmdBuf != null);

			updateGraphicsVolatileBuffers();

			vkCmdDrawIndexed(m_CurrentCmdBuf.cmdBuf, args.vertexCount,
				args.instanceCount,
				args.startIndexLocation,
				(.)args.startVertexLocation,
				args.startInstanceLocation);
		}

		public override void drawIndirect(uint32 offsetBytes)
		{
			Runtime.Assert(m_CurrentCmdBuf != null);

			updateGraphicsVolatileBuffers();

			BufferVK indirectParams = checked_cast<BufferVK, IBuffer>(m_CurrentGraphicsState.indirectParams);
			Runtime.Assert(indirectParams != null);

			// TODO: is this right?
			vkCmdDrawIndirect(m_CurrentCmdBuf.cmdBuf, indirectParams.buffer, offsetBytes, 1, 0);
		}

		public override void setComputeState(ComputeState state)
		{
			endRenderPass();

			Runtime.Assert(m_CurrentCmdBuf != null);

			ComputePipelineVK pso = checked_cast<ComputePipelineVK, IComputePipeline>(state.pipeline);

			if (m_EnableAutomaticBarriers && arraysAreDifferent(state.bindings, m_CurrentComputeState.bindings))
			{
				for (int i = 0; i < state.bindings.Count && i < pso.desc.bindingLayouts.Count; i++)
				{
					BindingLayoutVK layout = pso.pipelineBindingLayouts[i].Get<BindingLayoutVK>();

					if ((layout.desc.visibility & ShaderType.Compute) == 0)
						continue;

					if (m_EnableAutomaticBarriers)
					{
						setResourceStatesForBindingSet(state.bindings[i]);
					}
				}
			}

			if (m_CurrentComputeState.pipeline != state.pipeline)
			{
				vkCmdBindPipeline(m_CurrentCmdBuf.cmdBuf, VkPipelineBindPoint.eCompute, pso.pipeline);

				m_CurrentCmdBuf.referencedResources.Add(state.pipeline);
			}

			if (arraysAreDifferent(m_CurrentComputeState.bindings, state.bindings) || m_AnyVolatileBufferWrites)
			{
				bindBindingSets(VkPipelineBindPoint.eCompute, pso.pipelineLayout, state.bindings);
			}

			m_CurrentPipelineLayout = pso.pipelineLayout;
			m_CurrentPipelineShaderStages = VkShaderStageFlags.eComputeBit;

			if (state.indirectParams != null && state.indirectParams != m_CurrentComputeState.indirectParams)
			{
				BufferVK indirectParams = checked_cast<BufferVK, IBuffer>(state.indirectParams);

				m_CurrentCmdBuf.referencedResources.Add(state.indirectParams);

				if (m_EnableAutomaticBarriers)
				{
					requireBufferState(indirectParams, ResourceStates.IndirectArgument);
				}
			}

			commitBarriers();

			m_CurrentGraphicsState = GraphicsState();
			m_CurrentComputeState = state;
			m_CurrentMeshletState = MeshletState();
			m_CurrentRayTracingState = .();
			m_AnyVolatileBufferWrites = false;
		}
		public override void dispatch(uint32 groupsX, uint32 groupsY, uint32 groupsZ)
		{
			Runtime.Assert(m_CurrentCmdBuf != null);

			updateComputeVolatileBuffers();

			vkCmdDispatch(m_CurrentCmdBuf.cmdBuf, groupsX, groupsY, groupsZ);
		}
		public override void dispatchIndirect(uint32 offsetBytes)
		{
			Runtime.Assert(m_CurrentCmdBuf != null);

			updateComputeVolatileBuffers();

			BufferVK indirectParams = checked_cast<BufferVK, IBuffer>(m_CurrentComputeState.indirectParams);
			Runtime.Assert(indirectParams != null);

			vkCmdDispatchIndirect(m_CurrentCmdBuf.cmdBuf, indirectParams.buffer, offsetBytes);
		}

		public override void setMeshletState(MeshletState state)
		{
			Runtime.Assert(m_CurrentCmdBuf != null);

			MeshletPipelineVK pso = checked_cast<MeshletPipelineVK, IMeshletPipeline>(state.pipeline);
			FramebufferVK fb = checked_cast<FramebufferVK, IFramebuffer>(state.framebuffer);

			if (m_EnableAutomaticBarriers)
			{
				trackResourcesAndBarriers(state);
			}

			bool anyBarriers = this.anyBarriers();
			bool updatePipeline = false;

			if (m_CurrentMeshletState.pipeline != state.pipeline)
			{
				vkCmdBindPipeline(m_CurrentCmdBuf.cmdBuf, VkPipelineBindPoint.eGraphics, pso.pipeline);

				m_CurrentCmdBuf.referencedResources.Add(state.pipeline);
				updatePipeline = true;
			}

			if (m_CurrentMeshletState.framebuffer != state.framebuffer || anyBarriers /* because barriers cannot be set inside a renderpass */)
			{
				endRenderPass();
			}

			commitBarriers();

			if (m_CurrentMeshletState.framebuffer == null)
			{
				var beginInfo = VkRenderPassBeginInfo()
					.setRenderPass(fb.renderPass)
					.setFramebuffer(fb.framebuffer)
					.setRenderArea(VkRect2D()
					.setOffset(VkOffset2D(0, 0))
					.setExtent(VkExtent2D(fb.framebufferInfo.width, fb.framebufferInfo.height)))
					.setClearValueCount(0);

				vkCmdBeginRenderPass(m_CurrentCmdBuf.cmdBuf, &beginInfo,
					VkSubpassContents.eInline);

				m_CurrentCmdBuf.referencedResources.Add(state.framebuffer);
			}

			m_CurrentPipelineLayout = pso.pipelineLayout;
			m_CurrentPipelineShaderStages = convertShaderTypeToShaderStageFlagBits(pso.shaderMask);

			if (arraysAreDifferent(m_CurrentComputeState.bindings, state.bindings) || m_AnyVolatileBufferWrites)
			{
				bindBindingSets(VkPipelineBindPoint.eGraphics, pso.pipelineLayout, state.bindings);
			}

			if (!state.viewport.viewports.IsEmpty && arraysAreDifferent(state.viewport.viewports, m_CurrentMeshletState.viewport.viewports))
			{
				nvrhi.StaticVector<VkViewport, const c_MaxViewports> viewports = .();
				for ( /*readonly ref*/var vp in ref state.viewport.viewports)
				{
					viewports.PushBack(VKViewportWithDXCoords(vp));
				}

				vkCmdSetViewport(m_CurrentCmdBuf.cmdBuf, 0, uint32(viewports.Count), viewports.Ptr);
			}

			if (!state.viewport.scissorRects.IsEmpty && arraysAreDifferent(state.viewport.scissorRects, m_CurrentMeshletState.viewport.scissorRects))
			{
				nvrhi.StaticVector<VkRect2D, const c_MaxViewports> scissors = .();
				for ( /*readonly ref*/var sc in ref state.viewport.scissorRects)
				{
					scissors.PushBack(VkRect2D(VkOffset2D(sc.minX, sc.minY),
						VkExtent2D(Math.Abs(sc.maxX - sc.minX), Math.Abs(sc.maxY - sc.minY))));
				}

				vkCmdSetScissor(m_CurrentCmdBuf.cmdBuf, 0, uint32(scissors.Count), scissors.Ptr);
			}

			if (pso.usesBlendConstants && (updatePipeline || m_CurrentMeshletState.blendConstantColor != state.blendConstantColor))
			{
				vkCmdSetBlendConstants(m_CurrentCmdBuf.cmdBuf, .(state.blendConstantColor.r, state.blendConstantColor.g, state.blendConstantColor.b, state.blendConstantColor.a));
			}

			if (state.indirectParams != null)
			{
				m_CurrentCmdBuf.referencedResources.Add(state.indirectParams);
			}

			m_CurrentComputeState = ComputeState();
			m_CurrentGraphicsState = GraphicsState();
			m_CurrentMeshletState = state;
			m_CurrentRayTracingState = nvrhi.rt.State();
			m_AnyVolatileBufferWrites = false;
		}

		public override void dispatchMesh(uint32 groupsX, uint32 groupsY = 1, uint32 groupsZ = 1)
		{
			Runtime.Assert(m_CurrentCmdBuf != null);

			if (groupsY > 1 || groupsZ > 1)
			{
				// only 1D dispatches are supported by Vulkan
				utils.NotSupported();
				return;
			}

			updateMeshletVolatileBuffers();

			vkCmdDrawMeshTasksNV(m_CurrentCmdBuf.cmdBuf, groupsX, 0);
		}

		public override void setRayTracingState(nvrhi.rt.State state)
		{
			if (state.shaderTable == null)
				return;

			ShaderTable shaderTable = checked_cast<ShaderTable, IShaderTable>(state.shaderTable);
			RayTracingPipelineVK pso = shaderTable.pipeline;

			if (shaderTable.rayGenerationShader < 0)
			{
				m_Context.error("The STB does not have a valid RayGen shader set");
				return;
			}

			if (m_EnableAutomaticBarriers)
			{
				for (int i = 0; i < state.bindings.Count && i < pso.desc.globalBindingLayouts.Count; i++)
				{
					BindingLayoutVK layout = pso.pipelineBindingLayouts[i].Get<BindingLayoutVK>();

					if ((layout.desc.visibility & ShaderType.AllRayTracing) == 0)
						continue;

					setResourceStatesForBindingSet(state.bindings[i]);
				}
			}

			if (m_CurrentRayTracingState.shaderTable != state.shaderTable)
			{
				m_CurrentCmdBuf.referencedResources.Add(state.shaderTable);
			}

			if (m_CurrentRayTracingState.shaderTable == null || m_CurrentRayTracingState.shaderTable.getPipeline() != pso)
			{
				vkCmdBindPipeline(m_CurrentCmdBuf.cmdBuf, VkPipelineBindPoint.eRayTracingKHR, pso.pipeline);
				m_CurrentPipelineLayout = pso.pipelineLayout;
				m_CurrentPipelineShaderStages = convertShaderTypeToShaderStageFlagBits(ShaderType.AllRayTracing);
			}

			if (arraysAreDifferent(m_CurrentRayTracingState.bindings, state.bindings) || m_AnyVolatileBufferWrites)
			{
				bindBindingSets(VkPipelineBindPoint.eRayTracingKHR, pso.pipelineLayout, state.bindings);
			}

			// Rebuild the SBT if we're binding a new one or if it's been changed since the previous bind.

			if (m_CurrentRayTracingState.shaderTable != shaderTable || m_CurrentShaderTablePointers.version != shaderTable.version)
			{
				readonly uint32 shaderGroupHandleSize = m_Context.rayTracingPipelineProperties.shaderGroupHandleSize;
				readonly uint32 shaderGroupBaseAlignment = m_Context.rayTracingPipelineProperties.shaderGroupBaseAlignment;

				readonly uint32 shaderTableSize = shaderTable.getNumEntries() * shaderGroupBaseAlignment;

				// First, allocate a piece of the upload buffer. That will be our SBT on the device.

				BufferVK uploadBuffer = null;
				uint64 uploadOffset = 0;
				uint8* uploadCpuVA = null;
				bool allocated = m_UploadManager.suballocateBuffer(shaderTableSize, &uploadBuffer, &uploadOffset, (void**)&uploadCpuVA,
					MakeVersion(m_CurrentCmdBuf.recordingID, m_CommandListParameters.queueType, false),
					shaderGroupBaseAlignment);

				if (!allocated)
				{
					m_Context.error("Failed to suballocate an upload buffer for the SBT");
					return;
				}

				Runtime.Assert(uploadCpuVA != null);
				Runtime.Assert(uploadBuffer != null);

				// Copy the shader and group handles into the device SBT, record the pointers.

				VkStridedDeviceAddressRegionKHR rayGenHandle = .();
				VkStridedDeviceAddressRegionKHR missHandles = .();
				VkStridedDeviceAddressRegionKHR hitGroupHandles = .();
				VkStridedDeviceAddressRegionKHR callableHandles = .();

				// ... RayGen

				uint32 sbtIndex = 0;
				Internal.MemCpy(uploadCpuVA + sbtIndex * shaderGroupBaseAlignment,
					pso.shaderGroupHandles.Ptr + shaderGroupHandleSize * (.)shaderTable.rayGenerationShader,
					shaderGroupHandleSize);
				rayGenHandle.setDeviceAddress(uploadBuffer.deviceAddress + uploadOffset + sbtIndex * shaderGroupBaseAlignment);
				rayGenHandle.setSize(shaderGroupBaseAlignment);
				rayGenHandle.setStride(shaderGroupBaseAlignment);
				sbtIndex++;

				// ... Miss

				if (!shaderTable.missShaders.IsEmpty)
				{
					missHandles.setDeviceAddress(uploadBuffer.deviceAddress + uploadOffset + sbtIndex * shaderGroupBaseAlignment);
					for (uint32 shaderGroupIndex in shaderTable.missShaders)
					{
						Internal.MemCpy(uploadCpuVA + sbtIndex * shaderGroupBaseAlignment,
							pso.shaderGroupHandles.Ptr + shaderGroupHandleSize * shaderGroupIndex,
							shaderGroupHandleSize);
						sbtIndex++;
					}
					missHandles.setSize(shaderGroupBaseAlignment * uint32(shaderTable.hitGroups.Count));
					missHandles.setStride(shaderGroupBaseAlignment);
				}

				// ... Hit Groups

				if (!shaderTable.hitGroups.IsEmpty)
				{
					hitGroupHandles.setDeviceAddress(uploadBuffer.deviceAddress + uploadOffset + sbtIndex * shaderGroupBaseAlignment);
					for (uint32 shaderGroupIndex in shaderTable.hitGroups)
					{
						Internal.MemCpy(uploadCpuVA + sbtIndex * shaderGroupBaseAlignment,
							pso.shaderGroupHandles.Ptr + shaderGroupHandleSize * shaderGroupIndex,
							shaderGroupHandleSize);
						sbtIndex++;
					}
					hitGroupHandles.setSize(shaderGroupBaseAlignment * uint32(shaderTable.hitGroups.Count));
					hitGroupHandles.setStride(shaderGroupBaseAlignment);
				}

				// ... Callable

				if (!shaderTable.callableShaders.IsEmpty)
				{
					callableHandles.setDeviceAddress(uploadBuffer.deviceAddress + uploadOffset + sbtIndex * shaderGroupBaseAlignment);
					for (uint32 shaderGroupIndex in shaderTable.callableShaders)
					{
						Internal.MemCpy(uploadCpuVA + sbtIndex * shaderGroupBaseAlignment,
							pso.shaderGroupHandles.Ptr + shaderGroupHandleSize * shaderGroupIndex,
							shaderGroupHandleSize);
						sbtIndex++;
					}
					callableHandles.setSize(shaderGroupBaseAlignment * uint32(shaderTable.callableShaders.Count));
					callableHandles.setStride(shaderGroupBaseAlignment);
				}

				// Store the device pointers to the SBT for use in dispatchRays later, and the version.

				m_CurrentShaderTablePointers.rayGen = rayGenHandle;
				m_CurrentShaderTablePointers.miss = missHandles;
				m_CurrentShaderTablePointers.hitGroups = hitGroupHandles;
				m_CurrentShaderTablePointers.callable = callableHandles;
				m_CurrentShaderTablePointers.version = shaderTable.version;
			}

			commitBarriers();

			m_CurrentGraphicsState = GraphicsState();
			m_CurrentComputeState = ComputeState();
			m_CurrentMeshletState = MeshletState();
			m_CurrentRayTracingState = state;
			m_AnyVolatileBufferWrites = false;
		}

		public override void dispatchRays(nvrhi.rt.DispatchRaysArguments args)
		{
			Runtime.Assert(m_CurrentCmdBuf != null);

			updateRayTracingVolatileBuffers();

			vkCmdTraceRaysKHR(m_CurrentCmdBuf.cmdBuf,
				&m_CurrentShaderTablePointers.rayGen,
				&m_CurrentShaderTablePointers.miss,
				&m_CurrentShaderTablePointers.hitGroups,
				&m_CurrentShaderTablePointers.callable,
				args.width, args.height, args.depth);
		}

		public override void buildBottomLevelAccelStruct(nvrhi.rt.IAccelStruct _as, nvrhi.rt.GeometryDesc* pGeometries, int numGeometries, nvrhi.rt.AccelStructBuildFlags buildFlags)
		{
			AccelStructVK @as = checked_cast<AccelStructVK, IAccelStruct>(_as);

			readonly bool performUpdate = (buildFlags & nvrhi.rt.AccelStructBuildFlags.PerformUpdate) != 0;
			if (performUpdate)
			{
				Runtime.Assert(@as.allowUpdate);
			}

			List<VkAccelerationStructureGeometryKHR> geometries = scope .();
			List<VkAccelerationStructureBuildRangeInfoKHR> buildRanges = scope .();
			List<uint32> maxPrimitiveCounts = scope .();
			geometries.Resize(numGeometries);
			maxPrimitiveCounts.Resize(numGeometries);
			buildRanges.Resize(numGeometries);

			for (int i = 0; i < numGeometries; i++)
			{
				convertBottomLevelGeometry(pGeometries[i], ref geometries[i], ref maxPrimitiveCounts[i], &buildRanges[i], m_Context);

				readonly ref GeometryDesc src = ref pGeometries[i];

				switch (src.geometryType)
				{
				case nvrhi.rt.GeometryType.Triangles:
					{
						readonly ref GeometryTriangles srct = ref src.geometryData.triangles;
						if (m_EnableAutomaticBarriers)
						{
							if (srct.indexBuffer != null)
								requireBufferState(srct.indexBuffer, nvrhi.ResourceStates.AccelStructBuildInput);
							if (srct.vertexBuffer != null)
								requireBufferState(srct.vertexBuffer, nvrhi.ResourceStates.AccelStructBuildInput);
						}
						break;
					}
				case nvrhi.rt.GeometryType.AABBs:
					{
						readonly ref nvrhi.rt.GeometryAABBs srca = ref src.geometryData.aabbs;
						if (m_EnableAutomaticBarriers)
						{
							if (srca.buffer != null)
								requireBufferState(srca.buffer, nvrhi.ResourceStates.AccelStructBuildInput);
						}
						break;
					}
				}
			}

			var buildInfo = VkAccelerationStructureBuildGeometryInfoKHR()
				.setType(VkAccelerationStructureTypeKHR.eBottomLevelKHR)
				.setMode(performUpdate ? VkBuildAccelerationStructureModeKHR.eUpdateKHR : VkBuildAccelerationStructureModeKHR.eBuildKHR)
				.setPGeometries(geometries.Ptr)
				.setFlags(convertAccelStructBuildFlags(buildFlags))
				.setDstAccelerationStructure(@as.accelStruct);

			if (@as.allowUpdate)
				buildInfo.flags |= VkBuildAccelerationStructureFlagsKHR.eAllowUpdateBitKHR;

			if (performUpdate)
				buildInfo.setSrcAccelerationStructure(@as.accelStruct);

#if NVRHI_WITH_RTXMU
			commitBarriers();

			std::array<VkAccelerationStructureBuildGeometryInfoKHR, 1> buildInfos = { buildInfo };
			std::array<const VkAccelerationStructureBuildRangeInfoKHR*, 1> buildRangeArrays = { buildRanges.Ptr };
			std::array<const uint32*, 1> maxPrimArrays = { maxPrimitiveCounts.Ptr };

			if(@as.rtxmuId == ~0uL)
			{
				List<uint64> accelStructsToBuild;
				m_Context.rtxMemUtil.PopulateBuildCommandList(m_CurrentCmdBuf.cmdBuf,
															   buildInfos.Ptr,
															   buildRangeArrays.Ptr,
															   maxPrimArrays.Ptr,
															   (uint32)buildInfos.Count,
															   accelStructsToBuild);


				@as.rtxmuId = accelStructsToBuild[0];
			
				@as.rtxmuBuffer = m_Context.rtxMemUtil.GetBuffer(@as.rtxmuId);
				@as.accelStruct = m_Context.rtxMemUtil.GetAccelerationStruct(@as.rtxmuId);
				@as.accelStructDeviceAddress = m_Context.rtxMemUtil.GetDeviceAddress(@as.rtxmuId);

				m_CurrentCmdBuf.rtxmuBuildIds.push_back(@as.rtxmuId);
			}
			else
			{
				List<uint64> buildsToUpdate(1, @as.rtxmuId);

				m_Context.rtxMemUtil.PopulateUpdateCommandList(m_CurrentCmdBuf.cmdBuf,
																buildInfos.Ptr,
																buildRangeArrays.Ptr,
																(uint32)buildInfos.Count,
																buildsToUpdate);
			}
#else

			if (m_EnableAutomaticBarriers)
			{
				requireBufferState(@as.dataBuffer, nvrhi.ResourceStates.AccelStructWrite);
			}
			commitBarriers();

			VkAccelerationStructureBuildSizesInfoKHR buildSizes = .();
			vkGetAccelerationStructureBuildSizesKHR(m_Context.device,
				VkAccelerationStructureBuildTypeKHR.eDeviceKHR, &buildInfo, maxPrimitiveCounts.Ptr, &buildSizes);

			if (buildSizes.accelerationStructureSize > @as.dataBuffer.Get<IBuffer>().getDesc().byteSize)
			{
				String message = scope $"BLAS {utils.DebugNameToString(@as.desc.debugName)} build requires at least {buildSizes.accelerationStructureSize} bytes in the data buffer, while the allocated buffer is only {@as.dataBuffer.Get<IBuffer>().getDesc().byteSize} bytes";

				m_Context.error(message);
				return;
			}

			var scratchSize = performUpdate
				? buildSizes.updateScratchSize
				: buildSizes.buildScratchSize;

			BufferVK scratchBuffer = null;
			uint64 scratchOffset = 0;
			uint64 currentVersion = MakeVersion(m_CurrentCmdBuf.recordingID, m_CommandListParameters.queueType, false);

			bool allocated = m_ScratchManager.suballocateBuffer(scratchSize, &scratchBuffer, &scratchOffset, null,
				currentVersion, m_Context.accelStructProperties.minAccelerationStructureScratchOffsetAlignment);

			if (!allocated)
			{
				String message = scope $"Couldn't suballocate a scratch buffer for BLAS {utils.DebugNameToString(@as.desc.debugName)} build. The build requires {scratchSize} bytes of scratch space.";

				m_Context.error(message);
				return;
			}

			Runtime.Assert(scratchBuffer.deviceAddress != 0);
			buildInfo.setScratchData(VkDeviceOrHostAddressKHR().setDeviceAddress(scratchBuffer.deviceAddress + scratchOffset));

			VkAccelerationStructureBuildGeometryInfoKHR[1] buildInfos = .(buildInfo);
			VkAccelerationStructureBuildRangeInfoKHR*[1] buildRangeArrays = .(buildRanges.Ptr);

			vkCmdBuildAccelerationStructuresKHR(m_CurrentCmdBuf.cmdBuf, buildInfos.Count, &buildInfos, &buildRangeArrays);
#endif
			if (@as.desc.trackLiveness)
				m_CurrentCmdBuf.referencedResources.Add(@as);
		}

		public override void compactBottomLevelAccelStructs()
		{
#if NVRHI_WITH_RTXMU

			if (!m_Context.rtxMuResources.asBuildsCompletedIsEmpty)
			{
				std::lock_guard lockGuard(m_Context.rtxMuResources.asListMutex);

				if (!m_Context.rtxMuResources.asBuildsCompletedIsEmpty)
				{
					m_Context.rtxMemUtil.PopulateCompactionCommandList(m_CurrentCmdBuf.cmdBuf, m_Context.rtxMuResources.asBuildsCompleted);

					m_CurrentCmdBuf.rtxmuCompactionIds.insert(m_CurrentCmdBuf.rtxmuCompactionIds.end(), m_Context.rtxMuResources.asBuildsCompleted.begin(), m_Context.rtxMuResources.asBuildsCompleted.end());

					m_Context.rtxMuResources.asBuildsCompleted.clear();
				}
			}
#endif
		}

		public override void buildTopLevelAccelStruct(nvrhi.rt.IAccelStruct _as, nvrhi.rt.InstanceDesc* pInstances, int numInstances, nvrhi.rt.AccelStructBuildFlags buildFlags)
		{
			AccelStructVK @as = checked_cast<AccelStructVK, IAccelStruct>(_as);

			@as.instances.Resize(numInstances);

			for (int i = 0; i < numInstances; i++)
			{
				readonly ref InstanceDesc src = ref pInstances[i];
				ref VkAccelerationStructureInstanceKHR dst = ref @as.instances[i];

				AccelStructVK blas = checked_cast<AccelStructVK, IAccelStruct>(src.bottomLevelAS);
#if NVRHI_WITH_RTXMU
				blas.rtxmuBuffer = m_Context.rtxMemUtil.GetBuffer(blas.rtxmuId);
				blas.accelStruct = m_Context.rtxMemUtil.GetAccelerationStruct(blas.rtxmuId);
				blas.accelStructDeviceAddress = m_Context.rtxMemUtil.GetDeviceAddress(blas.rtxmuId);
				dst.setAccelerationStructureReference(blas.accelStructDeviceAddress);
#else
				dst.setAccelerationStructureReference(blas.accelStructDeviceAddress);
#endif
				dst.setInstanceCustomIndex(src.instanceID);
				dst.setInstanceShaderBindingTableRecordOffset(src.instanceContributionToHitGroupIndex * m_Context.rayTracingPipelineProperties.shaderGroupBaseAlignment);
				dst.setFlags(convertInstanceFlags(src.flags));
				dst.setMask(src.instanceMask);
				var src;
				Internal.MemCpy(&dst.transform.matrix, &src.transform, sizeof(float) * 12);

#if !NVRHI_WITH_RTXMU
				if (m_EnableAutomaticBarriers)
				{
					requireBufferState(blas.dataBuffer, nvrhi.ResourceStates.AccelStructBuildBlas);
				}
#endif
			}

#if NVRHI_WITH_RTXMU
			m_Context.rtxMemUtil.PopulateUAVBarriersCommandList(m_CurrentCmdBuf.cmdBuf, m_CurrentCmdBuf.rtxmuBuildIds);
#endif

			uint64 currentVersion = MakeVersion(m_CurrentCmdBuf.recordingID, m_CommandListParameters.queueType, false);

			BufferVK uploadBuffer = null;
			uint64 uploadOffset = 0;
			void* uploadCpuVA = null;
			m_UploadManager.suballocateBuffer((uint64)@as.instances.Count * sizeof(VkAccelerationStructureInstanceKHR),
				&uploadBuffer, &uploadOffset, &uploadCpuVA, currentVersion);

			// Copy the instance data to GPU-visible memory.
			// The VkAccelerationStructureInstanceKHR struct should be directly copyable, but ReSharper/clang thinks it's not,
			// so the inspection is disabled with a comment below.
			Internal.MemCpy(uploadCpuVA, @as.instances.Ptr, // NOLINT(bugprone-undefined-memory-manipulation)
				@as.instances.Count * sizeof(VkAccelerationStructureInstanceKHR));

			if (m_EnableAutomaticBarriers)
			{
				requireBufferState(@as.dataBuffer, nvrhi.ResourceStates.AccelStructWrite);
			}
			commitBarriers();

			buildTopLevelAccelStructInternal(@as, uploadBuffer.deviceAddress + uploadOffset, numInstances, buildFlags, currentVersion);

			if (@as.desc.trackLiveness)
				m_CurrentCmdBuf.referencedResources.Add(@as);
		}

		public override void buildTopLevelAccelStructFromBuffer(nvrhi.rt.IAccelStruct _as, nvrhi.IBuffer _instanceBuffer, uint64 instanceBufferOffset, int numInstances, nvrhi.rt.AccelStructBuildFlags buildFlags)
		{
			AccelStructVK @as = checked_cast<AccelStructVK, IAccelStruct>(_as);
			BufferVK instanceBuffer = checked_cast<BufferVK, IBuffer>(_instanceBuffer);

			@as.instances.Clear();

			if (m_EnableAutomaticBarriers)
			{
				requireBufferState(@as.dataBuffer, ResourceStates.AccelStructWrite);
				requireBufferState(instanceBuffer, ResourceStates.AccelStructBuildInput);
			}
			commitBarriers();

			uint64 currentVersion = MakeVersion(m_CurrentCmdBuf.recordingID, m_CommandListParameters.queueType, false);

			buildTopLevelAccelStructInternal(@as, instanceBuffer.deviceAddress + instanceBufferOffset, numInstances, buildFlags, currentVersion);

			if (@as.desc.trackLiveness)
				m_CurrentCmdBuf.referencedResources.Add(@as);
		}


		public override void beginTimerQuery(ITimerQuery _query)
		{
			endRenderPass();

			TimerQueryVK query = checked_cast<TimerQueryVK, ITimerQuery>(_query);

			Runtime.Assert(query.beginQueryIndex >= 0);
			Runtime.Assert(!query.started);
			Runtime.Assert(m_CurrentCmdBuf != null);

			query.resolved = false;

			vkCmdResetQueryPool(m_CurrentCmdBuf.cmdBuf, m_Device.getTimerQueryPool(), (.)query.beginQueryIndex, 2);
			vkCmdWriteTimestamp(m_CurrentCmdBuf.cmdBuf, VkPipelineStageFlags.eBottomOfPipeBit, m_Device.getTimerQueryPool(), (.)query.beginQueryIndex);
		}
		public override void endTimerQuery(ITimerQuery _query)
		{
			endRenderPass();

			TimerQueryVK query = checked_cast<TimerQueryVK, ITimerQuery>(_query);

			Runtime.Assert(query.endQueryIndex >= 0);
			Runtime.Assert(!query.started);
			Runtime.Assert(!query.resolved);

			Runtime.Assert(m_CurrentCmdBuf != null);

			vkCmdWriteTimestamp(m_CurrentCmdBuf.cmdBuf, VkPipelineStageFlags.eBottomOfPipeBit, m_Device.getTimerQueryPool(), (.)query.endQueryIndex);
			query.started = true;
		}

		public override void beginMarker(char8* name)
		{
			if (m_Context.extensions.EXT_debug_marker)
			{
				Runtime.Assert(m_CurrentCmdBuf != null);

				var markerInfo = VkDebugMarkerMarkerInfoEXT()
					.setPMarkerName(name);
				vkCmdDebugMarkerBeginEXT(m_CurrentCmdBuf.cmdBuf, &markerInfo);
			}
		}
		public override void endMarker()
		{
			if (m_Context.extensions.EXT_debug_marker)
			{
				Runtime.Assert(m_CurrentCmdBuf != null);

				vkCmdDebugMarkerEndEXT(m_CurrentCmdBuf.cmdBuf);
			}
		}

		public override void setEnableAutomaticBarriers(bool enable)
		{
			m_EnableAutomaticBarriers = enable;
		}
		public override  void setResourceStatesForBindingSet(IBindingSet _bindingSet)
		{
			if (_bindingSet.getDesc() == null)
				return; // is bindless

			BindingSetVK bindingSet = checked_cast<BindingSetVK, IBindingSet>(_bindingSet);

			for (var bindingIndex in bindingSet.bindingsThatNeedTransitions)
			{
				readonly /*ref*/ BindingSetItem binding = /*ref*/ bindingSet.desc.bindings[bindingIndex];

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
					requireBufferState(checked_cast<AccelStructVK, IResource>(binding.resourceHandle).dataBuffer, ResourceStates.AccelStructRead);

				default:
						// do nothing
					break;
				}
			}
		}

		public override  void setEnableUavBarriersForTexture(ITexture _texture, bool enableBarriers)
		{
			TextureVK texture = checked_cast<TextureVK, ITexture>(_texture);

			m_StateTracker.setEnableUavBarriersForTexture(texture, enableBarriers);
		}
		public override  void setEnableUavBarriersForBuffer(IBuffer _buffer, bool enableBarriers)
		{
			BufferVK buffer = checked_cast<BufferVK, IBuffer>(_buffer);

			m_StateTracker.setEnableUavBarriersForBuffer(buffer, enableBarriers);
		}

		public override  void beginTrackingTextureState(ITexture _texture, TextureSubresourceSet subresources, ResourceStates stateBits)
		{
			TextureVK texture = checked_cast<TextureVK, ITexture>(_texture);

			m_StateTracker.beginTrackingTextureState(texture, subresources, stateBits);
		}
		public override  void beginTrackingBufferState(IBuffer _buffer, ResourceStates stateBits)
		{
			BufferVK buffer = checked_cast<BufferVK, IBuffer>(_buffer);

			m_StateTracker.beginTrackingBufferState(buffer, stateBits);
		}

		public override  void setTextureState(ITexture _texture, TextureSubresourceSet subresources, ResourceStates stateBits)
		{
			TextureVK texture = checked_cast<TextureVK, ITexture>(_texture);

			m_StateTracker.endTrackingTextureState(texture, subresources, stateBits, false);
		}
		public override  void setBufferState(IBuffer _buffer, ResourceStates stateBits)
		{
			BufferVK buffer = checked_cast<BufferVK, IBuffer>(_buffer);

			m_StateTracker.endTrackingBufferState(buffer, stateBits, false);
		}
		public override  void setAccelStructState(nvrhi.rt.IAccelStruct _as, ResourceStates stateBits)
		{
			AccelStructVK @as = checked_cast<AccelStructVK, IAccelStruct>(_as);

			if (@as.dataBuffer != null)
			{
				BufferVK buffer = checked_cast<BufferVK, IBuffer>(@as.dataBuffer.Get<IBuffer>());
				m_StateTracker.endTrackingBufferState(buffer, stateBits, false);
			}
		}

		public override  void setPermanentTextureState(ITexture _texture, ResourceStates stateBits)
		{
			TextureVK texture = checked_cast<TextureVK, ITexture>(_texture);

			m_StateTracker.endTrackingTextureState(texture, AllSubresources, stateBits, true);
		}

		public override  void setPermanentBufferState(IBuffer _buffer, ResourceStates stateBits)
		{
			BufferVK buffer = checked_cast<BufferVK, IBuffer>(_buffer);

			m_StateTracker.endTrackingBufferState(buffer, stateBits, true);
		}

		public override void commitBarriers()
		{
			if (m_StateTracker.getBufferBarriers().IsEmpty && m_StateTracker.getTextureBarriers().IsEmpty)
				return;

			endRenderPass();

			List<VkImageMemoryBarrier> imageBarriers = scope .();
			List<VkBufferMemoryBarrier> bufferBarriers = scope .();
			VkPipelineStageFlags beforeStageFlags = VkPipelineStageFlags.eNone;
			VkPipelineStageFlags afterStageFlags = VkPipelineStageFlags.eNone;

			for (readonly ref TextureBarrier barrier in ref m_StateTracker.getTextureBarriers())
			{
				ResourceStateMapping before = convertResourceState(barrier.stateBefore);
				ResourceStateMapping after = convertResourceState(barrier.stateAfter);

				if ((before.stageFlags != beforeStageFlags || after.stageFlags != afterStageFlags) && !imageBarriers.IsEmpty)
				{
					vkCmdPipelineBarrier(
						m_CurrentCmdBuf.cmdBuf,
						beforeStageFlags,
						afterStageFlags,
						VkDependencyFlags(),
						0,
						null,
						0,
						null,
						(.)imageBarriers.Count,
						imageBarriers.Ptr);

					imageBarriers.Clear();
				}

				beforeStageFlags = before.stageFlags;
				afterStageFlags = after.stageFlags;

				Runtime.Assert(after.imageLayout != VkImageLayout.eUndefined);

				TextureVK texture = (TextureVK)barrier.texture;

				readonly ref FormatInfo formatInfo = ref getFormatInfo(texture.desc.format);

				VkImageAspectFlags aspectMask = VkImageAspectFlags.eNone;
				if (formatInfo.hasDepth) aspectMask |= VkImageAspectFlags.eDepthBit;
				if (formatInfo.hasStencil) aspectMask |= VkImageAspectFlags.eStencilBit;
				if (aspectMask == .eNone) aspectMask = VkImageAspectFlags.eColorBit;

				VkImageSubresourceRange subresourceRange = VkImageSubresourceRange()
					.setBaseArrayLayer(barrier.entireTexture ? 0 : barrier.arraySlice)
					.setLayerCount(barrier.entireTexture ? texture.desc.arraySize : 1)
					.setBaseMipLevel(barrier.entireTexture ? 0 : barrier.mipLevel)
					.setLevelCount(barrier.entireTexture ? texture.desc.mipLevels : 1)
					.setAspectMask(aspectMask);

				imageBarriers.Add(VkImageMemoryBarrier()
					.setSrcAccessMask(before.accessMask)
					.setDstAccessMask(after.accessMask)
					.setOldLayout(before.imageLayout)
					.setNewLayout(after.imageLayout)
					.setSrcQueueFamilyIndex(VK_QUEUE_FAMILY_IGNORED)
					.setDstQueueFamilyIndex(VK_QUEUE_FAMILY_IGNORED)
					.setImage(texture.image)
					.setSubresourceRange(subresourceRange));
			}

			if (!imageBarriers.IsEmpty)
			{
				vkCmdPipelineBarrier(
					m_CurrentCmdBuf.cmdBuf,
					beforeStageFlags,
					afterStageFlags,
					VkDependencyFlags(),
					0,
					null,
					0,
					null,
					(.)imageBarriers.Count,
					imageBarriers.Ptr);
			}

			beforeStageFlags = VkPipelineStageFlags.eNone;
			afterStageFlags = VkPipelineStageFlags.eNone;
			imageBarriers.Clear();

			for (readonly ref BufferBarrier barrier in ref m_StateTracker.getBufferBarriers())
			{
				ResourceStateMapping before = convertResourceState(barrier.stateBefore);
				ResourceStateMapping after = convertResourceState(barrier.stateAfter);

				if ((before.stageFlags != beforeStageFlags || after.stageFlags != afterStageFlags) && !bufferBarriers.IsEmpty)
				{
					vkCmdPipelineBarrier(
						m_CurrentCmdBuf.cmdBuf,
						beforeStageFlags,
						afterStageFlags,
						VkDependencyFlags(), 0, null, (.)bufferBarriers.Count, bufferBarriers.Ptr, 0, null);

					bufferBarriers.Clear();
				}

				beforeStageFlags = before.stageFlags;
				afterStageFlags = after.stageFlags;

				BufferVK buffer = (BufferVK)barrier.buffer;

				bufferBarriers.Add(VkBufferMemoryBarrier()
					.setSrcAccessMask(before.accessMask)
					.setDstAccessMask(after.accessMask)
					.setSrcQueueFamilyIndex(VK_QUEUE_FAMILY_IGNORED)
					.setDstQueueFamilyIndex(VK_QUEUE_FAMILY_IGNORED)
					.setBuffer(buffer.buffer)
					.setOffset(0)
					.setSize(buffer.desc.byteSize));
			}

			if (!bufferBarriers.IsEmpty)
			{
				vkCmdPipelineBarrier(
					m_CurrentCmdBuf.cmdBuf,
					beforeStageFlags,
					afterStageFlags,
					VkDependencyFlags(), 0, null, (.)bufferBarriers.Count, bufferBarriers.Ptr, 0, null);
			}
			bufferBarriers.Clear();

			m_StateTracker.clearBarriers();
		}

		public override ResourceStates getTextureSubresourceState(ITexture _texture, ArraySlice arraySlice, MipLevel mipLevel)
		{
			TextureVK texture = checked_cast<TextureVK, ITexture>(_texture);

			return m_StateTracker.getTextureSubresourceState(texture, arraySlice, mipLevel);
		}
		public override ResourceStates getBufferState(IBuffer _buffer)
		{
			BufferVK buffer = checked_cast<BufferVK, IBuffer>(_buffer);

			return m_StateTracker.getBufferState(buffer);
		}

		public override nvrhi.IDevice getDevice() { return m_Device; }
		public override readonly ref CommandListParameters getDesc()  { return ref m_CommandListParameters; }

		public TrackedCommandBufferPtr getCurrentCmdBuf() { return m_CurrentCmdBuf; }

		private DeviceVK m_Device;
		private VulkanContext* m_Context;

		private CommandListParameters m_CommandListParameters;

		private CommandListResourceStateTracker m_StateTracker;
		private bool m_EnableAutomaticBarriers = true;

		// current internal command buffer
		private TrackedCommandBufferPtr m_CurrentCmdBuf = null;

		private VkPipelineLayout m_CurrentPipelineLayout;
		private VkShaderStageFlags m_CurrentPipelineShaderStages;
		private GraphicsState m_CurrentGraphicsState = .();
		private ComputeState m_CurrentComputeState = .();
		private MeshletState m_CurrentMeshletState = .();
		private nvrhi.rt.State m_CurrentRayTracingState;
		private bool m_AnyVolatileBufferWrites = false;

		private struct ShaderTableState
		{
			public VkStridedDeviceAddressRegionKHR rayGen;
			public VkStridedDeviceAddressRegionKHR miss;
			public VkStridedDeviceAddressRegionKHR hitGroups;
			public VkStridedDeviceAddressRegionKHR callable;
			public uint32 version = 0;
		}
		ShaderTableState m_CurrentShaderTablePointers;

		private Dictionary<BufferVK, VolatileBufferState> m_VolatileBufferStates = new .() ~ delete _;

		private UploadManager m_UploadManager;
		private UploadManager m_ScratchManager;

		private void clearTexture(ITexture _texture, TextureSubresourceSet subresources, VkClearColorValue clearValue)
		{
			var subresources;
			var clearValue;
			endRenderPass();

			TextureVK texture = checked_cast<TextureVK, ITexture>(_texture);
			Runtime.Assert(texture != null);
			Runtime.Assert(m_CurrentCmdBuf != null);

			subresources = subresources.resolve(texture.desc, false);

			if (m_EnableAutomaticBarriers)
			{
				requireTextureState(texture, subresources, ResourceStates.CopyDest);
			}
			commitBarriers();

			VkImageSubresourceRange subresourceRange = VkImageSubresourceRange()
				.setAspectMask(VkImageAspectFlags.eColorBit)
				.setBaseArrayLayer(subresources.baseArraySlice)
				.setLayerCount(subresources.numArraySlices)
				.setBaseMipLevel(subresources.baseMipLevel)
				.setLevelCount(subresources.numMipLevels);

			vkCmdClearColorImage(m_CurrentCmdBuf.cmdBuf, texture.image,
				VkImageLayout.eTransferDstOptimal,
				&clearValue,
				1, &subresourceRange);
		}

		private void bindBindingSets(VkPipelineBindPoint bindPoint, VkPipelineLayout pipelineLayout, BindingSetVector bindings)
		{
			BindingVector<VkDescriptorSet> descriptorSets = .();
			StaticVector<uint32, const c_MaxVolatileConstantBuffers> dynamicOffsets = .();

			for ( /*readonly ref*/var bindingSetHandle in ref bindings)
			{
				readonly BindingSetDesc* desc = bindingSetHandle.getDesc();
				if (desc != null)
				{
					BindingSetVK bindingSet = checked_cast<BindingSetVK, IBindingSet>(bindingSetHandle);
					descriptorSets.PushBack(bindingSet.descriptorSet);

					for (BufferVK constnatBuffer in bindingSet.volatileConstantBuffers)
					{
						if (m_VolatileBufferStates.ContainsKey(constnatBuffer))
						{
							String message = scope $"Binding volatile constant buffer {utils.DebugNameToString(constnatBuffer.desc.debugName)} before writing into it is invalid.";
							m_Context.error(message);

							dynamicOffsets.PushBack(0); // use zero offset just to use something
						}
						else
						{
							uint32 version = (.)m_VolatileBufferStates[constnatBuffer].latestVersion;
							uint64 offset = version * constnatBuffer.desc.byteSize;
							Runtime.Assert(offset < uint32.MaxValue);
							dynamicOffsets.PushBack(uint32(offset));
						}
					}

					if (desc.trackLiveness)
						m_CurrentCmdBuf.referencedResources.Add(bindingSetHandle);
				}
				else
				{
					DescriptorTableVK table = checked_cast<DescriptorTableVK, IBindingSet>(bindingSetHandle);
					descriptorSets.PushBack(table.descriptorSet);
				}
			}

			if (!descriptorSets.IsEmpty)
			{
				vkCmdBindDescriptorSets(m_CurrentCmdBuf.cmdBuf, bindPoint, pipelineLayout, /* firstSet = */ 0, uint32(descriptorSets.Count), descriptorSets.Ptr,
					uint32(dynamicOffsets.Count), dynamicOffsets.Ptr);
			}
		}

		private void endRenderPass()
		{
			if (m_CurrentGraphicsState.framebuffer != null || m_CurrentMeshletState.framebuffer != null)
			{
				vkCmdEndRenderPass(m_CurrentCmdBuf.cmdBuf);
				m_CurrentGraphicsState.framebuffer = null;
				m_CurrentMeshletState.framebuffer = null;
			}
		}

		private void trackResourcesAndBarriers(GraphicsState state)
		{
			Runtime.Assert(m_EnableAutomaticBarriers);

			if (arraysAreDifferent(state.bindings, m_CurrentGraphicsState.bindings))
			{
				for (int i = 0; i < state.bindings.Count; i++)
				{
					setResourceStatesForBindingSet(state.bindings[i]);
				}
			}

			if (state.indexBuffer.buffer != null && state.indexBuffer.buffer != m_CurrentGraphicsState.indexBuffer.buffer)
			{
				requireBufferState(state.indexBuffer.buffer, ResourceStates.IndexBuffer);
			}

			if (arraysAreDifferent(state.vertexBuffers, m_CurrentGraphicsState.vertexBuffers))
			{
				for ( /*readonly ref*/var vb in ref state.vertexBuffers)
				{
					requireBufferState(vb.buffer, ResourceStates.VertexBuffer);
				}
			}

			if (m_CurrentGraphicsState.framebuffer != state.framebuffer)
			{
				setResourceStatesForFramebuffer(state.framebuffer);
			}

			if (state.indirectParams != null && state.indirectParams != m_CurrentGraphicsState.indirectParams)
			{
				requireBufferState(state.indirectParams, ResourceStates.IndirectArgument);
			}
		}

		private void trackResourcesAndBarriers(MeshletState state)
		{
			Runtime.Assert(m_EnableAutomaticBarriers);

			if (arraysAreDifferent(state.bindings, m_CurrentMeshletState.bindings))
			{
				for (int i = 0; i < state.bindings.Count; i++)
				{
					setResourceStatesForBindingSet(state.bindings[i]);
				}
			}

			if (m_CurrentMeshletState.framebuffer != state.framebuffer)
			{
				setResourceStatesForFramebuffer(state.framebuffer);
			}

			if (state.indirectParams != null && state.indirectParams != m_CurrentMeshletState.indirectParams)
			{
				requireBufferState(state.indirectParams, ResourceStates.IndirectArgument);
			}
		}

		private void writeVolatileBuffer(BufferVK buffer, void* data, int dataSize)
		{
			ref VolatileBufferState state = ref m_VolatileBufferStates[buffer];

			if (!state.initialized)
			{
				state.minVersion = int32(buffer.desc.maxVersions);
				state.maxVersion = -1;
				state.initialized = true;
			}

			uint64[uint32(CommandQueue.Count)] queueCompletionValues = .(
				getQueueLastFinishedID(m_Device, CommandQueue.Graphics),
				getQueueLastFinishedID(m_Device, CommandQueue.Compute),
				getQueueLastFinishedID(m_Device, CommandQueue.Copy)
				);

			uint32 searchStart = buffer.versionSearchStart;
			uint32 maxVersions = buffer.desc.maxVersions;
			uint32 version = 0;

			uint64 originalVersionInfo = 0;

			// Since versionTracking[] can be accessed by multiple threads concurrently,
			// perform the search in a loop ending with compare_exchange until the exchange is successful.
			while (true)
			{
				bool found = false;

				// Search through the versions of this buffer, looking for either unused (0)
				// or submitted and already finished versions

				for (uint32 searchIndex = 0; searchIndex < maxVersions; searchIndex++)
				{
					version = searchIndex + searchStart;
					version = (version >= maxVersions) ? (version - maxVersions) : version;

					originalVersionInfo = buffer.versionTracking[version];

					if (originalVersionInfo == 0)
					{
						// Previously unused version - definitely available
						found = true;
						break;
					}

					// Decode the bitfield
					bool isSubmitted = (originalVersionInfo & c_VersionSubmittedFlag) != 0;
					uint32 queueIndex = uint32(originalVersionInfo >> c_VersionQueueShift) & c_VersionQueueMask;
					uint64 id = originalVersionInfo & c_VersionIDMask;

					// If the version is in a recorded but not submitted command list,
					// we can't use it. So, only compare the version ID for submitted CLs.
					if (isSubmitted)
					{
						// Versions can potentially be used in CLs submitted to different queues.
						// So we store the queue index and use look at the last finished CL in that queue.

						if (queueIndex >= uint32(CommandQueue.Count))
						{
							// If the version points at an invalid queue, assume it's available. Signal the error too.
							utils.InvalidEnum();
							found = true;
							break;
						}

						if (id <= queueCompletionValues[queueIndex])
						{
							// If the version was used in a completed CL, it's available.
							found = true;
							break;
						}
					}
				}

				if (!found)
				{
					// Not enough versions - need to relay this information to the developer.
					// This has to be a real message and not assert, because asserts only happen in the
					// debug mode, and buffer versioning will behave differently in debug vs. release,
					// or validation on vs. off, because it is timing related.

					String message = scope $"Volatile constant buffer {utils.DebugNameToString(buffer.desc.debugName)} has maxVersions = {buffer.desc.maxVersions}, which is insufficient.";

					m_Context.error(message);
					return;
				}

				// Encode the current CL ID for this version of the buffer, in a "pending" state
				uint64 newVersionInfo = (uint64(m_CommandListParameters.queueType) << c_VersionQueueShift) | (m_CurrentCmdBuf.recordingID);

				// Try to store the new version info, end the loop if we actually won this version, i.e. no other thread has claimed it
				if (buffer.versionTracking[version].CompareAndExchangeWeak(originalVersionInfo, newVersionInfo))
					break;
			}

			buffer.versionSearchStart = (version + 1 < maxVersions) ? (version + 1) : 0;

			// Store the current version and expand the version range in this CL
			state.latestVersion = int32(version);
			state.minVersion = Math.Min(int32(version), state.minVersion);
			state.maxVersion = Math.Max(int32(version), state.maxVersion);

			// Finally, write the actual data
			void* hostData = (char8*)buffer.mappedMemory + version * buffer.desc.byteSize;
			Internal.MemCpy(hostData, data, dataSize);

			m_AnyVolatileBufferWrites = true;
		}

		private void flushVolatileBufferWrites()
		{
			// The volatile CBs are permanently mapped with the eHostVisible flag, but not eHostCoherent,
			// so before using the data on the GPU, we need to make sure it's available there.
			// Go over all the volatile CBs that were used in this CL and flush their written versions.

			List<VkMappedMemoryRange> ranges = scope .();

			for (var iter in ref m_VolatileBufferStates)
			{
				BufferVK buffer = iter.key;
				ref VolatileBufferState state = ref *iter.valueRef;

				if (state.maxVersion < state.minVersion || !state.initialized)
					continue;

				// Flush all the versions between min and max - that might be too conservative,
				// but that should be fine - better than using potentially hundreds of ranges.
				int32 numVersions = state.maxVersion - state.minVersion + 1;

				var range = VkMappedMemoryRange()
					.setMemory(buffer.memory)
					.setOffset((.)state.minVersion * buffer.desc.byteSize)
					.setSize((.)numVersions * buffer.desc.byteSize);

				ranges.Add(range);
			}

			if (!ranges.IsEmpty)
			{
				vkFlushMappedMemoryRanges(m_Context.device, (.)ranges.Count, ranges.Ptr);
			}
		}

		private void submitVolatileBuffers(uint64 recordingID, uint64 submittedID)
		{
			// For each volatile CB that was written in this command list, and for every version thereof,
			// we need to replace the tracking information from "pending" to "submitted".
			// This is potentially slow as there might be hundreds of versions of a buffer,
			// but at least the find-and-replace operation is constrained to the min/max version range.

			uint64 stateToFind = (uint64(m_CommandListParameters.queueType) << c_VersionQueueShift) | (recordingID & c_VersionIDMask);
			uint64 stateToReplace = (uint64(m_CommandListParameters.queueType) << c_VersionQueueShift) | (submittedID & c_VersionIDMask) | c_VersionSubmittedFlag;

			for (var iter in ref m_VolatileBufferStates)
			{
				BufferVK buffer = iter.key;
				ref VolatileBufferState state = ref *iter.valueRef;

				if (!state.initialized)
					continue;

				for (int32 version = state.minVersion; version <= state.maxVersion; version++)
				{
					// Use compare_exchange to conditionally replace the entries equal to stateToFind with stateToReplace.
					uint64 expected = stateToFind;
					buffer.versionTracking[version].CompareAndExchangeStrong(expected, stateToReplace);
				}
			}
		}


		private void updateGraphicsVolatileBuffers()
		{
			if (m_AnyVolatileBufferWrites && m_CurrentGraphicsState.pipeline != null)
			{
				GraphicsPipelineVK pso = checked_cast<GraphicsPipelineVK, IGraphicsPipeline>(m_CurrentGraphicsState.pipeline);

				bindBindingSets(VkPipelineBindPoint.eGraphics, pso.pipelineLayout, m_CurrentGraphicsState.bindings);

				m_AnyVolatileBufferWrites = false;
			}
		}

		private void updateComputeVolatileBuffers()
		{
			if (m_AnyVolatileBufferWrites && m_CurrentComputeState.pipeline != null)
			{
				ComputePipelineVK pso = checked_cast<ComputePipelineVK, IComputePipeline>(m_CurrentComputeState.pipeline);

				bindBindingSets(VkPipelineBindPoint.eCompute, pso.pipelineLayout, m_CurrentComputeState.bindings);

				m_AnyVolatileBufferWrites = false;
			}
		}

		private void updateMeshletVolatileBuffers()
		{
			if (m_AnyVolatileBufferWrites && m_CurrentMeshletState.pipeline != null)
			{
				MeshletPipelineVK pso = checked_cast<MeshletPipelineVK, nvrhi.IMeshletPipeline>(m_CurrentMeshletState.pipeline);

				bindBindingSets(VkPipelineBindPoint.eGraphics, pso.pipelineLayout, m_CurrentMeshletState.bindings);

				m_AnyVolatileBufferWrites = false;
			}
		}

		private void updateRayTracingVolatileBuffers()
		{
			if (m_AnyVolatileBufferWrites && m_CurrentRayTracingState.shaderTable != null)
			{
				RayTracingPipelineVK pso = checked_cast<RayTracingPipelineVK, nvrhi.rt.IPipeline>(m_CurrentRayTracingState.shaderTable.getPipeline());

				bindBindingSets(VkPipelineBindPoint.eRayTracingKHR, pso.pipelineLayout, m_CurrentComputeState.bindings);

				m_AnyVolatileBufferWrites = false;
			}
		}


		private void requireTextureState(ITexture _texture, TextureSubresourceSet subresources, ResourceStates state)
		{
			TextureVK texture = checked_cast<TextureVK, ITexture>(_texture);

			m_StateTracker.requireTextureState(texture, subresources, state);
		}

		private void requireBufferState(IBuffer _buffer, ResourceStates state)
		{
			BufferVK buffer = checked_cast<BufferVK, IBuffer>(_buffer);

			m_StateTracker.requireBufferState(buffer, state);
		}

		private bool anyBarriers()
		{
			return !m_StateTracker.getBufferBarriers().IsEmpty || !m_StateTracker.getTextureBarriers().IsEmpty;
		}

		private void buildTopLevelAccelStructInternal(AccelStructVK @as, VkDeviceAddress instanceData, int numInstances, nvrhi.rt.AccelStructBuildFlags buildFlags, uint64 currentVersion)
		{
			readonly bool performUpdate = (buildFlags & AccelStructBuildFlags.PerformUpdate) != 0;
			if (performUpdate)
			{
				Runtime.Assert(@as.allowUpdate);
				Runtime.Assert(@as.instances.Count == numInstances);
			}

			var geometry = VkAccelerationStructureGeometryKHR()
				.setGeometryType(VkGeometryTypeKHR.eInstancesKHR);

			geometry.geometry.setInstances(VkAccelerationStructureGeometryInstancesDataKHR()
				.setData(VkDeviceOrHostAddressConstKHR() { deviceAddress = instanceData })
				.setArrayOfPointers(false));

			VkAccelerationStructureGeometryKHR[1] geometries = .(geometry);
			VkAccelerationStructureBuildRangeInfoKHR[1] buildRanges = .(
				VkAccelerationStructureBuildRangeInfoKHR().setPrimitiveCount(uint32(numInstances)));
			uint32[1] maxPrimitiveCounts = .(uint32(numInstances));

			var buildInfo = VkAccelerationStructureBuildGeometryInfoKHR()
				.setType(VkAccelerationStructureTypeKHR.eTopLevelKHR)
				.setMode(performUpdate ? VkBuildAccelerationStructureModeKHR.eUpdateKHR : VkBuildAccelerationStructureModeKHR.eBuildKHR)
				.setPGeometries(&geometries)
				.setFlags(convertAccelStructBuildFlags(buildFlags))
				.setDstAccelerationStructure(@as.accelStruct);

			if (@as.allowUpdate)
				buildInfo.flags |= VkBuildAccelerationStructureFlagsKHR.eAllowUpdateBitKHR;

			if (performUpdate)
				buildInfo.setSrcAccelerationStructure(@as.accelStruct);

			VkAccelerationStructureBuildSizesInfoKHR buildSizes = .();
			vkGetAccelerationStructureBuildSizesKHR(m_Context.device,
				VkAccelerationStructureBuildTypeKHR.eDeviceKHR, &buildInfo, &maxPrimitiveCounts, &buildSizes);

			if (buildSizes.accelerationStructureSize > @as.dataBuffer.Get<IBuffer>().getDesc().byteSize)
			{
				String message = scope $"TLAS {utils.DebugNameToString(@as.desc.debugName)} build requires at least {buildSizes.accelerationStructureSize} bytes in the data buffer, while the allocated buffer is only {@as.dataBuffer.Get<IBuffer>().getDesc().byteSize} bytes";

				m_Context.error(message);
				return;
			}

			var scratchSize = performUpdate
				? buildSizes.updateScratchSize
				: buildSizes.buildScratchSize;

			BufferVK scratchBuffer = null;
			uint64 scratchOffset = 0;

			bool allocated = m_ScratchManager.suballocateBuffer(scratchSize, &scratchBuffer, &scratchOffset, null,
				currentVersion, m_Context.accelStructProperties.minAccelerationStructureScratchOffsetAlignment);

			if (!allocated)
			{
				String message = scope $"Couldn't suballocate a scratch buffer for TLAS {utils.DebugNameToString(@as.desc.debugName)} build. The build requires {scratchSize} bytes of scratch space.";

				m_Context.error(message);
				return;
			}

			Runtime.Assert(scratchBuffer.deviceAddress != 0);
			buildInfo.setScratchData(VkDeviceOrHostAddressKHR().setDeviceAddress(scratchBuffer.deviceAddress + scratchOffset));

			VkAccelerationStructureBuildGeometryInfoKHR[1] buildInfos = .(buildInfo);
			VkAccelerationStructureBuildRangeInfoKHR*[1] buildRangeArrays = .(&buildRanges);

			vkCmdBuildAccelerationStructuresKHR(m_CurrentCmdBuf.cmdBuf, 1, &buildInfos, &buildRangeArrays);
		}
	}
}