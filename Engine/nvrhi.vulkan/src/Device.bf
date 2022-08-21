using Bulkan;
namespace nvrhi.vulkan
{
	class Device :  /*RefCounter<nvrhi.vulkan.IDevice>*/nvrhi.vulkan.IDevice
	{
	    // Internal backend methods

	    public this(DeviceDesc desc){
			/*
			: m_Context(desc.instance, desc.physicalDevice, desc.device, desc.allocationCallbacks)
			, m_Allocator(m_Context)
			, m_TimerQueryAllocator(desc.maxTimerQueries, true)
			*/

			if (desc.graphicsQueue)
			{
			    m_Queues[uint32(CommandQueue.Graphics)] = std::make_unique<Queue>(m_Context,
			        CommandQueue.Graphics, desc.graphicsQueue, desc.graphicsQueueIndex);
			}

			if (desc.computeQueue)
			{
			    m_Queues[uint32(CommandQueue.Compute)] = std::make_unique<Queue>(m_Context,
			        CommandQueue.Compute, desc.computeQueue, desc.computeQueueIndex);
			}

			if (desc.transferQueue)
			{
			    m_Queues[uint32(CommandQueue.Copy)] = std::make_unique<Queue>(m_Context,
			        CommandQueue.Copy, desc.transferQueue, desc.transferQueueIndex);
			}

			// maps Vulkan extension strings into the corresponding boolean flags in Device
			const Dictionary<String, bool*> extensionStringMap = {
			    { VK_KHR_MAINTENANCE1_EXTENSION_NAME, &m_Context.extensions.KHR_maintenance1 },
			    { VK_EXT_DEBUG_REPORT_EXTENSION_NAME, &m_Context.extensions.EXT_debug_report },
			    { VK_EXT_DEBUG_MARKER_EXTENSION_NAME, &m_Context.extensions.EXT_debug_marker },
			    { VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME, &m_Context.extensions.KHR_acceleration_structure },
			    { VK_KHR_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME, &m_Context.extensions.KHR_buffer_device_address },
			    { VK_KHR_RAY_QUERY_EXTENSION_NAME,&m_Context.extensions.KHR_ray_query },
			    { VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME, &m_Context.extensions.KHR_ray_tracing_pipeline },
			    { VK_NV_MESH_SHADER_EXTENSION_NAME, &m_Context.extensions.NV_mesh_shader },
			    { VK_KHR_FRAGMENT_SHADING_RATE_EXTENSION_NAME, &m_Context.extensions.KHR_fragment_shading_rate },
			};

			// parse the extension/layer lists and figure out which extensions are enabled
			for(int i = 0; i < desc.numInstanceExtensions; i++)
			{
			    var ext = extensionStringMap.find(desc.instanceExtensions[i]);
			    if (ext != extensionStringMap.end())
			    {
			        *(ext.second) = true;
			    }
			}

			for(int i = 0; i < desc.numDeviceExtensions; i++)
			{
			    var ext = extensionStringMap.find(desc.deviceExtensions[i]);
			    if (ext != extensionStringMap.end())
			    {
			        *(ext.second) = true;
			    }
			}

			// Get the device properties with supported extensions

			void* pNext = null;
			VkPhysicalDeviceAccelerationStructurePropertiesKHR accelStructProperties;
			VkPhysicalDeviceRayTracingPipelinePropertiesKHR rayTracingPipelineProperties;
			VkPhysicalDeviceFragmentShadingRatePropertiesKHR shadingRateProperties;
			VkPhysicalDeviceProperties2 deviceProperties2;

			if (m_Context.extensions.KHR_acceleration_structure)
			{
			    accelStructProperties.pNext = pNext;
			    pNext = &accelStructProperties;
			}

			if (m_Context.extensions.KHR_ray_tracing_pipeline)
			{
			    rayTracingPipelineProperties.pNext = pNext;
			    pNext = &rayTracingPipelineProperties;
			}

			if (m_Context.extensions.KHR_fragment_shading_rate)
			{
			    shadingRateProperties.pNext = pNext;
			    pNext = &shadingRateProperties;
			}

			deviceProperties2.pNext = pNext;

			m_Context.physicalDevice.getProperties2(&deviceProperties2);

			m_Context.physicalDeviceProperties = deviceProperties2.properties;
			m_Context.accelStructProperties = accelStructProperties;
			m_Context.rayTracingPipelineProperties = rayTracingPipelineProperties;
			m_Context.shadingRateProperties = shadingRateProperties;
			m_Context.messageCallback = desc.errorCB;

			if (m_Context.extensions.KHR_fragment_shading_rate)
			{
			    VkPhysicalDeviceFeatures2 deviceFeatures2;
			    VkPhysicalDeviceFragmentShadingRateFeaturesKHR shadingRateFeatures;
			    deviceFeatures2.setPNext(&shadingRateFeatures);
			    m_Context.physicalDevice.getFeatures2(&deviceFeatures2);
			    m_Context.shadingRateFeatures = shadingRateFeatures;
			}
#if NVRHI_WITH_RTXMU
			if (m_Context.extensions.KHR_acceleration_structure)
			{
			    m_Context.rtxMemUtil = std::make_unique<rtxmu::VkAccelStructManager>(desc.instance, desc.device, desc.physicalDevice);

			    // Initialize suballocator blocks to 8 MB
			    m_Context.rtxMemUtil.Initialize(8388608);

			    m_Context.rtxMuResources = std::make_unique<RtxMuResources>();
			}
#endif
			var pipelineInfo = VkPipelineCacheCreateInfo();
			VkResult res = m_Context.device.createPipelineCache(&pipelineInfo,
			    m_Context.allocationCallbacks,
			    &m_Context.pipelineCache);

			if (res != VkResult.eSuccess)
			{
			    m_Context.error("Failed to create the pipeline cache");
			}
		}
	    public ~this()
    {
        if (m_TimerQueryPool)
        {
            m_Context.device.destroyQueryPool(m_TimerQueryPool);
            m_TimerQueryPool = VkQueryPool();
        }

        if (m_Context.pipelineCache)
        {
            m_Context.device.destroyPipelineCache(m_Context.pipelineCache);
            m_Context.pipelineCache = VkPipelineCache();
        }
    }

	    public Queue getQueue(CommandQueue queue) { return m_Queues[int32(queue)]; }
	    public VkQueryPool getTimerQueryPool() { return m_TimerQueryPool; }

	    // IResource implementation

	    public override NativeObject getNativeObject(ObjectType objectType)
    {
        switch (objectType)
        {
        case ObjectType.VK_Device:
            return NativeObject(m_Context.device);
        case ObjectType.VK_PhysicalDevice:
            return NativeObject(m_Context.physicalDevice);
        case ObjectType.VK_Instance:
            return NativeObject(m_Context.instance);
        case ObjectType.Nvrhi_VK_Device:
            return NativeObject(this);
        default:
            return null;
        }
    }


	    // IDevice implementation

	    public HeapHandle createHeap(const HeapDesc& d)
    {
        VkMemoryRequirements memoryRequirements;
        memoryRequirements.alignment = 0;
        memoryRequirements.memoryTypeBits = ~0u; // just pick whatever fits the property flags
        memoryRequirements.size = d.capacity;

        VkMemoryPropertyFlags memoryPropertyFlags;
        switch(d.type)
        {
        case HeapType.DeviceLocal:
            memoryPropertyFlags = VkMemoryPropertyFlagBits.eDeviceLocal;
            break;
        case HeapType.Upload: 
            memoryPropertyFlags = VkMemoryPropertyFlagBits.eHostVisible;
            break;
        case HeapType.Readback: 
            memoryPropertyFlags = VkMemoryPropertyFlagBits.eHostVisible | VkMemoryPropertyFlagBits.eHostCached;
            break;
        default:
            utils.InvalidEnum();
            return null;
        }

        Heap heap = new Heap(m_Context, m_Allocator);
        heap.desc = d;
        heap.managed = true;

        readonly VkResult res = m_Allocator.allocateMemory(heap, memoryRequirements, memoryPropertyFlags);

        if (res != VkResult.eSuccess)
        {
            String message = scope $"""Failed to allocate memory for Heap {utils.DebugNameToString(d.debugName)}, VkResult = {resultToString(res)}""";

            m_Context.error(message);

            delete heap;
            return null;
        }

        if (!d.debugNameIsEmpty)
        {
            m_Context.nameVKObject(heap.memory, VkDebugReportObjectTypeEXT.eDeviceMemory, d.debugName.c_str());
        }

        return HeapHandle.Create(heap);
    }

	    public TextureHandle createTexture(TextureDesc desc)
    {
        Texture *texture = new Texture(m_Context, m_Allocator);
        Runtime.Assert(texture);
        fillTextureInfo(texture, desc);

        VkResult res = m_Context.device.createImage(&texture.imageInfo, m_Context.allocationCallbacks, &texture.image);
        ASSERT_VK_OK!(res);
        CHECK_VK_FAIL!(res);

        m_Context.nameVKObject(texture.image, VkDebugReportObjectTypeEXT.eImage, desc.debugName.c_str());

        if (!desc.isVirtual)
        {
            res = m_Allocator.allocateTextureMemory(texture);
            ASSERT_VK_OK!(res);
            CHECK_VK_FAIL!(res);

            m_Context.nameVKObject(texture.memory, VkDebugReportObjectTypeEXT.eDeviceMemory, desc.debugName.c_str());
        }

        return TextureHandle.Create(texture);
    }
	    public MemoryRequirements getTextureMemoryRequirements(ITexture _texture)
    {
        Texture texture = checked_cast<Texture, ITexture>(_texture);

        VkMemoryRequirements vulkanMemReq;
        m_Context.device.getImageMemoryRequirements(texture.image, &vulkanMemReq);

        MemoryRequirements memReq;
        memReq.alignment = vulkanMemReq.alignment;
        memReq.size = vulkanMemReq.size;
        return memReq;
    }
	    public bool bindTextureMemory(ITexture _texture, IHeap _heap, uint64 offset)
    {
        Texture texture = checked_cast<Texture, ITexture>(_texture);
        Heap heap = checked_cast<Heap>(_heap);

        if (texture.heap)
            return false;

        if (!texture.desc.isVirtual)
            return false;

        m_Context.device.bindImageMemory(texture.image, heap.memory, offset);

        texture.heap = heap;

        return true;
    }

	    public TextureHandle createHandleForNativeTexture(ObjectType objectType, NativeObject _texture, TextureDesc desc)
    {
        if (_texture.integer == 0)
            return null;

        if (objectType != ObjectType.VK_Image)
            return null;

        VkImage image(VkImage(_texture.integer));

        Texture *texture = new Texture(m_Context, m_Allocator);
        fillTextureInfo(texture, desc);

        texture.image = image;
        texture.managed = false;

        return TextureHandle.Create(texture);
    }

	    public StagingTextureHandle createStagingTexture(TextureDesc desc, CpuAccessMode cpuAccess)
    {
        Runtime.Assert(cpuAccess != CpuAccessMode.None);

        StagingTexture tex = new StagingTexture();
        tex.desc = desc;
        tex.populateSliceRegions();

        BufferDesc bufDesc;
        bufDesc.byteSize = uint32(tex.getBufferSize());
        Runtime.Assert(bufDesc.byteSize > 0);
        bufDesc.debugName = desc.debugName;
        bufDesc.cpuAccess = cpuAccess;

        BufferHandle internalBuffer = createBuffer(bufDesc);
        tex.buffer = checked_cast<Buffer, IBuffer>(internalBuffer.Get());

        if (!tex.buffer)
        {
            delete tex;
            return null;
        }

        return StagingTextureHandle.Create(tex);
    }

	    public void *mapStagingTexture(IStagingTexture _tex, TextureSlice slice, CpuAccessMode cpuAccess, int *outRowPitch)
    {
        Runtime.Assert(slice.x == 0);
        Runtime.Assert(slice.y == 0);
        Runtime.Assert(cpuAccess != CpuAccessMode.None);

        StagingTexture tex = checked_cast<StagingTexture>(_tex);

        var resolvedSlice = slice.resolve(tex.desc);

        var region = tex.getSliceRegion(resolvedSlice.mipLevel, resolvedSlice.arraySlice, resolvedSlice.z);

        Runtime.Assert((region.offset & 0x3) == 0); // per vulkan spec
        Runtime.Assert(region.size > 0);

        const FormatInfo& formatInfo = getFormatInfo(tex.desc.format);
        Runtime.Assert(outRowPitch);

        var wInBlocks = resolvedSlice.width / formatInfo.blockSize;

        *outRowPitch = wInBlocks * formatInfo.bytesPerBlock;

        return mapBuffer(tex.buffer, cpuAccess, region.offset, region.size);
    }

	    public void unmapStagingTexture(IStagingTexture _tex)
    {
        StagingTexture tex = checked_cast<StagingTexture>(_tex);

        unmapBuffer(tex.buffer);
    }

	    public BufferHandle createBuffer(BufferDesc desc)
    {
        // Check some basic constraints first - the validation layer is expected to handle them too

        if (desc.isVolatile && desc.maxVersions == 0)
            return null;

        if (desc.isVolatile && !desc.isConstantBuffer)
            return null;

        if (desc.byteSize == 0)
            return null;


        Buffer *buffer = new Buffer(m_Context, m_Allocator);
        buffer.desc = desc;

        VkBufferUsageFlags usageFlags = VkBufferUsageFlagBits.eTransferSrc |
                                          VkBufferUsageFlagBits.eTransferDst;

        if (desc.isVertexBuffer)
            usageFlags |= VkBufferUsageFlagBits.eVertexBuffer;
        
        if (desc.isIndexBuffer)
            usageFlags |= VkBufferUsageFlagBits.eIndexBuffer;
        
        if (desc.isDrawIndirectArgs)
            usageFlags |= VkBufferUsageFlagBits.eIndirectBuffer;
        
        if (desc.isConstantBuffer)
            usageFlags |= VkBufferUsageFlagBits.eUniformBuffer;

        if (desc.structStride != 0 || desc.canHaveUAVs || desc.canHaveRawViews)
            usageFlags |= VkBufferUsageFlagBits.eStorageBuffer;
        
        if (desc.canHaveTypedViews)
            usageFlags |= VkBufferUsageFlagBits.eUniformTexelBuffer;

        if (desc.canHaveTypedViews && desc.canHaveUAVs)
            usageFlags |= VkBufferUsageFlagBits.eStorageTexelBuffer;

        if (desc.isAccelStructBuildInput)
            usageFlags |= VkBufferUsageFlagBits.eAccelerationStructureBuildInputReadOnlyKHR;

        if (desc.isAccelStructStorage)
            usageFlags |= VkBufferUsageFlagBits.eAccelerationStructureStorageKHR;

        if (m_Context.extensions.KHR_buffer_device_address)
            usageFlags |= VkBufferUsageFlagBits.eShaderDeviceAddress;

        uint64 size = desc.byteSize;

        if (desc.isVolatile)
        {
            Runtime.Assert(!desc.isVirtual);

            uint64 alignment = m_Context.physicalDeviceProperties.limits.minUniformBufferOffsetAlignment;

            uint64 atomSize = m_Context.physicalDeviceProperties.limits.nonCoherentAtomSize;
            alignment = Math.Max(alignment, atomSize);

            Runtime.Assert((alignment & (alignment - 1)) == 0); // check if it's a power of 2
            
            size = (size + alignment - 1) & ~(alignment - 1);
            buffer.desc.byteSize = size;

            size *= desc.maxVersions;

            buffer.versionTracking.resize(desc.maxVersions);
            std::fill(buffer.versionTracking.begin(), buffer.versionTracking.end(), 0);

            buffer.desc.cpuAccess = CpuAccessMode.Write; // to get the right memory type allocated
        }
        else if (desc.byteSize < 65536)
        {
            // vulkan allows for <= 64kb buffer updates to be done inline via vkCmdUpdateBuffer,
            // but the data size must always be a multiple of 4
            // enlarge the buffer slightly to allow for this
            size += size % 4;
        }

        var bufferInfo = VkBufferCreateInfo()
            .setSize(size)
            .setUsage(usageFlags)
            .setSharingMode(VkSharingMode.eExclusive);

        VkResult res = m_Context.device.createBuffer(&bufferInfo, m_Context.allocationCallbacks, &buffer.buffer);
        CHECK_VK_FAIL!(res);;

        m_Context.nameVKObject(VkBuffer(buffer.buffer), VkDebugReportObjectTypeEXT.eBuffer, desc.debugName.c_str());

        if (!desc.isVirtual)
        {
            res = m_Allocator.allocateBufferMemory(buffer, (usageFlags & VkBufferUsageFlagBits.eShaderDeviceAddress) != VkBufferUsageFlags(0));
            CHECK_VK_FAIL!(res);

            m_Context.nameVKObject(buffer.memory, VkDebugReportObjectTypeEXT.eDeviceMemory, desc.debugName.c_str());

            if (desc.isVolatile)
            {
                buffer.mappedMemory = m_Context.device.mapMemory(buffer.memory, 0, size);
                Runtime.Assert(buffer.mappedMemory);
            }

            if (m_Context.extensions.KHR_buffer_device_address)
            {
                var addressInfo = VkBufferDeviceAddressInfo().setBuffer(buffer.buffer);

                buffer.deviceAddress = m_Context.device.getBufferAddress(addressInfo);
            }
        }

        return BufferHandle.Create(buffer);
    }

	    public void *mapBuffer(IBuffer _buffer, CpuAccessMode flags)
    {
        Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

        return mapBuffer(buffer, flags, 0, buffer.desc.byteSize);
    }

	    public void unmapBuffer(IBuffer _buffer)
    {
        Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

        m_Context.device.unmapMemory(buffer.memory);

        // TODO: there should be a barrier
        // buffer.barrier(cmd, VkPipelineStageFlagBits.eTransfer, VkAccessFlagBits.eTransferRead);
    }

	    public MemoryRequirements getBufferMemoryRequirements(IBuffer _buffer)
    {
        Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

        VkMemoryRequirements vulkanMemReq;
        m_Context.device.getBufferMemoryRequirements(buffer.buffer, &vulkanMemReq);

        MemoryRequirements memReq;
        memReq.alignment = vulkanMemReq.alignment;
        memReq.size = vulkanMemReq.size;
        return memReq;
    }

	    public bool bindBufferMemory(IBuffer _buffer, IHeap _heap, uint64 offset)
    {
        Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);
        Heap heap = checked_cast<Heap>(_heap);

        if (buffer.heap)
            return false;

        if (!buffer.desc.isVirtual)
            return false;
        
        m_Context.device.bindBufferMemory(buffer.buffer, heap.memory, offset);

        buffer.heap = heap;

        if (m_Context.extensions.KHR_buffer_device_address)
        {
            var addressInfo = VkBufferDeviceAddressInfo().setBuffer(buffer.buffer);

            buffer.deviceAddress = m_Context.device.getBufferAddress(addressInfo);
        }

        return true;
    }

	    public BufferHandle createHandleForNativeBuffer(ObjectType objectType, NativeObject _buffer, BufferDesc desc)
    {
        if (!_buffer.pointer)
            return null;

        if (objectType != ObjectType.VK_Buffer)
            return null;
        
        Buffer buffer = new Buffer(m_Context, m_Allocator);
        buffer.buffer = VkBuffer(_buffer.integer);
        buffer.desc = desc;
        buffer.managed = false;

        return BufferHandle.Create(buffer);
    }

	    public ShaderHandle createShader(const ShaderDesc& desc, const void *binary, const int binarySize)
    {
        Shader shader = new Shader(m_Context);

        shader.desc = desc;
        shader.stageFlagBits = convertShaderTypeToShaderStageFlagBits(desc.shaderType);

        var shaderInfo = VkShaderModuleCreateInfo()
            .setCodeSize(binarySize)
            .setPCode((const uint32 *)binary);

        readonly VkResult res = m_Context.device.createShaderModule(&shaderInfo, m_Context.allocationCallbacks, &shader.shaderModule);
        CHECK_VK_FAIL!(res);

        const String debugName = desc.debugName + ":" + desc.entryName;
        m_Context.nameVKObject(VkShaderModule(shader.shaderModule), VkDebugReportObjectTypeEXT.eShaderModule, debugName.c_str());

        return ShaderHandle.Create(shader);
    }

	    public ShaderHandle createShaderSpecialization(IShader _baseShader, const ShaderSpecialization* constants, const uint32 numConstants)
    {
        Shader baseShader = checked_cast<Shader, IShader>(_baseShader);
        Runtime.Assert(constants);
        Runtime.Assert(numConstants != 0);

        Shader newShader = new Shader(m_Context);

        // Hold a strong reference to the parent object
        newShader.baseShader = (baseShader.baseShader) ? baseShader.baseShader : baseShader;
        newShader.desc = baseShader.desc;
        newShader.shaderModule = baseShader.shaderModule;
        newShader.stageFlagBits = baseShader.stageFlagBits;
        newShader.specializationConstants.assign(constants, constants + numConstants);

        return ShaderHandle.Create(newShader);
    }

	    public ShaderLibraryHandle createShaderLibrary(const void* binary, const int binarySize)
    {
        ShaderLibrary library = new ShaderLibrary(m_Context);
        
        var shaderInfo = VkShaderModuleCreateInfo()
            .setCodeSize(binarySize)
            .setPCode((const uint32*)binary);

        readonly VkResult res = m_Context.device.createShaderModule(&shaderInfo, m_Context.allocationCallbacks, &library.shaderModule);
        CHECK_VK_FAIL!(res);

        return ShaderLibraryHandle.Create(library);
    }

	    public SamplerHandle createSampler(SamplerDesc desc)
    {
        Sampler sampler = new Sampler(m_Context);

        const bool anisotropyEnable = desc.maxAnisotropy > 1.0f;

        sampler.desc = desc;
        sampler.samplerInfo = VkSamplerCreateInfo()
                            .setMagFilter(desc.magFilter ? VkFilter.eLinear : VkFilter.eNearest)
                            .setMinFilter(desc.minFilter ? VkFilter.eLinear : VkFilter.eNearest)
                            .setMipmapMode(desc.mipFilter ? VkSamplerMipmapMode.eLinear : VkSamplerMipmapMode.eNearest)
                            .setAddressModeU(convertSamplerAddressMode(desc.addressU))
                            .setAddressModeV(convertSamplerAddressMode(desc.addressV))
                            .setAddressModeW(convertSamplerAddressMode(desc.addressW))
                            .setMipLodBias(desc.mipBias)
                            .setAnisotropyEnable(anisotropyEnable)
                            .setMaxAnisotropy(anisotropyEnable ? desc.maxAnisotropy : 1.f)
                            .setCompareEnable(desc.reductionType == SamplerReductionType.Comparison)
                            .setCompareOp(VkCompareOp.eLess)
                            .setMinLod(0.f)
                            .setMaxLod(float.MaxValue)
                            .setBorderColor(pickSamplerBorderColor(desc));

        VkSamplerReductionModeCreateInfo samplerReductionCreateInfo;
        if (desc.reductionType == SamplerReductionType.Minimum || desc.reductionType == SamplerReductionType.Maximum)
        {
            VkSamplerReductionModeEXT reductionMode =
                desc.reductionType == SamplerReductionType.Maximum ? VkSamplerReductionModeEXT.eMax : VkSamplerReductionModeEXT.eMin;
            samplerReductionCreateInfo.setReductionMode(reductionMode);

            sampler.samplerInfo.setPNext(&samplerReductionCreateInfo);
        }

        readonly VkResult res = m_Context.device.createSampler(&sampler.samplerInfo, m_Context.allocationCallbacks, &sampler.sampler);
        CHECK_VK_FAIL!(res);
        
        return SamplerHandle.Create(sampler);
    }

	    public InputLayoutHandle createInputLayout(const VertexAttributeDesc* attributeDesc, uint32 attributeCount, IShader vertexShader)
    {
        (void)vertexShader;

        InputLayout *layout = new InputLayout();

        int32 total_attribute_array_size = 0;

        // collect all buffer bindings
        Dictionary<uint32, VkVertexInputBindingDescription> bindingMap;
        for (uint32 i = 0; i < attributeCount; i++)
        {
            const VertexAttributeDesc& desc = attributeDesc[i];

            Runtime.Assert(desc.arraySize > 0);

            total_attribute_array_size += desc.arraySize;

            if (bindingMap.find(desc.bufferIndex) == bindingMap.end())
            {
                bindingMap[desc.bufferIndex] = VkVertexInputBindingDescription()
                    .setBinding(desc.bufferIndex)
                    .setStride(desc.elementStride)
                    .setInputRate(desc.isInstanced ? VkVertexInputRate::eInstance : VkVertexInputRate::eVertex);
            }
            else {
                Runtime.Assert(bindingMap[desc.bufferIndex].stride == desc.elementStride);
                Runtime.Assert(bindingMap[desc.bufferIndex].inputRate == (desc.isInstanced ? VkVertexInputRate::eInstance : VkVertexInputRate::eVertex));
            }
        }

        for (readonly ref var b in ref bindingMap)
        {
            layout.bindingDesc.push_back(b.second);
        }

        // build attribute descriptions
        layout.inputDesc.resize(attributeCount);
        layout.attributeDesc.resize(total_attribute_array_size);

        uint32 attributeLocation = 0;
        for (uint32 i = 0; i < attributeCount; i++)
        {
            const VertexAttributeDesc& in = attributeDesc[i];
            layout.inputDesc[i] = in;

            uint32 element_size_bytes = getFormatInfo(in.format).bytesPerBlock;

            uint32 bufferOffset = 0;

            for (uint32 slot = 0; slot < in.arraySize; ++slot)
            {
                var& outAttrib = layout.attributeDesc[attributeLocation];

                outAttrib.location = attributeLocation;
                outAttrib.binding = in.bufferIndex;
                outAttrib.format = nvrhi.vulkan.convertFormat(in.format);
                outAttrib.offset = bufferOffset + in.offset;
                bufferOffset += element_size_bytes;

                ++attributeLocation;
            }
        }

        return InputLayoutHandle.Create(layout);
    }

	    // event queries
	    public EventQueryHandle createEventQuery()
    {
        EventQuery *query = new EventQuery();
        return EventQueryHandle.Create(query);
    }

	    public void setEventQuery(IEventQuery _query, CommandQueue queue)
    {
        EventQuery query = checked_cast<EventQuery, IEventQuery>(_query);

        Runtime.Assert(query.commandListID == 0);

        query.queue = queue;
        query.commandListID = m_Queues[uint32(queue)].getLastSubmittedID();
    }

	    public bool pollEventQuery(IEventQuery _query)
    {
        EventQuery query = checked_cast<EventQuery, IEventQuery>(_query);
        
        var& queue = *m_Queues[uint32(query.queue)];

        return queue.pollCommandList(query.commandListID);
    }

	    public void waitEventQuery(IEventQuery _query)
    {
        EventQuery query = checked_cast<EventQuery, IEventQuery>(_query);

        if (query.commandListID == 0)
            return;

        var& queue = *m_Queues[uint32(query.queue)];

        bool success = queue.waitCommandList(query.commandListID, ~0uL);
        Runtime.Assert(success);
        (void)success;
    }

	    public void resetEventQuery(IEventQuery _query)
    {
        EventQuery query = checked_cast<EventQuery, IEventQuery>(_query);

        query.commandListID = 0;
    }

	    // timer queries
	    public TimerQueryHandle createTimerQuery(void)
    {
        if (!m_TimerQueryPool)
        {
            m_Mutex.Enter(); defer m_Mutex.Exit();

            if (!m_TimerQueryPool)
            {
                // set up the timer query pool on first use
                var poolInfo = VkQueryPoolCreateInfo()
                    .setQueryType(VkQueryType.eTimestamp)
                    .setQueryCount(uint32(m_TimerQueryAllocator.getCapacity()) * 2); // use 2 Vulkan queries per 1 TimerQuery

                readonly VkResult res = m_Context.device.createQueryPool(&poolInfo, m_Context.allocationCallbacks, &m_TimerQueryPool);
                CHECK_VK_FAIL!(res);
            }
        }

        int32 queryIndex = m_TimerQueryAllocator.allocate();

        if (queryIndex < 0)
        {
            m_Context.error("Insufficient query pool space, increase Device::numTimerQueries");
            return null;
        }

        TimerQuery query = new TimerQuery(m_TimerQueryAllocator);
        query.beginQueryIndex = queryIndex * 2;
        query.endQueryIndex = queryIndex * 2 + 1;

        return TimerQueryHandle.Create(query);
    }

	    public bool pollTimerQuery(ITimerQuery _query)
    {
        TimerQuery query = checked_cast<TimerQuery, ITimerQuery>(_query);

        Runtime.Assert(query.started);

        if (query.resolved)
        {
            return true;
        }

        uint32 timestamps[2] = { 0, 0 };

        VkResult res;
        res = m_Context.device.getQueryPoolResults(m_TimerQueryPool,
                                                 query.beginQueryIndex, 2,
                                                 sizeof(timestamps), timestamps,
                                                 sizeof(timestamps[0]), VkQueryResultFlags());
        Runtime.Assert(res == VkResult.eSuccess || res == VkResult.VK_NOT_READY);

        if (res == VkResult.VK_NOT_READY)
        {
            return false;
        }

        readonly var timestampPeriod = m_Context.physicalDeviceProperties.limits.timestampPeriod; // in nanoseconds
        readonly float scale = 1e-9f * timestampPeriod;

        query.time = float(timestamps[1] - timestamps[0]) * scale;
        query.resolved = true;
        return true;
    }

	    public float getTimerQueryTime(ITimerQuery _query)
    {
        TimerQuery query = checked_cast<TimerQuery, ITimerQuery>(_query);

        if (!query.started)
            return 0.f;

        if (!query.resolved)
        {
            while(!pollTimerQuery(query))
                ;
        }

        query.started = false;

        Runtime.Assert(query.resolved);
        return query.time;
    }

	    public void resetTimerQuery(ITimerQuery _query)
    {
        TimerQuery query = checked_cast<TimerQuery, ITimerQuery>(_query);

        query.started = false;
        query.resolved = false;
        query.time = 0.f;
    }

	    public GraphicsAPI getGraphicsAPI()
    {
        return GraphicsAPI::VULKAN;
    }

	    public FramebufferHandle createFramebuffer(const FramebufferDesc& desc)
    {
        Framebuffer *fb = new Framebuffer(m_Context);
        fb.desc = desc;
        fb.framebufferInfo = FramebufferInfo(desc);

        attachment_vector<VkAttachmentDescription2> attachmentDescs(desc.colorAttachments.size());
        attachment_vector<VkAttachmentReference2> colorAttachmentRefs(desc.colorAttachments.size());
        VkAttachmentReference2 depthAttachmentRef;

        StaticVector<VkImageView, const c_MaxRenderTargets + 1> attachmentViews;
        attachmentViews.resize(desc.colorAttachments.size());

        uint32 numArraySlices = 0;

        for(uint32 i = 0; i < desc.colorAttachments.size(); i++)
        {
            readonly ref var rt = ref desc.colorAttachments[i];
            Texture t = checked_cast<Texture, ITexture>(rt.texture);

            Runtime.Assert(fb.framebufferInfo.width == t.desc.width >> rt.subresources.baseMipLevel);
            Runtime.Assert(fb.framebufferInfo.height == t.desc.height >> rt.subresources.baseMipLevel);

            const VkFormat attachmentFormat = (rt.format == Format.UNKNOWN ? t.imageInfo.format : convertFormat(rt.format));

            attachmentDescs[i] = VkAttachmentDescription2()
                                        .setFormat(attachmentFormat)
                                        .setSamples(t.imageInfo.samples)
                                        .setLoadOp(VkAttachmentLoadOp.eLoad)
                                        .setStoreOp(VkAttachmentStoreOp.eStore)
                                        .setInitialLayout(VkImageLayout.eColorAttachmentOptimal)
                                        .setFinalLayout(VkImageLayout.eColorAttachmentOptimal);

            colorAttachmentRefs[i] = VkAttachmentReference2()
                                        .setAttachment(i)
                                        .setLayout(VkImageLayout.eColorAttachmentOptimal);

            TextureSubresourceSet subresources = rt.subresources.resolve(t.desc, true);

            TextureDimension dimension = getDimensionForFramebuffer(t.desc.dimension, subresources.numArraySlices > 1);

            readonly ref var view = ref t.getSubresourceView(subresources, dimension);
            attachmentViews[i] = view.view;

            fb.resources.push_back(rt.texture);

            if (numArraySlices)
                Runtime.Assert(numArraySlices == subresources.numArraySlices);
            else
                numArraySlices = subresources.numArraySlices;
        }

        // add depth/stencil attachment if present
        if (desc.depthAttachment.valid())
        {
            readonly ref var att = ref desc.depthAttachment;

            Texture texture = checked_cast<Texture, ITexture>(att.texture);

            Runtime.Assert(fb.framebufferInfo.width == texture.desc.width >> att.subresources.baseMipLevel);
            Runtime.Assert(fb.framebufferInfo.height == texture.desc.height >> att.subresources.baseMipLevel);

            VkImageLayout depthLayout = VkImageLayout.eDepthStencilAttachmentOptimal;
            if (desc.depthAttachment.isReadOnly)
            {
                depthLayout = VkImageLayout.eDepthStencilReadOnlyOptimal;
            }

            attachmentDescs.push_back(VkAttachmentDescription2()
                                        .setFormat(texture.imageInfo.format)
                                        .setSamples(texture.imageInfo.samples)
                                        .setLoadOp(VkAttachmentLoadOp.eLoad)
                                        .setStoreOp(VkAttachmentStoreOp.eStore)
                                        .setInitialLayout(depthLayout)
                                        .setFinalLayout(depthLayout));

            depthAttachmentRef = VkAttachmentReference2()
                                    .setAttachment(uint32(attachmentDescs.size()) - 1)
                                    .setLayout(depthLayout);

            TextureSubresourceSet subresources = att.subresources.resolve(texture.desc, true);

            TextureDimension dimension = getDimensionForFramebuffer(texture.desc.dimension, subresources.numArraySlices > 1);

            readonly ref var view = ref texture.getSubresourceView(subresources, dimension);
            attachmentViews.push_back(view.view);

            fb.resources.push_back(att.texture);

            if (numArraySlices)
                Runtime.Assert(numArraySlices == subresources.numArraySlices);
            else
                numArraySlices = subresources.numArraySlices;
        }

        var subpass = VkSubpassDescription2()
            .setPipelineBindPoint(VkPipelineBindPoint.eGraphics)
            .setColorAttachmentCount(uint32(desc.colorAttachments.size()))
            .setPColorAttachments(colorAttachmentRefs.Ptr)
            .setPDepthStencilAttachment(desc.depthAttachment.valid() ? &depthAttachmentRef : null);

        // add VRS attachment
        // declare the structures here to avoid using pointers to out-of-scope objects in renderPassInfo further
        VkAttachmentReference2 vrsAttachmentRef;
        VkFragmentShadingRateAttachmentInfoKHR shadingRateAttachmentInfo;

        if (desc.shadingRateAttachment.valid())
        {
            readonly ref var vrsAttachment = ref desc.shadingRateAttachment;
            Texture vrsTexture = checked_cast<Texture, ITexture>(vrsAttachment.texture);
            Runtime.Assert(vrsTexture.imageInfo.format == VkFormat.eR8Uint);
            Runtime.Assert(vrsTexture.imageInfo.samples == VkSampleCountFlagBits.e1);
            var vrsAttachmentDesc = VkAttachmentDescription2()
                .setFormat(VkFormat.eR8Uint)
                .setSamples(VkSampleCountFlagBits.e1)
                .setLoadOp(VkAttachmentLoadOp.eLoad)
                .setStoreOp(VkAttachmentStoreOp.eStore)
                .setInitialLayout(VkImageLayout.eFragmentShadingRateAttachmentOptimalKHR)
                .setFinalLayout(VkImageLayout.eFragmentShadingRateAttachmentOptimalKHR);

            attachmentDescs.push_back(vrsAttachmentDesc);

            TextureSubresourceSet subresources = vrsAttachment.subresources.resolve(vrsTexture.desc, true);
            TextureDimension dimension = getDimensionForFramebuffer(vrsTexture.desc.dimension, subresources.numArraySlices > 1);

            readonly ref var view = ref vrsTexture.getSubresourceView(subresources, dimension);
            attachmentViews.push_back(view.view);

            fb.resources.push_back(vrsAttachment.texture);

            if (numArraySlices)
                Runtime.Assert(numArraySlices == subresources.numArraySlices);
            else
                numArraySlices = subresources.numArraySlices;

            var rateProps = VkPhysicalDeviceFragmentShadingRatePropertiesKHR();
            var props = VkPhysicalDeviceProperties2();
            props.pNext = &rateProps;
            m_Context.physicalDevice.getProperties2(&props);

            vrsAttachmentRef = VkAttachmentReference2()
                .setAttachment(uint32(attachmentDescs.size()) - 1)
                .setLayout(VkImageLayout.eFragmentShadingRateAttachmentOptimalKHR);

            shadingRateAttachmentInfo = VkFragmentShadingRateAttachmentInfoKHR()
                .setPFragmentShadingRateAttachment(&vrsAttachmentRef)
                .setShadingRateAttachmentTexelSize(rateProps.minFragmentShadingRateAttachmentTexelSize);

            subpass.setPNext(&shadingRateAttachmentInfo);
        }

        var renderPassInfo = VkRenderPassCreateInfo2()
                    .setAttachmentCount(uint32(attachmentDescs.size()))
                    .setPAttachments(attachmentDescs.Ptr)
                    .setSubpassCount(1)
                    .setPSubpasses(&subpass);

        VkResult res = m_Context.device.createRenderPass2(&renderPassInfo,
                                                           m_Context.allocationCallbacks,
                                                           &fb.renderPass);
        CHECK_VK_FAIL!(res);
        
        // set up the framebuffer object
        var framebufferInfo = VkFramebufferCreateInfo()
                                .setRenderPass(fb.renderPass)
                                .setAttachmentCount(uint32(attachmentViews.size()))
                                .setPAttachments(attachmentViews.Ptr)
                                .setWidth(fb.framebufferInfo.width)
                                .setHeight(fb.framebufferInfo.height)
                                .setLayers(numArraySlices);

        res = m_Context.device.createFramebuffer(&framebufferInfo, m_Context.allocationCallbacks,
                                               &fb.framebuffer);
        CHECK_VK_FAIL!(res);
        
        return FramebufferHandle.Create(fb);
    }

	    public GraphicsPipelineHandle createGraphicsPipeline(const GraphicsPipelineDesc& desc, IFramebuffer _fb)
    {
        if (desc.renderState.singlePassStereo.enabled)
        {
            m_Context.error("Single-pass stereo is not supported by the Vulkan backend");
            return null;
        }

        VkResult res;

        Framebuffer fb = checked_cast<Framebuffer>(_fb);
        
        InputLayout inputLayout = checked_cast<InputLayout>(desc.inputLayout.Get());

        GraphicsPipeline *pso = new GraphicsPipeline(m_Context);
        pso.desc = desc;
        pso.framebufferInfo = fb.framebufferInfo;
        
        for (const BindingLayoutHandle& _layout : desc.bindingLayouts)
        {
            BindingLayout layout = checked_cast<BindingLayout>(_layout.Get());
            pso.pipelineBindingLayouts.push_back(layout);
        }

        Shader VS = checked_cast<Shader, IShader>(desc.VS.Get());
        Shader HS = checked_cast<Shader, IShader>(desc.HS.Get());
        Shader DS = checked_cast<Shader, IShader>(desc.DS.Get());
        Shader GS = checked_cast<Shader, IShader>(desc.GS.Get());
        Shader PS = checked_cast<Shader, IShader>(desc.PS.Get());

        int numShaders = 0;
        int numShadersWithSpecializations = 0;
        int numSpecializationConstants = 0;

        // Count the spec constants for all stages
        countSpecializationConstants(VS, numShaders, numShadersWithSpecializations, numSpecializationConstants);
        countSpecializationConstants(HS, numShaders, numShadersWithSpecializations, numSpecializationConstants);
        countSpecializationConstants(DS, numShaders, numShadersWithSpecializations, numSpecializationConstants);
        countSpecializationConstants(GS, numShaders, numShadersWithSpecializations, numSpecializationConstants);
        countSpecializationConstants(PS, numShaders, numShadersWithSpecializations, numSpecializationConstants);

        List<VkPipelineShaderStageCreateInfo> shaderStages;
        List<VkSpecializationInfo> specInfos;
        List<VkSpecializationMapEntry> specMapEntries;
        List<uint32> specData;

        // Allocate buffers for specialization constants and related structures
        // so that shaderStageCreateInfo(...) can directly use pointers inside the vectors
        // because the vectors won't reallocate their buffers
        shaderStages.reserve(numShaders);
        specInfos.reserve(numShadersWithSpecializations);
        specMapEntries.reserve(numSpecializationConstants);
        specData.reserve(numSpecializationConstants);

        // Set up shader stages
        if (desc.VS)
        {
            shaderStages.push_back(makeShaderStageCreateInfo(VS, 
                specInfos, specMapEntries, specData));
            pso.shaderMask = pso.shaderMask | ShaderType.Vertex;
        }

        if (desc.HS)
        {
            shaderStages.push_back(makeShaderStageCreateInfo(HS, 
                specInfos, specMapEntries, specData));
            pso.shaderMask = pso.shaderMask | ShaderType.Hull;
        }

        if (desc.DS)
        {
            shaderStages.push_back(makeShaderStageCreateInfo(DS, 
                specInfos, specMapEntries, specData));
            pso.shaderMask = pso.shaderMask | ShaderType.Domain;
        }

        if (desc.GS)
        {
            shaderStages.push_back(makeShaderStageCreateInfo(GS, 
                specInfos, specMapEntries, specData));
            pso.shaderMask = pso.shaderMask | ShaderType.Geometry;
        }

        if (desc.PS)
        {
            shaderStages.push_back(makeShaderStageCreateInfo(PS, 
                specInfos, specMapEntries, specData));
            pso.shaderMask = pso.shaderMask | ShaderType.Pixel;
        }

        // set up vertex input state
        var vertexInput = VkPipelineVertexInputStateCreateInfo();
        if (inputLayout)
        {
            vertexInput.setVertexBindingDescriptionCount(uint32(inputLayout.bindingDesc.size()))
                       .setPVertexBindingDescriptions(inputLayout.bindingDesc.Ptr)
                       .setVertexAttributeDescriptionCount(uint32(inputLayout.attributeDesc.size()))
                       .setPVertexAttributeDescriptions(inputLayout.attributeDesc.Ptr);
        }

        var inputAssembly = VkPipelineInputAssemblyStateCreateInfo()
                                .setTopology(convertPrimitiveTopology(desc.primType));

        // fixed function state
        readonly ref var rasterState = ref desc.renderState.rasterState;
        readonly ref var depthStencilState = ref desc.renderState.depthStencilState;
        readonly ref var blendState = ref desc.renderState.blendState;

        var viewportState = VkPipelineViewportStateCreateInfo()
            .setViewportCount(1)
            .setScissorCount(1);

        var rasterizer = VkPipelineRasterizationStateCreateInfo()
                            // .setDepthClampEnable(??)
                            // .setRasterizerDiscardEnable(??)
                            .setPolygonMode(convertFillMode(rasterState.fillMode))
                            .setCullMode(convertCullMode(rasterState.cullMode))
                            .setFrontFace(rasterState.frontCounterClockwise ?
                                            VkFrontFace::eCounterClockwise : VkFrontFace::eClockwise)
                            .setDepthBiasEnable(rasterState.depthBias ? true : false)
                            .setDepthBiasConstantFactor(float(rasterState.depthBias))
                            .setDepthBiasClamp(rasterState.depthBiasClamp)
                            .setDepthBiasSlopeFactor(rasterState.slopeScaledDepthBias)
                            .setLineWidth(1.0f);
        
        var multisample = VkPipelineMultisampleStateCreateInfo()
                            .setRasterizationSamples(VkSampleCountFlagBits(fb.framebufferInfo.sampleCount))
                            .setAlphaToCoverageEnable(blendState.alphaToCoverageEnable);

        var depthStencil = VkPipelineDepthStencilStateCreateInfo()
                                .setDepthTestEnable(depthStencilState.depthTestEnable)
                                .setDepthWriteEnable(depthStencilState.depthWriteEnable)
                                .setDepthCompareOp(convertCompareOp(depthStencilState.depthFunc))
                                .setStencilTestEnable(depthStencilState.stencilEnable)
                                .setFront(convertStencilState(depthStencilState, depthStencilState.frontFaceStencil))
                                .setBack(convertStencilState(depthStencilState, depthStencilState.backFaceStencil));

        // VRS state
        std::array<VkFragmentShadingRateCombinerOpKHR, 2> combiners = { convertShadingRateCombiner(desc.shadingRateState.pipelinePrimitiveCombiner), convertShadingRateCombiner(desc.shadingRateState.imageCombiner) };
        var shadingRateState = VkPipelineFragmentShadingRateStateCreateInfoKHR()
            .setCombinerOps(combiners)
            .setFragmentSize(convertFragmentShadingRate(desc.shadingRateState.shadingRate));

        BindingVector<VkDescriptorSetLayout> descriptorSetLayouts;
        uint32 pushConstantSize = 0;
        for (const BindingLayoutHandle& _layout : desc.bindingLayouts)
        {
            BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(_layout.Get());
            descriptorSetLayouts.push_back(layout.descriptorSetLayout);

            if (!layout.isBindless)
            {
                for (const BindingLayoutItem& item : layout.desc.bindings)
                {
                    if (item.type == ResourceType.PushConstants)
                    {
                        pushConstantSize = item.size;
                        // assume there's only one push constant item in all layouts -- the validation layer makes sure of that
                        break;
                    }
                }
            }
        }

        var pushConstantRange = VkPushConstantRange()
            .setOffset(0)
            .setSize(pushConstantSize)
            .setStageFlags(convertShaderTypeToShaderStageFlagBits(pso.shaderMask));

        var pipelineLayoutInfo = VkPipelineLayoutCreateInfo()
                                    .setSetLayoutCount(uint32(descriptorSetLayouts.size()))
                                    .setPSetLayouts(descriptorSetLayouts.Ptr)
                                    .setPushConstantRangeCount(pushConstantSize ? 1 : 0)
                                    .setPPushConstantRanges(&pushConstantRange);

        res = m_Context.device.createPipelineLayout(&pipelineLayoutInfo,
                                                  m_Context.allocationCallbacks,
                                                  &pso.pipelineLayout);
        CHECK_VK_FAIL!(res);

        attachment_vector<VkPipelineColorBlendAttachmentState> colorBlendAttachments(fb.desc.colorAttachments.size());

        for(uint32 i = 0; i < uint32(fb.desc.colorAttachments.size()); i++)
        {
            colorBlendAttachments[i] = convertBlendState(blendState.targets[i]);
        }

        var colorBlend = VkPipelineColorBlendStateCreateInfo()
                            .setAttachmentCount(uint32(colorBlendAttachments.size()))
                            .setPAttachments(colorBlendAttachments.Ptr);

        pso.usesBlendConstants = blendState.usesConstantColor(uint32(fb.desc.colorAttachments.size()));

        VkDynamicState[4] dynamicStates = .(
            VkDynamicState.eViewport,
            VkDynamicState.eScissor,
            VkDynamicState.eBlendConstants,
            VkDynamicState.eFragmentShadingRateKHR
        );

        var dynamicStateInfo = VkPipelineDynamicStateCreateInfo()
            .setDynamicStateCount(pso.usesBlendConstants ? 3 : 2)
            .setPDynamicStates(dynamicStates);

        var pipelineInfo = VkGraphicsPipelineCreateInfo()
            .setStageCount(uint32(shaderStages.size()))
            .setPStages(shaderStages.Ptr)
            .setPVertexInputState(&vertexInput)
            .setPInputAssemblyState(&inputAssembly)
            .setPViewportState(&viewportState)
            .setPRasterizationState(&rasterizer)
            .setPMultisampleState(&multisample)
            .setPDepthStencilState(&depthStencil)
            .setPColorBlendState(&colorBlend)
            .setPDynamicState(&dynamicStateInfo)
            .setLayout(pso.pipelineLayout)
            .setRenderPass(fb.renderPass)
            .setSubpass(0)
            .setBasePipelineHandle(null)
            .setBasePipelineIndex(-1)
            .setPTessellationState(null)
            .setPNext(&shadingRateState);

        var tessellationState = VkPipelineTessellationStateCreateInfo();

        if (desc.primType == PrimitiveType.PatchList)
        {
            tessellationState.setPatchControlPoints(desc.patchControlPoints);
            pipelineInfo.setPTessellationState(&tessellationState);
        }

        res = m_Context.device.createGraphicsPipelines(m_Context.pipelineCache,
                                                     1, &pipelineInfo,
                                                     m_Context.allocationCallbacks,
                                                     &pso.pipeline);
        ASSERT_VK_OK!(res); // for debugging
        CHECK_VK_FAIL!(res);;
        
        return GraphicsPipelineHandle.Create(pso);
    }

	    public ComputePipelineHandle createComputePipeline(const ComputePipelineDesc& desc)
    {
        VkResult res;

        Runtime.Assert(desc.CS);
        
        ComputePipeline *pso = new ComputePipeline(m_Context);
        pso.desc = desc;

        for (const BindingLayoutHandle& _layout : desc.bindingLayouts)
        {
            BindingLayout layout = checked_cast<BindingLayout>(_layout.Get());
            pso.pipelineBindingLayouts.push_back(layout);
        }

        BindingVector<VkDescriptorSetLayout> descriptorSetLayouts;
        uint32 pushConstantSize = 0;
        for (const BindingLayoutHandle& _layout : desc.bindingLayouts)
        {
            BindingLayout layout = checked_cast<BindingLayout>(_layout.Get());
            descriptorSetLayouts.push_back(layout.descriptorSetLayout);

            if (!layout.isBindless)
            {
                for (const BindingLayoutItem& item : layout.desc.bindings)
                {
                    if (item.type == ResourceType.PushConstants)
                    {
                        pushConstantSize = item.size;
                        // assume there's only one push constant item in all layouts -- the validation layer makes sure of that
                        break;
                    }
                }
            }
        }

        var pushConstantRange = VkPushConstantRange()
            .setOffset(0)
            .setSize(pushConstantSize)
            .setStageFlags(VkShaderStageFlagBits.eCompute);

        var pipelineLayoutInfo = VkPipelineLayoutCreateInfo()
            .setSetLayoutCount(uint32(descriptorSetLayouts.size()))
            .setPSetLayouts(descriptorSetLayouts.Ptr)
            .setPushConstantRangeCount(0)
            .setPushConstantRangeCount(pushConstantSize ? 1 : 0)
            .setPPushConstantRanges(&pushConstantRange);

        res = m_Context.device.createPipelineLayout(&pipelineLayoutInfo,
                                                  m_Context.allocationCallbacks,
                                                  &pso.pipelineLayout);

        CHECK_VK_FAIL!(res);

        Shader CS = checked_cast<Shader, IShader>(desc.CS.Get());

        // See createGraphicsPipeline() for a more expanded implementation
        // of shader specializations with multiple shaders in the pipeline

        int numShaders = 0;
        int numShadersWithSpecializations = 0;
        int numSpecializationConstants = 0;

        countSpecializationConstants(CS, numShaders, numShadersWithSpecializations, numSpecializationConstants);

        Runtime.Assert(numShaders == 1);

        List<VkSpecializationInfo> specInfos;
        List<VkSpecializationMapEntry> specMapEntries;
        List<uint32> specData;

        specInfos.reserve(numShadersWithSpecializations);
        specMapEntries.reserve(numSpecializationConstants);
        specData.reserve(numSpecializationConstants);

        var shaderStageInfo = makeShaderStageCreateInfo(CS, 
            specInfos, specMapEntries, specData);
        
        var pipelineInfo = VkComputePipelineCreateInfo()
                                .setStage(shaderStageInfo)
                                .setLayout(pso.pipelineLayout);

        res = m_Context.device.createComputePipelines(m_Context.pipelineCache,
                                                    1, &pipelineInfo,
                                                    m_Context.allocationCallbacks,
                                                    &pso.pipeline);

        CHECK_VK_FAIL!(res);

        return ComputePipelineHandle.Create(pso);
    }

	    public MeshletPipelineHandle createMeshletPipeline(const MeshletPipelineDesc& desc, IFramebuffer _fb)
    {
        if (!m_Context.extensions.NV_mesh_shader)
            utils.NotSupported();

        VkResult res;

        Framebuffer fb = checked_cast<Framebuffer>(_fb);
        
        MeshletPipeline *pso = new MeshletPipeline(m_Context);
        pso.desc = desc;
        pso.framebufferInfo = fb.framebufferInfo;
        
        for (const BindingLayoutHandle& _layout : desc.bindingLayouts)
        {
            BindingLayout layout = checked_cast<BindingLayout>(_layout.Get());
            pso.pipelineBindingLayouts.push_back(layout);
        }

        Shader AS = checked_cast<Shader, IShader>(desc.AS.Get());
        Shader MS = checked_cast<Shader, IShader>(desc.MS.Get());
        Shader PS = checked_cast<Shader, IShader>(desc.PS.Get());

        int numShaders = 0;
        int numShadersWithSpecializations = 0;
        int numSpecializationConstants = 0;

        // Count the spec constants for all stages
        countSpecializationConstants(AS, numShaders, numShadersWithSpecializations, numSpecializationConstants);
        countSpecializationConstants(MS, numShaders, numShadersWithSpecializations, numSpecializationConstants);
        countSpecializationConstants(PS, numShaders, numShadersWithSpecializations, numSpecializationConstants);

        List<VkPipelineShaderStageCreateInfo> shaderStages;
        List<VkSpecializationInfo> specInfos;
        List<VkSpecializationMapEntry> specMapEntries;
        List<uint32> specData;

        // Allocate buffers for specialization constants and related structures
        // so that shaderStageCreateInfo(...) can directly use pointers inside the vectors
        // because the vectors won't reallocate their buffers
        shaderStages.reserve(numShaders);
        specInfos.reserve(numShadersWithSpecializations);
        specMapEntries.reserve(numSpecializationConstants);
        specData.reserve(numSpecializationConstants);

        // Set up shader stages
        if (desc.AS)
        {
            shaderStages.push_back(makeShaderStageCreateInfo(AS, 
                specInfos, specMapEntries, specData));
            pso.shaderMask = pso.shaderMask | ShaderType.Vertex;
        }

        if (desc.MS)
        {
            shaderStages.push_back(makeShaderStageCreateInfo(MS, 
                specInfos, specMapEntries, specData));
            pso.shaderMask = pso.shaderMask | ShaderType.Hull;
        }
        
        if (desc.PS)
        {
            shaderStages.push_back(makeShaderStageCreateInfo(PS, 
                specInfos, specMapEntries, specData));
            pso.shaderMask = pso.shaderMask | ShaderType.Pixel;
        }

        var inputAssembly = VkPipelineInputAssemblyStateCreateInfo()
            .setTopology(convertPrimitiveTopology(desc.primType));
        
        // fixed function state
        readonly ref var rasterState = ref desc.renderState.rasterState;
        readonly ref var depthStencilState = ref desc.renderState.depthStencilState;
        readonly ref var blendState = ref desc.renderState.blendState;

        var viewportState = VkPipelineViewportStateCreateInfo()
            .setViewportCount(1)
            .setScissorCount(1);

        var rasterizer = VkPipelineRasterizationStateCreateInfo()
                            // .setDepthClampEnable(??)
                            // .setRasterizerDiscardEnable(??)
                            .setPolygonMode(convertFillMode(rasterState.fillMode))
                            .setCullMode(convertCullMode(rasterState.cullMode))
                            .setFrontFace(rasterState.frontCounterClockwise ?
                                            VkFrontFace::eCounterClockwise : VkFrontFace::eClockwise)
                            .setDepthBiasEnable(rasterState.depthBias ? true : false)
                            .setDepthBiasConstantFactor(float(rasterState.depthBias))
                            .setDepthBiasClamp(rasterState.depthBiasClamp)
                            .setDepthBiasSlopeFactor(rasterState.slopeScaledDepthBias)
                            .setLineWidth(1.0f);
        
        var multisample = VkPipelineMultisampleStateCreateInfo()
                            .setRasterizationSamples(VkSampleCountFlagBits(fb.framebufferInfo.sampleCount))
                            .setAlphaToCoverageEnable(blendState.alphaToCoverageEnable);

        var depthStencil = VkPipelineDepthStencilStateCreateInfo()
                                .setDepthTestEnable(depthStencilState.depthTestEnable)
                                .setDepthWriteEnable(depthStencilState.depthWriteEnable)
                                .setDepthCompareOp(convertCompareOp(depthStencilState.depthFunc))
                                .setStencilTestEnable(depthStencilState.stencilEnable)
                                .setFront(convertStencilState(depthStencilState, depthStencilState.frontFaceStencil))
                                .setBack(convertStencilState(depthStencilState, depthStencilState.backFaceStencil));

        BindingVector<VkDescriptorSetLayout> descriptorSetLayouts;
        uint32 pushConstantSize = 0;
        for (const BindingLayoutHandle& _layout : desc.bindingLayouts)
        {
            BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(_layout.Get());
            descriptorSetLayouts.push_back(layout.descriptorSetLayout);

            if (!layout.isBindless)
            {
                for (const BindingLayoutItem& item : layout.desc.bindings)
                {
                    if (item.type == ResourceType.PushConstants)
                    {
                        pushConstantSize = item.size;
                        // assume there's only one push constant item in all layouts -- the validation layer makes sure of that
                        break;
                    }
                }
            }
        }

        var pushConstantRange = VkPushConstantRange()
            .setOffset(0)
            .setSize(pushConstantSize)
            .setStageFlags(convertShaderTypeToShaderStageFlagBits(pso.shaderMask));

        var pipelineLayoutInfo = VkPipelineLayoutCreateInfo()
                                    .setSetLayoutCount(uint32(descriptorSetLayouts.size()))
                                    .setPSetLayouts(descriptorSetLayouts.Ptr)
                                    .setPushConstantRangeCount(pushConstantSize ? 1 : 0)
                                    .setPPushConstantRanges(&pushConstantRange);

        res = m_Context.device.createPipelineLayout(&pipelineLayoutInfo,
                                                  m_Context.allocationCallbacks,
                                                  &pso.pipelineLayout);
        CHECK_VK_FAIL!(res);

        attachment_vector<VkPipelineColorBlendAttachmentState> colorBlendAttachments(fb.desc.colorAttachments.size());

        for(uint32 i = 0; i < uint32(fb.desc.colorAttachments.size()); i++)
        {
            colorBlendAttachments[i] = convertBlendState(blendState.targets[i]);
        }

        var colorBlend = VkPipelineColorBlendStateCreateInfo()
                            .setAttachmentCount(uint32(colorBlendAttachments.size()))
                            .setPAttachments(colorBlendAttachments.Ptr);

        pso.usesBlendConstants = blendState.usesConstantColor(uint32(fb.desc.colorAttachments.size()));
        
        VkDynamicState dynamicStates[3] = {
            VkDynamicState.eViewport,
            VkDynamicState.eScissor,
            VkDynamicState.eBlendConstants
        };

        var dynamicStateInfo = VkPipelineDynamicStateCreateInfo()
            .setDynamicStateCount(pso.usesBlendConstants ? 3 : 2)
            .setPDynamicStates(dynamicStates);

        var pipelineInfo = VkGraphicsPipelineCreateInfo()
            .setStageCount(uint32(shaderStages.size()))
            .setPStages(shaderStages.Ptr)
            //.setPVertexInputState(&vertexInput)
            .setPInputAssemblyState(&inputAssembly)
            .setPViewportState(&viewportState)
            .setPRasterizationState(&rasterizer)
            .setPMultisampleState(&multisample)
            .setPDepthStencilState(&depthStencil)
            .setPColorBlendState(&colorBlend)
            .setPDynamicState(&dynamicStateInfo)
            .setLayout(pso.pipelineLayout)
            .setRenderPass(fb.renderPass)
            .setSubpass(0)
            .setBasePipelineHandle(null)
            .setBasePipelineIndex(-1);

        res = m_Context.device.createGraphicsPipelines(m_Context.pipelineCache,
                                                     1, &pipelineInfo,
                                                     m_Context.allocationCallbacks,
                                                     &pso.pipeline);
        ASSERT_VK_OK!(res); // for debugging
        CHECK_VK_FAIL!(res);
        
        return MeshletPipelineHandle.Create(pso);
    }

	    public nvrhi.rt.PipelineHandle createRayTracingPipeline(const nvrhi.rt.PipelineDesc& desc)
    {
        RayTracingPipeline pso = new RayTracingPipeline(m_Context);
        pso.desc = desc;

        // TODO: move the pipeline layout creation to a common function

        for (const BindingLayoutHandle& _layout : desc.globalBindingLayouts)
        {
            BindingLayout layout = checked_cast<BindingLayout>(_layout.Get());
            pso.pipelineBindingLayouts.push_back(layout);
        }

        BindingVector<VkDescriptorSetLayout> descriptorSetLayouts;
        uint32 pushConstantSize = 0;
        ShaderType pushConstantVisibility = ShaderType.None;
        for (const BindingLayoutHandle& _layout : desc.globalBindingLayouts)
        {
            BindingLayout layout = checked_cast<BindingLayout>(_layout.Get());
            descriptorSetLayouts.push_back(layout.descriptorSetLayout);

            if (!layout.isBindless)
            {
                for (const BindingLayoutItem& item : layout.desc.bindings)
                {
                    if (item.type == ResourceType.PushConstants)
                    {
                        pushConstantSize = item.size;
                        pushConstantVisibility = layout.desc.visibility;
                        // assume there's only one push constant item in all layouts -- the validation layer makes sure of that
                        break;
                    }
                }
            }
        }

        var pushConstantRange = VkPushConstantRange()
            .setOffset(0)
            .setSize(pushConstantSize)
            .setStageFlags(convertShaderTypeToShaderStageFlagBits(pushConstantVisibility));

        var pipelineLayoutInfo = VkPipelineLayoutCreateInfo()
            .setSetLayoutCount(uint32(descriptorSetLayouts.size()))
            .setPSetLayouts(descriptorSetLayouts.Ptr)
            .setPushConstantRangeCount(0)
            .setPushConstantRangeCount(pushConstantSize ? 1 : 0)
            .setPPushConstantRanges(&pushConstantRange);

        VkResult res = m_Context.device.createPipelineLayout(&pipelineLayoutInfo,
                                                               m_Context.allocationCallbacks,
                                                               &pso.pipelineLayout);

        CHECK_VK_FAIL!(res);

        // Count all shader modules with their specializations,
        // place them into a dictionary to remove duplicates.

        int numShaders = 0;
        int numShadersWithSpecializations = 0;
        int numSpecializationConstants = 0;

        Dictionary<Shader, uint32> shaderStageIndices; // shader . index

        for (readonly ref var shaderDesc in ref desc.shaders)
        {
            if (shaderDesc.bindingLayout)
            {
                utils.NotSupported();
                return null;
            }

            registerShaderModule(shaderDesc.shader, shaderStageIndices, numShaders, 
                numShadersWithSpecializations, numSpecializationConstants);
        }

        for (readonly ref var hitGroupDesc in ref desc.hitGroups)
        {
            if (hitGroupDesc.bindingLayout)
            {
                utils.NotSupported();
                return null;
            }

            registerShaderModule(hitGroupDesc.closestHitShader, shaderStageIndices, numShaders,
                numShadersWithSpecializations, numSpecializationConstants);

            registerShaderModule(hitGroupDesc.anyHitShader, shaderStageIndices, numShaders,
                numShadersWithSpecializations, numSpecializationConstants);

            registerShaderModule(hitGroupDesc.intersectionShader, shaderStageIndices, numShaders,
                numShadersWithSpecializations, numSpecializationConstants);
        }

        Runtime.Assert(numShaders == shaderStageIndices.size());

        // Populate the shader stages, shader groups, and specializations arrays.

        List<VkPipelineShaderStageCreateInfo> shaderStages;
        List<VkRayTracingShaderGroupCreateInfoKHR> shaderGroups;
        List<VkSpecializationInfo> specInfos;
        List<VkSpecializationMapEntry> specMapEntries;
        List<uint32> specData;

        shaderStages.resize(numShaders);
        shaderGroups.reserve(desc.shaders.size() + desc.hitGroups.size());
        specInfos.reserve(numShadersWithSpecializations);
        specMapEntries.reserve(numSpecializationConstants);
        specData.reserve(numSpecializationConstants);

        // ... Individual shaders (RayGen, Miss, Callable)

        for (readonly ref var shaderDesc in ref desc.shaders)
        {
            String exportName = shaderDesc.exportName;

            var shaderGroupCreateInfo = VkRayTracingShaderGroupCreateInfoKHR()
                .setType(VkRayTracingShaderGroupTypeKHR::eGeneral)
                .setClosestHitShader(VK_SHADER_UNUSED_KHR)
                .setAnyHitShader(VK_SHADER_UNUSED_KHR)
                .setIntersectionShader(VK_SHADER_UNUSED_KHR);

            if (shaderDesc.shader)
            {
                Shader shader = checked_cast<Shader, IShader>(shaderDesc.shader.Get());
                uint32 shaderStageIndex = shaderStageIndices[shader];
                shaderStages[shaderStageIndex] = makeShaderStageCreateInfo(shader, specInfos, specMapEntries, specData);

                if (exportNameIsEmpty)
                    exportName = shader.desc.entryName;

                shaderGroupCreateInfo.setGeneralShader(shaderStageIndex);
            }

            if (!exportNameIsEmpty)
            {
                pso.shaderGroups[exportName] = uint32(shaderGroups.size());
                shaderGroups.push_back(shaderGroupCreateInfo);
            }
        }

        // ... Hit groups

        for (readonly ref var hitGroupDesc in ref desc.hitGroups)
        {
            var shaderGroupCreateInfo = VkRayTracingShaderGroupCreateInfoKHR()
                .setType(hitGroupDesc.isProceduralPrimitive 
                    ? VkRayTracingShaderGroupTypeKHR::eProceduralHitGroup
                    : VkRayTracingShaderGroupTypeKHR::eTrianglesHitGroup)
                .setGeneralShader(VK_SHADER_UNUSED_KHR)
                .setClosestHitShader(VK_SHADER_UNUSED_KHR)
                .setAnyHitShader(VK_SHADER_UNUSED_KHR)
                .setIntersectionShader(VK_SHADER_UNUSED_KHR);

            if (hitGroupDesc.closestHitShader)
            {
                Shader shader = checked_cast<Shader, IShader>(hitGroupDesc.closestHitShader.Get());
                uint32 shaderStageIndex = shaderStageIndices[shader];
                shaderStages[shaderStageIndex] = makeShaderStageCreateInfo(shader, specInfos, specMapEntries, specData);
                shaderGroupCreateInfo.setClosestHitShader(shaderStageIndex);
            }
            if (hitGroupDesc.anyHitShader)
            {
                Shader shader = checked_cast<Shader, IShader>(hitGroupDesc.anyHitShader.Get());
                uint32 shaderStageIndex = shaderStageIndices[shader];
                shaderStages[shaderStageIndex] = makeShaderStageCreateInfo(shader, specInfos, specMapEntries, specData);
                shaderGroupCreateInfo.setAnyHitShader(shaderStageIndex);
            }
            if (hitGroupDesc.intersectionShader)
            {
                Shader shader = checked_cast<Shader, IShader>(hitGroupDesc.intersectionShader.Get());
                uint32 shaderStageIndex = shaderStageIndices[shader];
                shaderStages[shaderStageIndex] = makeShaderStageCreateInfo(shader, specInfos, specMapEntries, specData);
                shaderGroupCreateInfo.setIntersectionShader(shaderStageIndex);
            }

            Runtime.Assert(!hitGroupDesc.exportNameIsEmpty);
            
            pso.shaderGroups[hitGroupDesc.exportName] = uint32(shaderGroups.size());
            shaderGroups.push_back(shaderGroupCreateInfo);
        }

        // Create the pipeline object

        var libraryInfo = VkPipelineLibraryCreateInfoKHR();
        
        var pipelineInfo = VkRayTracingPipelineCreateInfoKHR()
            .setStages(shaderStages)
            .setGroups(shaderGroups)
            .setLayout(pso.pipelineLayout)
            .setMaxPipelineRayRecursionDepth(desc.maxRecursionDepth)
            .setPLibraryInfo(&libraryInfo);

        res = m_Context.device.createRayTracingPipelinesKHR(VkDeferredOperationKHR(), m_Context.pipelineCache,
            1, &pipelineInfo,
            m_Context.allocationCallbacks,
            &pso.pipeline);

        CHECK_VK_FAIL!(res);

        // Obtain the shader group handles to fill the SBT buffer later

        pso.shaderGroupHandles.resize(m_Context.rayTracingPipelineProperties.shaderGroupHandleSize * shaderGroups.size());

        res = m_Context.device.getRayTracingShaderGroupHandlesKHR(pso.pipeline, 0, 
            uint32(shaderGroups.size()), 
            pso.shaderGroupHandles.size(), pso.shaderGroupHandles.Ptr);

        CHECK_VK_FAIL!(res);

        return nvrhi.rt.PipelineHandle.Create(pso);
    }

	    public BindingLayoutHandle createBindingLayout(const BindingLayoutDesc& desc)
    {
        BindingLayout ret = new BindingLayout(m_Context, desc);

        ret.bake();

        return BindingLayoutHandle.Create(ret);
    }

	    public BindingLayoutHandle createBindlessLayout(const BindlessLayoutDesc& desc)
    {
        BindingLayout ret = new BindingLayout(m_Context, desc);

        ret.bake();

        return BindingLayoutHandle.Create(ret);
    }

	    public BindingSetHandle createBindingSet(const BindingSetDesc& desc, IBindingLayout _layout)
    {
        BindingLayout layout = checked_cast<BindingLayout>(_layout);

        BindingSet *ret = new BindingSet(m_Context);
        ret.desc = desc;
        ret.layout = layout;

        readonly ref var descriptorSetLayout = ref layout.descriptorSetLayout;
        readonly ref var poolSizes = ref layout.descriptorPoolSizeInfo;

        // create descriptor pool to allocate a descriptor from
        var poolInfo = VkDescriptorPoolCreateInfo()
            .setPoolSizeCount(uint32(poolSizes.size()))
            .setPPoolSizes(poolSizes.Ptr)
            .setMaxSets(1);

        VkResult res = m_Context.device.createDescriptorPool(&poolInfo,
                                                             m_Context.allocationCallbacks,
                                                             &ret.descriptorPool);
        CHECK_VK_FAIL!(res);
        
        // create the descriptor set
        var descriptorSetAllocInfo = VkDescriptorSetAllocateInfo()
            .setDescriptorPool(ret.descriptorPool)
            .setDescriptorSetCount(1)
            .setPSetLayouts(&descriptorSetLayout);

        res = m_Context.device.allocateDescriptorSets(&descriptorSetAllocInfo,
            &ret.descriptorSet);
        CHECK_VK_FAIL!(res);
        
        // collect all of the descriptor write data
        StaticVector<VkDescriptorImageInfo, const c_MaxBindingsPerLayout> descriptorImageInfo;
        StaticVector<VkDescriptorBufferInfo, const c_MaxBindingsPerLayout> descriptorBufferInfo;
        StaticVector<VkWriteDescriptorSet, const c_MaxBindingsPerLayout> descriptorWriteInfo;
        StaticVector<VkWriteDescriptorSetAccelerationStructureKHR, const c_MaxBindingsPerLayout> accelStructWriteInfo;

        var generateWriteDescriptorData =
            // generates a VkWriteDescriptorSet struct in descriptorWriteInfo
            [&](uint32 bindingLocation,
                VkDescriptorType descriptorType,
                VkDescriptorImageInfo *imageInfo,
                VkDescriptorBufferInfo *bufferInfo,
                VkBufferView *bufferView,
                const void* pNext = null)
        {
            descriptorWriteInfo.push_back(
                VkWriteDescriptorSet()
                .setDstSet(ret.descriptorSet)
                .setDstBinding(bindingLocation)
                .setDstArrayElement(0)
                .setDescriptorCount(1)
                .setDescriptorType(descriptorType)
                .setPImageInfo(imageInfo)
                .setPBufferInfo(bufferInfo)
                .setPTexelBufferView(bufferView)
                .setPNext(pNext)
            );
        };

        for (int bindingIndex = 0; bindingIndex < desc.bindings.size(); bindingIndex++)
        {
            const BindingSetItem& binding = desc.bindings[bindingIndex];
            const VkDescriptorSetLayoutBinding& layoutBinding = layout.vulkanLayoutBindings[bindingIndex];

            if (binding.resourceHandle == null)
            {
                continue;
            }

            ret.resources.push_back(binding.resourceHandle); // keep a strong reference to the resource

            switch (binding.type)
            {
            case ResourceType.Texture_SRV:
            {
                readonly var texture = checked_cast<Texture *>(binding.resourceHandle);

                readonly var subresource = binding.subresources.resolve(texture.desc, false);
                readonly var textureViewType = getTextureViewType(binding.format, texture.desc.format);
                var& view = texture.getSubresourceView(subresource, binding.dimension, textureViewType);

                var& imageInfo = descriptorImageInfo.emplace_back();
                imageInfo = VkDescriptorImageInfo()
                    .setImageView(view.view)
                    .setImageLayout(VkImageLayout.eShaderReadOnlyOptimal);

                generateWriteDescriptorData(layoutBinding.binding,
                    layoutBinding.descriptorType,
                    &imageInfo, null, null);

                if (!texture.permanentState)
                    ret.bindingsThatNeedTransitions.push_back(static_cast<uint16>(bindingIndex));
                else
                    verifyPermanentResourceState(texture.permanentState,
                        ResourceStates.ShaderResource,
                        true, texture.desc.debugName, m_Context.messageCallback);
            }

            break;

            case ResourceType.Texture_UAV:
            {
                readonly var texture = checked_cast<Texture *>(binding.resourceHandle);

                readonly var subresource = binding.subresources.resolve(texture.desc, true);
                readonly var textureViewType = getTextureViewType(binding.format, texture.desc.format);
                var& view = texture.getSubresourceView(subresource, binding.dimension, textureViewType);

                var& imageInfo = descriptorImageInfo.emplace_back();
                imageInfo = VkDescriptorImageInfo()
                    .setImageView(view.view)
                    .setImageLayout(VkImageLayout.eGeneral);

                generateWriteDescriptorData(layoutBinding.binding,
                    layoutBinding.descriptorType,
                    &imageInfo, null, null);

                if (!texture.permanentState)
                    ret.bindingsThatNeedTransitions.push_back(static_cast<uint16>(bindingIndex));
                else
                    verifyPermanentResourceState(texture.permanentState,
                        ResourceStates.UnorderedAccess,
                        true, texture.desc.debugName, m_Context.messageCallback);
            }

            break;

            case ResourceType.TypedBuffer_SRV:
            case ResourceType.TypedBuffer_UAV:
            {
                readonly var buffer = checked_cast<Buffer *>(binding.resourceHandle);

                Runtime.Assert(buffer.desc.canHaveTypedViews);
                const bool isUAV = (binding.type == ResourceType.TypedBuffer_UAV);
                if (isUAV)
                    Runtime.Assert(buffer.desc.canHaveUAVs);

                Format format = binding.format;

                if (format == Format.UNKNOWN)
                {
                    format = buffer.desc.format;
                }

                var vkformat = nvrhi.vulkan.convertFormat(format);

                readonly ref var bufferViewFound = ref buffer.viewCache.find(vkformat);
                var& bufferViewRef = (bufferViewFound != buffer.viewCache.end()) ? bufferViewFound.second : buffer.viewCache[vkformat];
                if (bufferViewFound == buffer.viewCache.end())
                {
                    Runtime.Assert(format != Format.UNKNOWN);
                    readonly var range = binding.range.resolve(buffer.desc);

                    var bufferViewInfo = VkBufferViewCreateInfo()
                        .setBuffer(buffer.buffer)
                        .setOffset(range.byteOffset)
                        .setRange(range.byteSize)
                        .setFormat(vkformat);

                    res = m_Context.device.createBufferView(&bufferViewInfo, m_Context.allocationCallbacks, &bufferViewRef);
                    ASSERT_VK_OK!(res);
                }

                generateWriteDescriptorData(layoutBinding.binding,
                    layoutBinding.descriptorType,
                    null, null, &bufferViewRef);

                if (!buffer.permanentState)
                    ret.bindingsThatNeedTransitions.push_back(static_cast<uint16>(bindingIndex));
                else
                    verifyPermanentResourceState(buffer.permanentState, 
                        isUAV ? ResourceStates.UnorderedAccess : ResourceStates.ShaderResource,
                        false, buffer.desc.debugName, m_Context.messageCallback);
            }
            break;

            case ResourceType.StructuredBuffer_SRV:
            case ResourceType.StructuredBuffer_UAV:
            case ResourceType.RawBuffer_SRV:
            case ResourceType.RawBuffer_UAV:
            case ResourceType.ConstantBuffer:
            case ResourceType.VolatileConstantBuffer:
            {
                readonly var buffer = checked_cast<Buffer *>(binding.resourceHandle);

                if (binding.type == ResourceType.StructuredBuffer_UAV || binding.type == ResourceType.RawBuffer_UAV)
                    Runtime.Assert(buffer.desc.canHaveUAVs);
                if (binding.type == ResourceType.StructuredBuffer_UAV || binding.type == ResourceType.StructuredBuffer_SRV)
                    Runtime.Assert(buffer.desc.structStride != 0);
                if (binding.type == ResourceType.RawBuffer_SRV|| binding.type == ResourceType.RawBuffer_UAV)
                    Runtime.Assert(buffer.desc.canHaveRawViews);

                readonly var range = binding.range.resolve(buffer.desc);

                var& bufferInfo = descriptorBufferInfo.emplace_back();
                bufferInfo = VkDescriptorBufferInfo()
                    .setBuffer(buffer.buffer)
                    .setOffset(range.byteOffset)
                    .setRange(range.byteSize);

                Runtime.Assert(buffer.buffer);
                generateWriteDescriptorData(layoutBinding.binding,
                    layoutBinding.descriptorType,
                    null, &bufferInfo, null);

                if (binding.type == ResourceType.VolatileConstantBuffer) 
                {
                    Runtime.Assert(buffer.desc.isVolatile);
                    ret.volatileConstantBuffers.push_back(buffer);
                }
                else
                {
                    if (!buffer.permanentState)
                        ret.bindingsThatNeedTransitions.push_back(static_cast<uint16>(bindingIndex));
                    else
                    {
                        ResourceStates requiredState;
                        if (binding.type == ResourceType.StructuredBuffer_UAV || binding.type == ResourceType.RawBuffer_SRV)
                            requiredState = ResourceStates.UnorderedAccess;
                        else if (binding.type == ResourceType.ConstantBuffer)
                            requiredState = ResourceStates.ConstantBuffer;
                        else
                            requiredState = ResourceStates.ShaderResource;

                        verifyPermanentResourceState(buffer.permanentState, requiredState,
                            false, buffer.desc.debugName, m_Context.messageCallback);
                    }
                }
            }

            break;

            case ResourceType.Sampler:
            {
                readonly var sampler = checked_cast<Sampler *>(binding.resourceHandle);

                var& imageInfo = descriptorImageInfo.emplace_back();
                imageInfo = VkDescriptorImageInfo()
                    .setSampler(sampler.sampler);

                generateWriteDescriptorData(layoutBinding.binding,
                    layoutBinding.descriptorType,
                    &imageInfo, null, null);
            }

            break;

            case ResourceType.RayTracingAccelStruct:
            {
                readonly var @as = checked_cast<AccelStruct, IAccelStruct>(binding.resourceHandle);

                var& accelStructWrite = accelStructWriteInfo.emplace_back();
                accelStructWrite.accelerationStructureCount = 1;
                accelStructWrite.pAccelerationStructures = &@as.accelStruct;

                generateWriteDescriptorData(layoutBinding.binding,
                    layoutBinding.descriptorType,
                    null, null, null, &accelStructWrite);

                ret.bindingsThatNeedTransitions.push_back(static_cast<uint16>(bindingIndex));
            }

            break;

            case ResourceType.PushConstants:
                break;

            case ResourceType.None:
            case ResourceType.Count:
            default:
                utils.InvalidEnum();
                break;
            }
        }

        m_Context.device.updateDescriptorSets(uint32(descriptorWriteInfo.size()), descriptorWriteInfo.Ptr, 0, null);

        return BindingSetHandle.Create(ret);
    }

	    public DescriptorTableHandle createDescriptorTable(IBindingLayout _layout)
    { 
        BindingLayout layout = checked_cast<BindingLayout>(_layout);

        DescriptorTable ret = new DescriptorTable(m_Context);
        ret.layout = layout;
        ret.capacity = layout.vulkanLayoutBindings[0].descriptorCount;

        readonly ref var descriptorSetLayout = ref layout.descriptorSetLayout;
        readonly ref var poolSizes = ref layout.descriptorPoolSizeInfo;

        // create descriptor pool to allocate a descriptor from
        var poolInfo = VkDescriptorPoolCreateInfo()
            .setPoolSizeCount(uint32(poolSizes.size()))
            .setPPoolSizes(poolSizes.Ptr)
            .setMaxSets(1);

        VkResult res = m_Context.device.createDescriptorPool(&poolInfo,
                                                             m_Context.allocationCallbacks,
                                                             &ret.descriptorPool);
        CHECK_VK_FAIL!(res);

        // create the descriptor set
        var descriptorSetAllocInfo = VkDescriptorSetAllocateInfo()
            .setDescriptorPool(ret.descriptorPool)
            .setDescriptorSetCount(1)
            .setPSetLayouts(&descriptorSetLayout);

        res = m_Context.device.allocateDescriptorSets(&descriptorSetAllocInfo,
            &ret.descriptorSet);
        CHECK_VK_FAIL!(res);

        return DescriptorTableHandle.Create(ret);
    }

	    public void resizeDescriptorTable(IDescriptorTable _descriptorTable, uint32 newSize, bool keepContents)
    {
        Runtime.Assert(newSize <= checked_cast<DescriptorTable>(_descriptorTable).layout.getBindlessDesc().maxCapacity);
        (void)_descriptorTable;
        (void)newSize;
        (void)keepContents;
    }

	    public bool writeDescriptorTable(IDescriptorTable _descriptorTable, const BindingSetItem& binding)
    {
        DescriptorTable descriptorTable = checked_cast<DescriptorTable>(_descriptorTable);
        BindingLayout layout = checked_cast<BindingLayout>(descriptorTable.layout.Get());

        if (binding.slot >= descriptorTable.capacity)
            return false;

        VkResult res;

        // collect all of the descriptor write data
        StaticVector<VkDescriptorImageInfo, const c_MaxBindingsPerLayout> descriptorImageInfo;
        StaticVector<VkDescriptorBufferInfo, const c_MaxBindingsPerLayout> descriptorBufferInfo;
        StaticVector<VkWriteDescriptorSet, const c_MaxBindingsPerLayout> descriptorWriteInfo;

        var generateWriteDescriptorData =
            // generates a VkWriteDescriptorSet struct in descriptorWriteInfo
            [&](uint32 bindingLocation,
                VkDescriptorType descriptorType,
                VkDescriptorImageInfo* imageInfo,
                VkDescriptorBufferInfo* bufferInfo,
                VkBufferView* bufferView)
        {
            descriptorWriteInfo.push_back(
                VkWriteDescriptorSet()
                .setDstSet(descriptorTable.descriptorSet)
                .setDstBinding(bindingLocation)
                .setDstArrayElement(binding.slot)
                .setDescriptorCount(1)
                .setDescriptorType(descriptorType)
                .setPImageInfo(imageInfo)
                .setPBufferInfo(bufferInfo)
                .setPTexelBufferView(bufferView)
            );
        };

        for (uint32 bindingLocation = 0; bindingLocation < uint32(layout.bindlessDesc.registerSpaces.size()); bindingLocation++)
        {
            if (layout.bindlessDesc.registerSpaces[bindingLocation].type == binding.type)
            {
                const VkDescriptorSetLayoutBinding& layoutBinding = layout.vulkanLayoutBindings[bindingLocation];

                switch (binding.type)
                {
                case ResourceType.Texture_SRV:
                {
                    readonly ref var texture = checked_cast<Texture, ITexture>(binding.resourceHandle);

                    readonly var subresource = binding.subresources.resolve(texture.desc, false);
                    readonly var textureViewType = getTextureViewType(binding.format, texture.desc.format);
                    var& view = texture.getSubresourceView(subresource, binding.dimension, textureViewType);

                    var& imageInfo = descriptorImageInfo.emplace_back();
                    imageInfo = VkDescriptorImageInfo()
                        .setImageView(view.view)
                        .setImageLayout(VkImageLayout.eShaderReadOnlyOptimal);

                    generateWriteDescriptorData(layoutBinding.binding,
                        layoutBinding.descriptorType,
                        &imageInfo, null, null);
                }

                break;

                case ResourceType.Texture_UAV:
                {
                    readonly var texture = checked_cast<Texture, ITexture>(binding.resourceHandle);

                    readonly var subresource = binding.subresources.resolve(texture.desc, true);
                    readonly var textureViewType = getTextureViewType(binding.format, texture.desc.format);
                    var& view = texture.getSubresourceView(subresource, binding.dimension, textureViewType);

                    var& imageInfo = descriptorImageInfo.emplace_back();
                    imageInfo = VkDescriptorImageInfo()
                        .setImageView(view.view)
                        .setImageLayout(VkImageLayout.eGeneral);

                    generateWriteDescriptorData(layoutBinding.binding,
                        layoutBinding.descriptorType,
                        &imageInfo, null, null);
                }

                break;

                case ResourceType.TypedBuffer_SRV:
                case ResourceType.TypedBuffer_UAV:
                {
                    readonly ref var buffer = checked_cast<Buffer, IBuffer>(binding.resourceHandle);

                    var vkformat = nvrhi.vulkan.convertFormat(binding.format);

                    readonly ref var bufferViewFound = ref buffer.viewCache.find(vkformat);
                    var& bufferViewRef = (bufferViewFound != buffer.viewCache.end()) ? bufferViewFound.second : buffer.viewCache[vkformat];
                    if (bufferViewFound == buffer.viewCache.end())
                    {
                        Runtime.Assert(binding.format != Format.UNKNOWN);
                        readonly var range = binding.range.resolve(buffer.desc);

                        var bufferViewInfo = VkBufferViewCreateInfo()
                            .setBuffer(buffer.buffer)
                            .setOffset(range.byteOffset)
                            .setRange(range.byteSize)
                            .setFormat(vkformat);

                        res = m_Context.device.createBufferView(&bufferViewInfo, m_Context.allocationCallbacks, &bufferViewRef);
                        ASSERT_VK_OK!(res);
                    }

                    generateWriteDescriptorData(layoutBinding.binding,
                        layoutBinding.descriptorType,
                        null, null, &bufferViewRef);
                }
                break;

                case ResourceType.StructuredBuffer_SRV:
                case ResourceType.StructuredBuffer_UAV:
                case ResourceType.RawBuffer_SRV:
                case ResourceType.RawBuffer_UAV:
                case ResourceType.ConstantBuffer:
                case ResourceType.VolatileConstantBuffer:
                {
                    readonly var buffer = checked_cast<Buffer, IBuffer>(binding.resourceHandle);

                    readonly var range = binding.range.resolve(buffer.desc);

                    var& bufferInfo = descriptorBufferInfo.emplace_back();
                    bufferInfo = VkDescriptorBufferInfo()
                        .setBuffer(buffer.buffer)
                        .setOffset(range.byteOffset)
                        .setRange(range.byteSize);

                    Runtime.Assert(buffer.buffer);
                    generateWriteDescriptorData(layoutBinding.binding,
                        layoutBinding.descriptorType,
                        null, &bufferInfo, null);
                }

                break;

                case ResourceType.Sampler:
                {
                    readonly ref var sampler = checked_cast<Sampler*>(binding.resourceHandle);

                    var& imageInfo = descriptorImageInfo.emplace_back();
                    imageInfo = VkDescriptorImageInfo()
                        .setSampler(sampler.sampler);

                    generateWriteDescriptorData(layoutBinding.binding,
                        layoutBinding.descriptorType,
                        &imageInfo, null, null);
                }

                break;

                case ResourceType.RayTracingAccelStruct:
                    utils.NotImplemented();
                    break;

                case ResourceType.PushConstants:
                    utils.NotSupported();
                    break;

                case ResourceType.None:
                case ResourceType.Count:
                default:
                    utils.InvalidEnum();
                }
            }
        }

        m_Context.device.updateDescriptorSets(uint32(descriptorWriteInfo.size()), descriptorWriteInfo.Ptr, 0, null);

        return true;
    }
	    
	    public nvrhi.rt.AccelStructHandle createAccelStruct(const nvrhi.rt.AccelStructDesc& desc)
    {
        AccelStruct @as = new AccelStruct(m_Context);
        @as.desc = desc;
        @as.allowUpdate = (desc.buildFlags & nvrhi.rt.AccelStructBuildFlags.AllowUpdate) != 0;

#if NVRHI_WITH_RTXMU
        bool isManaged = desc.isTopLevel;
#else
        bool isManaged = true;
#endif

        if (isManaged)
        {
            List<VkAccelerationStructureGeometryKHR> geometries;
            List<uint32> maxPrimitiveCounts;

            var buildInfo = VkAccelerationStructureBuildGeometryInfoKHR();

            if (desc.isTopLevel)
            {
                geometries.push_back(VkAccelerationStructureGeometryKHR()
                    .setGeometryType(VkGeometryTypeKHR.eInstances));

                geometries[0].geometry.setInstances(VkAccelerationStructureGeometryInstancesDataKHR());

                maxPrimitiveCounts.push_back(uint32(desc.topLevelMaxInstances));

                buildInfo.setType(VkAccelerationStructureTypeKHR.eTopLevel);
            }
            else
            {
                geometries.resize(desc.bottomLevelGeometries.size());
                maxPrimitiveCounts.resize(desc.bottomLevelGeometries.size());

                for (int i = 0; i < desc.bottomLevelGeometries.size(); i++)
                {
                    convertBottomLevelGeometry(desc.bottomLevelGeometries[i], geometries[i], maxPrimitiveCounts[i], null, m_Context);
                }

                buildInfo.setType(VkAccelerationStructureTypeKHR.eBottomLevel);
            }

            buildInfo.setMode(VkBuildAccelerationStructureModeKHR::eBuild)
                .setGeometries(geometries)
                .setFlags(convertAccelStructBuildFlags(desc.buildFlags));

            var buildSizes = m_Context.device.getAccelerationStructureBuildSizesKHR(
                VkAccelerationStructureBuildTypeKHR.eDevice, buildInfo, maxPrimitiveCounts);

            BufferDesc bufferDesc;
            bufferDesc.byteSize = buildSizes.accelerationStructureSize;
            bufferDesc.debugName = desc.debugName;
            bufferDesc.initialState = desc.isTopLevel ? ResourceStates.AccelStructRead : ResourceStates.AccelStructBuildBlas;
            bufferDesc.keepInitialState = true;
            bufferDesc.isAccelStructStorage = true;
            bufferDesc.isVirtual = desc.isVirtual;
            @as.dataBuffer = createBuffer(bufferDesc);

            Buffer dataBuffer = checked_cast<Buffer, IBuffer>(@as.dataBuffer.Get());

            var createInfo = VkAccelerationStructureCreateInfoKHR()
                .setType(desc.isTopLevel ? VkAccelerationStructureTypeKHR.eTopLevel : VkAccelerationStructureTypeKHR.eBottomLevel)
                .setBuffer(dataBuffer.buffer)
                .setSize(buildSizes.accelerationStructureSize);

            @as.accelStruct = m_Context.device.createAccelerationStructureKHR(createInfo, m_Context.allocationCallbacks);

            if (!desc.isVirtual)
            {
                var addressInfo = VkAccelerationStructureDeviceAddressInfoKHR()
                    .setAccelerationStructure(@as.accelStruct);

                @as.accelStructDeviceAddress = m_Context.device.getAccelerationStructureAddressKHR(addressInfo);
            }
        }

        // Sanitize the geometry data to avoid dangling pointers, we don't need these buffers in the Desc
        for (var& geometry : @as.desc.bottomLevelGeometries)
        {
            Compiler.Assert(offsetof(nvrhi.rt.GeometryTriangles, indexBuffer)
                == offsetof(nvrhi.rt.GeometryAABBs, buffer));
            Compiler.Assert(offsetof(nvrhi.rt.GeometryTriangles, vertexBuffer)
                == offsetof(nvrhi.rt.GeometryAABBs, unused));

            // Clear only the triangles' data, because the AABBs' data is aliased to triangles (verified above)
            geometry.geometryData.triangles.indexBuffer = null;
            geometry.geometryData.triangles.vertexBuffer = null;
        }

        return nvrhi.rt.AccelStructHandle.Create(@as);
    }

	    public MemoryRequirements getAccelStructMemoryRequirements(nvrhi.rt.IAccelStruct _as)
    {
        AccelStruct @as = checked_cast<AccelStruct, IAccelStruct>(_as);

        if (@as.dataBuffer)
            return getBufferMemoryRequirements(@as.dataBuffer);

        return MemoryRequirements();
    }

	    public bool bindAccelStructMemory(nvrhi.rt.IAccelStruct _as, IHeap heap, uint64 offset)
    {
        AccelStruct @as = checked_cast<AccelStruct, IAccelStruct>(_as);

        if (!@as.dataBuffer)
            return false;

        const bool bound = bindBufferMemory(@as.dataBuffer, heap, offset);

        if (bound)
        {
            var addressInfo = VkAccelerationStructureDeviceAddressInfoKHR()
                .setAccelerationStructure(@as.accelStruct);

            @as.accelStructDeviceAddress = m_Context.device.getAccelerationStructureAddressKHR(addressInfo);
        }

        return bound;
    }

	    public CommandListHandle createCommandList(CommandListParameters @params = .())
    {
        if (!m_Queues[uint32(params.queueType)])
            return null;

        CommandList cmdList = new CommandList(this, m_Context, params);

        return CommandListHandle.Create(cmdList);
    }

	    public uint64 executeCommandLists(ICommandList const* pCommandLists, int numCommandLists, CommandQueue executionQueue = .Graphics)
    {
        Queue& queue = *m_Queues[uint32(executionQueue)];

        uint64 submissionID = queue.submit(pCommandLists, numCommandLists);

        for (int i = 0; i < numCommandLists; i++)
        {
            checked_cast<CommandList>(pCommandLists[i]).executed(queue, submissionID);
        }

        return submissionID;
    }

	    public void queueWaitForCommandList(CommandQueue waitQueueID, CommandQueue executionQueueID, uint64 instance)
    {
        queueWaitForSemaphore(waitQueueID, getQueueSemaphore(executionQueueID), instance);
    }

	    public void waitForIdle()
    {
        m_Context.device.waitIdle();
    }

	    public void runGarbageCollection()
    {
        for (var& m_Queue : m_Queues)
        {
            if (m_Queue)
            {
                m_Queue.retireCommandBuffers();
            }
        }
    }

	    public bool queryFeatureSupport(Feature feature, void* pInfo, int infoSize)
    {
        switch (feature)  // NOLINT(clang-diagnostic-switch-enum)
        {
        case Feature.DeferredCommandLists:
            return true;
        case Feature.RayTracingAccelStruct:
            return m_Context.extensions.KHR_acceleration_structure;
        case Feature.RayTracingPipeline:
            return m_Context.extensions.KHR_ray_tracing_pipeline;
        case Feature.RayQuery:
            return m_Context.extensions.KHR_ray_query;
        case Feature.ShaderSpecializations:
            return true;
        case Feature.Meshlets:
            return m_Context.extensions.NV_mesh_shader;
        case Feature.VariableRateShading:
            if (pInfo)
            {
                if (infoSize == sizeof(VariableRateShadingFeatureInfo))
                {
                    var* pVrsInfo = reinterpret_cast<VariableRateShadingFeatureInfo*>(pInfo);
                    readonly ref var tileExtent = ref m_Context.shadingRateProperties.minFragmentShadingRateAttachmentTexelSize;
                    pVrsInfo.shadingRateImageTileSize = Math.Max(tileExtent.width, tileExtent.height);
                }
                else
                    utils.NotSupported();
            }
            return m_Context.extensions.KHR_fragment_shading_rate && m_Context.shadingRateFeatures.attachmentFragmentShadingRate;
        case Feature.VirtualResources:
            return true;
        case Feature.ComputeQueue:
            return (m_Queues[uint32(CommandQueue.Compute)] != null);
        case Feature.CopyQueue:
            return (m_Queues[uint32(CommandQueue.Copy)] != null);
        default:
            return false;
        }
    }


	    public FormatSupport queryFormatSupport(Format format)
    {
        VkFormat vulkanFormat = convertFormat(format);
        
        VkFormatProperties props;
        m_Context.physicalDevice.getFormatProperties(vulkanFormat, &props);

        FormatSupport result = FormatSupport.None;

        if (props.bufferFeatures)
            result = result | FormatSupport.Buffer;

        if (format == Format.R32_UINT || format == Format.R16_UINT) {
            // There is no explicit bit in VkFormatFeatureFlags for index buffers
            result = result | FormatSupport.IndexBuffer;
        }
        
        if (props.bufferFeatures & VkFormatFeatureFlagBits.eVertexBuffer)
            result = result | FormatSupport.VertexBuffer;

        if (props.optimalTilingFeatures)
            result = result | FormatSupport.Texture;

        if (props.optimalTilingFeatures & VkFormatFeatureFlagBits.eDepthStencilAttachment)
            result = result | FormatSupport.DepthStencil;

        if (props.optimalTilingFeatures & VkFormatFeatureFlagBits.eColorAttachment)
            result = result | FormatSupport.RenderTarget;

        if (props.optimalTilingFeatures & VkFormatFeatureFlagBits.eColorAttachmentBlend)
            result = result | FormatSupport.Blendable;

        if ((props.optimalTilingFeatures & VkFormatFeatureFlagBits.eSampledImage) ||
            (props.bufferFeatures & VkFormatFeatureFlagBits.eUniformTexelBuffer))
        {
            result = result | FormatSupport.ShaderLoad;
        }

        if (props.optimalTilingFeatures & VkFormatFeatureFlagBits.eSampledImageFilterLinear)
            result = result | FormatSupport.ShaderSample;

        if ((props.optimalTilingFeatures & VkFormatFeatureFlagBits.eStorageImage) ||
            (props.bufferFeatures & VkFormatFeatureFlagBits.eStorageTexelBuffer))
        {
            result = result | FormatSupport.ShaderUavLoad;
            result = result | FormatSupport.ShaderUavStore;
        }

        if ((props.optimalTilingFeatures & VkFormatFeatureFlagBits.eStorageImageAtomic) ||
            (props.bufferFeatures & VkFormatFeatureFlagBits.eStorageTexelBufferAtomic))
        {
            result = result | FormatSupport.ShaderAtomic;
        }

        return result;
    }

	    public NativeObject getNativeQueue(ObjectType objectType, CommandQueue queue)
    {
        if (objectType != ObjectType.VK_Queue)
            return null;

        if (queue >= CommandQueue.Count)
            return null;

        return NativeObject(m_Queues[uint32(queue)].getVkQueue());
    }

	    public override IMessageCallback getMessageCallback()  { return m_Context.messageCallback; }

	    // nvrhi.vulkanIDevice implementation
	    public VkSemaphore getQueueSemaphore(CommandQueue queueID)
    {
        Queue queue = m_Queues[uint32(queueID)];

        return queue.trackingSemaphore;
    }
	    public void queueWaitForSemaphore(CommandQueue waitQueueID, VkSemaphore semaphore, uint64 value)
    {
        Queue waitQueue = m_Queues[uint32(waitQueueID)];

        waitQueue.addWaitSemaphore(semaphore, value);
    }

	    public void queueSignalSemaphore(CommandQueue executionQueueID, VkSemaphore semaphore, uint64 value)
    {
        Queue executionQueue = m_Queues[uint32(executionQueueID)];

        executionQueue.addSignalSemaphore(semaphore, value);
    }

	    public override uint64 queueGetCompletedInstance(CommandQueue queue)
    {
        return m_Context.device.getSemaphoreCounterValue(getQueueSemaphore(queue));
    }

	    public FramebufferHandle createHandleForNativeFramebuffer(VkRenderPass renderPass, VkFramebuffer framebuffer,
        const FramebufferDesc& desc, bool transferOwnership)
    {
        Framebuffer fb = new Framebuffer(m_Context);
        fb.desc = desc;
        fb.framebufferInfo = FramebufferInfo(desc);
        fb.renderPass = renderPass;
        fb.framebuffer = framebuffer;
        fb.managed = transferOwnership;

        for (readonly ref var rt in ref desc.colorAttachments)
        {
            if (rt.valid())
                fb.resources.push_back(rt.texture);
        }

        if (desc.depthAttachment.valid())
        {
            fb.resources.push_back(desc.depthAttachment.texture);
        }

        return FramebufferHandle.Create(fb);
    }


	    private VulkanContext m_Context;
	    private VulkanAllocator m_Allocator;
	    
	    private VkQueryPool m_TimerQueryPool = null;
	    private utils.BitSetAllocator m_TimerQueryAllocator;

	    private Monitor m_Mutex;

	    // array of submission queues
	    private Queue[uint32(CommandQueue.Count)] m_Queues;
	    
	    private void *mapBuffer(IBuffer _buffer, CpuAccessMode flags, uint64 offset, int size) const
    {
        Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

        Runtime.Assert(flags != CpuAccessMode.None);

        // If the buffer has been used in a command list before, wait for that CL to complete
        if (buffer.lastUseCommandListID != 0)
        {
            var& queue = m_Queues[uint32(buffer.lastUseQueue)];
            queue.waitCommandList(buffer.lastUseCommandListID, ~0uL);
        }

        VkAccessFlags accessFlags;

        switch(flags)
        {
            case CpuAccessMode.Read:
                accessFlags = VkAccessFlagBits.eHostRead;
                break;

            case CpuAccessMode.Write:
                accessFlags = VkAccessFlagBits.eHostWrite;
                break;
                
            case CpuAccessMode.None:
            default:
                utils.InvalidEnum();
                break;
        }

        // TODO: there should be a barrier... But there can't be a command list here
        // buffer.barrier(cmd, VkPipelineStageFlagBits.eHost, accessFlags);

        void* ptr = null;
        readonly VkResult res = m_Context.device.mapMemory(buffer.memory, offset, size, VkMemoryMapFlags(), &ptr);
        Runtime.Assert(res == VkResult.eSuccess);

        return ptr;
    }
	}
}