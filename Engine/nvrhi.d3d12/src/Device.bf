using System.Threading;
using Win32.Foundation;
using System.Collections;
using Win32.Graphics.Direct3D12;
namespace nvrhi.d3d12;

class Device : RefCounter<nvrhi.d3d12.IDevice>
{
    public this(DeviceDesc desc){
		m_Resources = new .(m_Context, desc);

		m_Context.device = desc.pDevice;
		m_Context.messageCallback = desc.errorCB;

		if (desc.pGraphicsCommandQueue)
		    m_Queues[int32(CommandQueue::Graphics)] = std::make_unique<Queue>(m_Context, desc.pGraphicsCommandQueue);
		if (desc.pComputeCommandQueue)
		    m_Queues[int32(CommandQueue::Compute)] = std::make_unique<Queue>(m_Context, desc.pComputeCommandQueue);
		if (desc.pCopyCommandQueue)
		    m_Queues[int32(CommandQueue::Copy)] = std::make_unique<Queue>(m_Context, desc.pCopyCommandQueue);

		m_Resources.depthStencilViewHeap.allocateResources(D3D12_DESCRIPTOR_HEAP_TYPE_DSV, desc.depthStencilViewHeapSize, false);
		m_Resources.renderTargetViewHeap.allocateResources(D3D12_DESCRIPTOR_HEAP_TYPE_RTV, desc.renderTargetViewHeapSize, false);
		m_Resources.shaderResourceViewHeap.allocateResources(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, desc.shaderResourceViewHeapSize, true);
		m_Resources.samplerHeap.allocateResources(D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER, desc.samplerHeapSize, true);

		m_Context.device.CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS, &m_Options, sizeof(m_Options));
		bool hasOptions5 = SUCCEEDED(m_Context.device.CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS5, &m_Options5, sizeof(m_Options5)));
		bool hasOptions6 = SUCCEEDED(m_Context.device.CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS6, &m_Options6, sizeof(m_Options6)));
		bool hasOptions7 = SUCCEEDED(m_Context.device.CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS7, &m_Options7, sizeof(m_Options7)));

		if (SUCCEEDED(m_Context.device.QueryInterface(&m_Context.device5)) && hasOptions5)
		{
		    m_RayTracingSupported = m_Options5.RaytracingTier >= D3D12_RAYTRACING_TIER_1_0;
		    m_TraceRayInlineSupported = m_Options5.RaytracingTier >= D3D12_RAYTRACING_TIER_1_1;

#ifdef NVRHI_WITH_RTXMU
		    if (m_RayTracingSupported)
		    {
		        m_Context.rtxMemUtil = std::make_unique<rtxmu::DxAccelStructManager>(m_Context.device5);

		        // Initialize suballocator blocks to 8 MB
		        m_Context.rtxMemUtil.Initialize(8388608);
		    }
#endif
		}

		if (SUCCEEDED(m_Context.device.QueryInterface(&m_Context.device2)) && hasOptions7)
		{
		    m_MeshletsSupported = m_Options7.MeshShaderTier >= D3D12_MESH_SHADER_TIER_1;
		}

		if (hasOptions6)
		{
		    m_VariableRateShadingSupported = m_Options6.VariableShadingRateTier >= D3D12_VARIABLE_SHADING_RATE_TIER_2;
		}

		{
		    D3D12_INDIRECT_ARGUMENT_DESC argDesc = {};
		    D3D12_COMMAND_SIGNATURE_DESC csDesc = {};
		    csDesc.NumArgumentDescs = 1;
		    csDesc.pArgumentDescs = &argDesc;

		    csDesc.ByteStride = 16;
		    argDesc.Type = D3D12_INDIRECT_ARGUMENT_TYPE.DRAW;
		    m_Context.device.CreateCommandSignature(csDesc, null, IID_PPV_ARGS(&m_Context.drawIndirectSignature));

		    csDesc.ByteStride = 12;
		    argDesc.Type = D3D12_INDIRECT_ARGUMENT_TYPE.DISPATCH;
		    m_Context.device.CreateCommandSignature(csDesc, null, IID_PPV_ARGS(&m_Context.dispatchIndirectSignature));
		}

		m_FenceEvent = CreateEvent(null, false, false, null);

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
    
    public NativeObject getNativeObject(ObjectType objectType)
    {
        switch (objectType)
        {
        case ObjectTypes::D3D12_Device:
            return NativeObject(m_Context.device);
        case ObjectTypes::Nvrhi_D3D12_Device:
            return NativeObject(this);
        default:
            return null;
        }
    }

    // IDevice implementation

    public HeapHandle createHeap(const HeapDesc& d)
    {
        D3D12_HEAP_DESC heapDesc;
        heapDesc.SizeInBytes = d.capacity;
        heapDesc.Alignment = D3D12_DEFAULT_MSAA_RESOURCE_PLACEMENT_ALIGNMENT;
        heapDesc.Properties.MemoryPoolPreference = D3D12_MEMORY_POOL_UNKNOWN;
        heapDesc.Properties.CPUPageProperty = D3D12_CPU_PAGE_PROPERTY_UNKNOWN;
        heapDesc.Properties.CreationNodeMask = 1; // no mGPU support in nvrhi so far
        heapDesc.Properties.VisibleNodeMask = 1;

        if (m_Options.ResourceHeapTier == D3D12_RESOURCE_HEAP_TIER_1)
            heapDesc.Flags = D3D12_HEAP_FLAG_ALLOW_ONLY_RT_DS_TEXTURES;
        else
            heapDesc.Flags = D3D12_HEAP_FLAG_ALLOW_ALL_BUFFERS_AND_TEXTURES;

        switch (d.type)
        {
        case HeapType::DeviceLocal:
            heapDesc.Properties.Type = D3D12_HEAP_TYPE_DEFAULT;
            break;
        case HeapType::Upload:
            heapDesc.Properties.Type = D3D12_HEAP_TYPE_UPLOAD;
            break;
        case HeapType::Readback:
            heapDesc.Properties.Type = D3D12_HEAP_TYPE_READBACK;
            break;
        default:
            nvrhi.utils.InvalidEnum();
            return null;
        }

        D3D12RefCountPtr<ID3D12Heap> d3dHeap;
        const HRESULT res = m_Context.device.CreateHeap(&heapDesc, IID_PPV_ARGS(&d3dHeap));

        if (FAILED(res))
        {
            std::stringstream ss;
            ss << "CreateHeap call failed for heap " << nvrhi.utils.DebugNameToString(d.debugName)
                << ", HRESULT = 0x" << std::hex << std::setw(8) << res;
            m_Context.error(ss.str());

            return null;
        }

        if (!d.debugName.empty())
        {
            std::wstring wname(d.debugName.begin(), d.debugName.end());
            d3dHeap.SetName(wname.c_str());
        }

        Heap* heap = new Heap();
        heap.heap = d3dHeap;
        heap.desc = d;
        return HeapHandle::Create(heap);
    }

    public TextureHandle createTexture(const TextureDesc & d)
    {
        D3D12_RESOURCE_DESC rd = convertTextureDesc(d);
        D3D12_HEAP_PROPERTIES heapProps = {};
        D3D12_HEAP_FLAGS heapFlags = D3D12_HEAP_FLAG_NONE;

        if ((d.sharedResourceFlags & SharedResourceFlags::Shared) != 0)
            heapFlags |= D3D12_HEAP_FLAG_SHARED;
        if ((d.sharedResourceFlags & SharedResourceFlags::Shared_CrossAdapter) != 0) {
            rd.Flags |= D3D12_RESOURCE_FLAG_ALLOW_CROSS_ADAPTER;
            heapFlags |= D3D12_HEAP_FLAG_SHARED_CROSS_ADAPTER;
        }

        Texture* texture = new Texture(m_Context, m_Resources, d, rd);

        if (d.isVirtual)
        {
            // The resource is created in bindTextureMemory
            return TextureHandle::Create(texture);
        }

        heapProps.Type = D3D12_HEAP_TYPE_DEFAULT;

        D3D12_CLEAR_VALUE clearValue = convertTextureClearValue(d);

        HRESULT hr = m_Context.device.CreateCommittedResource(
            &heapProps,
            heapFlags,
            &texture.resourceDesc,
            convertResourceStates(d.initialState),
            d.useClearValue ? &clearValue : null,
            IID_PPV_ARGS(&texture.resource));

        if (FAILED(hr))
        {
            std::stringstream ss;
            ss << "Failed to create texture " << nvrhi.utils.DebugNameToString(d.debugName) << ", error code = 0x";
            ss.setf(std::ios::hex, std::ios::basefield);
            ss << hr;
            m_Context.error(ss.str());
            
            delete texture;
            return null;
        }

        texture.postCreate();

        return TextureHandle::Create(texture);
    }
    public MemoryRequirements getTextureMemoryRequirements(ITexture* _texture)
    {
        Texture* texture = checked_cast<Texture*>(_texture);
        
        D3D12_RESOURCE_ALLOCATION_INFO allocInfo = m_Context.device.GetResourceAllocationInfo(1, 1, &texture.resourceDesc);

        MemoryRequirements memReq;
        memReq.alignment = allocInfo.Alignment;
        memReq.size = allocInfo.SizeInBytes;
        return memReq;
    }
    public bool bindTextureMemory(ITexture* _texture, IHeap* _heap, uint64 offset)
    {
        Texture* texture = checked_cast<Texture*>(_texture);
        Heap* heap = checked_cast<Heap*>(_heap);

        if (texture.resource)
            return false; // already bound

        if (!texture.desc.isVirtual)
            return false; // not supported


        D3D12_CLEAR_VALUE clearValue = convertTextureClearValue(texture.desc);

        HRESULT hr = m_Context.device.CreatePlacedResource(
            heap.heap, offset,
            &texture.resourceDesc,
            convertResourceStates(texture.desc.initialState),
            texture.desc.useClearValue ? &clearValue : null,
            IID_PPV_ARGS(&texture.resource));

        if (FAILED(hr))
        {
            std::stringstream ss;
            ss << "Failed to create placed texture " << nvrhi.utils.DebugNameToString(texture.desc.debugName) << ", error code = 0x";
            ss.setf(std::ios::hex, std::ios::basefield);
            ss << hr;
            m_Context.error(ss.str());

            return false;
        }

        texture.heap = heap;
        texture.postCreate();

        return true;
    }

    public TextureHandle createHandleForNativeTexture(ObjectType objectType, NativeObject _texture, const TextureDesc& desc)
    {
        if (_texture.pointer == null)
            return null;

        if (objectType != ObjectTypes::D3D12_Resource)
            return null;

        ID3D12Resource* pResource = static_cast<ID3D12Resource*>(_texture.pointer);

        Texture* texture = new Texture(m_Context, m_Resources, desc, pResource.GetDesc());
        texture.resource = pResource;
        texture.postCreate();

        return TextureHandle::Create(texture);
    }

    public StagingTextureHandle createStagingTexture(const TextureDesc& d, CpuAccessMode cpuAccess)
    {
        Runtime.Assert(cpuAccess != CpuAccessMode::None);

        StagingTexture *ret = new StagingTexture();
        ret.desc = d;
        ret.resourceDesc = convertTextureDesc(d);
        ret.computeSubresourceOffsets(m_Context.device);

        BufferDesc bufferDesc;
        bufferDesc.byteSize = ret.getSizeInBytes(m_Context.device);
        bufferDesc.structStride = 0;
        bufferDesc.debugName = d.debugName;
        bufferDesc.cpuAccess = cpuAccess;

        BufferHandle buffer = createBuffer(bufferDesc);
        ret.buffer = checked_cast<Buffer*>(buffer.Get());
        if (!ret.buffer)
        {
            delete ret;
            return null;
        }

        ret.cpuAccess = cpuAccess;
        return StagingTextureHandle::Create(ret);
    }
    public void *mapStagingTexture(IStagingTexture* _tex, const TextureSlice& slice, CpuAccessMode cpuAccess, int *outRowPitch)
    {
        StagingTexture* tex = checked_cast<StagingTexture*>(_tex);

        Runtime.Assert(slice.x == 0);
        Runtime.Assert(slice.y == 0);
        Runtime.Assert(cpuAccess != CpuAccessMode::None);
        Runtime.Assert(tex.mappedRegion.size == 0);
        Runtime.Assert(tex.mappedAccess == CpuAccessMode::None);

        auto resolvedSlice = slice.resolve(tex.desc);
        auto region = tex.getSliceRegion(m_Context.device, resolvedSlice);

        if (tex.lastUseFence)
        {
            WaitForFence(tex.lastUseFence, tex.lastUseFenceValue, m_FenceEvent);
            tex.lastUseFence = null;
        }

        D3D12_RANGE range;

        if (cpuAccess == CpuAccessMode::Read)
        {
            range = { SIZE_T(region.offset), region.offset + region.size };
        } else {
            range = { 0, 0 };
        }

        uint8 *ret;
        const HRESULT res = tex.buffer.resource.Map(0, &range, (void**)&ret);

        if (FAILED(res))
        {
            std::stringstream ss;
            ss << "Map call failed for textre " << nvrhi.utils.DebugNameToString(tex.desc.debugName)
                << ", HRESULT = 0x" << std::hex << std::setw(8) << res;
            m_Context.error(ss.str());

            return null;
        }
        
        tex.mappedRegion = region;
        tex.mappedAccess = cpuAccess;

        *outRowPitch = region.footprint.Footprint.RowPitch;
        return ret + tex.mappedRegion.offset;
    }
    public void unmapStagingTexture(IStagingTexture* _tex)
    {
        StagingTexture* tex = checked_cast<StagingTexture*>(_tex);

        Runtime.Assert(tex.mappedRegion.size != 0);
        Runtime.Assert(tex.mappedAccess != CpuAccessMode::None);

        D3D12_RANGE range;

        if (tex.mappedAccess == CpuAccessMode::Write)
        {
            range = { SIZE_T(tex.mappedRegion.offset), tex.mappedRegion.offset + tex.mappedRegion.size };
        } else {
            range = { 0, 0 };
        }

        tex.buffer.resource.Unmap(0, &range);

        tex.mappedRegion.size = 0;
        tex.mappedAccess = CpuAccessMode::None;
    } 

    public BufferHandle createBuffer(const BufferDesc& d)
    {
        BufferDesc desc = d;
        if (desc.isConstantBuffer)
        {
            desc.byteSize = align(d.byteSize, 256ull);
        }

        Buffer* buffer = new Buffer(m_Context, m_Resources, desc);
        
        if (d.isVolatile)
        {
            // Do not create any resources for volatile buffers. Done.
            return BufferHandle::Create(buffer);
        }

        D3D12_RESOURCE_DESC& resourceDesc = buffer.resourceDesc;
        resourceDesc.Width = buffer.desc.byteSize;
        resourceDesc.Height = 1;
        resourceDesc.DepthOrArraySize = 1;
        resourceDesc.MipLevels = 1;
        resourceDesc.Format = DXGI_FORMAT_UNKNOWN;
        resourceDesc.SampleDesc.Count = 1;
        resourceDesc.SampleDesc.Quality = 0;
        resourceDesc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
        resourceDesc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;

        if (buffer.desc.canHaveUAVs)
            resourceDesc.Flags |= D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;

        if (d.isVirtual)
        {
            return BufferHandle::Create(buffer);
        }

        D3D12_HEAP_PROPERTIES heapProps = {};
        D3D12_HEAP_FLAGS heapFlags = D3D12_HEAP_FLAG_NONE;
        D3D12_RESOURCE_STATES initialState = D3D12_RESOURCE_STATE_COMMON;

        if ((d.sharedResourceFlags & SharedResourceFlags::Shared) != 0)
            heapFlags |= D3D12_HEAP_FLAG_SHARED;
        if ((d.sharedResourceFlags & SharedResourceFlags::Shared_CrossAdapter) != 0) {
            resourceDesc.Flags |= D3D12_RESOURCE_FLAG_ALLOW_CROSS_ADAPTER;
            heapFlags |= D3D12_HEAP_FLAG_SHARED_CROSS_ADAPTER;
        }

        switch(buffer.desc.cpuAccess)
        {
            case CpuAccessMode::None:
                heapProps.Type = D3D12_HEAP_TYPE_DEFAULT;
                initialState = convertResourceStates(d.initialState);
                break;

            case CpuAccessMode::Read:
                heapProps.Type = D3D12_HEAP_TYPE_READBACK;
                initialState = D3D12_RESOURCE_STATE_COPY_DEST;
                break;

            case CpuAccessMode::Write:
                heapProps.Type = D3D12_HEAP_TYPE_UPLOAD;
                initialState = D3D12_RESOURCE_STATE_GENERIC_READ;
                break;
        }

        HRESULT res = m_Context.device.CreateCommittedResource(
            &heapProps,
            heapFlags,
            &resourceDesc,
            initialState,
            null,
            IID_PPV_ARGS(&buffer.resource));

        if (FAILED(res))
        {
            std::stringstream ss;
            ss << "CreateCommittedResource call failed for buffer " << nvrhi.utils.DebugNameToString(d.debugName)
                << ", HRESULT = 0x" << std::hex << std::setw(8) << res;
            m_Context.error(ss.str());

            delete buffer;
            return null;
        }
        
        buffer.postCreate();

        return BufferHandle::Create(buffer);
    }

    public void *mapBuffer(IBuffer* _b, CpuAccessMode flags)
    {
        Buffer* b = checked_cast<Buffer*>(_b);

        if (b.lastUseFence)
        {
            WaitForFence(b.lastUseFence, b.lastUseFenceValue, m_FenceEvent);
            b.lastUseFence = null;
        }

        D3D12_RANGE range;

        if (flags == CpuAccessMode::Read)
        {
            range = { 0, b.desc.byteSize };
        } else {
            range = { 0, 0 };
        }

        void *mappedBuffer;
        const HRESULT res = b.resource.Map(0, &range, &mappedBuffer);

        if (FAILED(res))
        {
            std::stringstream ss;
            ss << "Map call failed for buffer " << nvrhi.utils.DebugNameToString(b.desc.debugName)
               << ", HRESULT = 0x" << std::hex << std::setw(8) << res;
            m_Context.error(ss.str());
            
            return null;
        }
        
        return mappedBuffer;
    }
    public void unmapBuffer(IBuffer* _b)
    {
        Buffer* b = checked_cast<Buffer*>(_b);

        b.resource.Unmap(0, null);
    }
    public MemoryRequirements getBufferMemoryRequirements(IBuffer* _buffer)
    {
        Buffer* buffer = checked_cast<Buffer*>(_buffer);

        D3D12_RESOURCE_ALLOCATION_INFO allocInfo = m_Context.device.GetResourceAllocationInfo(1, 1, &buffer.resourceDesc);

        MemoryRequirements memReq;
        memReq.alignment = allocInfo.Alignment;
        memReq.size = allocInfo.SizeInBytes;
        return memReq;
    }
    public bool bindBufferMemory(IBuffer* _buffer, IHeap* _heap, uint64 offset)
    {
        Buffer* buffer = checked_cast<Buffer*>(_buffer);
        Heap* heap = checked_cast<Heap*>(_heap);

        if (buffer.resource)
            return false; // already bound

        if (!buffer.desc.isVirtual)
            return false; // not supported

        HRESULT hr = m_Context.device.CreatePlacedResource(
            heap.heap, offset,
            &buffer.resourceDesc,
            convertResourceStates(buffer.desc.initialState),
            null,
            IID_PPV_ARGS(&buffer.resource));

        if (FAILED(hr))
        {
            std::stringstream ss;
            ss << "Failed to create placed buffer " << nvrhi.utils.DebugNameToString(buffer.desc.debugName) << ", error code = 0x";
            ss.setf(std::ios::hex, std::ios::basefield);
            ss << hr;
            m_Context.error(ss.str());

            return false;
        }

        buffer.heap = heap;
        buffer.postCreate();

        return true;
    }

    public BufferHandle createHandleForNativeBuffer(ObjectType objectType, NativeObject _buffer, const BufferDesc& desc)
    {
        if (_buffer.pointer == null)
            return null;

        if (objectType != ObjectTypes::D3D12_Resource)
            return null;

        ID3D12Resource* pResource = static_cast<ID3D12Resource*>(_buffer.pointer);

        Buffer* buffer = new Buffer(m_Context, m_Resources, desc);
        buffer.resource = pResource;
        
        buffer.postCreate();

        return BufferHandle::Create(buffer);
    }

    public ShaderHandle createShader(const ShaderDesc & d, const void * binary, const int binarySize)
    {
        if (binarySize == 0)
            return null;

        Shader* shader = new Shader();
        shader.bytecode.resize(binarySize);
        shader.desc = d;
        memcpy(&shader.bytecode[0], binary, binarySize);

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
        case ShaderType::Vertex:
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
        case ShaderType::Hull:
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
        case ShaderType::Domain:
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
        case ShaderType::Geometry:
            if ((d.fastGSFlags & FastGeometryShaderFlags::ForceFastGS) != 0 || d.numCustomSemantics || d.pCoordinateSwizzling)
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
                pExtn.ForceFastGS = (d.fastGSFlags & FastGeometryShaderFlags::ForceFastGS) != 0;
                pExtn.UseViewportMask = (d.fastGSFlags & FastGeometryShaderFlags::UseViewportMask) != 0;
                pExtn.OffsetRtIndexByVpIndex = (d.fastGSFlags & FastGeometryShaderFlags::OffsetTargetIndexByViewportIndex) != 0;
                pExtn.DontUseViewportOrder = (d.fastGSFlags & FastGeometryShaderFlags::StrictApiOrder) != 0;
                pExtn.UseSpecificShaderExt = d.useSpecificShaderExt;
                pExtn.UseAttributeSkipMask = false;

                shader.extensions.push_back(pExtn);
            }
            break;

        case ShaderType::Compute:
        case ShaderType::Pixel:
        case ShaderType::Amplification:
        case ShaderType::Mesh:
        case ShaderType::AllGraphics:
        case ShaderType::RayGeneration:
        case ShaderType::Miss:
        case ShaderType::ClosestHit:
        case ShaderType::AnyHit:
        case ShaderType::Intersection:
            if (d.numCustomSemantics)
            {
                nvrhi.utils.NotSupported();
                return null;
            }
            break;

        case ShaderType::None:
        case ShaderType::AllRayTracing:
        case ShaderType::All:
        default:
            nvrhi.utils.InvalidEnum();
            return null;
        }
#else
        if (d.numCustomSemantics || d.pCoordinateSwizzling || (d.fastGSFlags != 0) || d.hlslExtensionsUAV >= 0)
        {
            nvrhi.utils.NotSupported();
            delete shader;

            // NVAPI is unavailable
            return null;
        }
#endif
        
        return ShaderHandle::Create(shader);
    }
    public ShaderHandle createShaderSpecialization(IShader*, const ShaderSpecialization*, uint32)
    {
        nvrhi.utils.NotSupported();
        return null;
    }
    public ShaderLibraryHandle createShaderLibrary(const void* binary, const int binarySize)
    {
        ShaderLibrary* shaderLibrary = new ShaderLibrary();

        shaderLibrary.bytecode.resize(binarySize);
        memcpy(&shaderLibrary.bytecode[0], binary, binarySize);

        return ShaderLibraryHandle::Create(shaderLibrary);
    }

    public SamplerHandle createSampler(const SamplerDesc& d)
    {
        Sampler* sampler = new Sampler(m_Context, d);
        return SamplerHandle::Create(sampler);
    }

    public InputLayoutHandle createInputLayout(const VertexAttributeDesc * d, uint32 attributeCount, IShader* vertexShader)
    {
        // The shader is not needed here, there are no separate IL objects in DX12
        (void)vertexShader;

        InputLayout* layout = new InputLayout();
        layout.attributes.resize(attributeCount);

        for (uint32 index = 0; index < attributeCount; index++)
        {
            VertexAttributeDesc& attr = layout.attributes[index];

            // Copy the description to get a stable name pointer in desc
            attr = d[index];

            Runtime.Assert(attr.arraySize > 0);

            const DxgiFormatMapping& formatMapping = getDxgiFormatMapping(attr.format);
            const FormatInfo& formatInfo = getFormatInfo(attr.format);

            for (uint32 semanticIndex = 0; semanticIndex < attr.arraySize; semanticIndex++)
            {
                D3D12_INPUT_ELEMENT_DESC desc;

                desc.SemanticName = attr.name.c_str();
                desc.AlignedByteOffset = attr.offset + semanticIndex * formatInfo.bytesPerBlock;
                desc.Format = formatMapping.srvFormat;
                desc.InputSlot = attr.bufferIndex;
                desc.SemanticIndex = semanticIndex;

                if (attr.isInstanced)
                {
                    desc.InputSlotClass = D3D12_INPUT_CLASSIFICATION_PER_INSTANCE_DATA;
                    desc.InstanceDataStepRate = 1;
                }
                else
                {
                    desc.InputSlotClass = D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA;
                    desc.InstanceDataStepRate = 0;
                }

                layout.inputElements.push_back(desc);
            }

            if (layout.elementStrides.find(attr.bufferIndex) == layout.elementStrides.end())
            {
                layout.elementStrides[attr.bufferIndex] = attr.elementStride;
            } else {
                Runtime.Assert(layout.elementStrides[attr.bufferIndex] == attr.elementStride);
            }
        }

        return InputLayoutHandle::Create(layout);
    }

    public EventQueryHandle createEventQuery(void)
    {
        EventQuery *ret = new EventQuery();
        return EventQueryHandle::Create(ret);
    }
    public void setEventQuery(IEventQuery* _query, CommandQueue queue)
    {
        EventQuery* query = checked_cast<EventQuery*>(_query);
        Queue* pQueue = getQueue(queue);
        
        query.started = true;
        query.fence = pQueue.fence;
        query.fenceCounter = pQueue.lastSubmittedInstance;
        query.resolved = false;
    }
    public bool pollEventQuery(IEventQuery* _query)
    {
        EventQuery* query = checked_cast<EventQuery*>(_query);

        if (!query.started)
            return false;

        if (query.resolved)
            return true;

        Runtime.Assert(query.fence);
        
        if (query.fence.GetCompletedValue() >= query.fenceCounter)
        {
            query.resolved = true;
            query.fence = null;
        }

        return query.resolved;
    }
    public void waitEventQuery(IEventQuery* _query)
    {
        EventQuery* query = checked_cast<EventQuery*>(_query);

        if (!query.started || query.resolved)
            return;

        Runtime.Assert(query.fence);

        WaitForFence(query.fence, query.fenceCounter, m_FenceEvent);
    }
    public void resetEventQuery(IEventQuery* _query)
    {
        EventQuery* query = checked_cast<EventQuery*>(_query);

        query.started = false;
        query.resolved = false;
        query.fence = null;
    }

    public TimerQueryHandle createTimerQuery(void)
    {
        if (!m_Context.timerQueryHeap)
        {
            std::lock_guard lockGuard(m_Mutex);

            if (!m_Context.timerQueryHeap)
            {
                D3D12_QUERY_HEAP_DESC queryHeapDesc = {};
                queryHeapDesc.Type = D3D12_QUERY_HEAP_TYPE_TIMESTAMP;
                queryHeapDesc.Count = uint32(m_Resources.timerQueries.getCapacity()) * 2; // Use 2 D3D12 queries per 1 TimerQuery
                m_Context.device.CreateQueryHeap(&queryHeapDesc, IID_PPV_ARGS(&m_Context.timerQueryHeap));

                BufferDesc qbDesc;
                qbDesc.byteSize = queryHeapDesc.Count * 8;
                qbDesc.cpuAccess = CpuAccessMode::Read;

                BufferHandle timerQueryBuffer = createBuffer(qbDesc);
                m_Context.timerQueryResolveBuffer = checked_cast<Buffer*>(timerQueryBuffer.Get());
            }
        }

        int32 queryIndex = m_Resources.timerQueries.allocate();

        if (queryIndex < 0)
            return null;
        
        TimerQuery* query = new TimerQuery(m_Resources);
        query.beginQueryIndex = uint32(queryIndex) * 2;
        query.endQueryIndex = query.beginQueryIndex + 1;
        query.resolved = false;
        query.time = 0.f;

        return TimerQueryHandle::Create(query);
    }
    public bool pollTimerQuery(ITimerQuery* _query)
    {
        TimerQuery* query = checked_cast<TimerQuery*>(_query);

        if (!query.started)
            return false;

        if (!query.fence)
            return true;

        if (query.fence.GetCompletedValue() >= query.fenceCounter)
        {
            query.fence = null;
            return true;
        }

        return false;
    }
    public float getTimerQueryTime(ITimerQuery* _query)
    {
        TimerQuery* query = checked_cast<TimerQuery*>(_query);

        if (!query.resolved)
        {
            if (query.fence)
            {
                WaitForFence(query.fence, query.fenceCounter, m_FenceEvent);
                query.fence = null;
            }

            uint64 frequency;
            getQueue(CommandQueue::Graphics).queue.GetTimestampFrequency(&frequency);

            D3D12_RANGE bufferReadRange = {
                query.beginQueryIndex * sizeof(uint64),
                (query.beginQueryIndex + 2) * sizeof(uint64) };
            uint64 *data;
            const HRESULT res = m_Context.timerQueryResolveBuffer.resource.Map(0, &bufferReadRange, (void**)&data);

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
    public void resetTimerQuery(ITimerQuery* _query)
    {
        TimerQuery* query = checked_cast<TimerQuery*>(_query);

        query.started = false;
        query.resolved = false;
        query.time = 0.f;
        query.fence = null;
    }

    public GraphicsAPI getGraphicsAPI()
    {
        return GraphicsAPI::D3D12;
    }

    public FramebufferHandle createFramebuffer(const FramebufferDesc& desc)
    {
        Framebuffer *fb = new Framebuffer(m_Resources);
        fb.desc = desc;
        fb.framebufferInfo = FramebufferInfo(desc);

        if (!desc.colorAttachments.empty())
        {
            Texture* texture = checked_cast<Texture*>(desc.colorAttachments[0].texture);
            fb.rtWidth = texture.desc.width;
            fb.rtHeight = texture.desc.height;
        } else if (desc.depthAttachment.valid())
        {
            Texture* texture = checked_cast<Texture*>(desc.depthAttachment.texture);
            fb.rtWidth = texture.desc.width;
            fb.rtHeight = texture.desc.height;
        }

        for (int rt = 0; rt < desc.colorAttachments.size(); rt++)
        {
            auto& attachment = desc.colorAttachments[rt];

            Texture* texture = checked_cast<Texture*>(attachment.texture);
            Runtime.Assert(texture.desc.width == fb.rtWidth);
            Runtime.Assert(texture.desc.height == fb.rtHeight);

            DescriptorIndex index = m_Resources.renderTargetViewHeap.allocateDescriptor();

            const D3D12_CPU_DESCRIPTOR_HANDLE descriptorHandle = m_Resources.renderTargetViewHeap.getCpuHandle(index);
            texture.createRTV(descriptorHandle.ptr, attachment.format, attachment.subresources);

            fb.RTVs.push_back(index);
            fb.textures.push_back(texture);
        }

        if (desc.depthAttachment.valid())
        {
            Texture* texture = checked_cast<Texture*>(desc.depthAttachment.texture);
            Runtime.Assert(texture.desc.width == fb.rtWidth);
            Runtime.Assert(texture.desc.height == fb.rtHeight);

            DescriptorIndex index = m_Resources.depthStencilViewHeap.allocateDescriptor();

            const D3D12_CPU_DESCRIPTOR_HANDLE descriptorHandle = m_Resources.depthStencilViewHeap.getCpuHandle(index);
            texture.createDSV(descriptorHandle.ptr, desc.depthAttachment.subresources, desc.depthAttachment.isReadOnly);

            fb.DSV = index;
            fb.textures.push_back(texture);
        }

        return FramebufferHandle::Create(fb);
    }
    
    public GraphicsPipelineHandle createGraphicsPipeline(const GraphicsPipelineDesc& desc, IFramebuffer* fb)
    {
        RefCountPtr<RootSignature> pRS = getRootSignature(desc.bindingLayouts, desc.inputLayout != null);

        D3D12RefCountPtr<ID3D12PipelineState> pPSO = createPipelineState(desc, pRS, fb.getFramebufferInfo());

        return createHandleForNativeGraphicsPipeline(pRS, pPSO, desc, fb.getFramebufferInfo());
    }
    
    public ComputePipelineHandle createComputePipeline(const ComputePipelineDesc& desc)
    {
        RefCountPtr<RootSignature> pRS = getRootSignature(desc.bindingLayouts, false);
        D3D12RefCountPtr<ID3D12PipelineState> pPSO = createPipelineState(desc, pRS);

        if (pPSO == null)
            return null;

        ComputePipeline *pso = new ComputePipeline();

        pso.desc = desc;

        pso.rootSignature = pRS;
        pso.pipelineState = pPSO;

        return ComputePipelineHandle::Create(pso);
    }

    public MeshletPipelineHandle createMeshletPipeline(const MeshletPipelineDesc& desc, IFramebuffer* fb)
    {
        RefCountPtr<RootSignature> pRS = getRootSignature(desc.bindingLayouts, false);

        D3D12RefCountPtr<ID3D12PipelineState> pPSO = createPipelineState(desc, pRS, fb.getFramebufferInfo());

        return createHandleForNativeMeshletPipeline(pRS, pPSO, desc, fb.getFramebufferInfo());
    }

	/**
	#define NEW_ON_STACK(T) (T*)alloca(sizeof(T))
	*/


    public nvrhi.rt.PipelineHandle createRayTracingPipeline(const nvrhi.rt.PipelineDesc& desc)
    {
        RayTracingPipeline* pso = new RayTracingPipeline(m_Context);
        pso.desc = desc;
        pso.maxLocalRootParameters = 0;

        // Collect all DXIL libraries that are referenced in `desc`, and enumerate their exports.
        // Build local root signatures for all referenced local binding layouts.
        // Convert the export names to wstring.

        struct Library
        {
            const void* pBlob = null;
            int blobSize = 0;
            List<std::pair<std::wstring, std::wstring>> exports; // vector(originalName, newName)
            List<D3D12_EXPORT_DESC> d3dExports;
        };

        // Go through the individual shaders first.

        Dictionary<const void*, Library> dxilLibraries;

        for (const nvrhi.rt.PipelineShaderDesc& shaderDesc : desc.shaders)
        {
            const void* pBlob = null;
            int blobSize = 0;
            shaderDesc.shader.getBytecode(&pBlob, &blobSize);

            // Assuming that no shader is referenced twice, we just add every shader to its library export list.

            Library& library = dxilLibraries[pBlob];
            library.pBlob = pBlob;
            library.blobSize = blobSize;

            String originalShaderName = shaderDesc.shader.getDesc().entryName;
            String newShaderName = shaderDesc.exportName.empty() ? originalShaderName : shaderDesc.exportName;

            library.exports.push_back(std::make_pair<std::wstring, std::wstring>(
                std::wstring(originalShaderName.begin(), originalShaderName.end()),
                std::wstring(newShaderName.begin(), newShaderName.end())
                ));

            // Build a local root signature for the shader, if needed.

            if (shaderDesc.bindingLayout)
            {
                RootSignatureHandle& localRS = pso.localRootSignatures[shaderDesc.bindingLayout];
                if (!localRS)
                {
                    localRS = buildRootSignature({ shaderDesc.bindingLayout }, false, true);

                    BindingLayout* layout = checked_cast<BindingLayout*>(shaderDesc.bindingLayout.Get());
                    pso.maxLocalRootParameters = std::max(pso.maxLocalRootParameters, uint32(layout.rootParameters.size()));
                }
            }
        }

        // Still in the collection phase - go through the hit groups.
        // Rename all exports used in the hit groups to avoid collisions between different libraries.

        List<D3D12_HIT_GROUP_DESC> d3dHitGroups;
        Dictionary<IShader*, std::wstring> hitGroupShaderNames;
        List<std::wstring> hitGroupExportNames;

        for (const nvrhi.rt.PipelineHitGroupDesc& hitGroupDesc : desc.hitGroups)
        {
            for (const ShaderHandle& shader : { hitGroupDesc.closestHitShader, hitGroupDesc.anyHitShader, hitGroupDesc.intersectionShader })
            {
                if (!shader)
                    continue;

                std::wstring& newName = hitGroupShaderNames[shader];

                // See if we've encountered this particular shader before...

                if (newName.empty())
                {
                    // No - add it to the corresponding library, come up with a new name for it.

                    const void* pBlob = null;
                    int blobSize = 0;
                    shader.getBytecode(&pBlob, &blobSize);

                    Library& library = dxilLibraries[pBlob];
                    library.pBlob = pBlob;
                    library.blobSize = blobSize;

                    String originalShaderName = shader.getDesc().entryName;
                    String newShaderName = originalShaderName + std::to_string(hitGroupShaderNames.size());

                    library.exports.push_back(std::make_pair<std::wstring, std::wstring>(
                        std::wstring(originalShaderName.begin(), originalShaderName.end()),
                        std::wstring(newShaderName.begin(), newShaderName.end())
                        ));

                    newName = std::wstring(newShaderName.begin(), newShaderName.end());
                }
            }

            // Build a local root signature for the hit group, if needed.

            if (hitGroupDesc.bindingLayout)
            {
                RootSignatureHandle& localRS = pso.localRootSignatures[hitGroupDesc.bindingLayout];
                if (!localRS)
                {
                    localRS = buildRootSignature({ hitGroupDesc.bindingLayout }, false, true);

                    BindingLayout* layout = checked_cast<BindingLayout*>(hitGroupDesc.bindingLayout.Get());
                    pso.maxLocalRootParameters = std::max(pso.maxLocalRootParameters, uint32(layout.rootParameters.size()));
                }
            }

            // Create a hit group descriptor and store the new export names in it.

            D3D12_HIT_GROUP_DESC d3dHitGroupDesc = {};
            if (hitGroupDesc.anyHitShader)
                d3dHitGroupDesc.AnyHitShaderImport = hitGroupShaderNames[hitGroupDesc.anyHitShader].c_str();
            if (hitGroupDesc.closestHitShader)
                d3dHitGroupDesc.ClosestHitShaderImport = hitGroupShaderNames[hitGroupDesc.closestHitShader].c_str();
            if (hitGroupDesc.intersectionShader)
                d3dHitGroupDesc.IntersectionShaderImport = hitGroupShaderNames[hitGroupDesc.intersectionShader].c_str();

            if (hitGroupDesc.isProceduralPrimitive)
                d3dHitGroupDesc.Type = D3D12_HIT_GROUP_TYPE_PROCEDURAL_PRIMITIVE;
            else
                d3dHitGroupDesc.Type = D3D12_HIT_GROUP_TYPE_TRIANGLES;

            std::wstring hitGroupExportName = std::wstring(hitGroupDesc.exportName.begin(), hitGroupDesc.exportName.end());
            hitGroupExportNames.push_back(hitGroupExportName); // store the wstring so that it's not deallocated
            d3dHitGroupDesc.HitGroupExport = hitGroupExportNames[hitGroupExportNames.size() - 1].c_str();
            d3dHitGroups.push_back(d3dHitGroupDesc);
        }

        // Create descriptors for DXIL libraries, enumerate the exports used from each library.

        List<D3D12_DXIL_LIBRARY_DESC> d3dDxilLibraries;
        d3dDxilLibraries.reserve(dxilLibraries.size());
        for (auto& it : dxilLibraries)
        {
            Library& library = it.second;

            for (const std::pair<std::wstring, std::wstring>& exportNames : library.exports)
            {
                D3D12_EXPORT_DESC d3dExportDesc = {};
                d3dExportDesc.ExportToRename = exportNames.first.c_str();
                d3dExportDesc.Name = exportNames.second.c_str();
                d3dExportDesc.Flags = D3D12_EXPORT_FLAG_NONE;
                library.d3dExports.push_back(d3dExportDesc);
            }

            D3D12_DXIL_LIBRARY_DESC d3dLibraryDesc = {};
            d3dLibraryDesc.DXILLibrary.pShaderBytecode = library.pBlob;
            d3dLibraryDesc.DXILLibrary.BytecodeLength = library.blobSize;
            d3dLibraryDesc.NumExports = UINT(library.d3dExports.size());
            d3dLibraryDesc.pExports = library.d3dExports.data();

            d3dDxilLibraries.push_back(d3dLibraryDesc);
        }

        // Start building the D3D state subobject array.

        List<D3D12_STATE_SUBOBJECT> d3dSubobjects;

        // Same subobject is reused multiple times and copied to the vector each time.
        D3D12_STATE_SUBOBJECT d3dSubobject = {};

        // Subobject: Shader config

        D3D12_RAYTRACING_SHADER_CONFIG d3dShaderConfig = {};
        d3dShaderConfig.MaxAttributeSizeInBytes = desc.maxAttributeSize;
        d3dShaderConfig.MaxPayloadSizeInBytes = desc.maxPayloadSize;

        d3dSubobject.Type = D3D12_STATE_SUBOBJECT_TYPE_RAYTRACING_SHADER_CONFIG;
        d3dSubobject.pDesc = &d3dShaderConfig;
        d3dSubobjects.push_back(d3dSubobject);

        // Subobject: Pipeline config

        D3D12_RAYTRACING_PIPELINE_CONFIG d3dPipelineConfig = {};
        d3dPipelineConfig.MaxTraceRecursionDepth = desc.maxRecursionDepth;

        d3dSubobject.Type = D3D12_STATE_SUBOBJECT_TYPE_RAYTRACING_PIPELINE_CONFIG;
        d3dSubobject.pDesc = &d3dPipelineConfig;
        d3dSubobjects.push_back(d3dSubobject);

        // Subobjects: DXIL libraries

        for (const D3D12_DXIL_LIBRARY_DESC& d3dLibraryDesc : d3dDxilLibraries)
        {
            d3dSubobject.Type = D3D12_STATE_SUBOBJECT_TYPE_DXIL_LIBRARY;
            d3dSubobject.pDesc = &d3dLibraryDesc;
            d3dSubobjects.push_back(d3dSubobject);
        }

        // Subobjects: hit groups

        for (const D3D12_HIT_GROUP_DESC& d3dHitGroupDesc : d3dHitGroups)
        {
            d3dSubobject.Type = D3D12_STATE_SUBOBJECT_TYPE_HIT_GROUP;
            d3dSubobject.pDesc = &d3dHitGroupDesc;
            d3dSubobjects.push_back(d3dSubobject);
        }

        // Subobject: global root signature

        D3D12_GLOBAL_ROOT_SIGNATURE d3dGlobalRootSignature = {};

        if (!desc.globalBindingLayouts.empty())
        {
            RootSignatureHandle rootSignature = buildRootSignature(desc.globalBindingLayouts, false, false);
            pso.globalRootSignature = checked_cast<RootSignature*>(rootSignature.Get());
            d3dGlobalRootSignature.pGlobalRootSignature = pso.globalRootSignature.getNativeObject(ObjectTypes::D3D12_RootSignature);

            d3dSubobject.Type = D3D12_STATE_SUBOBJECT_TYPE_GLOBAL_ROOT_SIGNATURE;
            d3dSubobject.pDesc = &d3dGlobalRootSignature;
            d3dSubobjects.push_back(d3dSubobject);
        }

        // Subobjects: local root signatures

        // Make sure that adding local root signatures does not resize the array,
        // because we need to store pointers to array elements there.
        d3dSubobjects.reserve(d3dSubobjects.size() + pso.localRootSignatures.size() * 2);

        // Same - pre-allocate the arrays to avoid resizing them
        int numAssociations = desc.shaders.size() + desc.hitGroups.size();
        List<std::wstring> d3dAssociationExports;
        List<LPCWSTR> d3dAssociationExportsCStr;
        d3dAssociationExports.reserve(numAssociations);
        d3dAssociationExportsCStr.reserve(numAssociations);

        for (const auto& it : pso.localRootSignatures)
        {
            auto d3dLocalRootSignature = NEW_ON_STACK(D3D12_LOCAL_ROOT_SIGNATURE);
            d3dLocalRootSignature.pLocalRootSignature = it.second.getNativeObject(ObjectTypes::D3D12_RootSignature);

            d3dSubobject.Type = D3D12_STATE_SUBOBJECT_TYPE_LOCAL_ROOT_SIGNATURE;
            d3dSubobject.pDesc = d3dLocalRootSignature;
            d3dSubobjects.push_back(d3dSubobject);

            auto d3dAssociation = NEW_ON_STACK(D3D12_SUBOBJECT_TO_EXPORTS_ASSOCIATION);
            d3dAssociation.pSubobjectToAssociate = &d3dSubobjects[d3dSubobjects.size() - 1];
            d3dAssociation.NumExports = 0;
            int firstExportIndex = d3dAssociationExportsCStr.size();

            for (auto shader : desc.shaders)
            {
                if (shader.bindingLayout == it.first)
                {
                    String exportName = shader.exportName.empty() ? shader.shader.getDesc().entryName : shader.exportName;
                    std::wstring exportNameW = std::wstring(exportName.begin(), exportName.end());
                    d3dAssociationExports.push_back(exportNameW);
                    d3dAssociationExportsCStr.push_back(d3dAssociationExports[d3dAssociationExports.size() - 1].c_str());
                    d3dAssociation.NumExports += 1;
                }
            }

            for (auto hitGroup : desc.hitGroups)
            {
                if (hitGroup.bindingLayout == it.first)
                {
                    std::wstring exportNameW = std::wstring(hitGroup.exportName.begin(), hitGroup.exportName.end());
                    d3dAssociationExports.push_back(exportNameW);
                    d3dAssociationExportsCStr.push_back(d3dAssociationExports[d3dAssociationExports.size() - 1].c_str());
                    d3dAssociation.NumExports += 1;
                }
            }
            
            d3dAssociation.pExports = &d3dAssociationExportsCStr[firstExportIndex];

            d3dSubobject.Type = D3D12_STATE_SUBOBJECT_TYPE_SUBOBJECT_TO_EXPORTS_ASSOCIATION;
            d3dSubobject.pDesc = d3dAssociation;
            d3dSubobjects.push_back(d3dSubobject);
        }

        // Top-level PSO descriptor structure

        D3D12_STATE_OBJECT_DESC pipelineDesc = {};
        pipelineDesc.Type = D3D12_STATE_OBJECT_TYPE_RAYTRACING_PIPELINE;
        pipelineDesc.NumSubobjects = static_cast<UINT>(d3dSubobjects.size());
        pipelineDesc.pSubobjects = d3dSubobjects.data();

        HRESULT hr = m_Context.device5.CreateStateObject(&pipelineDesc, IID_PPV_ARGS(&pso.pipelineState));
        if (FAILED(hr))
        {
            m_Context.error("Failed to create a DXR pipeline state object");
            return null;
        }

        hr = pso.pipelineState.QueryInterface(IID_PPV_ARGS(&pso.pipelineInfo));
        if (FAILED(hr))
        {
            m_Context.error("Failed to get a DXR pipeline info interface from a PSO");
            return null;
        }

        for (const nvrhi.rt.PipelineShaderDesc& shaderDesc : desc.shaders)
        {
            String exportName = !shaderDesc.exportName.empty() ? shaderDesc.exportName : shaderDesc.shader.getDesc().entryName;
            std::wstring exportNameW = std::wstring(exportName.begin(), exportName.end());
            const void* pShaderIdentifier = pso.pipelineInfo.GetShaderIdentifier(exportNameW.c_str());

            if (pShaderIdentifier == null)
            {
                m_Context.error("Failed to get an identifier for a shader in a fresh DXR PSO");
                return null;
            }

            pso.exports[exportName] = RayTracingPipeline::ExportTableEntry{ shaderDesc.bindingLayout, pShaderIdentifier };
        }

        for(const nvrhi.rt.PipelineHitGroupDesc& hitGroupDesc : desc.hitGroups)
        { 
            std::wstring exportNameW = std::wstring(hitGroupDesc.exportName.begin(), hitGroupDesc.exportName.end());
            const void* pShaderIdentifier = pso.pipelineInfo.GetShaderIdentifier(exportNameW.c_str());

            if (pShaderIdentifier == null)
            {
                m_Context.error("Failed to get an identifier for a hit group in a fresh DXR PSO");
                return null;
            }

            pso.exports[hitGroupDesc.exportName] = RayTracingPipeline::ExportTableEntry{ hitGroupDesc.bindingLayout, pShaderIdentifier };
        }

        return nvrhi.rt.PipelineHandle::Create(pso);
    }

    public BindingLayoutHandle createBindingLayout(const BindingLayoutDesc& desc)
    {
        BindingLayout* ret = new BindingLayout(desc);
        return BindingLayoutHandle::Create(ret);
    }
    public BindingLayoutHandle createBindlessLayout(const BindlessLayoutDesc& desc)
    {
        BindlessLayout* ret = new BindlessLayout(desc);
        return BindingLayoutHandle::Create(ret);
    }

    public BindingSetHandle createBindingSet(const BindingSetDesc& desc, IBindingLayout* _layout)
    {
        BindingSet *ret = new BindingSet(m_Context, m_Resources);
        ret.desc = desc;

        BindingLayout* pipelineLayout = checked_cast<BindingLayout*>(_layout);
        ret.layout = pipelineLayout;

        ret.createDescriptors();

        return BindingSetHandle::Create(ret);
    }
    public DescriptorTableHandle createDescriptorTable(IBindingLayout* layout)
    {
        (void)layout; // not necessary on DX12

        DescriptorTable* ret = new DescriptorTable(m_Resources);
        ret.capacity = 0;
        ret.firstDescriptor = 0;
        
        return DescriptorTableHandle::Create(ret);
    }

    public void resizeDescriptorTable(IDescriptorTable* _descriptorTable, uint32 newSize, bool keepContents)
    {
        DescriptorTable* descriptorTable = checked_cast<DescriptorTable*>(_descriptorTable);

        if (newSize == descriptorTable.capacity)
            return;

        if (newSize < descriptorTable.capacity)
        {
            m_Resources.shaderResourceViewHeap.releaseDescriptors(descriptorTable.firstDescriptor + newSize, descriptorTable.capacity - newSize);
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
                D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);

            m_Context.device.CopyDescriptorsSimple(descriptorTable.capacity,
                m_Resources.shaderResourceViewHeap.getCpuHandleShaderVisible(descriptorTable.firstDescriptor),
                m_Resources.shaderResourceViewHeap.getCpuHandle(originalFirst),
                D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);

            m_Resources.shaderResourceViewHeap.releaseDescriptors(originalFirst, descriptorTable.capacity);
        }

        descriptorTable.capacity = newSize;
    }
    public bool writeDescriptorTable(IDescriptorTable* _descriptorTable, const BindingSetItem& binding)
    {
        DescriptorTable* descriptorTable = checked_cast<DescriptorTable*>(_descriptorTable);

        if (binding.slot >= descriptorTable.capacity)
            return false;

        D3D12_CPU_DESCRIPTOR_HANDLE descriptorHandle = m_Resources.shaderResourceViewHeap.getCpuHandle(descriptorTable.firstDescriptor + binding.slot);

        switch (binding.type)
        {
        case ResourceType::None:
            Buffer::createNullSRV(descriptorHandle.ptr, Format::UNKNOWN, m_Context);
            break; 
        case ResourceType::Texture_SRV: {
            Texture* texture = checked_cast<Texture*>(binding.resourceHandle);
            texture.createSRV(descriptorHandle.ptr, binding.format, binding.dimension, binding.subresources);
            break;
        }
        case ResourceType::Texture_UAV: {
            Texture* texture = checked_cast<Texture*>(binding.resourceHandle);
            texture.createUAV(descriptorHandle.ptr, binding.format, binding.dimension, binding.subresources);
            break;
        }
        case ResourceType::TypedBuffer_SRV:
        case ResourceType::StructuredBuffer_SRV:
        case ResourceType::RawBuffer_SRV: {
            Buffer* buffer = checked_cast<Buffer*>(binding.resourceHandle);
            buffer.createSRV(descriptorHandle.ptr, binding.format, binding.range, binding.type);
            break;
        }
        case ResourceType::TypedBuffer_UAV:
        case ResourceType::StructuredBuffer_UAV:
        case ResourceType::RawBuffer_UAV: {
            Buffer* buffer = checked_cast<Buffer*>(binding.resourceHandle);
            buffer.createUAV(descriptorHandle.ptr, binding.format, binding.range, binding.type);
            break;
        }
        case ResourceType::ConstantBuffer: {
            Buffer* buffer = checked_cast<Buffer*>(binding.resourceHandle);
            buffer.createCBV(descriptorHandle.ptr);
            break;
        }
        case ResourceType::RayTracingAccelStruct: {
            AccelStruct* accelStruct = checked_cast<AccelStruct*>(binding.resourceHandle);
            accelStruct.createSRV(descriptorHandle.ptr);
            break;
        }

        case ResourceType::VolatileConstantBuffer:
            m_Context.error("Attempted to bind a volatile constant buffer to a bindless set.");
            return false;

        case ResourceType::Sampler:
        case ResourceType::PushConstants:
        case ResourceType::Count:
        default:
            nvrhi.utils.InvalidEnum();
            return false;
        }

        m_Resources.shaderResourceViewHeap.copyToShaderVisibleHeap(descriptorTable.firstDescriptor + binding.slot, 1);
        return true;
    }

    public nvrhi.rt.AccelStructHandle createAccelStruct(const nvrhi.rt.AccelStructDesc& desc)
    {
        List<D3D12_RAYTRACING_GEOMETRY_DESC> d3dGeometryDescs;
        d3dGeometryDescs.resize(desc.bottomLevelGeometries.size());

        D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS ASInputs;
        if (desc.isTopLevel)
        {
            ASInputs.Type = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL;
            ASInputs.InstanceDescs = 0;
            ASInputs.NumDescs = UINT(desc.topLevelMaxInstances);
        }
        else
        {
            for (uint32 i = 0; i < desc.bottomLevelGeometries.size(); i++)
            {
                fillD3dGeometryDesc(d3dGeometryDescs[i], desc.bottomLevelGeometries[i]);
            }

            ASInputs.Type = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL;
            ASInputs.pGeometryDescs = d3dGeometryDescs.data();
            ASInputs.NumDescs = UINT(d3dGeometryDescs.size());
        }

        ASInputs.DescsLayout = D3D12_ELEMENTS_LAYOUT_ARRAY;
        ASInputs.Flags = (D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAGS)desc.buildFlags;

        D3D12_RAYTRACING_ACCELERATION_STRUCTURE_PREBUILD_INFO ASPreBuildInfo = {};
        m_Context.device5.GetRaytracingAccelerationStructurePrebuildInfo(&ASInputs, &ASPreBuildInfo);

        AccelStruct* as = new AccelStruct(m_Context);
        as.desc = desc;
        as.allowUpdate = (desc.buildFlags & nvrhi.rt.AccelStructBuildFlags::AllowUpdate) != 0;

        Runtime.Assert(ASPreBuildInfo.ResultDataMaxSizeInBytes <= ~0u);

#ifdef NVRHI_WITH_RTXMU
        bool needBuffer = desc.isTopLevel;
#else
        bool needBuffer = true;
#endif

        if (needBuffer)
        {
            BufferDesc bufferDesc;
            bufferDesc.canHaveUAVs = true;
            bufferDesc.byteSize = ASPreBuildInfo.ResultDataMaxSizeInBytes;
            bufferDesc.initialState = desc.isTopLevel ? ResourceStates::AccelStructRead : ResourceStates::AccelStructBuildBlas;
            bufferDesc.keepInitialState = true;
            bufferDesc.isAccelStructStorage = true;
            bufferDesc.debugName = desc.debugName;
            bufferDesc.isVirtual = desc.isVirtual;
            BufferHandle buffer = createBuffer(bufferDesc);
            as.dataBuffer = checked_cast<Buffer*>(buffer.Get());
        }
        
        // Sanitize the geometry data to avoid dangling pointers, we don't need these buffers in the Desc
        for (auto& geometry : as.desc.bottomLevelGeometries)
        {
            static_assert(offsetof(nvrhi.rt.GeometryTriangles, indexBuffer)
                == offsetof(nvrhi.rt.GeometryAABBs, buffer));
            static_assert(offsetof(nvrhi.rt.GeometryTriangles, vertexBuffer)
                == offsetof(nvrhi.rt.GeometryAABBs, unused));

            // Clear only the triangles' data, because the AABBs' data is aliased to triangles (verified above)
            geometry.geometryData.triangles.indexBuffer = null;
            geometry.geometryData.triangles.vertexBuffer = null;
        }

        return nvrhi.rt.AccelStructHandle::Create(as);
    }
    public MemoryRequirements getAccelStructMemoryRequirements(nvrhi.rt.IAccelStruct* _as)
    {
        AccelStruct* as = checked_cast<AccelStruct*>(_as);

        if (as.dataBuffer)
            return getBufferMemoryRequirements(as.dataBuffer);

        return MemoryRequirements();
    }
    public bool bindAccelStructMemory(nvrhi.rt.IAccelStruct* _as, IHeap* heap, uint64 offset)
    {
        AccelStruct* as = checked_cast<AccelStruct*>(_as);

        if (as.dataBuffer)
            return bindBufferMemory(as.dataBuffer, heap, offset);

        return false;
    }

    public nvrhi.CommandListHandle createCommandList(const CommandListParameters& params)
    {
        if (!getQueue(params.queueType))
            return null;

        return CommandListHandle::Create(new CommandList(this, m_Context, m_Resources, params));
    }
    public uint64 executeCommandLists(nvrhi.ICommandList* const* pCommandLists, int numCommandLists, CommandQueue executionQueue)
    {
        m_CommandListsToExecute.resize(numCommandLists);
        for (int i = 0; i < numCommandLists; i++)
        {
            m_CommandListsToExecute[i] = checked_cast<CommandList*>(pCommandLists[i]).getD3D12CommandList();
        }

        Queue* pQueue = getQueue(executionQueue);

        pQueue.queue.ExecuteCommandLists(uint32(m_CommandListsToExecute.size()), m_CommandListsToExecute.data());
        pQueue.lastSubmittedInstance++;
        pQueue.queue.Signal(pQueue.fence, pQueue.lastSubmittedInstance);

        for (int i = 0; i < numCommandLists; i++)
        {
            auto instance = checked_cast<CommandList*>(pCommandLists[i]).executed(pQueue);
            pQueue.commandListsInFlight.push_front(instance);
        }

        HRESULT hr = m_Context.device.GetDeviceRemovedReason();
        if (FAILED(hr))
        {
            m_Context.messageCallback.message(MessageSeverity::Fatal, "Device Removed!");
        }

        return pQueue.lastSubmittedInstance;
    }
    public void queueWaitForCommandList(CommandQueue waitQueue, CommandQueue executionQueue, uint64 instanceID)
    {
        Queue* pWaitQueue = getQueue(waitQueue);
        Queue* pExecutionQueue = getQueue(executionQueue);
        Runtime.Assert(instanceID <= pExecutionQueue.lastSubmittedInstance);

        pWaitQueue.queue.Wait(pExecutionQueue.fence, instanceID);
    }
    public void waitForIdle()
    {
        // Wait for every queue to reach its last submitted instance
        for (const auto& pQueue : m_Queues)
        {
            if (!pQueue)
                continue;

            if (pQueue.updateLastCompletedInstance() < pQueue.lastSubmittedInstance)
            {
                WaitForFence(pQueue.fence, pQueue.lastSubmittedInstance, m_FenceEvent);
            }
        }
    }
    public void runGarbageCollection()
    {
        for (const auto& pQueue : m_Queues)
        {
            if (!pQueue)
                continue;

            pQueue.updateLastCompletedInstance();

            // Starting from the back of the queue, i.e. oldest submitted command lists,
            // see if those command lists have finished executing.
            while (!pQueue.commandListsInFlight.empty())
            {
                std::shared_ptr<CommandListInstance> instance = pQueue.commandListsInFlight.back();
                
                if (pQueue.lastCompletedInstance >= instance.submittedInstance)
                {
#ifdef NVRHI_WITH_RTXMU
                    if (!instance.rtxmuBuildIds.empty())
                    {
                        std::lock_guard lockGuard(m_Resources.asListMutex);

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
                    pQueue.commandListsInFlight.pop_back();
                }
                else
                {
                    break;
                }
            }
        }
    }
    public bool queryFeatureSupport(Feature feature, void* pInfo, int infoSize = 0)
    {
        switch (feature)  // NOLINT(clang-diagnostic-switch-enum)
        {
        case Feature::DeferredCommandLists:
            return true;
        case Feature::SinglePassStereo:
            return m_SinglePassStereoSupported;
        case Feature::RayTracingAccelStruct:
            return m_RayTracingSupported;
        case Feature::RayTracingPipeline:
            return m_RayTracingSupported;
        case Feature::RayQuery:
            return m_TraceRayInlineSupported;
        case Feature::FastGeometryShader:
            return m_FastGeometryShaderSupported;
        case Feature::Meshlets:
            return m_MeshletsSupported;
        case Feature::VariableRateShading:
            if (pInfo)
            {
                if (infoSize == sizeof(VariableRateShadingFeatureInfo))
                {
                    auto* pVrsInfo = reinterpret_cast<VariableRateShadingFeatureInfo*>(pInfo);
                    pVrsInfo.shadingRateImageTileSize = m_Options6.ShadingRateImageTileSize;
                }
                else
                    nvrhi.utils.NotSupported();
            }
            return m_VariableRateShadingSupported;
        case Feature::VirtualResources:
            return true;
        case Feature::ComputeQueue:
            return (getQueue(CommandQueue::Compute) != null);
        case Feature::CopyQueue:
            return (getQueue(CommandQueue::Copy) != null);
        default:
            return false;
        }
    }
    public FormatSupport queryFormatSupport(Format format)
    {
        const DxgiFormatMapping& formatMapping = getDxgiFormatMapping(format);

        FormatSupport result = FormatSupport::None;

        D3D12_FEATURE_DATA_FORMAT_SUPPORT featureData = {};
        featureData.Format = formatMapping.rtvFormat;

        m_Context.device.CheckFeatureSupport(D3D12_FEATURE_FORMAT_SUPPORT, &featureData, sizeof(featureData));

        if (featureData.Support1 & D3D12_FORMAT_SUPPORT1_BUFFER)
            result = result | FormatSupport::Buffer;
        if (featureData.Support1 & (D3D12_FORMAT_SUPPORT1_TEXTURE1D | D3D12_FORMAT_SUPPORT1_TEXTURE2D | D3D12_FORMAT_SUPPORT1_TEXTURE3D | D3D12_FORMAT_SUPPORT1_TEXTURECUBE))
            result = result | FormatSupport::Texture;
        if (featureData.Support1 & D3D12_FORMAT_SUPPORT1_DEPTH_STENCIL)
            result = result | FormatSupport::DepthStencil;
        if (featureData.Support1 & D3D12_FORMAT_SUPPORT1_RENDER_TARGET)
            result = result | FormatSupport::RenderTarget;
        if (featureData.Support1 & D3D12_FORMAT_SUPPORT1_BLENDABLE)
            result = result | FormatSupport::Blendable;

        if (formatMapping.srvFormat != featureData.Format)
        {
            featureData.Format = formatMapping.srvFormat;
            featureData.Support1 = (D3D12_FORMAT_SUPPORT1)0;
            featureData.Support2 = (D3D12_FORMAT_SUPPORT2)0;
            m_Context.device.CheckFeatureSupport(D3D12_FEATURE_FORMAT_SUPPORT, &featureData, sizeof(featureData));
        }

        if (featureData.Support1 & D3D12_FORMAT_SUPPORT1_IA_INDEX_BUFFER)
            result = result | FormatSupport::IndexBuffer;
        if (featureData.Support1 & D3D12_FORMAT_SUPPORT1_IA_VERTEX_BUFFER)
            result = result | FormatSupport::VertexBuffer;
        if (featureData.Support1 & D3D12_FORMAT_SUPPORT1_SHADER_LOAD)
            result = result | FormatSupport::ShaderLoad;
        if (featureData.Support1 & D3D12_FORMAT_SUPPORT1_SHADER_SAMPLE)
            result = result | FormatSupport::ShaderSample;
        if (featureData.Support2 & D3D12_FORMAT_SUPPORT2_UAV_ATOMIC_ADD)
            result = result | FormatSupport::ShaderAtomic;
        if (featureData.Support2 & D3D12_FORMAT_SUPPORT2_UAV_TYPED_LOAD)
            result = result | FormatSupport::ShaderUavLoad;
        if (featureData.Support2 & D3D12_FORMAT_SUPPORT2_UAV_TYPED_STORE)
            result = result | FormatSupport::ShaderUavStore;

        return result;
    }
    public NativeObject getNativeQueue(ObjectType objectType, CommandQueue queue)
    {
        if (objectType != ObjectTypes::D3D12_CommandQueue)
            return null;

        if (queue >= CommandQueue::Count)
            return null;

        Queue* pQueue = getQueue(queue);

        if (!pQueue)
            return null;

        return NativeObject(pQueue.queue.Get());
    }
    public IMessageCallback* getMessageCallback() override { return m_Context.messageCallback; }

    // d3d12::IDevice implementation

    public RootSignatureHandle buildRootSignature(const StaticVector<BindingLayoutHandle, c_MaxBindingLayouts>& pipelineLayouts, bool allowInputLayout, bool isLocal, const D3D12_ROOT_PARAMETER1* pCustomParameters = null, uint32 numCustomParameters = 0)
    {
        HRESULT res;

        RootSignature* rootsig = new RootSignature(m_Resources);
        
        // Assemble the root parameter table from the pipeline binding layouts
        // Also attach the root parameter offsets to the pipeline layouts

        List<D3D12_ROOT_PARAMETER1> rootParameters;

        // Add custom parameters in the beginning of the RS
        for (uint32 index = 0; index < numCustomParameters; index++)
        {
            rootParameters.push_back(pCustomParameters[index]);
        }

        for(uint32 layoutIndex = 0; layoutIndex < uint32(pipelineLayouts.size()); layoutIndex++)
        {
            if (pipelineLayouts[layoutIndex].getDesc())
            {
                BindingLayout* layout = checked_cast<BindingLayout*>(pipelineLayouts[layoutIndex].Get());
                RootParameterIndex rootParameterOffset = RootParameterIndex(rootParameters.size());

                rootsig.pipelineLayouts.push_back(std::make_pair(layout, rootParameterOffset));

                rootParameters.insert(rootParameters.end(), layout.rootParameters.begin(), layout.rootParameters.end());

                if (layout.pushConstantByteSize)
                {
                    rootsig.pushConstantByteSize = layout.pushConstantByteSize;
                    rootsig.rootParameterPushConstants = layout.rootParameterPushConstants + rootParameterOffset;
                }
            }
            else if (pipelineLayouts[layoutIndex].getBindlessDesc())
            {
                BindlessLayout* layout = checked_cast<BindlessLayout*>(pipelineLayouts[layoutIndex].Get());
                RootParameterIndex rootParameterOffset = RootParameterIndex(rootParameters.size());

                rootsig.pipelineLayouts.push_back(std::make_pair(layout, rootParameterOffset));

                rootParameters.push_back(layout.rootParameter);
            }
        }

        // Build the description structure

        D3D12_VERSIONED_ROOT_SIGNATURE_DESC rsDesc = {};
        rsDesc.Version = D3D_ROOT_SIGNATURE_VERSION_1_1;

        if (allowInputLayout)
        {
            rsDesc.Desc_1_1.Flags |= D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT;
        }
        if (isLocal)
        {
            rsDesc.Desc_1_1.Flags |= D3D12_ROOT_SIGNATURE_FLAG_LOCAL_ROOT_SIGNATURE;
        }

        if (!rootParameters.empty())
        {
            rsDesc.Desc_1_1.pParameters = rootParameters.data();
            rsDesc.Desc_1_1.NumParameters = UINT(rootParameters.size());
        }

        // Serialize the root signature

        RefCountPtr<ID3DBlob> rsBlob;
        RefCountPtr<ID3DBlob> errorBlob;
        res = D3D12SerializeVersionedRootSignature(&rsDesc, &rsBlob, &errorBlob);

        if (FAILED(res))
        {
            std::stringstream ss;
            ss << "D3D12SerializeVersionedRootSignature call failed, HRESULT = 0x" << std::hex << std::setw(8) << res;
            if (errorBlob) {
                ss << std::endl << (const char8*)errorBlob.GetBufferPointer();
            }
            m_Context.error(ss.str());
            
            return null;
        }

        // Create the RS object

        res = m_Context.device.CreateRootSignature(0, rsBlob.GetBufferPointer(), rsBlob.GetBufferSize(), IID_PPV_ARGS(&rootsig.handle));

        if (FAILED(res))
        {
            std::stringstream ss;
            ss << "CreateRootSignature call failed, HRESULT = 0x" << std::hex << std::setw(8) << res;
            m_Context.error(ss.str());

            return null;
        }

        return RootSignatureHandle::Create(rootsig);
    }
    public GraphicsPipelineHandle createHandleForNativeGraphicsPipeline(IRootSignature* rootSignature, ID3D12PipelineState* pipelineState, const GraphicsPipelineDesc& desc, const FramebufferInfo& framebufferInfo)
    {
        if (rootSignature == null)
            return null;

        if (pipelineState == null)
            return null;

        GraphicsPipeline *pso = new GraphicsPipeline();
        pso.desc = desc;
        pso.framebufferInfo = framebufferInfo;
        pso.rootSignature = checked_cast<RootSignature*>(rootSignature);
        pso.pipelineState = pipelineState;
        pso.requiresBlendFactor = desc.renderState.blendState.usesConstantColor(uint32(pso.framebufferInfo.colorFormats.size()));
        
        return GraphicsPipelineHandle::Create(pso);
    }
    public MeshletPipelineHandle createHandleForNativeMeshletPipeline(IRootSignature* rootSignature, ID3D12PipelineState* pipelineState, const MeshletPipelineDesc& desc, const FramebufferInfo& framebufferInfo)
    {
        if (rootSignature == null)
            return null;

        if (pipelineState == null)
            return null;

        MeshletPipeline *pso = new MeshletPipeline();
        pso.desc = desc;
        pso.framebufferInfo = framebufferInfo;
        pso.rootSignature = checked_cast<RootSignature*>(rootSignature);
        pso.pipelineState = pipelineState;
        pso.requiresBlendFactor = desc.renderState.blendState.usesConstantColor(uint32(pso.framebufferInfo.colorFormats.size()));

        return MeshletPipelineHandle::Create(pso);
    }
    public IDescriptorHeap* getDescriptorHeap(DescriptorHeapType heapType)
    {
        switch(heapType)
        {
        case DescriptorHeapType::RenderTargetView:
            return &m_Resources.renderTargetViewHeap;
        case DescriptorHeapType::DepthStencilView:
            return &m_Resources.depthStencilViewHeap;
        case DescriptorHeapType::ShaderResrouceView:
            return &m_Resources.shaderResourceViewHeap;
        case DescriptorHeapType::Sampler:
            return &m_Resources.samplerHeap;
        }

        return null;
    }

    // Internal interface
    public Queue* getQueue(CommandQueue type) { return m_Queues[int32(type)].get(); }

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
    private D3D12_FEATURE_DATA_D3D12_OPTIONS7 m_Options7 = .()s;

    private RefCountPtr<RootSignature> getRootSignature(const StaticVector<BindingLayoutHandle, c_MaxBindingLayouts>& pipelineLayouts, bool allowInputLayout)
    {
        int hash = 0;

        for (const BindingLayoutHandle& pipelineLayout : pipelineLayouts)
            hash_combine(hash, pipelineLayout.Get());
        
        hash_combine(hash, allowInputLayout ? 1u : 0u);
        
        // Get a cached RS and AddRef it (if it exists)
        RefCountPtr<RootSignature> rootsig = m_Resources.rootsigCache[hash];

        if (!rootsig)
        {
            // Does not exist - build a new one, take ownership
            rootsig = checked_cast<RootSignature*>(buildRootSignature(pipelineLayouts, allowInputLayout, false).Get());
            rootsig.hash = hash;

            m_Resources.rootsigCache[hash] = rootsig;
        }

        // Pass ownership of the RS to caller
        return rootsig;
    }
    private D3D12RefCountPtr<ID3D12PipelineState> createPipelineState(const GraphicsPipelineDesc & state, RootSignature* pRS, const FramebufferInfo& fbinfo) const
	{
	    if (state.renderState.singlePassStereo.enabled && !m_SinglePassStereoSupported)
	    {
	        m_Context.error("Single-pass stereo is not supported by this device");
	        return null;
	    }

	    D3D12_GRAPHICS_PIPELINE_STATE_DESC desc = {};
	    desc.pRootSignature = pRS.handle;

	    Shader* shader;
	    shader = checked_cast<Shader*>(state.VS.Get());
	    if (shader) desc.VS = { &shader.bytecode[0], shader.bytecode.size() };

	    shader = checked_cast<Shader*>(state.HS.Get());
	    if (shader) desc.HS = { &shader.bytecode[0], shader.bytecode.size() };

	    shader = checked_cast<Shader*>(state.DS.Get());
	    if (shader) desc.DS = { &shader.bytecode[0], shader.bytecode.size() };

	    shader = checked_cast<Shader*>(state.GS.Get());
	    if (shader) desc.GS = { &shader.bytecode[0], shader.bytecode.size() };

	    shader = checked_cast<Shader*>(state.PS.Get());
	    if (shader) desc.PS = { &shader.bytecode[0], shader.bytecode.size() };


	    TranslateBlendState(state.renderState.blendState, desc.BlendState);
	    

	    const DepthStencilState& depthState = state.renderState.depthStencilState;
	    TranslateDepthStencilState(depthState, desc.DepthStencilState);

	    if ((depthState.depthTestEnable || depthState.stencilEnable) && fbinfo.depthFormat == Format::UNKNOWN)
	    {
	        desc.DepthStencilState.DepthEnable = FALSE;
	        desc.DepthStencilState.StencilEnable = FALSE;
	        m_Context.messageCallback.message(MessageSeverity::Warning, "depthEnable or stencilEnable is true, but no depth target is bound");
	    }

	    const RasterState& rasterState = state.renderState.rasterState;
	    TranslateRasterizerState(rasterState, desc.RasterizerState);

	    switch (state.primType)
	    {
	    case PrimitiveType::PointList:
	        desc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_POINT;
	        break;
	    case PrimitiveType::LineList:
	        desc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_LINE;
	        break;
	    case PrimitiveType::TriangleList:
	    case PrimitiveType::TriangleStrip:
	        desc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
	        break;
	    case PrimitiveType::PatchList:
	        desc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_PATCH;
	        break;
	    }

	    desc.DSVFormat = getDxgiFormatMapping(fbinfo.depthFormat).rtvFormat;

	    desc.SampleDesc.Count = fbinfo.sampleCount;
	    desc.SampleDesc.Quality = fbinfo.sampleQuality;

	    for (uint32 i = 0; i < uint32(fbinfo.colorFormats.size()); i++)
	    {
	        desc.RTVFormats[i] = getDxgiFormatMapping(fbinfo.colorFormats[i]).rtvFormat;
	    }

	    InputLayout* inputLayout = checked_cast<InputLayout*>(state.inputLayout.Get());
	    if (inputLayout && !inputLayout.inputElements.empty())
	    {
	        desc.InputLayout.NumElements = uint32(inputLayout.inputElements.size());
	        desc.InputLayout.pInputElementDescs = &(inputLayout.inputElements[0]);
	    }

	    desc.NumRenderTargets = uint32(fbinfo.colorFormats.size());
	    desc.SampleMask = ~0u;

	    D3D12RefCountPtr<ID3D12PipelineState> pipelineState;

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

	    const HRESULT hr = m_Context.device.CreateGraphicsPipelineState(&desc, IID_PPV_ARGS(&pipelineState));

	    if (FAILED(hr))
	    {
	        m_Context.error("Failed to create a graphics pipeline state object");
	        return null;
	    }

	    return pipelineState;
	}
    private D3D12RefCountPtr<ID3D12PipelineState> createPipelineState(const ComputePipelineDesc & state, RootSignature* pRS) const
    {
        D3D12RefCountPtr<ID3D12PipelineState> pipelineState;

        D3D12_COMPUTE_PIPELINE_STATE_DESC desc = {};

        desc.pRootSignature = pRS.handle;
        Shader* shader = checked_cast<Shader*>(state.CS.Get());
        desc.CS = { &shader.bytecode[0], shader.bytecode.size() };

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

        const HRESULT hr = m_Context.device.CreateComputePipelineState(&desc, IID_PPV_ARGS(&pipelineState));

        if (FAILED(hr))
        {
            m_Context.error("Failed to create a compute pipeline state object");
            return null;
        }

        return pipelineState;
    }
    private D3D12RefCountPtr<ID3D12PipelineState> createPipelineState(const MeshletPipelineDesc& state, RootSignature* pRS, const FramebufferInfo& fbinfo) const
    {
        D3D12RefCountPtr<ID3D12PipelineState> pipelineState;

#pragma warning(push)
#pragma warning(disable: 4324) // structure was padded due to alignment specifier
        struct PSO_STREAM
        {
            typealias ALIGNED_TYPE = __declspec(align(sizeof(void*))) D3D12_PIPELINE_STATE_SUBOBJECT_TYPE ;

            ALIGNED_TYPE RootSignature_Type;        ID3D12RootSignature* RootSignature;
            ALIGNED_TYPE PrimitiveTopology_Type;    D3D12_PRIMITIVE_TOPOLOGY_TYPE PrimitiveTopologyType;
            ALIGNED_TYPE AmplificationShader_Type;  D3D12_SHADER_BYTECODE AmplificationShader;
            ALIGNED_TYPE MeshShader_Type;           D3D12_SHADER_BYTECODE MeshShader;
            ALIGNED_TYPE PixelShader_Type;          D3D12_SHADER_BYTECODE PixelShader;
            ALIGNED_TYPE RasterizerState_Type;      D3D12_RASTERIZER_DESC RasterizerState;
            ALIGNED_TYPE DepthStencilState_Type;    D3D12_DEPTH_STENCIL_DESC DepthStencilState;
            ALIGNED_TYPE BlendState_Type;           D3D12_BLEND_DESC BlendState;
            ALIGNED_TYPE SampleDesc_Type;           DXGI_SAMPLE_DESC SampleDesc;
            ALIGNED_TYPE SampleMask_Type;           UINT SampleMask;
            ALIGNED_TYPE RenderTargets_Type;        D3D12_RT_FORMAT_ARRAY RenderTargets;
            ALIGNED_TYPE DSVFormat_Type;            DXGI_FORMAT DSVFormat;
        } psoDesc = { };
#pragma warning(pop)

        psoDesc.RootSignature_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_ROOT_SIGNATURE;
        psoDesc.PrimitiveTopology_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_PRIMITIVE_TOPOLOGY;
        psoDesc.AmplificationShader_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_AS;
        psoDesc.MeshShader_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_MS;
        psoDesc.PixelShader_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_PS;
        psoDesc.RasterizerState_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_RASTERIZER;
        psoDesc.DepthStencilState_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_DEPTH_STENCIL;
        psoDesc.BlendState_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_BLEND;
        psoDesc.SampleDesc_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_SAMPLE_DESC;
        psoDesc.SampleMask_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_SAMPLE_MASK;
        psoDesc.RenderTargets_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_RENDER_TARGET_FORMATS;
        psoDesc.DSVFormat_Type = D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_DEPTH_STENCIL_FORMAT;

        psoDesc.RootSignature = pRS.handle;

        TranslateBlendState(state.renderState.blendState, psoDesc.BlendState);
        
        const DepthStencilState& depthState = state.renderState.depthStencilState;
        TranslateDepthStencilState(depthState, psoDesc.DepthStencilState);

        if ((depthState.depthTestEnable || depthState.stencilEnable) && fbinfo.depthFormat == Format::UNKNOWN)
        {
            psoDesc.DepthStencilState.DepthEnable = FALSE;
            psoDesc.DepthStencilState.StencilEnable = FALSE;
        }

        const RasterState& rasterState = state.renderState.rasterState;
        TranslateRasterizerState(rasterState, psoDesc.RasterizerState);

        switch (state.primType)
        {
        case PrimitiveType::PointList:
            psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_POINT;
            break;
        case PrimitiveType::LineList:
            psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_LINE;
            break;
        case PrimitiveType::TriangleList:
        case PrimitiveType::TriangleStrip:
            psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
            break;
        case PrimitiveType::PatchList:
            m_Context.error("Unsupported primitive topology for meshlets");
            return null;
        default:
            nvrhi.utils.InvalidEnum();
            return null;
        }

        psoDesc.SampleDesc.Count = fbinfo.sampleCount;
        psoDesc.SampleDesc.Quality = fbinfo.sampleQuality;
        psoDesc.SampleMask = ~0u;

        for (uint32 i = 0; i < uint32(fbinfo.colorFormats.size()); i++)
        {
            psoDesc.RenderTargets.RTFormats[i] = getDxgiFormatMapping(fbinfo.colorFormats[i]).rtvFormat;
        }
        psoDesc.RenderTargets.NumRenderTargets = uint32(fbinfo.colorFormats.size());

        psoDesc.DSVFormat = getDxgiFormatMapping(fbinfo.depthFormat).rtvFormat;

        if (state.AS)
        {
            state.AS.getBytecode(&psoDesc.AmplificationShader.pShaderBytecode, &psoDesc.AmplificationShader.BytecodeLength);
        }

        if (state.MS)
        {
            state.MS.getBytecode(&psoDesc.MeshShader.pShaderBytecode, &psoDesc.MeshShader.BytecodeLength);
        }

        if (state.PS)
        {
            state.PS.getBytecode(&psoDesc.PixelShader.pShaderBytecode, &psoDesc.PixelShader.BytecodeLength);
        }

        D3D12_PIPELINE_STATE_STREAM_DESC streamDesc;
        streamDesc.pPipelineStateSubobjectStream = &psoDesc;
        streamDesc.SizeInBytes = sizeof(psoDesc);

        HRESULT hr = m_Context.device2.CreatePipelineState(&streamDesc, IID_PPV_ARGS(&pipelineState));
        if (FAILED(hr))
        {
            m_Context.error("Failed to create a meshlet pipeline state object");
            return null;
        }

        return pipelineState;
    }
}