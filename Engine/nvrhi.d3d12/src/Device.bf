using System.Threading;
using Win32.Foundation;
using System.Collections;
using Win32.Graphics.Direct3D12;
using System;
using Win32.System.Threading;
using Win32.System.WindowsProgramming;
using Win32.Graphics.Dxgi;
using System;
using nvrhi.d3dcommon;
using nvrhi.rt;
using Win32.Graphics.Direct3D;
namespace nvrhi.d3d12;

class Device : RefCounter<nvrhi.d3d12.IDevice>
{
	public this(DeviceDesc desc)
	{
		m_Resources = new .(m_Context, desc);

		m_Context.device = desc.pDevice;
		m_Context.messageCallback = desc.errorCB;

		if (desc.pGraphicsCommandQueue != null)
			m_Queues[int32(CommandQueue.Graphics)] = new Queue(m_Context, desc.pGraphicsCommandQueue);
		if (desc.pComputeCommandQueue != null)
			m_Queues[int32(CommandQueue.Compute)] = new Queue(m_Context, desc.pComputeCommandQueue);
		if (desc.pCopyCommandQueue != null)
			m_Queues[int32(CommandQueue.Copy)] = new Queue(m_Context, desc.pCopyCommandQueue);

		m_Resources.depthStencilViewHeap.allocateResources(D3D12_DESCRIPTOR_HEAP_TYPE.DSV, desc.depthStencilViewHeapSize, false);
		m_Resources.renderTargetViewHeap.allocateResources(D3D12_DESCRIPTOR_HEAP_TYPE.RTV, desc.renderTargetViewHeapSize, false);
		m_Resources.shaderResourceViewHeap.allocateResources(D3D12_DESCRIPTOR_HEAP_TYPE.CBV_SRV_UAV, desc.shaderResourceViewHeapSize, true);
		m_Resources.samplerHeap.allocateResources(D3D12_DESCRIPTOR_HEAP_TYPE.SAMPLER, desc.samplerHeapSize, true);

		m_Context.device.CheckFeatureSupport(D3D12_FEATURE.D3D12_OPTIONS, &m_Options, sizeof(decltype(m_Options)));
		bool hasOptions5 = SUCCEEDED(m_Context.device.CheckFeatureSupport(D3D12_FEATURE.D3D12_OPTIONS5, &m_Options5, sizeof(decltype(m_Options5))));
		bool hasOptions6 = SUCCEEDED(m_Context.device.CheckFeatureSupport(D3D12_FEATURE.D3D12_OPTIONS6, &m_Options6, sizeof(decltype(m_Options6))));
		bool hasOptions7 = SUCCEEDED(m_Context.device.CheckFeatureSupport(D3D12_FEATURE.D3D12_OPTIONS7, &m_Options7, sizeof(decltype(m_Options7))));

		if (SUCCEEDED(m_Context.device.QueryInterface(ID3D12Device5.IID, (void**)&m_Context.device5)) && hasOptions5)
		{
			m_RayTracingSupported = m_Options5.RaytracingTier >= D3D12_RAYTRACING_TIER._1_0;
			m_TraceRayInlineSupported = m_Options5.RaytracingTier >= D3D12_RAYTRACING_TIER._1_1;

#if NVRHI_WITH_RTXMU
			if (m_RayTracingSupported)
			{
				m_Context.rtxMemUtil = std.make_unique<rtxmu.DxAccelStructManager>(m_Context.device5);

				// Initialize suballocator blocks to 8 MB
				m_Context.rtxMemUtil.Initialize(8388608);
			}
#endif
		}

		if (SUCCEEDED(m_Context.device.QueryInterface(ID3D12Device2.IID, (void**)&m_Context.device2)) && hasOptions7)
		{
			m_MeshletsSupported = m_Options7.MeshShaderTier >= D3D12_MESH_SHADER_TIER._1;
		}

		if (hasOptions6)
		{
			m_VariableRateShadingSupported = m_Options6.VariableShadingRateTier >= D3D12_VARIABLE_SHADING_RATE_TIER._2;
		}
		{
			D3D12_INDIRECT_ARGUMENT_DESC argDesc = .();
			D3D12_COMMAND_SIGNATURE_DESC csDesc = .();
			csDesc.NumArgumentDescs = 1;
			csDesc.pArgumentDescs = &argDesc;

			csDesc.ByteStride = 16;
			argDesc.Type = D3D12_INDIRECT_ARGUMENT_TYPE.DRAW;
			m_Context.device.CreateCommandSignature(csDesc, null, ID3D12CommandSignature.IID, (void**)&m_Context.drawIndirectSignature);

			csDesc.ByteStride = 12;
			argDesc.Type = D3D12_INDIRECT_ARGUMENT_TYPE.DISPATCH;
			m_Context.device.CreateCommandSignature(csDesc, null, ID3D12CommandSignature.IID, (void**)&m_Context.dispatchIndirectSignature);
		}

		m_FenceEvent = CreateEventA(null, 0, 0, null);

		m_CommandListsToExecute.Reserve(64);

#if NVRHI_D3D12_WITH_NVAPI
		//We need to use NVAPI to set resource hints for SLI
		m_NvapiIsInitialized = NvAPI_Initialize() == NVAPI_OK;

		if (m_NvapiIsInitialized)
		{
			NV_QUERY_SINGLE_PASS_STEREO_SUPPORT_PARAMS stereoParams{};
			stereoParams.version = NV_QUERY_SINGLE_PASS_STEREO_SUPPORT_PARAMS_VER;

			if (NvAPI_D3D12_QuerySinglePassStereoSupport(m_Context.device, &stereoParams) == NVAPI_OK && stereoParams.bSinglePassStereoSupported)
			{
				m_SinglePassStereoSupported = true;
			}

			// There is no query for FastGS, so query support for FP16 atomics as a proxy.
			// Both features were introduced in the same architecture (Maxwell).
			bool supported = false;
			if (NvAPI_D3D12_IsNvShaderExtnOpCodeSupported(m_Context.device, NV_EXTN_OP_FP16_ATOMIC, &supported) == NVAPI_OK && supported)
			{
				m_FastGeometryShaderSupported = true;
			}
		}
#endif
	}

	public ~this()
	{
		waitForIdle();

		if (m_FenceEvent != 0)
		{
			CloseHandle(m_FenceEvent);
			m_FenceEvent = 0;
		}
	}

	// IResource implementation

	public override NativeObject getNativeObject(ObjectType objectType)
	{
		switch (objectType)
		{
		case ObjectType.D3D12_Device:
			return NativeObject(m_Context.device);
		case ObjectType.Nvrhi_D3D12_Device:
			return NativeObject(Internal.UnsafeCastToPtr(this));
		default:
			return null;
		}
	}

	// IDevice implementation

	public override HeapHandle createHeap(HeapDesc d)
	{
		D3D12_HEAP_DESC heapDesc;
		heapDesc.SizeInBytes = d.capacity;
		heapDesc.Alignment = D3D12_DEFAULT_MSAA_RESOURCE_PLACEMENT_ALIGNMENT;
		heapDesc.Properties.MemoryPoolPreference = D3D12_MEMORY_POOL.UNKNOWN;
		heapDesc.Properties.CPUPageProperty = D3D12_CPU_PAGE_PROPERTY.UNKNOWN;
		heapDesc.Properties.CreationNodeMask = 1; // no mGPU support in nvrhi so far
		heapDesc.Properties.VisibleNodeMask = 1;

		if (m_Options.ResourceHeapTier == D3D12_RESOURCE_HEAP_TIER._1)
			heapDesc.Flags = D3D12_HEAP_FLAGS.ALLOW_ONLY_RT_DS_TEXTURES;
		else
			heapDesc.Flags = D3D12_HEAP_FLAGS.ALLOW_ALL_BUFFERS_AND_TEXTURES;

		switch (d.type)
		{
		case HeapType.DeviceLocal:
			heapDesc.Properties.Type = D3D12_HEAP_TYPE.DEFAULT;
			break;
		case HeapType.Upload:
			heapDesc.Properties.Type = D3D12_HEAP_TYPE.UPLOAD;
			break;
		case HeapType.Readback:
			heapDesc.Properties.Type = D3D12_HEAP_TYPE.READBACK;
			break;
		default:
			nvrhi.utils.InvalidEnum();
			return null;
		}

		D3D12RefCountPtr<ID3D12Heap> d3dHeap = null;
		readonly HRESULT res = m_Context.device.CreateHeap(heapDesc, ID3D12Heap.IID, (void**)&d3dHeap);

		if (FAILED(res))
		{
			String message = scope $"CreateHeap call failed for heap {nvrhi.utils.DebugNameToString(d.debugName)}, HRESULT = 0x{res}";
			m_Context.error(message);

			return null;
		}

		if (!String.IsNullOrEmpty(d.debugName))
		{
			d3dHeap.SetName(d.debugName.ToScopedNativeWChar!());
		}

		Heap heap = new Heap();
		heap.heap = d3dHeap;
		heap.desc = d;
		return HeapHandle.Attach(heap);
	}

	public override TextureHandle createTexture(TextureDesc d)
	{
		D3D12_RESOURCE_DESC rd = convertTextureDesc(d);
		D3D12_HEAP_PROPERTIES heapProps = .();
		D3D12_HEAP_FLAGS heapFlags = D3D12_HEAP_FLAGS.NONE;

		if ((d.sharedResourceFlags & SharedResourceFlags.Shared) != 0)
			heapFlags |= D3D12_HEAP_FLAGS.SHARED;
		if ((d.sharedResourceFlags & SharedResourceFlags.Shared_CrossAdapter) != 0)
		{
			rd.Flags |= D3D12_RESOURCE_FLAGS.ALLOW_CROSS_ADAPTER;
			heapFlags |= D3D12_HEAP_FLAGS.SHARED_CROSS_ADAPTER;
		}

		Texture texture = new Texture(m_Context, m_Resources, d, rd);

		if (d.isVirtual)
		{
			// The resource is created in bindTextureMemory
			return TextureHandle.Attach(texture);
		}

		heapProps.Type = D3D12_HEAP_TYPE.DEFAULT;

		D3D12_CLEAR_VALUE clearValue = convertTextureClearValue(d);

		HRESULT hr = m_Context.device.CreateCommittedResource(
			heapProps,
			heapFlags,
			texture.resourceDesc,
			convertResourceStates(d.initialState),
			d.useClearValue ? &clearValue : null,
			ID3D12Resource.IID,
			(void**)&texture.resource);

		if (FAILED(hr))
		{
			String message = scope $"Failed to create texture {nvrhi.utils.DebugNameToString(d.debugName)}, error code = 0x{hr}";
			m_Context.error(message);

			delete texture;
			return null;
		}

		texture.postCreate();

		return TextureHandle.Attach(texture);
	}

	public override MemoryRequirements getTextureMemoryRequirements(ITexture _texture)
	{
		Texture texture = checked_cast<Texture, ITexture>(_texture);

		D3D12_RESOURCE_ALLOCATION_INFO allocInfo = m_Context.device.GetResourceAllocationInfo(1, 1, &texture.resourceDesc);

		MemoryRequirements memReq;
		memReq.alignment = allocInfo.Alignment;
		memReq.size = allocInfo.SizeInBytes;
		return memReq;
	}
	public override bool bindTextureMemory(ITexture _texture, IHeap _heap, uint64 offset)
	{
		Texture texture = checked_cast<Texture, ITexture>(_texture);
		Heap heap = checked_cast<Heap, IHeap>(_heap);

		if (texture.resource != null)
			return false; // already bound

		if (!texture.desc.isVirtual)
			return false; // not supported


		D3D12_CLEAR_VALUE clearValue = convertTextureClearValue(texture.desc);

		HRESULT hr = m_Context.device.CreatePlacedResource(
			ref *heap.heap, offset,
			texture.resourceDesc,
			convertResourceStates(texture.desc.initialState),
			texture.desc.useClearValue ? &clearValue : null,
			ID3D12Resource.IID,
			(void**)&texture.resource);

		if (FAILED(hr))
		{
			String message = scope $"Failed to create placed texture {nvrhi.utils.DebugNameToString(texture.desc.debugName)}, error code = 0x{hr}";
			m_Context.error(message);

			return false;
		}

		texture.heap = heap;
		texture.postCreate();

		return true;
	}

	public override TextureHandle createHandleForNativeTexture(ObjectType objectType, NativeObject _texture, TextureDesc desc)
	{
		if (_texture.pointer == null)
			return null;

		if (objectType != ObjectType.D3D12_Resource)
			return null;

		ID3D12Resource* pResource = (ID3D12Resource*)(_texture.pointer);

		Texture texture = new Texture(m_Context, m_Resources, desc, pResource.GetDesc());
		texture.resource = pResource;
		texture.postCreate();

		return TextureHandle.Attach(texture);
	}

	public override StagingTextureHandle createStagingTexture(TextureDesc d, CpuAccessMode cpuAccess)
	{
		Runtime.Assert(cpuAccess != CpuAccessMode.None);

		StagingTexture ret = new StagingTexture();
		ret.desc = d;
		ret.resourceDesc = convertTextureDesc(d);
		ret.computeSubresourceOffsets(m_Context.device);

		BufferDesc bufferDesc = .();
		bufferDesc.byteSize = (.)ret.getSizeInBytes(m_Context.device);
		bufferDesc.structStride = 0;
		bufferDesc.debugName = d.debugName;
		bufferDesc.cpuAccess = cpuAccess;

		BufferHandle buffer = createBuffer(bufferDesc);
		ret.buffer = checked_cast<Buffer, IBuffer>(buffer?.Get<IBuffer>());
		if (ret.buffer == null)
		{
			delete ret;
			return null;
		}

		ret.cpuAccess = cpuAccess;
		return StagingTextureHandle.Attach(ret);
	}
	public override void* mapStagingTexture(IStagingTexture _tex, TextureSlice slice, CpuAccessMode cpuAccess, int* outRowPitch)
	{
		StagingTexture tex = checked_cast<StagingTexture, IStagingTexture>(_tex);

		Runtime.Assert(slice.x == 0);
		Runtime.Assert(slice.y == 0);
		Runtime.Assert(cpuAccess != CpuAccessMode.None);
		Runtime.Assert(tex.mappedRegion.size == 0);
		Runtime.Assert(tex.mappedAccess == CpuAccessMode.None);

		var resolvedSlice = slice.resolve(tex.desc);
		var region = tex.getSliceRegion(m_Context.device, resolvedSlice);

		if (tex.lastUseFence != null)
		{
			WaitForFence(tex.lastUseFence, tex.lastUseFenceValue, m_FenceEvent);
			tex.lastUseFence = null;
		}

		D3D12_RANGE range = .();

		if (cpuAccess == CpuAccessMode.Read)
		{
			range = .() { Begin =  uint(region.offset), End = uint(region.offset + region.size) };
		} else
		{
			range = .() { Begin = 0, End = 0 };
		}

		uint8* ret = null;
		readonly HRESULT res = tex.buffer.resource.Map(0, &range, (void**)&ret);

		if (FAILED(res))
		{
			String message = scope $"Map call failed for texture {nvrhi.utils.DebugNameToString(tex.desc.debugName)}, HRESULT = 0x{res}";
			m_Context.error(message);

			return null;
		}

		tex.mappedRegion = region;
		tex.mappedAccess = cpuAccess;

		*outRowPitch = region.footprint.Footprint.RowPitch;
		return ret + tex.mappedRegion.offset;
	}
	public override void unmapStagingTexture(IStagingTexture _tex)
	{
		StagingTexture tex = checked_cast<StagingTexture, IStagingTexture>(_tex);

		Runtime.Assert(tex.mappedRegion.size != 0);
		Runtime.Assert(tex.mappedAccess != CpuAccessMode.None);

		D3D12_RANGE range;

		if (tex.mappedAccess == CpuAccessMode.Write)
		{
			range = .() { Begin = uint(tex.mappedRegion.offset), End = uint(tex.mappedRegion.offset + tex.mappedRegion.size) };
		} else
		{
			range = .() { Begin = 0, End = 0 };
		}

		tex.buffer.resource.Unmap(0, &range);

		tex.mappedRegion.size = 0;
		tex.mappedAccess = CpuAccessMode.None;
	}

	public override BufferHandle createBuffer(BufferDesc d)
	{
		BufferDesc desc = d;
		if (desc.isConstantBuffer)
		{
			desc.byteSize = align(d.byteSize, 256uL);
		}

		Buffer buffer = new Buffer(m_Context, m_Resources, desc);

		if (d.isVolatile)
		{
			// Do not create any resources for volatile buffers. Done.
			return BufferHandle.Attach(buffer);
		}

		ref D3D12_RESOURCE_DESC resourceDesc = ref buffer.resourceDesc;
		resourceDesc.Width = buffer.desc.byteSize;
		resourceDesc.Height = 1;
		resourceDesc.DepthOrArraySize = 1;
		resourceDesc.MipLevels = 1;
		resourceDesc.Format = DXGI_FORMAT.UNKNOWN;
		resourceDesc.SampleDesc.Count = 1;
		resourceDesc.SampleDesc.Quality = 0;
		resourceDesc.Dimension = D3D12_RESOURCE_DIMENSION.BUFFER;
		resourceDesc.Layout = D3D12_TEXTURE_LAYOUT.ROW_MAJOR;

		if (buffer.desc.canHaveUAVs)
			resourceDesc.Flags |= D3D12_RESOURCE_FLAGS.ALLOW_UNORDERED_ACCESS;

		if (d.isVirtual)
		{
			return BufferHandle.Attach(buffer);
		}

		D3D12_HEAP_PROPERTIES heapProps = .();
		D3D12_HEAP_FLAGS heapFlags = D3D12_HEAP_FLAGS.NONE;
		D3D12_RESOURCE_STATES initialState = D3D12_RESOURCE_STATES.COMMON;

		if ((d.sharedResourceFlags & SharedResourceFlags.Shared) != 0)
			heapFlags |= D3D12_HEAP_FLAGS.SHARED;
		if ((d.sharedResourceFlags & SharedResourceFlags.Shared_CrossAdapter) != 0)
		{
			resourceDesc.Flags |= D3D12_RESOURCE_FLAGS.ALLOW_CROSS_ADAPTER;
			heapFlags |= D3D12_HEAP_FLAGS.SHARED_CROSS_ADAPTER;
		}

		switch (buffer.desc.cpuAccess)
		{
		case CpuAccessMode.None:
			heapProps.Type = D3D12_HEAP_TYPE.DEFAULT;
			initialState = convertResourceStates(d.initialState);
			break;

		case CpuAccessMode.Read:
			heapProps.Type = D3D12_HEAP_TYPE.READBACK;
			initialState = D3D12_RESOURCE_STATES.COPY_DEST;
			break;

		case CpuAccessMode.Write:
			heapProps.Type = D3D12_HEAP_TYPE.UPLOAD;
			initialState = D3D12_RESOURCE_STATES.GENERIC_READ;
			break;
		}

		HRESULT res = m_Context.device.CreateCommittedResource(
			heapProps,
			heapFlags,
			resourceDesc,
			initialState,
			null,
			ID3D12Resource.IID,
			(void**)(&buffer.resource));

		if (FAILED(res))
		{
			String message = scope $"CreateCommittedResource call failed for buffer {nvrhi.utils.DebugNameToString(d.debugName)}, HRESULT = 0x{res}";
			m_Context.error(message);

			delete buffer;
			return null;
		}

		buffer.postCreate();

		return BufferHandle.Attach(buffer);
	}

	public override void* mapBuffer(IBuffer _b, CpuAccessMode flags)
	{
		Buffer b = checked_cast<Buffer, IBuffer>(_b);

		if (b.lastUseFence != null)
		{
			WaitForFence(b.lastUseFence, b.lastUseFenceValue, m_FenceEvent);
			b.lastUseFence = null;
		}

		D3D12_RANGE range;

		if (flags == CpuAccessMode.Read)
		{
			range = .() { Begin = 0, End = b.desc.byteSize };
		} else
		{
			range = .() { Begin = 0, End = 0 };
		}

		void* mappedBuffer = null;
		readonly HRESULT res = b.resource.Map(0, &range, &mappedBuffer);

		if (FAILED(res))
		{
			String message = scope $"Map call failed for buffer {nvrhi.utils.DebugNameToString(b.desc.debugName)}, HRESULT = 0x{res}";
			m_Context.error(message);

			return null;
		}

		return mappedBuffer;
	}
	public override void unmapBuffer(IBuffer _b)
	{
		Buffer b = checked_cast<Buffer, IBuffer>(_b);

		b.resource.Unmap(0, null);
	}
	public override MemoryRequirements getBufferMemoryRequirements(IBuffer _buffer)
	{
		Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

		D3D12_RESOURCE_ALLOCATION_INFO allocInfo = m_Context.device.GetResourceAllocationInfo(1, 1, &buffer.resourceDesc);

		MemoryRequirements memReq;
		memReq.alignment = allocInfo.Alignment;
		memReq.size = allocInfo.SizeInBytes;
		return memReq;
	}
	public override bool bindBufferMemory(IBuffer _buffer, IHeap _heap, uint64 offset)
	{
		Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);
		Heap heap = checked_cast<Heap, IHeap>(_heap);

		if (buffer.resource != null)
			return false; // already bound

		if (!buffer.desc.isVirtual)
			return false; // not supported

		HRESULT hr = m_Context.device.CreatePlacedResource(
			ref *heap.heap, offset,
			buffer.resourceDesc,
			convertResourceStates(buffer.desc.initialState),
			null,
			ID3D12Resource.IID,
			(void**)(&buffer.resource));

		if (FAILED(hr))
		{
			String message = scope $"Failed to create placed buffer {nvrhi.utils.DebugNameToString(buffer.desc.debugName)}, error code = 0x{hr}";
			m_Context.error(message);

			return false;
		}

		buffer.heap = heap;
		buffer.postCreate();

		return true;
	}

	public override BufferHandle createHandleForNativeBuffer(ObjectType objectType, NativeObject _buffer, BufferDesc desc)
	{
		if (_buffer.pointer == null)
			return null;

		if (objectType != ObjectType.D3D12_Resource)
			return null;

		ID3D12Resource* pResource = (ID3D12Resource*)(_buffer.pointer);

		Buffer buffer = new Buffer(m_Context, m_Resources, desc);
		buffer.resource = pResource;

		buffer.postCreate();

		return BufferHandle.Attach(buffer);
	}

	public override ShaderHandle createShader(ShaderDesc d, void* binary,  int binarySize)
	{
		if (binarySize == 0)
			return null;

		Shader shader = new Shader();
		shader.bytecode.Resize(binarySize);
		shader.desc = d;
		Internal.MemCpy(&shader.bytecode[0], binary, binarySize);

#if NVRHI_D3D12_WITH_NVAPI
		// Save the custom semantics structure because it may be on the stack or otherwise dynamic.
		// Note that this has to be a deep copy; currently NV_CUSTOM_SEMANTIC has no pointers, but that might change.
		if (d.numCustomSemantics && d.pCustomSemantics)
		{
			convertCustomSemantics(d.numCustomSemantics, d.pCustomSemantics, shader.customSemantics);
		}

		// Save the coordinate swizzling patterns for the same reason
		if (d.pCoordinateSwizzling)
		{
			const uint32 numSwizzles = 16;
			shader.coordinateSwizzling.resize(numSwizzles);
			memcpy(&shader.coordinateSwizzling[0], d.pCoordinateSwizzling, sizeof(uint32) * numSwizzles);
		}

		if (d.hlslExtensionsUAV >= 0)
		{
			NVAPI_D3D12_PSO_SET_SHADER_EXTENSION_SLOT_DESC* pExtn = new NVAPI_D3D12_PSO_SET_SHADER_EXTENSION_SLOT_DESC();
			memset(pExtn, 0, sizeof(*pExtn));
			pExtn.baseVersion = NV_PSO_EXTENSION_DESC_VER;
			pExtn.psoExtension = NV_PSO_SET_SHADER_EXTNENSION_SLOT_AND_SPACE;
			pExtn.version = NV_SET_SHADER_EXTENSION_SLOT_DESC_VER;

			pExtn.uavSlot = d.hlslExtensionsUAV;
			pExtn.registerSpace = 0;

			shader.extensions.push_back(pExtn);
		}

		switch (d.shaderType)
		{
		case ShaderType.Vertex:
			if (d.numCustomSemantics)
			{
				NVAPI_D3D12_PSO_VERTEX_SHADER_DESC* pExtn = new NVAPI_D3D12_PSO_VERTEX_SHADER_DESC();
				memset(pExtn, 0, sizeof(*pExtn));
				pExtn.baseVersion = NV_PSO_EXTENSION_DESC_VER;
				pExtn.psoExtension = NV_PSO_VERTEX_SHADER_EXTENSION;
				pExtn.version = NV_VERTEX_SHADER_PSO_EXTENSION_DESC_VER;

				pExtn.NumCustomSemantics = d.numCustomSemantics;
				pExtn.pCustomSemantics = &shader.customSemantics[0];
				pExtn.UseSpecificShaderExt = d.useSpecificShaderExt;

				shader.extensions.push_back(pExtn);
			}
			break;
		case ShaderType.Hull:
			if (d.numCustomSemantics)
			{
				NVAPI_D3D12_PSO_HULL_SHADER_DESC* pExtn = new NVAPI_D3D12_PSO_HULL_SHADER_DESC();
				memset(pExtn, 0, sizeof(*pExtn));
				pExtn.baseVersion = NV_PSO_EXTENSION_DESC_VER;
				pExtn.psoExtension = NV_PSO_VERTEX_SHADER_EXTENSION;
				pExtn.version = NV_HULL_SHADER_PSO_EXTENSION_DESC_VER;

				pExtn.NumCustomSemantics = d.numCustomSemantics;
				pExtn.pCustomSemantics = &shader.customSemantics[0];
				pExtn.UseSpecificShaderExt = d.useSpecificShaderExt;

				shader.extensions.push_back(pExtn);
			}
			break;
		case ShaderType.Domain:
			if (d.numCustomSemantics)
			{
				NVAPI_D3D12_PSO_DOMAIN_SHADER_DESC* pExtn = new NVAPI_D3D12_PSO_DOMAIN_SHADER_DESC();
				memset(pExtn, 0, sizeof(*pExtn));
				pExtn.baseVersion = NV_PSO_EXTENSION_DESC_VER;
				pExtn.psoExtension = NV_PSO_VERTEX_SHADER_EXTENSION;
				pExtn.version = NV_DOMAIN_SHADER_PSO_EXTENSION_DESC_VER;

				pExtn.NumCustomSemantics = d.numCustomSemantics;
				pExtn.pCustomSemantics = &shader.customSemantics[0];
				pExtn.UseSpecificShaderExt = d.useSpecificShaderExt;

				shader.extensions.push_back(pExtn);
			}
			break;
		case ShaderType.Geometry:
			if ((d.fastGSFlags & FastGeometryShaderFlags.ForceFastGS) != 0 || d.numCustomSemantics || d.pCoordinateSwizzling)
			{
				NVAPI_D3D12_PSO_GEOMETRY_SHADER_DESC* pExtn = new NVAPI_D3D12_PSO_GEOMETRY_SHADER_DESC();
				memset(pExtn, 0, sizeof(*pExtn));
				pExtn.baseVersion = NV_PSO_EXTENSION_DESC_VER;
				pExtn.psoExtension = NV_PSO_GEOMETRY_SHADER_EXTENSION;
				pExtn.version = NV_GEOMETRY_SHADER_PSO_EXTENSION_DESC_VER;

				pExtn.NumCustomSemantics = d.numCustomSemantics;
				pExtn.pCustomSemantics = d.numCustomSemantics ? &shader.customSemantics[0] : null;
				pExtn.UseCoordinateSwizzle = d.pCoordinateSwizzling != null;
				pExtn.pCoordinateSwizzling = d.pCoordinateSwizzling != null ? &shader.coordinateSwizzling[0] : null;
				pExtn.ForceFastGS = (d.fastGSFlags & FastGeometryShaderFlags.ForceFastGS) != 0;
				pExtn.UseViewportMask = (d.fastGSFlags & FastGeometryShaderFlags.UseViewportMask) != 0;
				pExtn.OffsetRtIndexByVpIndex = (d.fastGSFlags & FastGeometryShaderFlags.OffsetTargetIndexByViewportIndex) != 0;
				pExtn.DontUseViewportOrder = (d.fastGSFlags & FastGeometryShaderFlags.StrictApiOrder) != 0;
				pExtn.UseSpecificShaderExt = d.useSpecificShaderExt;
				pExtn.UseAttributeSkipMask = false;

				shader.extensions.push_back(pExtn);
			}
			break;

		case ShaderType.Compute:
		case ShaderType.Pixel:
		case ShaderType.Amplification:
		case ShaderType.Mesh:
		case ShaderType.AllGraphics:
		case ShaderType.RayGeneration:
		case ShaderType.Miss:
		case ShaderType.ClosestHit:
		case ShaderType.AnyHit:
		case ShaderType.Intersection:
			if (d.numCustomSemantics)
			{
				nvrhi.utils.NotSupported();
				return null;
			}
			break;

		case ShaderType.None:
		case ShaderType.AllRayTracing:
		case ShaderType.All:
		default:
			nvrhi.utils.InvalidEnum();
			return null;
		}
#else
		if (d.numCustomSemantics != 0 || d.pCoordinateSwizzling != null || (d.fastGSFlags != 0) || d.hlslExtensionsUAV >= 0)
		{
			nvrhi.utils.NotSupported();
			delete shader;

			// NVAPI is unavailable
			return null;
		}
#endif

		return ShaderHandle.Attach(shader);
	}
	public override ShaderHandle createShaderSpecialization(IShader shader, ShaderSpecialization* data, uint32 num)
	{
		nvrhi.utils.NotSupported();
		return null;
	}
	public override ShaderLibraryHandle createShaderLibrary(void* binary, int binarySize)
	{
		ShaderLibrary shaderLibrary = new ShaderLibrary();

		shaderLibrary.bytecode.Resize(binarySize);
		Internal.MemCpy(&shaderLibrary.bytecode[0], binary, binarySize);

		return ShaderLibraryHandle.Attach(shaderLibrary);
	}

	public override SamplerHandle createSampler(SamplerDesc d)
	{
		Sampler sampler = new Sampler(m_Context, d);
		return SamplerHandle.Attach(sampler);
	}

	public override InputLayoutHandle createInputLayout(VertexAttributeDesc* d, uint32 attributeCount, IShader vertexShader)
	{
		// The shader is not needed here, there are no separate IL objects in DX12
		(void)vertexShader;

		InputLayout layout = new InputLayout();
		layout.attributes.Resize(attributeCount);

		for (uint32 index = 0; index < attributeCount; index++)
		{
			ref VertexAttributeDesc attr = ref layout.attributes[index];

			// Copy the description to get a stable name pointer in desc
			attr = d[index];

			Runtime.Assert(attr.arraySize > 0);

			readonly ref DxgiFormatMapping formatMapping = ref getDxgiFormatMapping(attr.format);
			readonly ref FormatInfo formatInfo = ref getFormatInfo(attr.format);

			for (uint32 semanticIndex = 0; semanticIndex < attr.arraySize; semanticIndex++)
			{
				D3D12_INPUT_ELEMENT_DESC desc;

				desc.SemanticName = (uint8*)attr.name.CStr();
				desc.AlignedByteOffset = attr.offset + semanticIndex * formatInfo.bytesPerBlock;
				desc.Format = formatMapping.srvFormat;
				desc.InputSlot = attr.bufferIndex;
				desc.SemanticIndex = semanticIndex;

				if (attr.isInstanced)
				{
					desc.InputSlotClass = D3D12_INPUT_CLASSIFICATION.INSTANCE_DATA;
					desc.InstanceDataStepRate = 1;
				}
				else
				{
					desc.InputSlotClass = D3D12_INPUT_CLASSIFICATION.VERTEX_DATA;
					desc.InstanceDataStepRate = 0;
				}

				layout.inputElements.Add(desc);
			}

			if (!layout.elementStrides.ContainsKey(attr.bufferIndex))
			{
				layout.elementStrides[attr.bufferIndex] = attr.elementStride;
			} else
			{
				Runtime.Assert(layout.elementStrides[attr.bufferIndex] == attr.elementStride);
			}
		}

		return InputLayoutHandle.Attach(layout);
	}

	public override EventQueryHandle createEventQuery()
	{
		EventQuery ret = new EventQuery();
		return EventQueryHandle.Attach(ret);
	}

	public override void setEventQuery(IEventQuery _query, CommandQueue queue)
	{
		EventQuery query = checked_cast<EventQuery, IEventQuery>(_query);
		Queue pQueue = getQueue(queue);

		query.started = true;
		query.fence = pQueue.fence;
		query.fenceCounter = pQueue.lastSubmittedInstance;
		query.resolved = false;
	}
	public override bool pollEventQuery(IEventQuery _query)
	{
		EventQuery query = checked_cast<EventQuery, IEventQuery>(_query);

		if (!query.started)
			return false;

		if (query.resolved)
			return true;

		Runtime.Assert(query.fence != null);

		if (query.fence.GetCompletedValue() >= query.fenceCounter)
		{
			query.resolved = true;
			query.fence = null;
		}

		return query.resolved;
	}
	public override void waitEventQuery(IEventQuery _query)
	{
		EventQuery query = checked_cast<EventQuery, IEventQuery>(_query);

		if (!query.started || query.resolved)
			return;

		Runtime.Assert(query.fence != null);

		WaitForFence(query.fence, query.fenceCounter, m_FenceEvent);
	}
	public override void resetEventQuery(IEventQuery _query)
	{
		EventQuery query = checked_cast<EventQuery, IEventQuery>(_query);

		query.started = false;
		query.resolved = false;
		query.fence = null;
	}

	public override TimerQueryHandle createTimerQuery()
	{
		if (m_Context.timerQueryHeap == null)
		{
			m_Mutex.Enter(); defer m_Mutex.Exit();

			if (m_Context.timerQueryHeap == null)
			{
				D3D12_QUERY_HEAP_DESC queryHeapDesc = .();
				queryHeapDesc.Type = D3D12_QUERY_HEAP_TYPE.TIMESTAMP;
				queryHeapDesc.Count = uint32(m_Resources.timerQueries.getCapacity()) * 2; // Use 2 D3D12 queries per 1 TimerQuery
				m_Context.device.CreateQueryHeap(queryHeapDesc, ID3D12QueryHeap.IID, (void**)(&m_Context.timerQueryHeap));

				BufferDesc qbDesc = .();
				qbDesc.byteSize = queryHeapDesc.Count * 8;
				qbDesc.cpuAccess = CpuAccessMode.Read;

				BufferHandle timerQueryBuffer = createBuffer(qbDesc);
				m_Context.timerQueryResolveBuffer = checked_cast<Buffer, IBuffer>(timerQueryBuffer?.Get<IBuffer>());
			}
		}

		int32 queryIndex = m_Resources.timerQueries.allocate();

		if (queryIndex < 0)
			return null;

		TimerQuery query = new TimerQuery(m_Resources);
		query.beginQueryIndex = uint32(queryIndex) * 2;
		query.endQueryIndex = query.beginQueryIndex + 1;
		query.resolved = false;
		query.time = 0.f;

		return TimerQueryHandle.Attach(query);
	}
	public override bool pollTimerQuery(ITimerQuery _query)
	{
		TimerQuery query = checked_cast<TimerQuery, ITimerQuery>(_query);

		if (!query.started)
			return false;

		if (query.fence == null)
			return true;

		if (query.fence.GetCompletedValue() >= query.fenceCounter)
		{
			query.fence = null;
			return true;
		}

		return false;
	}
	public override float getTimerQueryTime(ITimerQuery _query)
	{
		TimerQuery query = checked_cast<TimerQuery, ITimerQuery>(_query);

		if (!query.resolved)
		{
			if (query.fence != null)
			{
				WaitForFence(query.fence, query.fenceCounter, m_FenceEvent);
				query.fence = null;
			}

			uint64 frequency = 0;
			getQueue(CommandQueue.Graphics).queue.GetTimestampFrequency(out frequency);

			D3D12_RANGE bufferReadRange = .()
				{
					Begin = query.beginQueryIndex * sizeof(uint64),
					End = (query.beginQueryIndex + 2) * sizeof(uint64)
				};
			uint64* data = null;
			readonly HRESULT res = m_Context.timerQueryResolveBuffer.resource.Map(0, &bufferReadRange, (void**)&data);

			if (FAILED(res))
			{
				m_Context.error("getTimerQueryTime: Map() failed");
				return 0.f;
			}

			query.resolved = true;
			query.time = float(double(data[query.endQueryIndex] - data[query.beginQueryIndex]) / double(frequency));

			m_Context.timerQueryResolveBuffer.resource.Unmap(0, null);
		}

		return query.time;
	}
	public override void resetTimerQuery(ITimerQuery _query)
	{
		TimerQuery query = checked_cast<TimerQuery, ITimerQuery>(_query);

		query.started = false;
		query.resolved = false;
		query.time = 0.f;
		query.fence = null;
	}

	public override GraphicsAPI getGraphicsAPI()
	{
		return GraphicsAPI.D3D12;
	}

	public override FramebufferHandle createFramebuffer(FramebufferDesc desc)
	{
		Framebuffer fb = new Framebuffer(m_Resources);
		fb.desc = desc;
		fb.framebufferInfo = FramebufferInfo(desc);

		if (!desc.colorAttachments.IsEmpty)
		{
			Texture texture = checked_cast<Texture, ITexture>(desc.colorAttachments[0].texture);
			fb.rtWidth = texture.desc.width;
			fb.rtHeight = texture.desc.height;
		} else if (desc.depthAttachment.valid())
		{
			Texture texture = checked_cast<Texture, ITexture>(desc.depthAttachment.texture);
			fb.rtWidth = texture.desc.width;
			fb.rtHeight = texture.desc.height;
		}

		for (int rt = 0; rt < desc.colorAttachments.Count; rt++)
		{
			var attachment = /*ref*/ desc.colorAttachments[rt];

			Texture texture = checked_cast<Texture, ITexture>(attachment.texture);
			Runtime.Assert(texture.desc.width == fb.rtWidth);
			Runtime.Assert(texture.desc.height == fb.rtHeight);

			DescriptorIndex index = m_Resources.renderTargetViewHeap.allocateDescriptor();

			readonly D3D12_CPU_DESCRIPTOR_HANDLE descriptorHandle = m_Resources.renderTargetViewHeap.getCpuHandle(index);
			texture.createRTV((.)descriptorHandle.ptr, attachment.format, attachment.subresources);

			fb.RTVs.PushBack(index);
			fb.textures.PushBack(texture);
		}

		if (desc.depthAttachment.valid())
		{
			Texture texture = checked_cast<Texture, ITexture>(desc.depthAttachment.texture);
			Runtime.Assert(texture.desc.width == fb.rtWidth);
			Runtime.Assert(texture.desc.height == fb.rtHeight);

			DescriptorIndex index = m_Resources.depthStencilViewHeap.allocateDescriptor();

			readonly D3D12_CPU_DESCRIPTOR_HANDLE descriptorHandle = m_Resources.depthStencilViewHeap.getCpuHandle(index);
			texture.createDSV((.)descriptorHandle.ptr, desc.depthAttachment.subresources, desc.depthAttachment.isReadOnly);

			fb.DSV = index;
			fb.textures.PushBack(texture);
		}

		return FramebufferHandle.Attach(fb);
	}

	public override GraphicsPipelineHandle createGraphicsPipeline(GraphicsPipelineDesc desc, IFramebuffer fb)
	{
		RefCountPtr<RootSignature> pRS = getRootSignature(desc.bindingLayouts, desc.inputLayout != null);

		D3D12RefCountPtr<ID3D12PipelineState> pPSO = createPipelineState(desc, pRS, fb.getFramebufferInfo());

		return createHandleForNativeGraphicsPipeline(pRS, pPSO, desc, fb.getFramebufferInfo());
	}

	public override ComputePipelineHandle createComputePipeline(ComputePipelineDesc desc)
	{
		RefCountPtr<RootSignature> pRS = getRootSignature(desc.bindingLayouts, false);
		D3D12RefCountPtr<ID3D12PipelineState> pPSO = createPipelineState(desc, pRS);

		if (pPSO == null)
			return null;

		ComputePipeline pso = new ComputePipeline();

		pso.desc = desc;

		pso.rootSignature = pRS;
		pso.pipelineState = pPSO;

		return ComputePipelineHandle.Attach(pso);
	}

	public override MeshletPipelineHandle createMeshletPipeline(MeshletPipelineDesc desc, IFramebuffer fb)
	{
		RefCountPtr<RootSignature> pRS = getRootSignature(desc.bindingLayouts, false);

		D3D12RefCountPtr<ID3D12PipelineState> pPSO = createPipelineState(desc, pRS, fb.getFramebufferInfo());

		return createHandleForNativeMeshletPipeline(pRS, pPSO, desc, fb.getFramebufferInfo());
	}

	public static mixin NEW_ON_STACK<T>()
	{
		T* data = null;
		data = scope:: [Align(alignof(T))] T[1]*;
		data
	}

	struct Library
	{
		public void* pBlob = null;
		public int blobSize = 0;
		public List<(char16*, char16*)> exports; // vector(originalName, newName)
		public List<D3D12_EXPORT_DESC> d3dExports;
	}

	public override nvrhi.rt.PipelineHandle createRayTracingPipeline(nvrhi.rt.PipelineDesc desc)
	{
		RayTracingPipeline pso = new RayTracingPipeline(m_Context);
		pso.desc = desc;
		pso.maxLocalRootParameters = 0;

		// Collect all DXIL libraries that are referenced in `desc`, and enumerate their exports.
		// Build local root signatures for all referenced local binding layouts.
		// Convert the export names to wstring.

		

		// Go through the individual shaders first.

		Dictionary<void*, Library> dxilLibraries = scope .();

		for (readonly ref nvrhi.rt.PipelineShaderDesc shaderDesc in ref desc.shaders)
		{
			void* pBlob = null;
			int blobSize = 0;
			shaderDesc.shader.getBytecode(&pBlob, &blobSize);

			// Assuming that no shader is referenced twice, we just add every shader to its library export list.

			ref Library library = ref dxilLibraries[pBlob];
			library.pBlob = pBlob;
			library.blobSize = blobSize;

			String originalShaderName = shaderDesc.shader.getDesc().entryName;
			String newShaderName = shaderDesc.exportName.IsEmpty ? originalShaderName : shaderDesc.exportName;

			library.exports.Add((originalShaderName.ToScopedNativeWChar!::(), newShaderName.ToScopedNativeWChar!::()));

			// Build a local root signature for the shader, if needed.

			if (shaderDesc.bindingLayout != null)
			{
				ref RootSignatureHandle localRS = ref pso.localRootSignatures[shaderDesc.bindingLayout];
				if (localRS == null)
				{
					StaticVector<BindingLayoutHandle, const c_MaxBindingLayouts> pipelineLayouts = .();
					pipelineLayouts.PushBack(shaderDesc.bindingLayout);
					localRS = buildRootSignature(pipelineLayouts, false, true);

					BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(shaderDesc.bindingLayout?.Get<IBindingLayout>());
					pso.maxLocalRootParameters = Math.Max(pso.maxLocalRootParameters, uint32(layout.rootParameters.Count));
				}
			}
		}

		// Still in the collection phase - go through the hit groups.
		// Rename all exports used in the hit groups to avoid collisions between different libraries.

		List<D3D12_HIT_GROUP_DESC> d3dHitGroups = scope .();
		Dictionary<IShader, char16*> hitGroupShaderNames = scope .();
		List<char16*> hitGroupExportNames = scope .();

		for (readonly ref nvrhi.rt.PipelineHitGroupDesc hitGroupDesc in ref desc.hitGroups)
		{
			for (readonly /*ref*/ ShaderHandle shader in /*ref*/ scope List<IShader>() { hitGroupDesc.closestHitShader, hitGroupDesc.anyHitShader, hitGroupDesc.intersectionShader })
			{
				if (shader == null)
					continue;

				char16* newName = hitGroupShaderNames[shader];

				// See if we've encountered this particular shader before...

				if (newName == null)
				{
					// No - add it to the corresponding library, come up with a new name for it.

					const void* pBlob = null;
					int blobSize = 0;
					shader.getBytecode(&pBlob, &blobSize);

					ref Library library = ref dxilLibraries[pBlob];
					library.pBlob = pBlob;
					library.blobSize = blobSize;

					String originalShaderName = shader.getDesc().entryName;
					String newShaderName = scope:: $"{originalShaderName}{hitGroupShaderNames.Count}";

					library.exports.Add((originalShaderName.ToScopedNativeWChar!::(), newShaderName.ToScopedNativeWChar!::()));

					newName = newShaderName.ToScopedNativeWChar!::();
				}
			}

			// Build a local root signature for the hit group, if needed.

			if (hitGroupDesc.bindingLayout != null)
			{
				ref RootSignatureHandle localRS = ref pso.localRootSignatures[hitGroupDesc.bindingLayout];
				if (localRS == null)
				{
					StaticVector<BindingLayoutHandle, const c_MaxBindingLayouts> pipelineLayouts = .();
					pipelineLayouts.PushBack(hitGroupDesc.bindingLayout);
					localRS = buildRootSignature(pipelineLayouts, false, true);

					BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(hitGroupDesc.bindingLayout?.Get<IBindingLayout>());
					pso.maxLocalRootParameters = Math.Max(pso.maxLocalRootParameters, uint32(layout.rootParameters.Count));
				}
			}

			// Create a hit group descriptor and store the new export names in it.

			D3D12_HIT_GROUP_DESC d3dHitGroupDesc = .();
			if (hitGroupDesc.anyHitShader != null)
				d3dHitGroupDesc.AnyHitShaderImport = hitGroupShaderNames[hitGroupDesc.anyHitShader];
			if (hitGroupDesc.closestHitShader != null)
				d3dHitGroupDesc.ClosestHitShaderImport = hitGroupShaderNames[hitGroupDesc.closestHitShader];
			if (hitGroupDesc.intersectionShader != null)
				d3dHitGroupDesc.IntersectionShaderImport = hitGroupShaderNames[hitGroupDesc.intersectionShader];

			if (hitGroupDesc.isProceduralPrimitive)
				d3dHitGroupDesc.Type = D3D12_HIT_GROUP_TYPE.PROCEDURAL_PRIMITIVE;
			else
				d3dHitGroupDesc.Type = D3D12_HIT_GROUP_TYPE.TRIANGLES;

			char16* hitGroupExportName = hitGroupDesc.exportName.ToScopedNativeWChar!::();
			hitGroupExportNames.Add(hitGroupExportName); // store the wstring so that it's not deallocated
			d3dHitGroupDesc.HitGroupExport = hitGroupExportNames[hitGroupExportNames.Count - 1];
			d3dHitGroups.Add(d3dHitGroupDesc);
		}

		// Create descriptors for DXIL libraries, enumerate the exports used from each library.

		List<D3D12_DXIL_LIBRARY_DESC> d3dDxilLibraries = scope .();
		d3dDxilLibraries.Reserve(dxilLibraries.Count);
		for (var it in ref dxilLibraries)
		{
			ref Library library = ref *it.valueRef;

			for (readonly (char16* key, char16* value) exportNames in library.exports)
			{
				D3D12_EXPORT_DESC d3dExportDesc = .();
				d3dExportDesc.ExportToRename = exportNames.key;
				d3dExportDesc.Name = exportNames.value;
				d3dExportDesc.Flags = D3D12_EXPORT_FLAGS.FLAG_NONE;
				library.d3dExports.Add(d3dExportDesc);
			}

			D3D12_DXIL_LIBRARY_DESC d3dLibraryDesc = .();
			d3dLibraryDesc.DXILLibrary.pShaderBytecode = library.pBlob;
			d3dLibraryDesc.DXILLibrary.BytecodeLength = (.)library.blobSize;
			d3dLibraryDesc.NumExports = UINT(library.d3dExports.Count);
			d3dLibraryDesc.pExports = library.d3dExports.Ptr;

			d3dDxilLibraries.Add(d3dLibraryDesc);
		}

		// Start building the D3D state subobject array.

		List<D3D12_STATE_SUBOBJECT> d3dSubobjects = scope .();

		// Same subobject is reused multiple times and copied to the vector each time.
		D3D12_STATE_SUBOBJECT d3dSubobject = .();

		// Subobject: Shader config

		D3D12_RAYTRACING_SHADER_CONFIG d3dShaderConfig = .();
		d3dShaderConfig.MaxAttributeSizeInBytes = desc.maxAttributeSize;
		d3dShaderConfig.MaxPayloadSizeInBytes = desc.maxPayloadSize;

		d3dSubobject.Type = D3D12_STATE_SUBOBJECT_TYPE.RAYTRACING_SHADER_CONFIG;
		d3dSubobject.pDesc = &d3dShaderConfig;
		d3dSubobjects.Add(d3dSubobject);

		// Subobject: Pipeline config

		D3D12_RAYTRACING_PIPELINE_CONFIG d3dPipelineConfig = .();
		d3dPipelineConfig.MaxTraceRecursionDepth = desc.maxRecursionDepth;

		d3dSubobject.Type = D3D12_STATE_SUBOBJECT_TYPE.RAYTRACING_PIPELINE_CONFIG;
		d3dSubobject.pDesc = &d3dPipelineConfig;
		d3dSubobjects.Add(d3dSubobject);

		// Subobjects: DXIL libraries

		for (readonly ref D3D12_DXIL_LIBRARY_DESC d3dLibraryDesc in ref d3dDxilLibraries)
		{
			d3dSubobject.Type = D3D12_STATE_SUBOBJECT_TYPE.DXIL_LIBRARY;
			d3dSubobject.pDesc = &d3dLibraryDesc;
			d3dSubobjects.Add(d3dSubobject);
		}

		// Subobjects: hit groups

		for (readonly ref D3D12_HIT_GROUP_DESC d3dHitGroupDesc in ref d3dHitGroups)
		{
			d3dSubobject.Type = D3D12_STATE_SUBOBJECT_TYPE.HIT_GROUP;
			d3dSubobject.pDesc = &d3dHitGroupDesc;
			d3dSubobjects.Add(d3dSubobject);
		}

		// Subobject: global root signature

		D3D12_GLOBAL_ROOT_SIGNATURE d3dGlobalRootSignature = .();

		if (!desc.globalBindingLayouts.IsEmpty)
		{
			RootSignatureHandle rootSignature = buildRootSignature(desc.globalBindingLayouts, false, false);
			pso.globalRootSignature = checked_cast<RootSignature, IRootSignature>(rootSignature.Get<IRootSignature>());
			d3dGlobalRootSignature.pGlobalRootSignature = (ID3D12RootSignature*)pso.globalRootSignature.getNativeObject(ObjectType.D3D12_RootSignature).pointer;

			d3dSubobject.Type = D3D12_STATE_SUBOBJECT_TYPE.GLOBAL_ROOT_SIGNATURE;
			d3dSubobject.pDesc = &d3dGlobalRootSignature;
			d3dSubobjects.Add(d3dSubobject);
		}

		// Subobjects: local root signatures

		// Make sure that adding local root signatures does not resize the array,
		// because we need to store pointers to array elements there.
		d3dSubobjects.Reserve(d3dSubobjects.Count + pso.localRootSignatures.Count * 2);

		// Same - pre-allocate the arrays to avoid resizing them
		int numAssociations = desc.shaders.Count + desc.hitGroups.Count;
		List<char16*> d3dAssociationExports = scope .();
		List<char16*> d3dAssociationExportsCStr = scope .();
		d3dAssociationExports.Reserve(numAssociations);
		d3dAssociationExportsCStr.Reserve(numAssociations);

		for (readonly var it in /*ref*/ pso.localRootSignatures)
		{
			var d3dLocalRootSignature = NEW_ON_STACK!<D3D12_LOCAL_ROOT_SIGNATURE>();
			d3dLocalRootSignature.pLocalRootSignature = (ID3D12RootSignature*)it.value.getNativeObject(ObjectType.D3D12_RootSignature).pointer;

			d3dSubobject.Type = D3D12_STATE_SUBOBJECT_TYPE.LOCAL_ROOT_SIGNATURE;
			d3dSubobject.pDesc = d3dLocalRootSignature;
			d3dSubobjects.Add(d3dSubobject);

			var d3dAssociation = NEW_ON_STACK!<D3D12_SUBOBJECT_TO_EXPORTS_ASSOCIATION>();
			d3dAssociation.pSubobjectToAssociate = &d3dSubobjects[d3dSubobjects.Count - 1];
			d3dAssociation.NumExports = 0;
			int firstExportIndex = d3dAssociationExportsCStr.Count;

			for (var shader in desc.shaders)
			{
				if (shader.bindingLayout == it.key)
				{
					String exportName = !String.IsNullOrEmpty(shader.exportName) ? shader.shader.getDesc().entryName : shader.exportName;
					d3dAssociationExports.Add(exportName.ToScopedNativeWChar!::());
					d3dAssociationExportsCStr.Add(d3dAssociationExports[d3dAssociationExports.Count - 1]);
					d3dAssociation.NumExports += 1;
				}
			}

			for (var hitGroup in desc.hitGroups)
			{
				if (hitGroup.bindingLayout == it.key)
				{
					d3dAssociationExports.Add(hitGroup.exportName.ToScopedNativeWChar!::());
					d3dAssociationExportsCStr.Add(d3dAssociationExports[d3dAssociationExports.Count - 1]);
					d3dAssociation.NumExports += 1;
				}
			}

			d3dAssociation.pExports = &d3dAssociationExportsCStr[firstExportIndex];

			d3dSubobject.Type = D3D12_STATE_SUBOBJECT_TYPE.SUBOBJECT_TO_EXPORTS_ASSOCIATION;
			d3dSubobject.pDesc = d3dAssociation;
			d3dSubobjects.Add(d3dSubobject);
		}

		// Top-level PSO descriptor structure

		D3D12_STATE_OBJECT_DESC pipelineDesc = .();
		pipelineDesc.Type = D3D12_STATE_OBJECT_TYPE.RAYTRACING_PIPELINE;
		pipelineDesc.NumSubobjects = (UINT)(d3dSubobjects.Count);
		pipelineDesc.pSubobjects = d3dSubobjects.Ptr;

		HRESULT hr = m_Context.device5.CreateStateObject(pipelineDesc, ID3D12StateObject.IID, (void**)(&pso.pipelineState));
		if (FAILED(hr))
		{
			m_Context.error("Failed to create a DXR pipeline state object");
			return null;
		}

		hr = pso.pipelineState.QueryInterface(ID3D12StateObjectProperties.IID, (void**)(&pso.pipelineInfo));
		if (FAILED(hr))
		{
			m_Context.error("Failed to get a DXR pipeline info interface from a PSO");
			return null;
		}

		for (readonly ref nvrhi.rt.PipelineShaderDesc shaderDesc in ref desc.shaders)
		{
			String exportName = !String.IsNullOrEmpty(shaderDesc.exportName) ? shaderDesc.exportName : shaderDesc.shader.getDesc().entryName;
			readonly void* pShaderIdentifier = pso.pipelineInfo.GetShaderIdentifier(exportName.ToScopedNativeWChar!::());

			if (pShaderIdentifier == null)
			{
				m_Context.error("Failed to get an identifier for a shader in a fresh DXR PSO");
				return null;
			}

			pso.exports[exportName] = RayTracingPipeline.ExportTableEntry() { bindingLayout = shaderDesc.bindingLayout, pShaderIdentifier = pShaderIdentifier };
		}

		for (readonly ref nvrhi.rt.PipelineHitGroupDesc hitGroupDesc in ref desc.hitGroups)
		{
			readonly void* pShaderIdentifier = pso.pipelineInfo.GetShaderIdentifier(hitGroupDesc.exportName.ToScopedNativeWChar!::());

			if (pShaderIdentifier == null)
			{
				m_Context.error("Failed to get an identifier for a hit group in a fresh DXR PSO");
				return null;
			}

			pso.exports[hitGroupDesc.exportName] = RayTracingPipeline.ExportTableEntry() { bindingLayout = hitGroupDesc.bindingLayout, pShaderIdentifier = pShaderIdentifier };
		}

		return nvrhi.rt.PipelineHandle.Attach(pso);
	}

	public override BindingLayoutHandle createBindingLayout(BindingLayoutDesc desc)
	{
		BindingLayout ret = new BindingLayout(desc);
		return BindingLayoutHandle.Attach(ret);
	}
	public override BindingLayoutHandle createBindlessLayout(BindlessLayoutDesc desc)
	{
		BindlessLayout ret = new BindlessLayout(desc);
		return BindingLayoutHandle.Attach(ret);
	}

	public override BindingSetHandle createBindingSet(BindingSetDesc desc, IBindingLayout _layout)
	{
		BindingSet ret = new BindingSet(m_Context, m_Resources);
		ret.desc = desc;

		BindingLayout pipelineLayout = checked_cast<BindingLayout, IBindingLayout>(_layout);
		ret.layout = pipelineLayout;

		ret.createDescriptors();

		return BindingSetHandle.Attach(ret);
	}
	public override DescriptorTableHandle createDescriptorTable(IBindingLayout layout)
	{
		(void)layout; // not necessary on DX12

		DescriptorTable ret = new DescriptorTable(m_Resources);
		ret.capacity = 0;
		ret.firstDescriptor = 0;

		return DescriptorTableHandle.Attach(ret);
	}

	public override void resizeDescriptorTable(IDescriptorTable _descriptorTable, uint32 newSize, bool keepContents)
	{
		DescriptorTable descriptorTable = checked_cast<DescriptorTable, IDescriptorTable>(_descriptorTable);

		if (newSize == descriptorTable.capacity)
			return;

		if (newSize < descriptorTable.capacity)
		{
			m_Resources.shaderResourceViewHeap.releaseDescriptors(descriptorTable.firstDescriptor + newSize, (.)descriptorTable.capacity - newSize);
			descriptorTable.capacity = newSize;
			return;
		}

		uint32 originalFirst = descriptorTable.firstDescriptor;
		if (!keepContents && descriptorTable.capacity > 0)
		{
			m_Resources.shaderResourceViewHeap.releaseDescriptors(descriptorTable.firstDescriptor, descriptorTable.capacity);
		}

		descriptorTable.firstDescriptor = m_Resources.shaderResourceViewHeap.allocateDescriptors(newSize);

		if (keepContents && descriptorTable.capacity > 0)
		{
			m_Context.device.CopyDescriptorsSimple(descriptorTable.capacity,
				m_Resources.shaderResourceViewHeap.getCpuHandle(descriptorTable.firstDescriptor),
				m_Resources.shaderResourceViewHeap.getCpuHandle(originalFirst),
				D3D12_DESCRIPTOR_HEAP_TYPE.CBV_SRV_UAV);

			m_Context.device.CopyDescriptorsSimple(descriptorTable.capacity,
				m_Resources.shaderResourceViewHeap.getCpuHandleShaderVisible(descriptorTable.firstDescriptor),
				m_Resources.shaderResourceViewHeap.getCpuHandle(originalFirst),
				D3D12_DESCRIPTOR_HEAP_TYPE.CBV_SRV_UAV);

			m_Resources.shaderResourceViewHeap.releaseDescriptors(originalFirst, descriptorTable.capacity);
		}

		descriptorTable.capacity = newSize;
	}
	public override bool writeDescriptorTable(IDescriptorTable _descriptorTable, BindingSetItem binding)
	{
		DescriptorTable descriptorTable = checked_cast<DescriptorTable, IDescriptorTable>(_descriptorTable);

		if (binding.slot >= descriptorTable.capacity)
			return false;

		D3D12_CPU_DESCRIPTOR_HANDLE descriptorHandle = m_Resources.shaderResourceViewHeap.getCpuHandle(descriptorTable.firstDescriptor + binding.slot);

		switch (binding.type)
		{
		case ResourceType.None:
			Buffer.createNullSRV((.)descriptorHandle.ptr, Format.UNKNOWN, m_Context);
			break;
		case ResourceType.Texture_SRV:
			{
				Texture texture = checked_cast<Texture, IResource>(binding.resourceHandle);
				texture.createSRV((.)descriptorHandle.ptr, binding.format, binding.dimension, binding.subresources);
				break;
			}
		case ResourceType.Texture_UAV:
			{
				Texture texture = checked_cast<Texture, IResource>(binding.resourceHandle);
				texture.createUAV((.)descriptorHandle.ptr, binding.format, binding.dimension, binding.subresources);
				break;
			}
		case ResourceType.TypedBuffer_SRV: fallthrough;
		case ResourceType.StructuredBuffer_SRV: fallthrough;
		case ResourceType.RawBuffer_SRV:
			{
				Buffer buffer = checked_cast<Buffer, IResource>(binding.resourceHandle);
				buffer.createSRV((.)descriptorHandle.ptr, binding.format, binding.range, binding.type);
				break;
			}
		case ResourceType.TypedBuffer_UAV: fallthrough;
		case ResourceType.StructuredBuffer_UAV: fallthrough;
		case ResourceType.RawBuffer_UAV:
			{
				Buffer buffer = checked_cast<Buffer, IResource>(binding.resourceHandle);
				buffer.createUAV((.)descriptorHandle.ptr, binding.format, binding.range, binding.type);
				break;
			}
		case ResourceType.ConstantBuffer:
			{
				Buffer buffer = checked_cast<Buffer, IResource>(binding.resourceHandle);
				buffer.createCBV((.)descriptorHandle.ptr);
				break;
			}
		case ResourceType.RayTracingAccelStruct:
			{
				AccelStruct accelStruct = checked_cast<AccelStruct, IResource>(binding.resourceHandle);
				accelStruct.createSRV((.)descriptorHandle.ptr);
				break;
			}

		case ResourceType.VolatileConstantBuffer:
			m_Context.error("Attempted to bind a volatile constant buffer to a bindless set.");
			return false;

		case ResourceType.Sampler: fallthrough;
		case ResourceType.PushConstants: fallthrough;
		case ResourceType.Count: fallthrough;
		default:
			nvrhi.utils.InvalidEnum();
			return false;
		}

		m_Resources.shaderResourceViewHeap.copyToShaderVisibleHeap(descriptorTable.firstDescriptor + binding.slot, 1);
		return true;
	}

	public override nvrhi.rt.AccelStructHandle createAccelStruct(nvrhi.rt.AccelStructDesc desc)
	{
		List<D3D12_RAYTRACING_GEOMETRY_DESC> d3dGeometryDescs = scope .();
		d3dGeometryDescs.Resize(desc.bottomLevelGeometries.Count);

		D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS ASInputs;
		if (desc.isTopLevel)
		{
			ASInputs.Type = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE.TOP_LEVEL;
			ASInputs.InstanceDescs = 0;
			ASInputs.NumDescs = UINT(desc.topLevelMaxInstances);
		}
		else
		{
			for (uint32 i = 0; i < desc.bottomLevelGeometries.Count; i++)
			{
				fillD3dGeometryDesc(ref d3dGeometryDescs[i], desc.bottomLevelGeometries[i]);
			}

			ASInputs.Type = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE.BOTTOM_LEVEL;
			ASInputs.pGeometryDescs = d3dGeometryDescs.Ptr;
			ASInputs.NumDescs = UINT(d3dGeometryDescs.Count);
		}

		ASInputs.DescsLayout = D3D12_ELEMENTS_LAYOUT.ARRAY;
		ASInputs.Flags = (D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAGS)desc.buildFlags;

		D3D12_RAYTRACING_ACCELERATION_STRUCTURE_PREBUILD_INFO ASPreBuildInfo = .();
		m_Context.device5.GetRaytracingAccelerationStructurePrebuildInfo(ASInputs, out ASPreBuildInfo);

		AccelStruct @as = new AccelStruct(m_Context);
		@as.desc = desc;
		@as.allowUpdate = (desc.buildFlags & nvrhi.rt.AccelStructBuildFlags.AllowUpdate) != 0;

		Runtime.Assert(ASPreBuildInfo.ResultDataMaxSizeInBytes <= ~0u);

#if NVRHI_WITH_RTXMU
		bool needBuffer = desc.isTopLevel;
#else
		bool needBuffer = true;
#endif

		if (needBuffer)
		{
			BufferDesc bufferDesc = .();
			bufferDesc.canHaveUAVs = true;
			bufferDesc.byteSize = ASPreBuildInfo.ResultDataMaxSizeInBytes;
			bufferDesc.initialState = desc.isTopLevel ? ResourceStates.AccelStructRead : ResourceStates.AccelStructBuildBlas;
			bufferDesc.keepInitialState = true;
			bufferDesc.isAccelStructStorage = true;
			bufferDesc.debugName = desc.debugName;
			bufferDesc.isVirtual = desc.isVirtual;
			BufferHandle buffer = createBuffer(bufferDesc);
			@as.dataBuffer = checked_cast<Buffer, IBuffer>(buffer.Get<IBuffer>());
		}

		// Sanitize the geometry data to avoid dangling pointers, we don't need these buffers in the Desc
		for (var geometry in ref @as.desc.bottomLevelGeometries)
		{
			Compiler.Assert(offsetof(nvrhi.rt.GeometryTriangles, indexBuffer)
				== offsetof(nvrhi.rt.GeometryAABBs, buffer));
			Compiler.Assert(offsetof(nvrhi.rt.GeometryTriangles, vertexBuffer)
				== offsetof(nvrhi.rt.GeometryAABBs, unused));

			// Clear only the triangles' data, because the AABBs' data is aliased to triangles (verified above)
			geometry.geometryData.triangles.indexBuffer = null;
			geometry.geometryData.triangles.vertexBuffer = null;
		}

		return nvrhi.rt.AccelStructHandle.Attach(@as);
	}
	public override MemoryRequirements getAccelStructMemoryRequirements(nvrhi.rt.IAccelStruct _as)
	{
		AccelStruct @as = checked_cast<AccelStruct, IAccelStruct>(_as);

		if (@as.dataBuffer != null)
			return getBufferMemoryRequirements(@as.dataBuffer);

		return MemoryRequirements();
	}
	public override bool bindAccelStructMemory(nvrhi.rt.IAccelStruct _as, IHeap heap, uint64 offset)
	{
		AccelStruct @as = checked_cast<AccelStruct, IAccelStruct>(_as);

		if (@as.dataBuffer != null)
			return bindBufferMemory(@as.dataBuffer, heap, offset);

		return false;
	}

	public override nvrhi.CommandListHandle createCommandList(CommandListParameters @params)
	{
		if (getQueue(@params.queueType) == null)
			return null;

		return nvrhi.CommandListHandle.Attach(new CommandList(this, m_Context, m_Resources, @params));
	}
	public override uint64 executeCommandLists(Span<nvrhi.ICommandList> pCommandLists, CommandQueue executionQueue)
	{
		int numCommandLists = pCommandLists.Length;
		m_CommandListsToExecute.Resize(numCommandLists);
		for (int i = 0; i < numCommandLists; i++)
		{
			m_CommandListsToExecute[i] = checked_cast<CommandList, nvrhi.ICommandList>(pCommandLists[i]).getD3D12CommandList();
		}

		Queue pQueue = getQueue(executionQueue);

		pQueue.queue.ExecuteCommandLists(uint32(m_CommandListsToExecute.Count), m_CommandListsToExecute.Ptr);
		pQueue.lastSubmittedInstance++;
		pQueue.queue.Signal(ref *pQueue.fence, pQueue.lastSubmittedInstance);

		for (int i = 0; i < numCommandLists; i++)
		{
			var instance = checked_cast<CommandList, nvrhi.ICommandList>(pCommandLists[i]).executed(pQueue);
			pQueue.commandListsInFlight.AddFront(instance);
		}

		HRESULT hr = m_Context.device.GetDeviceRemovedReason();
		if (FAILED(hr))
		{
			m_Context.messageCallback.message(MessageSeverity.Fatal, "Device Removed!");
		}

		return pQueue.lastSubmittedInstance;
	}
	public override void queueWaitForCommandList(CommandQueue waitQueue, CommandQueue executionQueue, uint64 instanceID)
	{
		Queue pWaitQueue = getQueue(waitQueue);
		Queue pExecutionQueue = getQueue(executionQueue);
		Runtime.Assert(instanceID <= pExecutionQueue.lastSubmittedInstance);

		pWaitQueue.queue.Wait(ref *pExecutionQueue.fence, instanceID);
	}

	public override void waitForIdle()
	{
		// Wait for every queue to reach its last submitted instance
		for (var pQueue in m_Queues)
		{
			if (pQueue == null)
				continue;

			if (pQueue.updateLastCompletedInstance() < pQueue.lastSubmittedInstance)
			{
				WaitForFence(pQueue.fence, pQueue.lastSubmittedInstance, m_FenceEvent);
			}
		}
	}
	public override void runGarbageCollection()
	{
		for (var pQueue in m_Queues)
		{
			if (pQueue == null)
				continue;

			pQueue.updateLastCompletedInstance();

			// Starting from the back of the queue, i.e. oldest submitted command lists,
			// see if those command lists have finished executing.
			while (!pQueue.commandListsInFlight.IsEmpty)
			{
				CommandListInstance instance = pQueue.commandListsInFlight.Back;

				if (pQueue.lastCompletedInstance >= instance.submittedInstance)
				{
#if NVRHI_WITH_RTXMU
					if (!instance.rtxmuBuildIds.IsEmpty)
					{
						std.lock_guard lockGuard(m_Resources.asListMutex);

						m_Resources.asBuildsCompleted.insert(m_Resources.asBuildsCompleted.end(),
							instance.rtxmuBuildIds.begin(), instance.rtxmuBuildIds.end());

						instance.rtxmuBuildIds.clear();
					}
					if (!instance.rtxmuCompactionIds.empty())
					{
						m_Context.rtxMemUtil.GarbageCollection(instance.rtxmuCompactionIds);
						instance.rtxmuCompactionIds.clear();
					}
#endif
					pQueue.commandListsInFlight.PopBack();
				}
				else
				{
					break;
				}
			}
		}
	}
	public override bool queryFeatureSupport(Feature feature, void* pInfo, int infoSize = 0)
	{
		switch (feature) // NOLINT(clang-diagnostic-switch-enum)
		{
		case Feature.DeferredCommandLists:
			return true;
		case Feature.SinglePassStereo:
			return m_SinglePassStereoSupported;
		case Feature.RayTracingAccelStruct:
			return m_RayTracingSupported;
		case Feature.RayTracingPipeline:
			return m_RayTracingSupported;
		case Feature.RayQuery:
			return m_TraceRayInlineSupported;
		case Feature.FastGeometryShader:
			return m_FastGeometryShaderSupported;
		case Feature.Meshlets:
			return m_MeshletsSupported;
		case Feature.VariableRateShading:
			if (pInfo != null)
			{
				if (infoSize == sizeof(VariableRateShadingFeatureInfo))
				{
					var pVrsInfo = (VariableRateShadingFeatureInfo*)(pInfo);
					pVrsInfo.shadingRateImageTileSize = m_Options6.ShadingRateImageTileSize;
				}
				else
					nvrhi.utils.NotSupported();
			}
			return m_VariableRateShadingSupported;
		case Feature.VirtualResources:
			return true;
		case Feature.ComputeQueue:
			return (getQueue(CommandQueue.Compute) != null);
		case Feature.CopyQueue:
			return (getQueue(CommandQueue.Copy) != null);
		default:
			return false;
		}
	}
	public override FormatSupport queryFormatSupport(Format format)
	{
		readonly ref DxgiFormatMapping formatMapping = ref getDxgiFormatMapping(format);

		FormatSupport result = FormatSupport.None;

		D3D12_FEATURE_DATA_FORMAT_SUPPORT featureData = .();
		featureData.Format = formatMapping.rtvFormat;

		m_Context.device.CheckFeatureSupport(D3D12_FEATURE.FORMAT_SUPPORT, &featureData, sizeof(decltype(featureData)));

		if (featureData.Support1 & D3D12_FORMAT_SUPPORT1.BUFFER != 0)
			result = result | FormatSupport.Buffer;
		if (featureData.Support1 & (D3D12_FORMAT_SUPPORT1.TEXTURE1D | D3D12_FORMAT_SUPPORT1.TEXTURE2D | D3D12_FORMAT_SUPPORT1.TEXTURE3D | D3D12_FORMAT_SUPPORT1.TEXTURECUBE) != 0)
			result = result | FormatSupport.Texture;
		if (featureData.Support1 & D3D12_FORMAT_SUPPORT1.DEPTH_STENCIL != 0)
			result = result | FormatSupport.DepthStencil;
		if (featureData.Support1 & D3D12_FORMAT_SUPPORT1.RENDER_TARGET != 0)
			result = result | FormatSupport.RenderTarget;
		if (featureData.Support1 & D3D12_FORMAT_SUPPORT1.BLENDABLE != 0)
			result = result | FormatSupport.Blendable;

		if (formatMapping.srvFormat != featureData.Format)
		{
			featureData.Format = formatMapping.srvFormat;
			featureData.Support1 = (D3D12_FORMAT_SUPPORT1)0;
			featureData.Support2 = (D3D12_FORMAT_SUPPORT2)0;
			m_Context.device.CheckFeatureSupport(D3D12_FEATURE.FORMAT_SUPPORT, &featureData, sizeof(decltype(featureData)));
		}

		if (featureData.Support1 & D3D12_FORMAT_SUPPORT1.IA_INDEX_BUFFER != 0)
			result = result | FormatSupport.IndexBuffer;
		if (featureData.Support1 & D3D12_FORMAT_SUPPORT1.IA_VERTEX_BUFFER != 0)
			result = result | FormatSupport.VertexBuffer;
		if (featureData.Support1 & D3D12_FORMAT_SUPPORT1.SHADER_LOAD != 0)
			result = result | FormatSupport.ShaderLoad;
		if (featureData.Support1 & D3D12_FORMAT_SUPPORT1.SHADER_SAMPLE != 0)
			result = result | FormatSupport.ShaderSample;
		if (featureData.Support2 & D3D12_FORMAT_SUPPORT2.UAV_ATOMIC_ADD != 0)
			result = result | FormatSupport.ShaderAtomic;
		if (featureData.Support2 & D3D12_FORMAT_SUPPORT2.UAV_TYPED_LOAD != 0)
			result = result | FormatSupport.ShaderUavLoad;
		if (featureData.Support2 & D3D12_FORMAT_SUPPORT2.UAV_TYPED_STORE != 0)
			result = result | FormatSupport.ShaderUavStore;

		return result;
	}
	public override NativeObject getNativeQueue(ObjectType objectType, CommandQueue queue)
	{
		if (objectType != ObjectType.D3D12_CommandQueue)
			return null;

		if (queue >= CommandQueue.Count)
			return null;

		Queue pQueue = getQueue(queue);

		if (pQueue == null)
			return null;

		return NativeObject(pQueue.queue);
	}
	public override IMessageCallback getMessageCallback() { return m_Context.messageCallback; }

	// d3d12.IDevice implementation

	public override RootSignatureHandle buildRootSignature(StaticVector<BindingLayoutHandle, const c_MaxBindingLayouts> pipelineLayouts, bool allowInputLayout, bool isLocal, D3D12_ROOT_PARAMETER1* pCustomParameters = null, uint32 numCustomParameters = 0)
	{
		HRESULT res;

		RootSignature rootsig = new RootSignature(m_Resources);

		// Assemble the root parameter table from the pipeline binding layouts
		// Also attach the root parameter offsets to the pipeline layouts

		List<D3D12_ROOT_PARAMETER1> rootParameters = scope .();

		// Add custom parameters in the beginning of the RS
		for (uint32 index = 0; index < numCustomParameters; index++)
		{
			rootParameters.Add(pCustomParameters[index]);
		}

		for (uint32 layoutIndex = 0; layoutIndex < uint32(pipelineLayouts.Count); layoutIndex++)
		{
			if (pipelineLayouts[layoutIndex].getDesc() != null)
			{
				BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(pipelineLayouts[layoutIndex].Get<IBindingLayout>());
				RootParameterIndex rootParameterOffset = RootParameterIndex(rootParameters.Count);

				rootsig.pipelineLayouts.PushBack((layout, rootParameterOffset));

				rootParameters.AddRange(layout.rootParameters);

				if (layout.pushConstantByteSize > 0)
				{
					rootsig.pushConstantByteSize = layout.pushConstantByteSize;
					rootsig.rootParameterPushConstants = layout.rootParameterPushConstants + rootParameterOffset;
				}
			}
			else if (pipelineLayouts[layoutIndex].getBindlessDesc() != null)
			{
				BindlessLayout layout = checked_cast<BindlessLayout, IBindingLayout>(pipelineLayouts[layoutIndex].Get<IBindingLayout>());
				RootParameterIndex rootParameterOffset = RootParameterIndex(rootParameters.Count);

				rootsig.pipelineLayouts.PushBack((layout, rootParameterOffset));

				rootParameters.Add(layout.rootParameter);
			}
		}

		// Build the description structure

		D3D12_VERSIONED_ROOT_SIGNATURE_DESC rsDesc = .();
		rsDesc.Version = D3D_ROOT_SIGNATURE_VERSION._1_1;

		if (allowInputLayout)
		{
			rsDesc.Desc_1_1.Flags |= D3D12_ROOT_SIGNATURE_FLAGS.ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT;
		}
		if (isLocal)
		{
			rsDesc.Desc_1_1.Flags |= D3D12_ROOT_SIGNATURE_FLAGS.LOCAL_ROOT_SIGNATURE;
		}

		if (!rootParameters.IsEmpty)
		{
			rsDesc.Desc_1_1.pParameters = rootParameters.Ptr;
			rsDesc.Desc_1_1.NumParameters = UINT(rootParameters.Count);
		}

		// Serialize the root signature

		D3D12RefCountPtr<ID3DBlob> rsBlob = null;
		D3D12RefCountPtr<ID3DBlob> errorBlob = null;
		res = D3D12SerializeVersionedRootSignature(rsDesc, out rsBlob, &errorBlob);

		if (FAILED(res))
		{
			String message = scope $"D3D12SerializeVersionedRootSignature call failed, HRESULT = 0x{res}";
			if (errorBlob != null)
			{
				message.AppendF("\n{}", (char8*)errorBlob.GetBufferPointer());
			}
			m_Context.error(message);

			return null;
		}

		// Create the RS object

		res = m_Context.device.CreateRootSignature(0, rsBlob.GetBufferPointer(), rsBlob.GetBufferSize(), ID3D12RootSignature.IID, (void**)(&rootsig.handle));

		if (FAILED(res))
		{
			String message = scope $"CreateRootSignature call failed, HRESULT = 0x{res}";
			m_Context.error(message);

			return null;
		}

		return RootSignatureHandle.Attach(rootsig);
	}

	public override GraphicsPipelineHandle createHandleForNativeGraphicsPipeline(IRootSignature rootSignature, ID3D12PipelineState* pipelineState, GraphicsPipelineDesc desc, FramebufferInfo framebufferInfo)
	{
		if (rootSignature == null)
			return null;

		if (pipelineState == null)
			return null;

		GraphicsPipeline pso = new GraphicsPipeline();
		pso.desc = desc;
		pso.framebufferInfo = framebufferInfo;
		pso.rootSignature = checked_cast<RootSignature, IRootSignature>(rootSignature);
		pso.pipelineState = pipelineState;
		pso.requiresBlendFactor = desc.renderState.blendState.usesConstantColor(uint32(pso.framebufferInfo.colorFormats.Count));

		return GraphicsPipelineHandle.Attach(pso);
	}
	public override MeshletPipelineHandle createHandleForNativeMeshletPipeline(IRootSignature rootSignature, ID3D12PipelineState* pipelineState, MeshletPipelineDesc desc, FramebufferInfo framebufferInfo)
	{
		if (rootSignature == null)
			return null;

		if (pipelineState == null)
			return null;

		MeshletPipeline pso = new MeshletPipeline();
		pso.desc = desc;
		pso.framebufferInfo = framebufferInfo;
		pso.rootSignature = checked_cast<RootSignature, IRootSignature>(rootSignature);
		pso.pipelineState = pipelineState;
		pso.requiresBlendFactor = desc.renderState.blendState.usesConstantColor(uint32(pso.framebufferInfo.colorFormats.Count));

		return MeshletPipelineHandle.Attach(pso);
	}
	public override IDescriptorHeap getDescriptorHeap(DescriptorHeapType heapType)
	{
		switch (heapType)
		{
		case DescriptorHeapType.RenderTargetView:
			return m_Resources.renderTargetViewHeap;
		case DescriptorHeapType.DepthStencilView:
			return m_Resources.depthStencilViewHeap;
		case DescriptorHeapType.ShaderResrouceView:
			return m_Resources.shaderResourceViewHeap;
		case DescriptorHeapType.Sampler:
			return m_Resources.samplerHeap;
		default:
			return null;
		}
	}

	// Internal interface
	public Queue getQueue(CommandQueue type) { return m_Queues[int32(type)]; }

	public Context* getContext() { return m_Context; }

	private Context* m_Context;
	private DeviceResources m_Resources;

	private Queue[(int32)CommandQueue.Count] m_Queues;
	private HANDLE m_FenceEvent;

	private Monitor m_Mutex;

	private List<ID3D12CommandList*> m_CommandListsToExecute; // used locally in executeCommandLists, member to avoid re-allocations

	private bool m_NvapiIsInitialized = false;
	private bool m_SinglePassStereoSupported = false;
	private bool m_FastGeometryShaderSupported = false;
	private bool m_RayTracingSupported = false;
	private bool m_TraceRayInlineSupported = false;
	private bool m_MeshletsSupported = false;
	private bool m_VariableRateShadingSupported = false;

	private D3D12_FEATURE_DATA_D3D12_OPTIONS  m_Options = .();
	private D3D12_FEATURE_DATA_D3D12_OPTIONS5 m_Options5 = .();
	private D3D12_FEATURE_DATA_D3D12_OPTIONS6 m_Options6 = .();
	private D3D12_FEATURE_DATA_D3D12_OPTIONS7 m_Options7 = .();

	private RefCountPtr<RootSignature> getRootSignature(StaticVector<BindingLayoutHandle, const c_MaxBindingLayouts> pipelineLayouts, bool allowInputLayout)
	{
		int hash = 0;

		for (readonly ref BindingLayoutHandle pipelineLayout in ref pipelineLayouts)
			hash_combine(ref hash, pipelineLayout?.Get<IBindingLayout>());

		hash_combine(ref hash, allowInputLayout ? 1 : 0);

		// Get a cached RS and AddRef it (if it exists)
		RefCountPtr<RootSignature> rootsig = m_Resources.rootsigCache[hash];

		if (rootsig == null)
		{
			// Does not exist - build a new one, take ownership
			rootsig = checked_cast<RootSignature, IRootSignature>(buildRootSignature(pipelineLayouts, allowInputLayout, false).Get<IRootSignature>());
			rootsig.hash = hash;

			m_Resources.rootsigCache[hash] = rootsig;
		}

		// Pass ownership of the RS to caller
		return rootsig;
	}
	private D3D12RefCountPtr<ID3D12PipelineState> createPipelineState(GraphicsPipelineDesc  state, RootSignature pRS, FramebufferInfo fbinfo)
	{
		if (state.renderState.singlePassStereo.enabled && !m_SinglePassStereoSupported)
		{
			m_Context.error("Single-pass stereo is not supported by this device");
			return null;
		}

		D3D12_GRAPHICS_PIPELINE_STATE_DESC desc = .();
		desc.pRootSignature = pRS.handle;

		Shader shader = null;
		shader = checked_cast<Shader, IShader>(state.VS?.Get<IShader>());
		if (shader != null) desc.VS = .() { pShaderBytecode = &shader.bytecode[0], BytecodeLength = uint(shader.bytecode.Count) };

		shader = checked_cast<Shader, IShader>(state.HS?.Get<IShader>());
		if (shader != null) desc.HS = .() { pShaderBytecode = &shader.bytecode[0], BytecodeLength = uint(shader.bytecode.Count) };

		shader = checked_cast<Shader, IShader>(state.DS?.Get<IShader>());
		if (shader != null) desc.DS = .() { pShaderBytecode = &shader.bytecode[0], BytecodeLength = uint(shader.bytecode.Count) };

		shader = checked_cast<Shader, IShader>(state.GS?.Get<IShader>());
		if (shader != null) desc.GS = .() { pShaderBytecode = &shader.bytecode[0], BytecodeLength = uint(shader.bytecode.Count) };

		shader = checked_cast<Shader, IShader>(state.PS?.Get<IShader>());
		if (shader != null) desc.PS = .() { pShaderBytecode = &shader.bytecode[0], BytecodeLength = uint(shader.bytecode.Count) };


		TranslateBlendState(state.renderState.blendState, ref desc.BlendState);


		readonly ref DepthStencilState depthState = ref state.renderState.depthStencilState;
		TranslateDepthStencilState(depthState, ref desc.DepthStencilState);

		if ((depthState.depthTestEnable || depthState.stencilEnable) && fbinfo.depthFormat == Format.UNKNOWN)
		{
			desc.DepthStencilState.DepthEnable = 0;
			desc.DepthStencilState.StencilEnable = 0;
			m_Context.messageCallback.message(MessageSeverity.Warning, "depthEnable or stencilEnable is true, but no depth target is bound");
		}

		readonly ref RasterState rasterState = ref state.renderState.rasterState;
		TranslateRasterizerState(rasterState, ref desc.RasterizerState);

		switch (state.primType)
		{
		case PrimitiveType.PointList:
			desc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE.POINT;
			break;
		case PrimitiveType.LineList:
			desc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE.LINE;
			break;
		case PrimitiveType.TriangleList: fallthrough;
		case PrimitiveType.TriangleStrip:
			desc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE.TRIANGLE;
			break;
		case PrimitiveType.PatchList:
			desc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE.PATCH;
			break;
		default: break;
		}

		desc.DSVFormat = getDxgiFormatMapping(fbinfo.depthFormat).rtvFormat;

		desc.SampleDesc.Count = fbinfo.sampleCount;
		desc.SampleDesc.Quality = fbinfo.sampleQuality;

		for (uint32 i = 0; i < uint32(fbinfo.colorFormats.Count); i++)
		{
			desc.RTVFormats[i] = getDxgiFormatMapping(fbinfo.colorFormats[i]).rtvFormat;
		}

		InputLayout inputLayout = checked_cast<InputLayout, IInputLayout>(state.inputLayout.Get<IInputLayout>());
		if (inputLayout != null && !inputLayout.inputElements.IsEmpty)
		{
			desc.InputLayout.NumElements = uint32(inputLayout.inputElements.Count);
			desc.InputLayout.pInputElementDescs = &(inputLayout.inputElements[0]);
		}

		desc.NumRenderTargets = uint32(fbinfo.colorFormats.Count);
		desc.SampleMask = ~0u;

		D3D12RefCountPtr<ID3D12PipelineState> pipelineState = null;

#if NVRHI_D3D12_WITH_NVAPI
		List<const NVAPI_D3D12_PSO_EXTENSION_DESC*> extensions;

		shader = checked_cast<Shader*>(state.VS.Get()); if (shader) extensions.insert(extensions.end(), shader.extensions.begin(), shader.extensions.end());
		shader = checked_cast<Shader*>(state.HS.Get()); if (shader) extensions.insert(extensions.end(), shader.extensions.begin(), shader.extensions.end());
		shader = checked_cast<Shader*>(state.DS.Get()); if (shader) extensions.insert(extensions.end(), shader.extensions.begin(), shader.extensions.end());
		shader = checked_cast<Shader*>(state.GS.Get()); if (shader) extensions.insert(extensions.end(), shader.extensions.begin(), shader.extensions.end());
		shader = checked_cast<Shader*>(state.PS.Get()); if (shader) extensions.insert(extensions.end(), shader.extensions.begin(), shader.extensions.end());

		if (rasterState.programmableSamplePositionsEnable || rasterState.quadFillEnable)
		{
			NVAPI_D3D12_PSO_RASTERIZER_STATE_DESC rasterizerDesc = {};
			rasterizerDesc.baseVersion = NV_PSO_EXTENSION_DESC_VER;
			rasterizerDesc.psoExtension = NV_PSO_RASTER_EXTENSION;
			rasterizerDesc.version = NV_RASTERIZER_PSO_EXTENSION_DESC_VER;

			rasterizerDesc.ProgrammableSamplePositionsEnable = rasterState.programmableSamplePositionsEnable;
			rasterizerDesc.SampleCount = rasterState.forcedSampleCount;
			memcpy(rasterizerDesc.SamplePositionsX, rasterState.samplePositionsX, sizeof(rasterState.samplePositionsX));
			memcpy(rasterizerDesc.SamplePositionsY, rasterState.samplePositionsY, sizeof(rasterState.samplePositionsY));
			rasterizerDesc.QuadFillMode = rasterState.quadFillEnable ? NVAPI_QUAD_FILLMODE_BBOX : NVAPI_QUAD_FILLMODE_DISABLED;

			extensions.push_back(&rasterizerDesc);
		}

		if (!extensions.empty())
		{
			NvAPI_Status status = NvAPI_D3D12_CreateGraphicsPipelineState(m_Context.device, &desc, NvU32(extensions.size()), &extensions[0], &pipelineState);

			if (status != NVAPI_OK || pipelineState == null)
			{
				m_Context.error("Failed to create a graphics pipeline state object with NVAPI extensions");
				return null;
			}

			return pipelineState;
		}
#endif

		readonly HRESULT hr = m_Context.device.CreateGraphicsPipelineState(desc, ID3D12PipelineState.IID, (void**)(&pipelineState));

		if (FAILED(hr))
		{
			m_Context.error("Failed to create a graphics pipeline state object");
			return null;
		}

		return pipelineState;
	}
	private D3D12RefCountPtr<ID3D12PipelineState> createPipelineState(ComputePipelineDesc state, RootSignature pRS)
	{
		D3D12RefCountPtr<ID3D12PipelineState> pipelineState = null;

		D3D12_COMPUTE_PIPELINE_STATE_DESC desc = .();

		desc.pRootSignature = pRS.handle;
		Shader shader = checked_cast<Shader, IShader>(state.CS?.Get<IShader>());
		desc.CS = .() { pShaderBytecode = &shader.bytecode[0], BytecodeLength = uint(shader.bytecode.Count) };

#if NVRHI_D3D12_WITH_NVAPI
		if (!shader.extensions.empty())
		{
			NvAPI_Status status = NvAPI_D3D12_CreateComputePipelineState(m_Context.device, &desc, 
				NvU32(shader.extensions.size()), const_cast<const NVAPI_D3D12_PSO_EXTENSION_DESC**>(shader.extensions.data()), &pipelineState);

			if (status != NVAPI_OK || pipelineState == null)
			{
				m_Context.error("Failed to create a compute pipeline state object with NVAPI extensions");
				return null;
			}

			return pipelineState;
		}
#endif

		readonly HRESULT hr = m_Context.device.CreateComputePipelineState(desc, ID3D12PipelineState.IID, (void**)(&pipelineState));

		if (FAILED(hr))
		{
			m_Context.error("Failed to create a compute pipeline state object");
			return null;
		}

		return pipelineState;
	}

	struct PSO_STREAM
	{
		[Align(sizeof(void*))] public D3D12_PIPELINE_STATE_SUBOBJECT_TYPE RootSignature_Type;        public ID3D12RootSignature* RootSignature;
		[Align(sizeof(void*))] public D3D12_PIPELINE_STATE_SUBOBJECT_TYPE PrimitiveTopology_Type;    public D3D12_PRIMITIVE_TOPOLOGY_TYPE PrimitiveTopologyType;
		[Align(sizeof(void*))] public D3D12_PIPELINE_STATE_SUBOBJECT_TYPE AmplificationShader_Type;  public D3D12_SHADER_BYTECODE AmplificationShader;
		[Align(sizeof(void*))] public D3D12_PIPELINE_STATE_SUBOBJECT_TYPE MeshShader_Type;           public D3D12_SHADER_BYTECODE MeshShader;
		[Align(sizeof(void*))] public D3D12_PIPELINE_STATE_SUBOBJECT_TYPE PixelShader_Type;          public D3D12_SHADER_BYTECODE PixelShader;
		[Align(sizeof(void*))] public D3D12_PIPELINE_STATE_SUBOBJECT_TYPE RasterizerState_Type;      public D3D12_RASTERIZER_DESC RasterizerState;
		[Align(sizeof(void*))] public D3D12_PIPELINE_STATE_SUBOBJECT_TYPE DepthStencilState_Type;    public D3D12_DEPTH_STENCIL_DESC DepthStencilState;
		[Align(sizeof(void*))] public D3D12_PIPELINE_STATE_SUBOBJECT_TYPE BlendState_Type;           public D3D12_BLEND_DESC BlendState;
		[Align(sizeof(void*))] public D3D12_PIPELINE_STATE_SUBOBJECT_TYPE SampleDesc_Type;           public DXGI_SAMPLE_DESC SampleDesc;
		[Align(sizeof(void*))] public D3D12_PIPELINE_STATE_SUBOBJECT_TYPE SampleMask_Type;           public UINT SampleMask;
		[Align(sizeof(void*))] public D3D12_PIPELINE_STATE_SUBOBJECT_TYPE RenderTargets_Type;        public D3D12_RT_FORMAT_ARRAY RenderTargets;
		[Align(sizeof(void*))] public D3D12_PIPELINE_STATE_SUBOBJECT_TYPE DSVFormat_Type;            public DXGI_FORMAT DSVFormat;
	}

	private D3D12RefCountPtr<ID3D12PipelineState> createPipelineState(MeshletPipelineDesc state, RootSignature pRS, FramebufferInfo fbinfo)
	{
		D3D12RefCountPtr<ID3D12PipelineState> pipelineState = null;

//#pragma warning(push)
//#pragma warning(disable: 4324) // structure was padded due to alignment specifier
		PSO_STREAM psoDesc = .();
//#pragma warning(pop)

		psoDesc.RootSignature_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE.ROOT_SIGNATURE;
		psoDesc.PrimitiveTopology_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE.PRIMITIVE_TOPOLOGY;
		psoDesc.AmplificationShader_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE.AS;
		psoDesc.MeshShader_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE.MS;
		psoDesc.PixelShader_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE.PS;
		psoDesc.RasterizerState_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE.RASTERIZER;
		psoDesc.DepthStencilState_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE.DEPTH_STENCIL;
		psoDesc.BlendState_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE.BLEND;
		psoDesc.SampleDesc_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE.SAMPLE_DESC;
		psoDesc.SampleMask_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE.SAMPLE_MASK;
		psoDesc.RenderTargets_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE.RENDER_TARGET_FORMATS;
		psoDesc.DSVFormat_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE.DEPTH_STENCIL_FORMAT;

		psoDesc.RootSignature = pRS.handle;

		TranslateBlendState(state.renderState.blendState, ref psoDesc.BlendState);

		readonly ref DepthStencilState depthState = ref state.renderState.depthStencilState;
		TranslateDepthStencilState(depthState, ref psoDesc.DepthStencilState);

		if ((depthState.depthTestEnable || depthState.stencilEnable) && fbinfo.depthFormat == Format.UNKNOWN)
		{
			psoDesc.DepthStencilState.DepthEnable = 0;
			psoDesc.DepthStencilState.StencilEnable = 0;
		}

		readonly ref RasterState rasterState = ref state.renderState.rasterState;
		TranslateRasterizerState(rasterState, ref psoDesc.RasterizerState);

		switch (state.primType)
		{
		case PrimitiveType.PointList:
			psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE.POINT;
			break;
		case PrimitiveType.LineList:
			psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE.LINE;
			break;
		case PrimitiveType.TriangleList: fallthrough;
		case PrimitiveType.TriangleStrip:
			psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE.TRIANGLE;
			break;
		case PrimitiveType.PatchList:
			m_Context.error("Unsupported primitive topology for meshlets");
			return null;
		default:
			nvrhi.utils.InvalidEnum();
			return null;
		}

		psoDesc.SampleDesc.Count = fbinfo.sampleCount;
		psoDesc.SampleDesc.Quality = fbinfo.sampleQuality;
		psoDesc.SampleMask = (.)~0u;

		for (uint32 i = 0; i < uint32(fbinfo.colorFormats.Count); i++)
		{
			psoDesc.RenderTargets.RTFormats[i] = getDxgiFormatMapping(fbinfo.colorFormats[i]).rtvFormat;
		}
		psoDesc.RenderTargets.NumRenderTargets = uint32(fbinfo.colorFormats.Count);

		psoDesc.DSVFormat = getDxgiFormatMapping(fbinfo.depthFormat).rtvFormat;

		if (state.AS != null)
		{
			state.AS.getBytecode(&psoDesc.AmplificationShader.pShaderBytecode, (.)&psoDesc.AmplificationShader.BytecodeLength);
		}

		if (state.MS != null)
		{
			state.MS.getBytecode(&psoDesc.MeshShader.pShaderBytecode, (.)&psoDesc.MeshShader.BytecodeLength);
		}

		if (state.PS != null)
		{
			state.PS.getBytecode(&psoDesc.PixelShader.pShaderBytecode, (.)&psoDesc.PixelShader.BytecodeLength);
		}

		D3D12_PIPELINE_STATE_STREAM_DESC streamDesc;
		streamDesc.pPipelineStateSubobjectStream = &psoDesc;
		streamDesc.SizeInBytes = sizeof(decltype(psoDesc));

		HRESULT hr = m_Context.device2.CreatePipelineState(streamDesc, ID3D12PipelineState.IID, (void**)(&pipelineState));
		if (FAILED(hr))
		{
			m_Context.error("Failed to create a meshlet pipeline state object");
			return null;
		}

		return pipelineState;
	}
}