using Bulkan;
using System.Collections;
using System;
using System.Threading;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	class Device : RefCounter<nvrhi.vulkan.IDevice>
	{
		// Internal backend methods

		public this(DeviceDesc desc)
		{
			m_Context = new .(desc.instance, desc.physicalDevice, desc.device, desc.allocationCallbacks);
			m_Allocator = new .(m_Context);
			m_TimerQueryAllocator = new .(desc.maxTimerQueries, true);

			if (desc.graphicsQueue != .Null)
			{
				m_Queues[uint32(CommandQueue.Graphics)] = new Queue(m_Context, CommandQueue.Graphics, desc.graphicsQueue, (.)desc.graphicsQueueIndex);
			}

			if (desc.computeQueue != .Null)
			{
				m_Queues[uint32(CommandQueue.Compute)] = new Queue(m_Context, CommandQueue.Compute, desc.computeQueue, (.)desc.computeQueueIndex);
			}

			if (desc.transferQueue != .Null)
			{
				m_Queues[uint32(CommandQueue.Copy)] = new Queue(m_Context, CommandQueue.Copy, desc.transferQueue, (.)desc.transferQueueIndex);
			}

			// maps Vulkan extension strings into the corresponding boolean flags in Device
			Dictionary<char8*, bool*> extensionStringMap = scope .()
				{
					(VulkanNative.VK_KHR_MAINTENANCE1_EXTENSION_NAME, &m_Context.extensions.KHR_maintenance1),
					(VulkanNative.VK_EXT_DEBUG_REPORT_EXTENSION_NAME, &m_Context.extensions.EXT_debug_report),
					(VulkanNative.VK_EXT_DEBUG_MARKER_EXTENSION_NAME, &m_Context.extensions.EXT_debug_marker),
					(VulkanNative.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME, &m_Context.extensions.KHR_acceleration_structure),
					(VulkanNative.VK_KHR_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME, &m_Context.extensions.KHR_buffer_device_address),
					(VulkanNative.VK_KHR_RAY_QUERY_EXTENSION_NAME, &m_Context.extensions.KHR_ray_query),
					(VulkanNative.VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME, &m_Context.extensions.KHR_ray_tracing_pipeline),
					(VulkanNative.VK_NV_MESH_SHADER_EXTENSION_NAME, &m_Context.extensions.NV_mesh_shader),
					(VulkanNative.VK_KHR_FRAGMENT_SHADING_RATE_EXTENSION_NAME, &m_Context.extensions.KHR_fragment_shading_rate)
				};

			// parse the extension/layer lists and figure out which extensions are enabled
			for (int i = 0; i < desc.numInstanceExtensions; i++)
			{
				if (extensionStringMap.ContainsKey(desc.instanceExtensions[i]))
				{
					*extensionStringMap[desc.instanceExtensions[i]] = true;
				}
			}

			for (int i = 0; i < desc.numDeviceExtensions; i++)
			{
				if (extensionStringMap.ContainsKey(desc.deviceExtensions[i]))
				{
					*extensionStringMap[desc.deviceExtensions[i]] = true;
				}
			}

			// Get the device properties with supported extensions

			void* pNext = null;
			VkPhysicalDeviceAccelerationStructurePropertiesKHR accelStructProperties = .();
			VkPhysicalDeviceRayTracingPipelinePropertiesKHR rayTracingPipelineProperties = .();
			VkPhysicalDeviceFragmentShadingRatePropertiesKHR shadingRateProperties = .();
			VkPhysicalDeviceProperties2 deviceProperties2 = .();

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

			vkGetPhysicalDeviceProperties2(m_Context.physicalDevice, &deviceProperties2);

			m_Context.physicalDeviceProperties = deviceProperties2.properties;
			m_Context.accelStructProperties = accelStructProperties;
			m_Context.rayTracingPipelineProperties = rayTracingPipelineProperties;
			m_Context.shadingRateProperties = shadingRateProperties;
			m_Context.messageCallback = desc.errorCB;

			if (m_Context.extensions.KHR_fragment_shading_rate)
			{
				VkPhysicalDeviceFeatures2 deviceFeatures2 = .();
				VkPhysicalDeviceFragmentShadingRateFeaturesKHR shadingRateFeatures = .();
				deviceFeatures2.setPNext(&shadingRateFeatures);
				vkGetPhysicalDeviceFeatures2(m_Context.physicalDevice, &deviceFeatures2);
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
			VkResult res = vkCreatePipelineCache(m_Context.device, &pipelineInfo,
				m_Context.allocationCallbacks,
				&m_Context.pipelineCache);

			if (res != VkResult.eVkSuccess)
			{
				m_Context.error("Failed to create the pipeline cache");
			}
		}
		public ~this()
		{
			if (m_TimerQueryPool != .Null)
			{
				vkDestroyQueryPool(m_Context.device, m_TimerQueryPool, m_Context.allocationCallbacks);
				m_TimerQueryPool = .Null;
			}

			if (m_Context.pipelineCache != .Null)
			{
				vkDestroyPipelineCache(m_Context.device, m_Context.pipelineCache, m_Context.allocationCallbacks);
				m_Context.pipelineCache = .Null;
			}

			for (var queue in m_Queues)
			{
				if (queue != null)
				{
					delete queue;
				}
			}

			delete m_TimerQueryAllocator;
			delete m_Allocator;
			delete m_Context;
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
				return NativeObject(Internal.UnsafeCastToPtr(this));
			default:
				return null;
			}
		}


		// IDevice implementation

		public override HeapHandle createHeap(HeapDesc d)
		{
			VkMemoryRequirements memoryRequirements = .();
			memoryRequirements.alignment = 0;
			memoryRequirements.memoryTypeBits = ~0u; // just pick whatever fits the property flags
			memoryRequirements.size = d.capacity;

			VkMemoryPropertyFlags memoryPropertyFlags;
			switch (d.type)
			{
			case HeapType.DeviceLocal:
				memoryPropertyFlags = VkMemoryPropertyFlags.eDeviceLocalBit;
				break;
			case HeapType.Upload:
				memoryPropertyFlags = VkMemoryPropertyFlags.eHostVisibleBit;
				break;
			case HeapType.Readback:
				memoryPropertyFlags = VkMemoryPropertyFlags.eHostVisibleBit | VkMemoryPropertyFlags.eHostCachedBit;
				break;
			default:
				utils.InvalidEnum();
				return null;
			}

			Heap heap = new Heap(m_Context, m_Allocator);
			heap.desc = d;
			heap.managed = true;

			readonly VkResult res = m_Allocator.allocateMemory(heap, memoryRequirements, memoryPropertyFlags);

			if (res != VkResult.eVkSuccess)
			{
				String message = scope $"Failed to allocate memory for Heap {utils.DebugNameToString(d.debugName)}, VkResult = {resultToString(res)}";

				m_Context.error(message);

				delete heap;
				return null;
			}

			if (!d.debugName.IsEmpty)
			{
				m_Context.nameVKObject(heap.memory, VkDebugReportObjectTypeEXT.eDeviceMemoryExt, d.debugName);
			}

			return HeapHandle.Attach(heap);
		}

		public override TextureHandle createTexture(TextureDesc desc)
		{
			Texture texture = new Texture(m_Context, m_Allocator);
			Runtime.Assert(texture != null);
			fillTextureInfo(texture, desc);

			VkResult res = vkCreateImage(m_Context.device, &texture.imageInfo, m_Context.allocationCallbacks, &texture.image);
			ASSERT_VK_OK!(res);
			CHECK_VK_FAIL!(res);

			m_Context.nameVKObject(texture.image, VkDebugReportObjectTypeEXT.eImageExt, desc.debugName);

			if (!desc.isVirtual)
			{
				res = m_Allocator.allocateTextureMemory(texture);
				ASSERT_VK_OK!(res);
				CHECK_VK_FAIL!(res);

				m_Context.nameVKObject(texture.memory, VkDebugReportObjectTypeEXT.eDeviceMemoryExt, desc.debugName);
			}

			return TextureHandle.Attach(texture);
		}
		public override MemoryRequirements getTextureMemoryRequirements(ITexture _texture)
		{
			Texture texture = checked_cast<Texture, ITexture>(_texture);

			VkMemoryRequirements vulkanMemReq = .();
			vkGetImageMemoryRequirements(m_Context.device, texture.image, &vulkanMemReq);

			MemoryRequirements memReq = .();
			memReq.alignment = vulkanMemReq.alignment;
			memReq.size = vulkanMemReq.size;
			return memReq;
		}
		public override bool bindTextureMemory(ITexture _texture, IHeap _heap, uint64 offset)
		{
			Texture texture = checked_cast<Texture, ITexture>(_texture);
			Heap heap = checked_cast<Heap, IHeap>(_heap);

			if (texture.heap != null)
				return false;

			if (!texture.desc.isVirtual)
				return false;

			vkBindImageMemory(m_Context.device, texture.image, heap.memory, offset);

			texture.heap = heap;

			return true;
		}

		public override TextureHandle createHandleForNativeTexture(ObjectType objectType, NativeObject _texture, TextureDesc desc)
		{
			if (_texture.integer == 0)
				return null;

			if (objectType != ObjectType.VK_Image)
				return null;

			VkImage image = VkImage(_texture.integer);

			Texture texture = new Texture(m_Context, m_Allocator);
			fillTextureInfo(texture, desc);

			texture.image = image;
			texture.managed = false;

			return TextureHandle.Attach(texture);
		}

		public override StagingTextureHandle createStagingTexture(TextureDesc desc, CpuAccessMode cpuAccess)
		{
			Runtime.Assert(cpuAccess != CpuAccessMode.None);

			StagingTexture tex = new StagingTexture();
			tex.desc = desc;
			tex.populateSliceRegions();

			BufferDesc bufDesc = .();
			bufDesc.byteSize = uint32(tex.getBufferSize());
			Runtime.Assert(bufDesc.byteSize > 0);
			bufDesc.debugName = desc.debugName;
			bufDesc.cpuAccess = cpuAccess;

			BufferHandle internalBuffer = createBuffer(bufDesc);
			tex.buffer = checked_cast<Buffer, IBuffer>(internalBuffer.Get<IBuffer>());

			if (tex.buffer == null)
			{
				delete tex;
				return null;
			}

			return StagingTextureHandle.Attach(tex);
		}

		public override void* mapStagingTexture(IStagingTexture _tex, TextureSlice slice, CpuAccessMode cpuAccess, int* outRowPitch)
		{
			Runtime.Assert(slice.x == 0);
			Runtime.Assert(slice.y == 0);
			Runtime.Assert(cpuAccess != CpuAccessMode.None);

			StagingTexture tex = checked_cast<StagingTexture, IStagingTexture>(_tex);

			var resolvedSlice = slice.resolve(tex.desc);

			var region = tex.getSliceRegion(resolvedSlice.mipLevel, resolvedSlice.arraySlice, resolvedSlice.z);

			Runtime.Assert((region.offset & 0x3) == 0); // per vulkan spec
			Runtime.Assert(region.size > 0);

			readonly ref FormatInfo formatInfo = ref getFormatInfo(tex.desc.format);
			Runtime.Assert(outRowPitch != null);

			var wInBlocks = resolvedSlice.width / formatInfo.blockSize;

			*outRowPitch = wInBlocks * formatInfo.bytesPerBlock;

			return mapBuffer(tex.buffer, cpuAccess, (.)region.offset, region.size);
		}

		public override void unmapStagingTexture(IStagingTexture _tex)
		{
			StagingTexture tex = checked_cast<StagingTexture, IStagingTexture>(_tex);

			unmapBuffer(tex.buffer);
		}

		public override BufferHandle createBuffer(BufferDesc desc)
		{
			// Check some basic constraints first - the validation layer is expected to handle them too

			if (desc.isVolatile && desc.maxVersions == 0)
				return null;

			if (desc.isVolatile && !desc.isConstantBuffer)
				return null;

			if (desc.byteSize == 0)
				return null;


			Buffer buffer = new Buffer(m_Context, m_Allocator);
			buffer.desc = desc;

			VkBufferUsageFlags usageFlags = VkBufferUsageFlags.eTransferSrcBit |
				VkBufferUsageFlags.eTransferDstBit;

			if (desc.isVertexBuffer)
				usageFlags |= VkBufferUsageFlags.eVertexBufferBit;

			if (desc.isIndexBuffer)
				usageFlags |= VkBufferUsageFlags.eIndexBufferBit;

			if (desc.isDrawIndirectArgs)
				usageFlags |= VkBufferUsageFlags.eIndirectBufferBit;

			if (desc.isConstantBuffer)
				usageFlags |= VkBufferUsageFlags.eUniformBufferBit;

			if (desc.structStride != 0 || desc.canHaveUAVs || desc.canHaveRawViews)
				usageFlags |= VkBufferUsageFlags.eStorageBufferBit;

			if (desc.canHaveTypedViews)
				usageFlags |= VkBufferUsageFlags.eUniformTexelBufferBit;

			if (desc.canHaveTypedViews && desc.canHaveUAVs)
				usageFlags |= VkBufferUsageFlags.eStorageTexelBufferBit;

			if (desc.isAccelStructBuildInput)
				usageFlags |= VkBufferUsageFlags.eAccelerationStructureBuildInputReadOnlyBitKHR;

			if (desc.isAccelStructStorage)
				usageFlags |= VkBufferUsageFlags.eAccelerationStructureStorageBitKHR;

			if (m_Context.extensions.KHR_buffer_device_address)
				usageFlags |= VkBufferUsageFlags.eShaderDeviceAddressBit;

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

				buffer.versionTracking.Resize(desc.maxVersions, default); //..Fill(0);
				//std::fill(buffer.versionTracking.begin(), buffer.versionTracking.end(), 0);

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

			VkResult res = vkCreateBuffer(m_Context.device, &bufferInfo, m_Context.allocationCallbacks, &buffer.buffer);
			CHECK_VK_FAIL!(res);

			m_Context.nameVKObject(VkBuffer(buffer.buffer), VkDebugReportObjectTypeEXT.eBufferExt, desc.debugName);

			if (!desc.isVirtual)
			{
				res = m_Allocator.allocateBufferMemory(buffer, (usageFlags & VkBufferUsageFlags.eShaderDeviceAddressBit) != VkBufferUsageFlags.None);
				CHECK_VK_FAIL!(res);

				m_Context.nameVKObject(buffer.memory, VkDebugReportObjectTypeEXT.eDeviceMemoryExt, desc.debugName);

				if (desc.isVolatile)
				{
					VkResult result = vkMapMemory(m_Context.device, buffer.memory, 0, size, 0 /*todo sed: flags*/, &buffer.mappedMemory);
					ASSERT_VK_OK!(result);
					Runtime.Assert(buffer.mappedMemory != null);
				}

				if (m_Context.extensions.KHR_buffer_device_address)
				{
					var addressInfo = VkBufferDeviceAddressInfo().setBuffer(buffer.buffer);

					buffer.deviceAddress = vkGetBufferDeviceAddress(m_Context.device, &addressInfo);
				}
			}

			return BufferHandle.Attach(buffer);
		}

		public override void* mapBuffer(IBuffer _buffer, CpuAccessMode flags)
		{
			Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

			return mapBuffer(buffer, flags, 0, (.)buffer.desc.byteSize);
		}

		public override void unmapBuffer(IBuffer _buffer)
		{
			Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

			vkUnmapMemory(m_Context.device, buffer.memory);

			// TODO: there should be a barrier
			// buffer.barrier(cmd, VkPipelineStageFlagBits.eTransfer, VkAccessFlags.eTransferRead);
		}

		public override MemoryRequirements getBufferMemoryRequirements(IBuffer _buffer)
		{
			Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

			VkMemoryRequirements vulkanMemReq = .();
			vkGetBufferMemoryRequirements(m_Context.device,  buffer.buffer, &vulkanMemReq);

			MemoryRequirements memReq;
			memReq.alignment = vulkanMemReq.alignment;
			memReq.size = vulkanMemReq.size;
			return memReq;
		}

		public override bool bindBufferMemory(IBuffer _buffer, IHeap _heap, uint64 offset)
		{
			Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);
			Heap heap = checked_cast<Heap, IHeap>(_heap);

			if (buffer.heap != null)
				return false;

			if (!buffer.desc.isVirtual)
				return false;

			vkBindBufferMemory(m_Context.device, buffer.buffer, heap.memory, offset);

			buffer.heap = heap;

			if (m_Context.extensions.KHR_buffer_device_address)
			{
				var addressInfo = VkBufferDeviceAddressInfo().setBuffer(buffer.buffer);

				buffer.deviceAddress = vkGetBufferDeviceAddress(m_Context.device, &addressInfo);
			}

			return true;
		}

		public override BufferHandle createHandleForNativeBuffer(ObjectType objectType, NativeObject _buffer, BufferDesc desc)
		{
			if (_buffer.pointer == null)
				return null;

			if (objectType != ObjectType.VK_Buffer)
				return null;

			Buffer buffer = new Buffer(m_Context, m_Allocator);
			buffer.buffer = VkBuffer(_buffer.integer);
			buffer.desc = desc;
			buffer.managed = false;

			return BufferHandle.Attach(buffer);
		}

		public override ShaderHandle createShader(ShaderDesc desc, void* binary, int binarySize)
		{
			Shader shader = new Shader(m_Context);

			shader.desc = desc;
			shader.desc.entryName = new .(desc.entryName);
			shader.stageFlagBits = convertShaderTypeToShaderStageFlagBits(desc.shaderType);

			var shaderInfo = VkShaderModuleCreateInfo()
				.setCodeSize((.)binarySize)
				.setPCode((uint32*)binary);

			readonly VkResult res = vkCreateShaderModule(m_Context.device, &shaderInfo, m_Context.allocationCallbacks, &shader.shaderModule);
			CHECK_VK_FAIL!(res);

			readonly String debugName = scope $"{desc.debugName}:{desc.entryName}";
			m_Context.nameVKObject(VkShaderModule(shader.shaderModule), VkDebugReportObjectTypeEXT.eShaderModuleExt, debugName);

			return ShaderHandle.Attach(shader);
		}

		public override ShaderHandle createShaderSpecialization(IShader _baseShader, ShaderSpecialization* constants, uint32 numConstants)
		{
			Shader baseShader = checked_cast<Shader, IShader>(_baseShader);
			Runtime.Assert(constants != null);
			Runtime.Assert(numConstants != 0);

			Shader newShader = new Shader(m_Context);

			// Hold a strong reference to the parent object
			newShader.baseShader = (baseShader.baseShader != null) ? baseShader.baseShader : baseShader;
			newShader.desc = baseShader.desc;
			newShader.shaderModule = baseShader.shaderModule;
			newShader.stageFlagBits = baseShader.stageFlagBits;
			newShader.specializationConstants.Assign(constants, numConstants);

			return ShaderHandle.Attach(newShader);
		}

		public override ShaderLibraryHandle createShaderLibrary(void* binary, int binarySize)
		{
			ShaderLibrary library = new ShaderLibrary(m_Context);

			var shaderInfo = VkShaderModuleCreateInfo()
				.setCodeSize((.)binarySize)
				.setPCode((uint32*)binary);

			readonly VkResult res = vkCreateShaderModule(m_Context.device, &shaderInfo, m_Context.allocationCallbacks, &library.shaderModule);
			CHECK_VK_FAIL!(res);

			return ShaderLibraryHandle.Attach(library);
		}

		public override SamplerHandle createSampler(SamplerDesc desc)
		{
			Sampler sampler = new Sampler(m_Context);

			readonly bool anisotropyEnable = desc.maxAnisotropy > 1.0f;

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

			VkSamplerReductionModeCreateInfo samplerReductionCreateInfo = .();
			if (desc.reductionType == SamplerReductionType.Minimum || desc.reductionType == SamplerReductionType.Maximum)
			{
				VkSamplerReductionMode reductionMode = desc.reductionType == SamplerReductionType.Maximum ? VkSamplerReductionMode.eMax : VkSamplerReductionMode.eMin;
				samplerReductionCreateInfo.setReductionMode(reductionMode);

				sampler.samplerInfo.setPNext(&samplerReductionCreateInfo);
			}

			readonly VkResult res = vkCreateSampler(m_Context.device, &sampler.samplerInfo, m_Context.allocationCallbacks, &sampler.sampler);
			CHECK_VK_FAIL!(res);

			return SamplerHandle.Attach(sampler);
		}

		public override InputLayoutHandle createInputLayout(VertexAttributeDesc* attributeDesc, uint32 attributeCount, IShader vertexShader)
		{
			InputLayout layout = new InputLayout();

			int32 total_attribute_array_size = 0;

			// collect all buffer bindings
			Dictionary<uint32, VkVertexInputBindingDescription> bindingMap = scope .();
			for (uint32 i = 0; i < attributeCount; i++)
			{
				readonly ref VertexAttributeDesc desc = ref attributeDesc[i];

				Runtime.Assert(desc.arraySize > 0);

				total_attribute_array_size += (.)desc.arraySize;

				if (!bindingMap.ContainsKey(desc.bufferIndex))
				{
					bindingMap[desc.bufferIndex] = VkVertexInputBindingDescription()
						.setBinding(desc.bufferIndex)
						.setStride(desc.elementStride)
						.setInputRate(desc.isInstanced ? VkVertexInputRate.eInstance : VkVertexInputRate.eVertex);
				}
				else
				{
					Runtime.Assert(bindingMap[desc.bufferIndex].stride == desc.elementStride);
					Runtime.Assert(bindingMap[desc.bufferIndex].inputRate == (desc.isInstanced ? VkVertexInputRate.eInstance : VkVertexInputRate.eVertex));
				}
			}

			for ( /*readonly ref*/var b in bindingMap)
			{
				layout.bindingDesc.Add(b.value);
			}

			// build attribute descriptions
			layout.inputDesc.Resize(attributeCount);
			layout.attributeDesc.Resize(total_attribute_array_size);

			uint32 attributeLocation = 0;
			for (uint32 i = 0; i < attributeCount; i++)
			{
				readonly ref VertexAttributeDesc @in = ref attributeDesc[i];
				layout.inputDesc[i] = @in;

				uint32 element_size_bytes = getFormatInfo(@in.format).bytesPerBlock;

				uint32 bufferOffset = 0;

				for (uint32 slot = 0; slot < @in.arraySize; ++slot)
				{
					var outAttrib = ref layout.attributeDesc[attributeLocation];

					outAttrib.location = attributeLocation;
					outAttrib.binding = @in.bufferIndex;
					outAttrib.format = nvrhi.vulkan.convertFormat(@in.format);
					outAttrib.offset = bufferOffset + @in.offset;
					bufferOffset += element_size_bytes;

					++attributeLocation;
				}
			}

			return InputLayoutHandle.Attach(layout);
		}

		// event queries
		public override EventQueryHandle createEventQuery()
		{
			EventQuery query = new EventQuery();
			return EventQueryHandle.Attach(query);
		}

		public override void setEventQuery(IEventQuery _query, CommandQueue queue)
		{
			EventQuery query = checked_cast<EventQuery, IEventQuery>(_query);

			Runtime.Assert(query.commandListID == 0);

			query.queue = queue;
			query.commandListID = m_Queues[uint32(queue)].getLastSubmittedID();
		}

		public override bool pollEventQuery(IEventQuery _query)
		{
			EventQuery query = checked_cast<EventQuery, IEventQuery>(_query);

			var queue = m_Queues[uint32(query.queue)];

			return queue.pollCommandList(query.commandListID);
		}

		public override void waitEventQuery(IEventQuery _query)
		{
			EventQuery query = checked_cast<EventQuery, IEventQuery>(_query);

			if (query.commandListID == 0)
				return;

			var queue = m_Queues[uint32(query.queue)];

			bool success = queue.waitCommandList(query.commandListID, ~0uL);
			Runtime.Assert(success);
			(void)success;
		}

		public override void resetEventQuery(IEventQuery _query)
		{
			EventQuery query = checked_cast<EventQuery, IEventQuery>(_query);

			query.commandListID = 0;
		}

		// timer queries
		public override TimerQueryHandle createTimerQuery()
		{
			if (m_TimerQueryPool == .Null)
			{
				m_Mutex.Enter(); defer m_Mutex.Exit();

				if (m_TimerQueryPool == .Null)
				{
					// set up the timer query pool on first use
					var poolInfo = VkQueryPoolCreateInfo()
						.setQueryType(VkQueryType.eTimestamp)
						.setQueryCount(uint32(m_TimerQueryAllocator.getCapacity()) * 2); // use 2 Vulkan queries per 1 TimerQuery

					readonly VkResult res = vkCreateQueryPool(m_Context.device, &poolInfo, m_Context.allocationCallbacks, &m_TimerQueryPool);
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

			return TimerQueryHandle.Attach(query);
		}

		public override bool pollTimerQuery(ITimerQuery _query)
		{
			TimerQuery query = checked_cast<TimerQuery, ITimerQuery>(_query);

			Runtime.Assert(query.started);

			if (query.resolved)
			{
				return true;
			}

			uint32[2] timestamps = .(0, 0);

			VkResult res;
			res = vkGetQueryPoolResults(m_Context.device, m_TimerQueryPool,
				(.)query.beginQueryIndex, 2,
				sizeof(decltype(timestamps)), &timestamps,
				sizeof(decltype(timestamps[0])), VkQueryResultFlags());
			Runtime.Assert(res == VkResult.eVkSuccess || res == VkResult.VK_NOT_READY);

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

		public override float getTimerQueryTime(ITimerQuery _query)
		{
			TimerQuery query = checked_cast<TimerQuery, ITimerQuery>(_query);

			if (!query.started)
				return 0.f;

			if (!query.resolved)
			{
				while (!pollTimerQuery(query))
				{
				}
			}

			query.started = false;

			Runtime.Assert(query.resolved);
			return query.time;
		}

		public override void resetTimerQuery(ITimerQuery _query)
		{
			TimerQuery query = checked_cast<TimerQuery, ITimerQuery>(_query);

			query.started = false;
			query.resolved = false;
			query.time = 0.f;
		}

		public override GraphicsAPI getGraphicsAPI()
		{
			return GraphicsAPI.VULKAN;
		}

		public override FramebufferHandle createFramebuffer(FramebufferDesc desc)
		{
			Framebuffer fb = new Framebuffer(m_Context);
			fb.desc = desc;
			fb.framebufferInfo = FramebufferInfo(desc);

			AttachmentVector<VkAttachmentDescription2> attachmentDescs = .(desc.colorAttachments.Count);
			AttachmentVector<VkAttachmentReference2> colorAttachmentRefs = .(desc.colorAttachments.Count);
			VkAttachmentReference2 depthAttachmentRef = .();

			StaticVector<VkImageView, const c_MaxRenderTargets + 1> attachmentViews = .();
			attachmentViews.Resize(desc.colorAttachments.Count);

			uint32 numArraySlices = 0;

			for (uint32 i = 0; i < desc.colorAttachments.Count; i++)
			{
				/*readonly ref*/ var rt = /*ref*/ desc.colorAttachments[i];
				Texture t = checked_cast<Texture, ITexture>(rt.texture);

				Runtime.Assert(fb.framebufferInfo.width == t.desc.width >> rt.subresources.baseMipLevel);
				Runtime.Assert(fb.framebufferInfo.height == t.desc.height >> rt.subresources.baseMipLevel);

				readonly VkFormat attachmentFormat = (rt.format == Format.UNKNOWN ? t.imageInfo.format : convertFormat(rt.format));

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

				/*readonly ref*/ var view = ref t.getSubresourceView(subresources, dimension);
				attachmentViews[i] = view.view;

				fb.resources.Add(rt.texture);

				if (numArraySlices > 0)
					Runtime.Assert(numArraySlices == subresources.numArraySlices);
				else
					numArraySlices = subresources.numArraySlices;
			}

			// add depth/stencil attachment if present
			if (desc.depthAttachment.valid())
			{
				/*readonly ref*/ var att = /*ref*/ desc.depthAttachment;

				Texture texture = checked_cast<Texture, ITexture>(att.texture);

				Runtime.Assert(fb.framebufferInfo.width == texture.desc.width >> att.subresources.baseMipLevel);
				Runtime.Assert(fb.framebufferInfo.height == texture.desc.height >> att.subresources.baseMipLevel);

				VkImageLayout depthLayout = VkImageLayout.eDepthStencilAttachmentOptimal;
				if (desc.depthAttachment.isReadOnly)
				{
					depthLayout = VkImageLayout.eDepthStencilReadOnlyOptimal;
				}

				attachmentDescs.PushBack(VkAttachmentDescription2()
					.setFormat(texture.imageInfo.format)
					.setSamples(texture.imageInfo.samples)
					.setLoadOp(VkAttachmentLoadOp.eLoad)
					.setStoreOp(VkAttachmentStoreOp.eStore)
					.setInitialLayout(depthLayout)
					.setFinalLayout(depthLayout));

				depthAttachmentRef = VkAttachmentReference2()
					.setAttachment(uint32(attachmentDescs.Count) - 1)
					.setLayout(depthLayout);

				TextureSubresourceSet subresources = att.subresources.resolve(texture.desc, true);

				TextureDimension dimension = getDimensionForFramebuffer(texture.desc.dimension, subresources.numArraySlices > 1);

				/*readonly ref*/ var view = ref texture.getSubresourceView(subresources, dimension);
				attachmentViews.PushBack(view.view);

				fb.resources.Add(att.texture);

				if (numArraySlices > 0)
					Runtime.Assert(numArraySlices == subresources.numArraySlices);
				else
					numArraySlices = subresources.numArraySlices;
			}

			var subpass = VkSubpassDescription2()
				.setPipelineBindPoint(VkPipelineBindPoint.eGraphics)
				.setColorAttachmentCount(uint32(desc.colorAttachments.Count))
				.setPColorAttachments(colorAttachmentRefs.Ptr)
				.setPDepthStencilAttachment(desc.depthAttachment.valid() ? &depthAttachmentRef : null);

			// add VRS attachment
			// declare the structures here to avoid using pointers to out-of-scope objects in renderPassInfo further
			VkAttachmentReference2 vrsAttachmentRef;
			VkFragmentShadingRateAttachmentInfoKHR shadingRateAttachmentInfo;

			if (desc.shadingRateAttachment.valid())
			{
				/*readonly ref*/ var vrsAttachment = /*ref*/ desc.shadingRateAttachment;
				Texture vrsTexture = checked_cast<Texture, ITexture>(vrsAttachment.texture);
				Runtime.Assert(vrsTexture.imageInfo.format == VkFormat.eR8Uint);
				Runtime.Assert(vrsTexture.imageInfo.samples == VkSampleCountFlags.e1Bit);
				var vrsAttachmentDesc = VkAttachmentDescription2()
					.setFormat(VkFormat.eR8Uint)
					.setSamples(VkSampleCountFlags.e1Bit)
					.setLoadOp(VkAttachmentLoadOp.eLoad)
					.setStoreOp(VkAttachmentStoreOp.eStore)
					.setInitialLayout(VkImageLayout.eFragmentShadingRateAttachmentOptimalKHR)
					.setFinalLayout(VkImageLayout.eFragmentShadingRateAttachmentOptimalKHR);

				attachmentDescs.PushBack(vrsAttachmentDesc);

				TextureSubresourceSet subresources = vrsAttachment.subresources.resolve(vrsTexture.desc, true);
				TextureDimension dimension = getDimensionForFramebuffer(vrsTexture.desc.dimension, subresources.numArraySlices > 1);

				/*readonly ref*/ var view = ref vrsTexture.getSubresourceView(subresources, dimension);
				attachmentViews.PushBack(view.view);

				fb.resources.Add(vrsAttachment.texture);

				if (numArraySlices > 0)
					Runtime.Assert(numArraySlices == subresources.numArraySlices);
				else
					numArraySlices = subresources.numArraySlices;

				var rateProps = VkPhysicalDeviceFragmentShadingRatePropertiesKHR();
				var props = VkPhysicalDeviceProperties2();
				props.pNext = &rateProps;
				vkGetPhysicalDeviceProperties2(m_Context.physicalDevice, &props);

				vrsAttachmentRef = VkAttachmentReference2()
					.setAttachment(uint32(attachmentDescs.Count) - 1)
					.setLayout(VkImageLayout.eFragmentShadingRateAttachmentOptimalKHR);

				shadingRateAttachmentInfo = VkFragmentShadingRateAttachmentInfoKHR()
					.setPFragmentShadingRateAttachment(&vrsAttachmentRef)
					.setShadingRateAttachmentTexelSize(rateProps.minFragmentShadingRateAttachmentTexelSize);

				subpass.setPNext(&shadingRateAttachmentInfo);
			}

			var renderPassInfo = VkRenderPassCreateInfo2()
				.setAttachmentCount(uint32(attachmentDescs.Count))
				.setPAttachments(attachmentDescs.Ptr)
				.setSubpassCount(1)
				.setPSubpasses(&subpass);

			VkResult res = vkCreateRenderPass2(m_Context.device, &renderPassInfo,
				m_Context.allocationCallbacks,
				&fb.renderPass);
			CHECK_VK_FAIL!(res);

			// set up the framebuffer object
			var framebufferInfo = VkFramebufferCreateInfo()
				.setRenderPass(fb.renderPass)
				.setAttachmentCount(uint32(attachmentViews.Count))
				.setPAttachments(attachmentViews.Ptr)
				.setWidth(fb.framebufferInfo.width)
				.setHeight(fb.framebufferInfo.height)
				.setLayers(numArraySlices);

			res = vkCreateFramebuffer(m_Context.device, &framebufferInfo, m_Context.allocationCallbacks,
				&fb.framebuffer);
			CHECK_VK_FAIL!(res);

			return FramebufferHandle.Attach(fb);
		}

		public override GraphicsPipelineHandle createGraphicsPipeline(GraphicsPipelineDesc desc, IFramebuffer _fb)
		{
			if (desc.renderState.singlePassStereo.enabled)
			{
				m_Context.error("Single-pass stereo is not supported by the Vulkan backend");
				return null;
			}

			VkResult res;

			Framebuffer fb = checked_cast<Framebuffer, IFramebuffer>(_fb);

			InputLayout inputLayout = checked_cast<InputLayout, IInputLayout>(desc.inputLayout?.Get<IInputLayout>());

			GraphicsPipeline pso = new GraphicsPipeline(m_Context);
			pso.desc = desc;
			pso.framebufferInfo = fb.framebufferInfo;

			for (readonly ref BindingLayoutHandle _layout in ref desc.bindingLayouts)
			{
				BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(_layout?.Get<IBindingLayout>());
				pso.pipelineBindingLayouts.PushBack(layout);
			}

			Shader VS = checked_cast<Shader, IShader>(desc.VS?.Get<IShader>());
			Shader HS = checked_cast<Shader, IShader>(desc.HS?.Get<IShader>());
			Shader DS = checked_cast<Shader, IShader>(desc.DS?.Get<IShader>());
			Shader GS = checked_cast<Shader, IShader>(desc.GS?.Get<IShader>());
			Shader PS = checked_cast<Shader, IShader>(desc.PS?.Get<IShader>());

			int numShaders = 0;
			int numShadersWithSpecializations = 0;
			int numSpecializationConstants = 0;

			// Count the spec constants for all stages
			countSpecializationConstants(VS, ref numShaders, ref numShadersWithSpecializations, ref numSpecializationConstants);
			countSpecializationConstants(HS, ref numShaders, ref numShadersWithSpecializations, ref numSpecializationConstants);
			countSpecializationConstants(DS, ref numShaders, ref numShadersWithSpecializations, ref numSpecializationConstants);
			countSpecializationConstants(GS, ref numShaders, ref numShadersWithSpecializations, ref numSpecializationConstants);
			countSpecializationConstants(PS, ref numShaders, ref numShadersWithSpecializations, ref numSpecializationConstants);

			List<VkPipelineShaderStageCreateInfo> shaderStages = scope .();
			List<VkSpecializationInfo> specInfos = scope .();
			List<VkSpecializationMapEntry> specMapEntries = scope .();
			List<uint32> specData = scope .();

			// Allocate buffers for specialization constants and related structures
			// so that shaderStageCreateInfo(...) can directly use pointers inside the vectors
			// because the vectors won't reallocate their buffers
			shaderStages.Reserve(numShaders);
			specInfos.Reserve(numShadersWithSpecializations);
			specMapEntries.Reserve(numSpecializationConstants);
			specData.Reserve(numSpecializationConstants);

			// Set up shader stages
			if (desc.VS != null)
			{
				shaderStages.Add(makeShaderStageCreateInfo(VS,
					specInfos, specMapEntries, specData));
				pso.shaderMask = pso.shaderMask | ShaderType.Vertex;
			}

			if (desc.HS != null)
			{
				shaderStages.Add(makeShaderStageCreateInfo(HS,
					specInfos, specMapEntries, specData));
				pso.shaderMask = pso.shaderMask | ShaderType.Hull;
			}

			if (desc.DS != null)
			{
				shaderStages.Add(makeShaderStageCreateInfo(DS,
					specInfos, specMapEntries, specData));
				pso.shaderMask = pso.shaderMask | ShaderType.Domain;
			}

			if (desc.GS != null)
			{
				shaderStages.Add(makeShaderStageCreateInfo(GS,
					specInfos, specMapEntries, specData));
				pso.shaderMask = pso.shaderMask | ShaderType.Geometry;
			}

			if (desc.PS != null)
			{
				shaderStages.Add(makeShaderStageCreateInfo(PS,
					specInfos, specMapEntries, specData));
				pso.shaderMask = pso.shaderMask | ShaderType.Pixel;
			}

			// set up vertex input state
			var vertexInput = VkPipelineVertexInputStateCreateInfo();
			if (inputLayout != null)
			{
				vertexInput.setVertexBindingDescriptionCount(uint32(inputLayout.bindingDesc.Count))
					.setPVertexBindingDescriptions(inputLayout.bindingDesc.Ptr)
					.setVertexAttributeDescriptionCount(uint32(inputLayout.attributeDesc.Count))
					.setPVertexAttributeDescriptions(inputLayout.attributeDesc.Ptr);
			}

			var inputAssembly = VkPipelineInputAssemblyStateCreateInfo()
				.setTopology(convertPrimitiveTopology(desc.primType));

			// fixed function state
			/*readonly ref*/ var rasterState = /*ref*/ desc.renderState.rasterState;
			/*readonly ref*/ var depthStencilState = /*ref*/ desc.renderState.depthStencilState;
			/*readonly ref*/ var blendState = /*ref*/ desc.renderState.blendState;

			var viewportState = VkPipelineViewportStateCreateInfo()
				.setViewportCount(1)
				.setScissorCount(1);

			var rasterizer = VkPipelineRasterizationStateCreateInfo() // .setDepthClampEnable(??)
								// .setRasterizerDiscardEnable(??)
				.setPolygonMode(convertFillMode(rasterState.fillMode))
				.setCullMode(convertCullMode(rasterState.cullMode))
				.setFrontFace(rasterState.frontCounterClockwise ?
				VkFrontFace.eCounterClockwise : VkFrontFace.eClockwise)
				.setDepthBiasEnable(rasterState.depthBias > 0 ? true : false)
				.setDepthBiasConstantFactor(float(rasterState.depthBias))
				.setDepthBiasClamp(rasterState.depthBiasClamp)
				.setDepthBiasSlopeFactor(rasterState.slopeScaledDepthBias)
				.setLineWidth(1.0f);

			var multisample = VkPipelineMultisampleStateCreateInfo()
				.setRasterizationSamples((VkSampleCountFlags)fb.framebufferInfo.sampleCount)
				.setAlphaToCoverageEnable(blendState.alphaToCoverageEnable);

			var depthStencil = VkPipelineDepthStencilStateCreateInfo()
				.setDepthTestEnable(depthStencilState.depthTestEnable)
				.setDepthWriteEnable(depthStencilState.depthWriteEnable)
				.setDepthCompareOp(convertCompareOp(depthStencilState.depthFunc))
				.setStencilTestEnable(depthStencilState.stencilEnable)
				.setFront(convertStencilState(depthStencilState, depthStencilState.frontFaceStencil))
				.setBack(convertStencilState(depthStencilState, depthStencilState.backFaceStencil));

			// VRS state
			VkFragmentShadingRateCombinerOpKHR[2] combiners = .(convertShadingRateCombiner(desc.shadingRateState.pipelinePrimitiveCombiner), convertShadingRateCombiner(desc.shadingRateState.imageCombiner));
			var shadingRateState = VkPipelineFragmentShadingRateStateCreateInfoKHR()
				.setCombinerOps(combiners)
				.setFragmentSize(convertFragmentShadingRate(desc.shadingRateState.shadingRate));

			BindingVector<VkDescriptorSetLayout> descriptorSetLayouts = .();
			uint32 pushConstantSize = 0;
			for (readonly ref BindingLayoutHandle _layout in ref desc.bindingLayouts)
			{
				BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(_layout?.Get<IBindingLayout>());
				descriptorSetLayouts.PushBack(layout.descriptorSetLayout);

				if (!layout.isBindless)
				{
					for (readonly ref BindingLayoutItem item in ref layout.desc.bindings)
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
				.setSetLayoutCount(uint32(descriptorSetLayouts.Count))
				.setPSetLayouts(descriptorSetLayouts.Ptr)
				.setPushConstantRangeCount(pushConstantSize > 0 ? 1 : 0)
				.setPPushConstantRanges(&pushConstantRange);

			res = vkCreatePipelineLayout(m_Context.device, &pipelineLayoutInfo,
				m_Context.allocationCallbacks,
				&pso.pipelineLayout);
			CHECK_VK_FAIL!(res);

			AttachmentVector<VkPipelineColorBlendAttachmentState> colorBlendAttachments = .(fb.desc.colorAttachments.Count);

			for (uint32 i = 0; i < uint32(fb.desc.colorAttachments.Count); i++)
			{
				colorBlendAttachments[i] = convertBlendState(blendState.targets[i]);
			}

			var colorBlend = VkPipelineColorBlendStateCreateInfo()
				.setAttachmentCount(uint32(colorBlendAttachments.Count))
				.setPAttachments(colorBlendAttachments.Ptr);

			pso.usesBlendConstants = blendState.usesConstantColor(uint32(fb.desc.colorAttachments.Count));

			VkDynamicState[4] dynamicStates = .(
				VkDynamicState.eViewport,
				VkDynamicState.eScissor,
				VkDynamicState.eBlendConstants,
				VkDynamicState.eFragmentShadingRateKHR
				);

			var dynamicStateInfo = VkPipelineDynamicStateCreateInfo()
				.setDynamicStateCount(pso.usesBlendConstants ? 3 : 2)
				.setPDynamicStates(&dynamicStates);

			var pipelineInfo = VkGraphicsPipelineCreateInfo()
				.setStageCount(uint32(shaderStages.Count))
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

			res = vkCreateGraphicsPipelines(m_Context.device, m_Context.pipelineCache,
				1, &pipelineInfo,
				m_Context.allocationCallbacks,
				&pso.pipeline);
			ASSERT_VK_OK!(res); // for debugging
			CHECK_VK_FAIL!(res);

			return GraphicsPipelineHandle.Attach(pso);
		}

		public override ComputePipelineHandle createComputePipeline(ComputePipelineDesc desc)
		{
			VkResult res;

			Runtime.Assert(desc.CS != null);

			ComputePipeline pso = new ComputePipeline(m_Context);
			pso.desc = desc;

			for (readonly ref BindingLayoutHandle _layout in ref desc.bindingLayouts)
			{
				BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(_layout.Get<IBindingLayout>());
				pso.pipelineBindingLayouts.PushBack(layout);
			}

			BindingVector<VkDescriptorSetLayout> descriptorSetLayouts = .();
			uint32 pushConstantSize = 0;
			for (readonly ref BindingLayoutHandle _layout in ref desc.bindingLayouts)
			{
				BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(_layout.Get<IBindingLayout>());
				descriptorSetLayouts.PushBack(layout.descriptorSetLayout);

				if (!layout.isBindless)
				{
					for (readonly ref BindingLayoutItem item in ref layout.desc.bindings)
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
				.setStageFlags(VkShaderStageFlags.eComputeBit);

			var pipelineLayoutInfo = VkPipelineLayoutCreateInfo()
				.setSetLayoutCount(uint32(descriptorSetLayouts.Count))
				.setPSetLayouts(descriptorSetLayouts.Ptr)
				.setPushConstantRangeCount(0)
				.setPushConstantRangeCount(pushConstantSize > 0 ? 1 : 0)
				.setPPushConstantRanges(&pushConstantRange);

			res = vkCreatePipelineLayout(m_Context.device, &pipelineLayoutInfo,
				m_Context.allocationCallbacks,
				&pso.pipelineLayout);

			CHECK_VK_FAIL!(res);

			Shader CS = checked_cast<Shader, IShader>(desc.CS.Get<IShader>());

			// See createGraphicsPipeline() for a more expanded implementation
			// of shader specializations with multiple shaders in the pipeline

			int numShaders = 0;
			int numShadersWithSpecializations = 0;
			int numSpecializationConstants = 0;

			countSpecializationConstants(CS, ref numShaders, ref numShadersWithSpecializations, ref numSpecializationConstants);

			Runtime.Assert(numShaders == 1);

			List<VkSpecializationInfo> specInfos = scope .();
			List<VkSpecializationMapEntry> specMapEntries = scope .();
			List<uint32> specData = scope .();

			specInfos.Reserve(numShadersWithSpecializations);
			specMapEntries.Reserve(numSpecializationConstants);
			specData.Reserve(numSpecializationConstants);

			var shaderStageInfo = makeShaderStageCreateInfo(CS,
				specInfos, specMapEntries, specData);

			var pipelineInfo = VkComputePipelineCreateInfo()
				.setStage(shaderStageInfo)
				.setLayout(pso.pipelineLayout);

			res = vkCreateComputePipelines(m_Context.device, m_Context.pipelineCache,
				1, &pipelineInfo,
				m_Context.allocationCallbacks,
				&pso.pipeline);

			CHECK_VK_FAIL!(res);

			return ComputePipelineHandle.Attach(pso);
		}

		public override MeshletPipelineHandle createMeshletPipeline(MeshletPipelineDesc desc, IFramebuffer _fb)
		{
			if (!m_Context.extensions.NV_mesh_shader)
				utils.NotSupported();

			VkResult res;

			Framebuffer fb = checked_cast<Framebuffer, IFramebuffer>(_fb);

			MeshletPipeline pso = new MeshletPipeline(m_Context);
			pso.desc = desc;
			pso.framebufferInfo = fb.framebufferInfo;

			for (readonly ref BindingLayoutHandle _layout in ref desc.bindingLayouts)
			{
				BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(_layout.Get<IBindingLayout>());
				pso.pipelineBindingLayouts.PushBack(layout);
			}

			Shader AS = checked_cast<Shader, IShader>(desc.AS.Get<IShader>());
			Shader MS = checked_cast<Shader, IShader>(desc.MS.Get<IShader>());
			Shader PS = checked_cast<Shader, IShader>(desc.PS.Get<IShader>());

			int numShaders = 0;
			int numShadersWithSpecializations = 0;
			int numSpecializationConstants = 0;

			// Count the spec constants for all stages
			countSpecializationConstants(AS, ref numShaders, ref numShadersWithSpecializations, ref numSpecializationConstants);
			countSpecializationConstants(MS, ref numShaders, ref numShadersWithSpecializations, ref numSpecializationConstants);
			countSpecializationConstants(PS, ref numShaders, ref numShadersWithSpecializations, ref numSpecializationConstants);

			List<VkPipelineShaderStageCreateInfo> shaderStages = scope .();
			List<VkSpecializationInfo> specInfos = scope .();
			List<VkSpecializationMapEntry> specMapEntries = scope .();
			List<uint32> specData = scope .();

			// Allocate buffers for specialization constants and related structures
			// so that shaderStageCreateInfo(...) can directly use pointers inside the vectors
			// because the vectors won't reallocate their buffers
			shaderStages.Reserve(numShaders);
			specInfos.Reserve(numShadersWithSpecializations);
			specMapEntries.Reserve(numSpecializationConstants);
			specData.Reserve(numSpecializationConstants);

			// Set up shader stages
			if (desc.AS != null)
			{
				shaderStages.Add(makeShaderStageCreateInfo(AS,
					specInfos, specMapEntries, specData));
				pso.shaderMask = pso.shaderMask | ShaderType.Vertex;
			}

			if (desc.MS != null)
			{
				shaderStages.Add(makeShaderStageCreateInfo(MS,
					specInfos, specMapEntries, specData));
				pso.shaderMask = pso.shaderMask | ShaderType.Hull;
			}

			if (desc.PS != null)
			{
				shaderStages.Add(makeShaderStageCreateInfo(PS,
					specInfos, specMapEntries, specData));
				pso.shaderMask = pso.shaderMask | ShaderType.Pixel;
			}

			var inputAssembly = VkPipelineInputAssemblyStateCreateInfo()
				.setTopology(convertPrimitiveTopology(desc.primType));

			// fixed function state
			/*readonly ref*/ var rasterState = /*ref*/ desc.renderState.rasterState;
			/*readonly ref*/ var depthStencilState = /*ref*/ desc.renderState.depthStencilState;
			/*readonly ref*/ var blendState = /*ref*/ desc.renderState.blendState;

			var viewportState = VkPipelineViewportStateCreateInfo()
				.setViewportCount(1)
				.setScissorCount(1);

			var rasterizer = VkPipelineRasterizationStateCreateInfo() // .setDepthClampEnable(??)
								// .setRasterizerDiscardEnable(??)
				.setPolygonMode(convertFillMode(rasterState.fillMode))
				.setCullMode(convertCullMode(rasterState.cullMode))
				.setFrontFace(rasterState.frontCounterClockwise ?
				VkFrontFace.eCounterClockwise : VkFrontFace.eClockwise)
				.setDepthBiasEnable(rasterState.depthBias > 0 ? true : false)
				.setDepthBiasConstantFactor(float(rasterState.depthBias))
				.setDepthBiasClamp(rasterState.depthBiasClamp)
				.setDepthBiasSlopeFactor(rasterState.slopeScaledDepthBias)
				.setLineWidth(1.0f);

			var multisample = VkPipelineMultisampleStateCreateInfo()
				.setRasterizationSamples((VkSampleCountFlags)(fb.framebufferInfo.sampleCount))
				.setAlphaToCoverageEnable(blendState.alphaToCoverageEnable);

			var depthStencil = VkPipelineDepthStencilStateCreateInfo()
				.setDepthTestEnable(depthStencilState.depthTestEnable)
				.setDepthWriteEnable(depthStencilState.depthWriteEnable)
				.setDepthCompareOp(convertCompareOp(depthStencilState.depthFunc))
				.setStencilTestEnable(depthStencilState.stencilEnable)
				.setFront(convertStencilState(depthStencilState, depthStencilState.frontFaceStencil))
				.setBack(convertStencilState(depthStencilState, depthStencilState.backFaceStencil));

			BindingVector<VkDescriptorSetLayout> descriptorSetLayouts = .();
			uint32 pushConstantSize = 0;
			for (readonly ref BindingLayoutHandle _layout in ref desc.bindingLayouts)
			{
				BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(_layout.Get<IBindingLayout>());
				descriptorSetLayouts.PushBack(layout.descriptorSetLayout);

				if (!layout.isBindless)
				{
					for (readonly ref BindingLayoutItem item in ref layout.desc.bindings)
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
				.setSetLayoutCount(uint32(descriptorSetLayouts.Count))
				.setPSetLayouts(descriptorSetLayouts.Ptr)
				.setPushConstantRangeCount(pushConstantSize > 0 ? 1 : 0)
				.setPPushConstantRanges(&pushConstantRange);

			res = vkCreatePipelineLayout(m_Context.device, &pipelineLayoutInfo,
				m_Context.allocationCallbacks,
				&pso.pipelineLayout);
			CHECK_VK_FAIL!(res);

			AttachmentVector<VkPipelineColorBlendAttachmentState> colorBlendAttachments = .(fb.desc.colorAttachments.Count);

			for (uint32 i = 0; i < uint32(fb.desc.colorAttachments.Count); i++)
			{
				colorBlendAttachments[i] = convertBlendState(blendState.targets[i]);
			}

			var colorBlend = VkPipelineColorBlendStateCreateInfo()
				.setAttachmentCount(uint32(colorBlendAttachments.Count))
				.setPAttachments(colorBlendAttachments.Ptr);

			pso.usesBlendConstants = blendState.usesConstantColor(uint32(fb.desc.colorAttachments.Count));

			VkDynamicState[3] dynamicStates = .(
				VkDynamicState.eViewport,
				VkDynamicState.eScissor,
				VkDynamicState.eBlendConstants
				);

			var dynamicStateInfo = VkPipelineDynamicStateCreateInfo()
				.setDynamicStateCount(pso.usesBlendConstants ? 3 : 2)
				.setPDynamicStates(&dynamicStates);

			var pipelineInfo = VkGraphicsPipelineCreateInfo()
				.setStageCount(uint32(shaderStages.Count))
				.setPStages(shaderStages.Ptr) //.setPVertexInputState(&vertexInput)
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

			res = vkCreateGraphicsPipelines(m_Context.device, m_Context.pipelineCache,
				1, &pipelineInfo,
				m_Context.allocationCallbacks,
				&pso.pipeline);
			ASSERT_VK_OK!(res); // for debugging
			CHECK_VK_FAIL!(res);

			return MeshletPipelineHandle.Attach(pso);
		}

		public override nvrhi.rt.PipelineHandle createRayTracingPipeline(nvrhi.rt.PipelineDesc desc)
		{
			RayTracingPipeline pso = new RayTracingPipeline(m_Context);
			pso.desc = desc;

			// TODO: move the pipeline layout creation to a common function

			for (readonly ref BindingLayoutHandle _layout in ref desc.globalBindingLayouts)
			{
				BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(_layout.Get<IBindingLayout>());
				pso.pipelineBindingLayouts.PushBack(layout);
			}

			BindingVector<VkDescriptorSetLayout> descriptorSetLayouts = .();
			uint32 pushConstantSize = 0;
			ShaderType pushConstantVisibility = ShaderType.None;
			for (readonly ref BindingLayoutHandle _layout in ref desc.globalBindingLayouts)
			{
				BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(_layout.Get<IBindingLayout>());
				descriptorSetLayouts.PushBack(layout.descriptorSetLayout);

				if (!layout.isBindless)
				{
					for (readonly ref BindingLayoutItem item in ref layout.desc.bindings)
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
				.setSetLayoutCount(uint32(descriptorSetLayouts.Count))
				.setPSetLayouts(descriptorSetLayouts.Ptr)
				.setPushConstantRangeCount(0)
				.setPushConstantRangeCount(pushConstantSize > 0 ? 1 : 0)
				.setPPushConstantRanges(&pushConstantRange);

			VkResult res = vkCreatePipelineLayout(m_Context.device, &pipelineLayoutInfo,
				m_Context.allocationCallbacks,
				&pso.pipelineLayout);

			CHECK_VK_FAIL!(res);

			// Count all shader modules with their specializations,
			// place them into a dictionary to remove duplicates.

			int numShaders = 0;
			int numShadersWithSpecializations = 0;
			int numSpecializationConstants = 0;

			Dictionary<Shader, uint32> shaderStageIndices = scope .(); // shader . index

			for ( /*readonly ref*/var shaderDesc in ref desc.shaders)
			{
				if (shaderDesc.bindingLayout != null)
				{
					utils.NotSupported();
					return null;
				}

				registerShaderModule(shaderDesc.shader, shaderStageIndices, ref numShaders,
					ref numShadersWithSpecializations, ref numSpecializationConstants);
			}

			for ( /*readonly ref*/var hitGroupDesc in ref desc.hitGroups)
			{
				if (hitGroupDesc.bindingLayout != null)
				{
					utils.NotSupported();
					return null;
				}

				registerShaderModule(hitGroupDesc.closestHitShader, shaderStageIndices, ref numShaders,
					ref numShadersWithSpecializations, ref numSpecializationConstants);

				registerShaderModule(hitGroupDesc.anyHitShader, shaderStageIndices, ref numShaders,
					ref numShadersWithSpecializations, ref numSpecializationConstants);

				registerShaderModule(hitGroupDesc.intersectionShader, shaderStageIndices, ref numShaders,
					ref numShadersWithSpecializations, ref numSpecializationConstants);
			}

			Runtime.Assert(numShaders == shaderStageIndices.Count);

			// Populate the shader stages, shader groups, and specializations arrays.

			List<VkPipelineShaderStageCreateInfo> shaderStages = scope .();
			List<VkRayTracingShaderGroupCreateInfoKHR> shaderGroups = scope .();
			List<VkSpecializationInfo> specInfos = scope .();
			List<VkSpecializationMapEntry> specMapEntries = scope .();
			List<uint32> specData = scope .();

			shaderStages.Resize(numShaders);
			shaderGroups.Reserve(desc.shaders.Count + desc.hitGroups.Count);
			specInfos.Reserve(numShadersWithSpecializations);
			specMapEntries.Reserve(numSpecializationConstants);
			specData.Reserve(numSpecializationConstants);

			// ... Individual shaders (RayGen, Miss, Callable)

			for ( /*readonly ref*/var shaderDesc in ref desc.shaders)
			{
				String exportName = shaderDesc.exportName;

				var shaderGroupCreateInfo = VkRayTracingShaderGroupCreateInfoKHR()
					.setType(VkRayTracingShaderGroupTypeKHR.eGeneralKHR)
					.setClosestHitShader(VK_SHADER_UNUSED_KHR)
					.setAnyHitShader(VK_SHADER_UNUSED_KHR)
					.setIntersectionShader(VK_SHADER_UNUSED_KHR);

				if (shaderDesc.shader != null)
				{
					Shader shader = checked_cast<Shader, IShader>(shaderDesc.shader.Get<IShader>());
					uint32 shaderStageIndex = shaderStageIndices[shader];
					shaderStages[shaderStageIndex] = makeShaderStageCreateInfo(shader, specInfos, specMapEntries, specData);

					if (String.IsNullOrEmpty(exportName))
						exportName = shader.desc.entryName;

					shaderGroupCreateInfo.setGeneralShader(shaderStageIndex);
				}

				if (!String.IsNullOrEmpty(exportName))
				{
					pso.shaderGroups[exportName] = uint32(shaderGroups.Count);
					shaderGroups.Add(shaderGroupCreateInfo);
				}
			}

			// ... Hit groups

			for ( /*readonly ref*/var hitGroupDesc in ref desc.hitGroups)
			{
				var shaderGroupCreateInfo = VkRayTracingShaderGroupCreateInfoKHR()
					.setType(hitGroupDesc.isProceduralPrimitive
					? VkRayTracingShaderGroupTypeKHR.eProceduralHitGroupKHR
					: VkRayTracingShaderGroupTypeKHR.eTrianglesHitGroupKHR)
					.setGeneralShader(VK_SHADER_UNUSED_KHR)
					.setClosestHitShader(VK_SHADER_UNUSED_KHR)
					.setAnyHitShader(VK_SHADER_UNUSED_KHR)
					.setIntersectionShader(VK_SHADER_UNUSED_KHR);

				if (hitGroupDesc.closestHitShader != null)
				{
					Shader shader = checked_cast<Shader, IShader>(hitGroupDesc.closestHitShader.Get<IShader>());
					uint32 shaderStageIndex = shaderStageIndices[shader];
					shaderStages[shaderStageIndex] = makeShaderStageCreateInfo(shader, specInfos, specMapEntries, specData);
					shaderGroupCreateInfo.setClosestHitShader(shaderStageIndex);
				}
				if (hitGroupDesc.anyHitShader != null)
				{
					Shader shader = checked_cast<Shader, IShader>(hitGroupDesc.anyHitShader.Get<IShader>());
					uint32 shaderStageIndex = shaderStageIndices[shader];
					shaderStages[shaderStageIndex] = makeShaderStageCreateInfo(shader, specInfos, specMapEntries, specData);
					shaderGroupCreateInfo.setAnyHitShader(shaderStageIndex);
				}
				if (hitGroupDesc.intersectionShader != null)
				{
					Shader shader = checked_cast<Shader, IShader>(hitGroupDesc.intersectionShader.Get<IShader>());
					uint32 shaderStageIndex = shaderStageIndices[shader];
					shaderStages[shaderStageIndex] = makeShaderStageCreateInfo(shader, specInfos, specMapEntries, specData);
					shaderGroupCreateInfo.setIntersectionShader(shaderStageIndex);
				}

				Runtime.Assert(!String.IsNullOrEmpty(hitGroupDesc.exportName));

				pso.shaderGroups[hitGroupDesc.exportName] = uint32(shaderGroups.Count);
				shaderGroups.Add(shaderGroupCreateInfo);
			}

			// Create the pipeline object

			var libraryInfo = VkPipelineLibraryCreateInfoKHR();

			var pipelineInfo = VkRayTracingPipelineCreateInfoKHR()
				.setPStages(shaderStages.Ptr)
				.setPGroups(shaderGroups.Ptr)
				.setLayout(pso.pipelineLayout)
				.setMaxPipelineRayRecursionDepth(desc.maxRecursionDepth)
				.setPLibraryInfo(&libraryInfo);

			res = vkCreateRayTracingPipelinesKHR(m_Context.device, .Null, m_Context.pipelineCache,
				1, &pipelineInfo,
				m_Context.allocationCallbacks,
				&pso.pipeline);

			CHECK_VK_FAIL!(res);

			// Obtain the shader group handles to fill the SBT buffer later

			pso.shaderGroupHandles.Resize(m_Context.rayTracingPipelineProperties.shaderGroupHandleSize * shaderGroups.Count);

			res = vkGetRayTracingShaderGroupHandlesKHR(m_Context.device, pso.pipeline, 0,
				uint32(shaderGroups.Count),
				(.)pso.shaderGroupHandles.Count, pso.shaderGroupHandles.Ptr);

			CHECK_VK_FAIL!(res);

			return nvrhi.rt.PipelineHandle.Attach(pso);
		}

		public override BindingLayoutHandle createBindingLayout(BindingLayoutDesc desc)
		{
			BindingLayout ret = new BindingLayout(m_Context, desc);

			ret.bake();

			return BindingLayoutHandle.Attach(ret);
		}

		public override BindingLayoutHandle createBindlessLayout(BindlessLayoutDesc desc)
		{
			BindingLayout ret = new BindingLayout(m_Context, desc);

			ret.bake();

			return BindingLayoutHandle.Attach(ret);
		}

		public override BindingSetHandle createBindingSet(BindingSetDesc desc, IBindingLayout _layout)
		{
			BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(_layout);

			BindingSet ret = new BindingSet(m_Context);
			ret.desc = desc;
			ret.layout = layout;

			/*readonly ref*/ var descriptorSetLayout = ref layout.descriptorSetLayout;
			/*readonly ref*/ var poolSizes = ref layout.descriptorPoolSizeInfo;

			// create descriptor pool to allocate a descriptor from
			var poolInfo = VkDescriptorPoolCreateInfo()
				.setPoolSizeCount(uint32(poolSizes.Count))
				.setPPoolSizes(poolSizes.Ptr)
				.setMaxSets(1);

			VkResult res = vkCreateDescriptorPool(m_Context.device, &poolInfo,
				m_Context.allocationCallbacks,
				&ret.descriptorPool);
			CHECK_VK_FAIL!(res);

			// create the descriptor set
			var descriptorSetAllocInfo = VkDescriptorSetAllocateInfo()
				.setDescriptorPool(ret.descriptorPool)
				.setDescriptorSetCount(1)
				.setPSetLayouts(&descriptorSetLayout);

			res = vkAllocateDescriptorSets(m_Context.device, &descriptorSetAllocInfo,
				&ret.descriptorSet);
			CHECK_VK_FAIL!(res);

			// collect all of the descriptor write data
			StaticVector<VkDescriptorImageInfo, const c_MaxBindingsPerLayout> descriptorImageInfo = .();
			StaticVector<VkDescriptorBufferInfo, const c_MaxBindingsPerLayout> descriptorBufferInfo = .();
			StaticVector<VkWriteDescriptorSet, const c_MaxBindingsPerLayout> descriptorWriteInfo = .();
			StaticVector<VkWriteDescriptorSetAccelerationStructureKHR, const c_MaxBindingsPerLayout> accelStructWriteInfo = .();

			delegate void(uint32 bindingLocation,
				VkDescriptorType descriptorType,
				VkDescriptorImageInfo* imageInfo,
				VkDescriptorBufferInfo* bufferInfo,
				VkBufferView* bufferView,
				void* pNext = null) generateWriteDescriptorData = // generates a VkWriteDescriptorSet struct in descriptorWriteInfo
				scope [&] (bindingLocation,
				descriptorType,
				imageInfo,
				bufferInfo,
				bufferView,
				pNext) =>
				{
					descriptorWriteInfo.PushBack(
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

			for (int bindingIndex = 0; bindingIndex < desc.bindings.Count; bindingIndex++)
			{
				readonly /*ref*/ BindingSetItem binding = /*ref*/ desc.bindings[bindingIndex];
				readonly ref VkDescriptorSetLayoutBinding layoutBinding = ref layout.vulkanLayoutBindings[bindingIndex];

				if (binding.resourceHandle == null)
				{
					continue;
				}

				ret.resources.Add(binding.resourceHandle); // keep a strong reference to the resource

				switch (binding.type)
				{
				case ResourceType.Texture_SRV:
					{
						readonly var texture = checked_cast<Texture, IResource>(binding.resourceHandle);

						readonly var subresource = binding.subresources.resolve(texture.desc, false);
						readonly var textureViewType = getTextureViewType(binding.format, texture.desc.format);
						var view = ref texture.getSubresourceView(subresource, binding.dimension, textureViewType);

						//var imageInfo = descriptorImageInfo.emplace_back();
						var imageInfo = VkDescriptorImageInfo()
							.setImageView(view.view)
							.setImageLayout(VkImageLayout.eShaderReadOnlyOptimal);

						generateWriteDescriptorData(layoutBinding.binding,
							layoutBinding.descriptorType,
							&imageInfo, null, null, null);

						descriptorImageInfo.PushBack(imageInfo);

						if (texture.permanentState == .Unknown)
							ret.bindingsThatNeedTransitions.Add((uint16)(bindingIndex));
						else
							verifyPermanentResourceState(texture.permanentState,
								ResourceStates.ShaderResource,
								true, texture.desc.debugName, m_Context.messageCallback);
					}

					break;

				case ResourceType.Texture_UAV:
					{
						readonly var texture = checked_cast<Texture, IResource>(binding.resourceHandle);

						readonly var subresource = binding.subresources.resolve(texture.desc, true);
						readonly var textureViewType = getTextureViewType(binding.format, texture.desc.format);
						var view = ref texture.getSubresourceView(subresource, binding.dimension, textureViewType);

						//var imageInfo = descriptorImageInfo.emplace_back();
						var imageInfo = VkDescriptorImageInfo()
							.setImageView(view.view)
							.setImageLayout(VkImageLayout.eGeneral);

						generateWriteDescriptorData(layoutBinding.binding,
							layoutBinding.descriptorType,
							&imageInfo, null, null, null);

						descriptorImageInfo.PushBack(imageInfo);

						if (texture.permanentState == .Unknown)
							ret.bindingsThatNeedTransitions.Add((uint16)(bindingIndex));
						else
							verifyPermanentResourceState(texture.permanentState,
								ResourceStates.UnorderedAccess,
								true, texture.desc.debugName, m_Context.messageCallback);
					}

					break;

				case ResourceType.TypedBuffer_SRV: fallthrough;
				case ResourceType.TypedBuffer_UAV:
					{
						readonly var buffer = checked_cast<Buffer, IResource>(binding.resourceHandle);

						Runtime.Assert(buffer.desc.canHaveTypedViews);
						readonly bool isUAV = (binding.type == ResourceType.TypedBuffer_UAV);
						if (isUAV)
							Runtime.Assert(buffer.desc.canHaveUAVs);

						Format format = binding.format;

						if (format == Format.UNKNOWN)
						{
							format = buffer.desc.format;
						}

						var vkformat = nvrhi.vulkan.convertFormat(format);

						/*readonly ref var bufferViewFound = ref buffer.viewCache.find(vkformat);
						var& bufferViewRef = (bufferViewFound != buffer.viewCache.end()) ? bufferViewFound.second : buffer.viewCache[vkformat];

						VkBufferView* x = null;
						if(buffer.viewCache.ContainsKey(vkformat)){
							x = &buffer.viewCache[vkformat];
						}else{
							buffer.viewCache.Add(vkformat, .Null);
							x = &buffer.viewCache[vkformat];
						}*/

						if (!buffer.viewCache.ContainsKey(vkformat))
						{
							buffer.viewCache.Add(vkformat, .Null);
						}

						var bufferViewRef = ref buffer.viewCache[vkformat];

						//if (bufferViewFound == buffer.viewCache.end())
						if (bufferViewRef == .Null)
						{
							Runtime.Assert(format != Format.UNKNOWN);
							readonly var range = binding.range.resolve(buffer.desc);

							var bufferViewInfo = VkBufferViewCreateInfo()
								.setBuffer(buffer.buffer)
								.setOffset(range.byteOffset)
								.setRange(range.byteSize)
								.setFormat(vkformat);

							res = vkCreateBufferView(m_Context.device, &bufferViewInfo, m_Context.allocationCallbacks, &bufferViewRef);
							ASSERT_VK_OK!(res);
						}

						generateWriteDescriptorData(layoutBinding.binding,
							layoutBinding.descriptorType,
							null, null, &bufferViewRef, null);

						if (buffer.permanentState == .Unknown)
							ret.bindingsThatNeedTransitions.Add((uint16)(bindingIndex));
						else
							verifyPermanentResourceState(buffer.permanentState,
								isUAV ? ResourceStates.UnorderedAccess : ResourceStates.ShaderResource,
								false, buffer.desc.debugName, m_Context.messageCallback);
					}
					break;

				case ResourceType.StructuredBuffer_SRV: fallthrough;
				case ResourceType.StructuredBuffer_UAV: fallthrough;
				case ResourceType.RawBuffer_SRV: fallthrough;
				case ResourceType.RawBuffer_UAV: fallthrough;
				case ResourceType.ConstantBuffer: fallthrough;
				case ResourceType.VolatileConstantBuffer:
					{
						readonly var buffer = checked_cast<Buffer, IResource>(binding.resourceHandle);

						if (binding.type == ResourceType.StructuredBuffer_UAV || binding.type == ResourceType.RawBuffer_UAV)
							Runtime.Assert(buffer.desc.canHaveUAVs);
						if (binding.type == ResourceType.StructuredBuffer_UAV || binding.type == ResourceType.StructuredBuffer_SRV)
							Runtime.Assert(buffer.desc.structStride != 0);
						if (binding.type == ResourceType.RawBuffer_SRV || binding.type == ResourceType.RawBuffer_UAV)
							Runtime.Assert(buffer.desc.canHaveRawViews);

						readonly var range = binding.range.resolve(buffer.desc);

						//var& bufferInfo = descriptorBufferInfo.emplace_back();
						var bufferInfo = VkDescriptorBufferInfo()
							.setBuffer(buffer.buffer)
							.setOffset(range.byteOffset)
							.setRange(range.byteSize);

						Runtime.Assert(buffer.buffer != .Null);
						generateWriteDescriptorData(layoutBinding.binding,
							layoutBinding.descriptorType,
							null, &bufferInfo, null, null);

						descriptorBufferInfo.PushBack(bufferInfo);

						if (binding.type == ResourceType.VolatileConstantBuffer)
						{
							Runtime.Assert(buffer.desc.isVolatile);
							ret.volatileConstantBuffers.PushBack(buffer);
						}
						else
						{
							if (buffer.permanentState == .Unknown)
								ret.bindingsThatNeedTransitions.Add((uint16)(bindingIndex));
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
						readonly var sampler = checked_cast<Sampler, IResource>(binding.resourceHandle);

						//var& imageInfo = descriptorImageInfo.emplace_back();
						var imageInfo = VkDescriptorImageInfo()
							.setSampler(sampler.sampler);

						generateWriteDescriptorData(layoutBinding.binding,
							layoutBinding.descriptorType,
							&imageInfo, null, null, null);

						descriptorImageInfo.PushBack(imageInfo);
					}

					break;

				case ResourceType.RayTracingAccelStruct:
					{
						readonly var @as = checked_cast<AccelStruct, IResource>(binding.resourceHandle);

						//var& accelStructWrite = accelStructWriteInfo.emplace_back();
						var accelStructWrite = VkWriteDescriptorSetAccelerationStructureKHR();
						accelStructWrite.accelerationStructureCount = 1;
						accelStructWrite.pAccelerationStructures = &@as.accelStruct;

						generateWriteDescriptorData(layoutBinding.binding,
							layoutBinding.descriptorType,
							null, null, null, &accelStructWrite);

						accelStructWriteInfo.PushBack(accelStructWrite);

						ret.bindingsThatNeedTransitions.Add((uint16)(bindingIndex));
					}

					break;

				case ResourceType.PushConstants:
					break;

				case ResourceType.None: fallthrough;
				case ResourceType.Count: fallthrough;
				default:
					utils.InvalidEnum();
					break;
				}
			}

			vkUpdateDescriptorSets(m_Context.device, uint32(descriptorWriteInfo.Count), descriptorWriteInfo.Ptr, 0, null);

			return BindingSetHandle.Attach(ret);
		}

		public override DescriptorTableHandle createDescriptorTable(IBindingLayout _layout)
		{
			BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(_layout);

			DescriptorTable ret = new DescriptorTable(m_Context);
			ret.layout = layout;
			ret.capacity = layout.vulkanLayoutBindings[0].descriptorCount;

			/*readonly ref*/ var descriptorSetLayout = ref layout.descriptorSetLayout;
			/*readonly ref*/ var poolSizes = ref layout.descriptorPoolSizeInfo;

			// create descriptor pool to allocate a descriptor from
			var poolInfo = VkDescriptorPoolCreateInfo()
				.setPoolSizeCount(uint32(poolSizes.Count))
				.setPPoolSizes(poolSizes.Ptr)
				.setMaxSets(1);

			VkResult res = vkCreateDescriptorPool(m_Context.device, &poolInfo,
				m_Context.allocationCallbacks,
				&ret.descriptorPool);
			CHECK_VK_FAIL!(res);

			// create the descriptor set
			var descriptorSetAllocInfo = VkDescriptorSetAllocateInfo()
				.setDescriptorPool(ret.descriptorPool)
				.setDescriptorSetCount(1)
				.setPSetLayouts(&descriptorSetLayout);

			res = vkAllocateDescriptorSets(m_Context.device, &descriptorSetAllocInfo,
				&ret.descriptorSet);
			CHECK_VK_FAIL!(res);

			return DescriptorTableHandle.Attach(ret);
		}

		public override void resizeDescriptorTable(IDescriptorTable _descriptorTable, uint32 newSize, bool keepContents)
		{
			Runtime.Assert(newSize <= checked_cast<DescriptorTable, IDescriptorTable>(_descriptorTable).layout.Get<IBindingLayout>().getBindlessDesc().maxCapacity);
			(void)_descriptorTable;
			(void)newSize;
			(void)keepContents;
		}

		public override bool writeDescriptorTable(IDescriptorTable _descriptorTable, BindingSetItem binding)
		{
			DescriptorTable descriptorTable = checked_cast<DescriptorTable, IDescriptorTable>(_descriptorTable);
			BindingLayout layout = checked_cast<BindingLayout, IBindingLayout>(descriptorTable.layout.Get<IBindingLayout>());

			if (binding.slot >= descriptorTable.capacity)
				return false;

			VkResult res;

			// collect all of the descriptor write data
			StaticVector<VkDescriptorImageInfo, const c_MaxBindingsPerLayout> descriptorImageInfo = .();
			StaticVector<VkDescriptorBufferInfo, const c_MaxBindingsPerLayout> descriptorBufferInfo = .();
			StaticVector<VkWriteDescriptorSet, const c_MaxBindingsPerLayout> descriptorWriteInfo = .();

			delegate void(uint32 bindingLocation,
				VkDescriptorType descriptorType,
				VkDescriptorImageInfo* imageInfo,
				VkDescriptorBufferInfo* bufferInfo,
				VkBufferView* bufferView) generateWriteDescriptorData = // generates a VkWriteDescriptorSet struct in descriptorWriteInfo
				scope [&] (bindingLocation,
				descriptorType,
				imageInfo,
				bufferInfo,
				bufferView) =>
				{
					descriptorWriteInfo.PushBack(
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

			for (uint32 bindingLocation = 0; bindingLocation < uint32(layout.bindlessDesc.registerSpaces.Count); bindingLocation++)
			{
				if (layout.bindlessDesc.registerSpaces[bindingLocation].type == binding.type)
				{
					readonly ref VkDescriptorSetLayoutBinding layoutBinding = ref layout.vulkanLayoutBindings[bindingLocation];

					switch (binding.type)
					{
					case ResourceType.Texture_SRV:
						{
							/*readonly ref*/ var texture = checked_cast<Texture, IResource>(binding.resourceHandle);

							readonly var subresource = binding.subresources.resolve(texture.desc, false);
							readonly var textureViewType = getTextureViewType(binding.format, texture.desc.format);
							var view = ref texture.getSubresourceView(subresource, binding.dimension, textureViewType);

							//var& imageInfo = descriptorImageInfo.emplace_back();
							var imageInfo = VkDescriptorImageInfo()
								.setImageView(view.view)
								.setImageLayout(VkImageLayout.eShaderReadOnlyOptimal);

							generateWriteDescriptorData(layoutBinding.binding,
								layoutBinding.descriptorType,
								&imageInfo, null, null);

							descriptorImageInfo.PushBack(imageInfo);
						}

						break;

					case ResourceType.Texture_UAV:
						{
							readonly var texture = checked_cast<Texture, IResource>(binding.resourceHandle);

							readonly var subresource = binding.subresources.resolve(texture.desc, true);
							readonly var textureViewType = getTextureViewType(binding.format, texture.desc.format);
							var view = ref texture.getSubresourceView(subresource, binding.dimension, textureViewType);

							//var& imageInfo = descriptorImageInfo.emplace_back();
							var imageInfo = VkDescriptorImageInfo()
								.setImageView(view.view)
								.setImageLayout(VkImageLayout.eGeneral);

							generateWriteDescriptorData(layoutBinding.binding,
								layoutBinding.descriptorType,
								&imageInfo, null, null);

							descriptorImageInfo.PushBack(imageInfo);
						}

						break;

					case ResourceType.TypedBuffer_SRV: fallthrough;
					case ResourceType.TypedBuffer_UAV:
						{
							/*readonly ref*/ var buffer = checked_cast<Buffer, IResource>(binding.resourceHandle);

							var vkformat = nvrhi.vulkan.convertFormat(binding.format);

							//readonly ref var bufferViewFound = ref buffer.viewCache.find(vkformat);
							//var& bufferViewRef = (bufferViewFound != buffer.viewCache.end()) ? bufferViewFound.second : buffer.viewCache[vkformat];
							if (!buffer.viewCache.ContainsKey(vkformat))
							{
								buffer.viewCache.Add(vkformat, .Null);
							}

							var bufferViewRef = ref buffer.viewCache[vkformat];

							//if (bufferViewFound == buffer.viewCache.end())
							if (bufferViewRef == .Null)
							{
								Runtime.Assert(binding.format != Format.UNKNOWN);
								readonly var range = binding.range.resolve(buffer.desc);

								var bufferViewInfo = VkBufferViewCreateInfo()
									.setBuffer(buffer.buffer)
									.setOffset(range.byteOffset)
									.setRange(range.byteSize)
									.setFormat(vkformat);

								res = vkCreateBufferView(m_Context.device, &bufferViewInfo, m_Context.allocationCallbacks, &bufferViewRef);
								ASSERT_VK_OK!(res);
							}

							generateWriteDescriptorData(layoutBinding.binding,
								layoutBinding.descriptorType,
								null, null, &bufferViewRef);
						}
						break;

					case ResourceType.StructuredBuffer_SRV: fallthrough;
					case ResourceType.StructuredBuffer_UAV: fallthrough;
					case ResourceType.RawBuffer_SRV: fallthrough;
					case ResourceType.RawBuffer_UAV: fallthrough;
					case ResourceType.ConstantBuffer: fallthrough;
					case ResourceType.VolatileConstantBuffer:
						{
							readonly var buffer = checked_cast<Buffer, IResource>(binding.resourceHandle);

							readonly var range = binding.range.resolve(buffer.desc);

							//var& bufferInfo = descriptorBufferInfo.emplace_back();
							var bufferInfo = VkDescriptorBufferInfo()
								.setBuffer(buffer.buffer)
								.setOffset(range.byteOffset)
								.setRange(range.byteSize);

							Runtime.Assert(buffer.buffer != .Null);
							generateWriteDescriptorData(layoutBinding.binding,
								layoutBinding.descriptorType,
								null, &bufferInfo, null);
							descriptorBufferInfo.PushBack(bufferInfo);
						}

						break;

					case ResourceType.Sampler:
						{
							/*readonly ref*/ var sampler = checked_cast<Sampler, IResource>(binding.resourceHandle);

							//var& imageInfo = descriptorImageInfo.emplace_back();
							var imageInfo = VkDescriptorImageInfo()
								.setSampler(sampler.sampler);

							generateWriteDescriptorData(layoutBinding.binding,
								layoutBinding.descriptorType,
								&imageInfo, null, null);
							descriptorImageInfo.PushBack(imageInfo);
						}

						break;

					case ResourceType.RayTracingAccelStruct:
						utils.NotImplemented();
						break;

					case ResourceType.PushConstants:
						utils.NotSupported();
						break;

					case ResourceType.None: fallthrough;
					case ResourceType.Count: fallthrough;
					default:
						utils.InvalidEnum();
					}
				}
			}

			vkUpdateDescriptorSets(m_Context.device, uint32(descriptorWriteInfo.Count), descriptorWriteInfo.Ptr, 0, null);

			return true;
		}

		public override nvrhi.rt.AccelStructHandle createAccelStruct(nvrhi.rt.AccelStructDesc desc)
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
				List<VkAccelerationStructureGeometryKHR> geometries = scope .();
				List<uint32> maxPrimitiveCounts = scope .();

				var buildInfo = VkAccelerationStructureBuildGeometryInfoKHR();

				if (desc.isTopLevel)
				{
					geometries.Add(VkAccelerationStructureGeometryKHR()
						.setGeometryType(VkGeometryTypeKHR.eInstancesKHR));

					geometries[0].geometry.setInstances(VkAccelerationStructureGeometryInstancesDataKHR());

					maxPrimitiveCounts.Add(uint32(desc.topLevelMaxInstances));

					buildInfo.setType(VkAccelerationStructureTypeKHR.eTopLevelKHR);
				}
				else
				{
					geometries.Resize(desc.bottomLevelGeometries.Count);
					maxPrimitiveCounts.Resize(desc.bottomLevelGeometries.Count);

					for (int i = 0; i < desc.bottomLevelGeometries.Count; i++)
					{
						convertBottomLevelGeometry(desc.bottomLevelGeometries[i], ref geometries[i], ref maxPrimitiveCounts[i], null, m_Context);
					}

					buildInfo.setType(VkAccelerationStructureTypeKHR.eBottomLevelKHR);
				}

				buildInfo.setMode(VkBuildAccelerationStructureModeKHR.eBuildKHR)
					.setPGeometries(geometries.Ptr)
					.setFlags(convertAccelStructBuildFlags(desc.buildFlags));

				VkAccelerationStructureBuildSizesInfoKHR buildSizes = .();
				vkGetAccelerationStructureBuildSizesKHR(m_Context,
					VkAccelerationStructureBuildTypeKHR.eDeviceKHR, &buildInfo, maxPrimitiveCounts.Ptr, &buildSizes);

				BufferDesc bufferDesc = .();
				bufferDesc.byteSize = buildSizes.accelerationStructureSize;
				bufferDesc.debugName = desc.debugName;
				bufferDesc.initialState = desc.isTopLevel ? ResourceStates.AccelStructRead : ResourceStates.AccelStructBuildBlas;
				bufferDesc.keepInitialState = true;
				bufferDesc.isAccelStructStorage = true;
				bufferDesc.isVirtual = desc.isVirtual;
				@as.dataBuffer = createBuffer(bufferDesc);

				Buffer dataBuffer = checked_cast<Buffer, IBuffer>(@as.dataBuffer.Get<IBuffer>());

				var createInfo = VkAccelerationStructureCreateInfoKHR()
					.setType(desc.isTopLevel ? VkAccelerationStructureTypeKHR.eTopLevelKHR : VkAccelerationStructureTypeKHR.eBottomLevelKHR)
					.setBuffer(dataBuffer.buffer)
					.setSize(buildSizes.accelerationStructureSize);

				vkCreateAccelerationStructureKHR(m_Context.device, &createInfo, m_Context.allocationCallbacks, &@as.accelStruct);

				if (!desc.isVirtual)
				{
					var addressInfo = VkAccelerationStructureDeviceAddressInfoKHR()
						.setAccelerationStructure(@as.accelStruct);

					@as.accelStructDeviceAddress = vkGetAccelerationStructureDeviceAddressKHR(m_Context.device, &addressInfo);
				}
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
			AccelStruct @as = checked_cast<AccelStruct, nvrhi.rt.IAccelStruct>(_as);

			if (@as.dataBuffer != null)
				return getBufferMemoryRequirements(@as.dataBuffer);

			return MemoryRequirements();
		}

		public override bool bindAccelStructMemory(nvrhi.rt.IAccelStruct _as, IHeap heap, uint64 offset)
		{
			AccelStruct @as = checked_cast<AccelStruct, nvrhi.rt.IAccelStruct>(_as);

			if (@as.dataBuffer == null)
				return false;

			readonly bool bound = bindBufferMemory(@as.dataBuffer, heap, offset);

			if (bound)
			{
				var addressInfo = VkAccelerationStructureDeviceAddressInfoKHR()
					.setAccelerationStructure(@as.accelStruct);

				@as.accelStructDeviceAddress = vkGetAccelerationStructureDeviceAddressKHR(m_Context.device, &addressInfo);
			}

			return bound;
		}

		public override CommandListHandle createCommandList(CommandListParameters @params = .())
		{
			if (m_Queues[uint32(@params.queueType)] == null)
				return null;

			CommandList cmdList = new CommandList(this, m_Context, @params);

			return CommandListHandle.Attach(cmdList);
		}

		public override uint64 executeCommandLists(Span<ICommandList> pCommandLists, CommandQueue executionQueue = .Graphics)
		{
			Queue queue = m_Queues[uint32(executionQueue)];

			uint64 submissionID = queue.submit(pCommandLists.Ptr, pCommandLists.Length);

			for (int i = 0; i < pCommandLists.Length; i++)
			{
				checked_cast<CommandList, ICommandList>(pCommandLists[i]).executed(queue, submissionID);
			}

			return submissionID;
		}

		public override void queueWaitForCommandList(CommandQueue waitQueueID, CommandQueue executionQueueID, uint64 instance)
		{
			queueWaitForSemaphore(waitQueueID, getQueueSemaphore(executionQueueID), instance);
		}

		public override void waitForIdle()
		{
			vkDeviceWaitIdle(m_Context.device);
		}

		public override void runGarbageCollection()
		{
			for (var m_Queue in m_Queues)
			{
				if (m_Queue != null)
				{
					m_Queue.retireCommandBuffers();
				}
			}
		}

		public override bool queryFeatureSupport(Feature feature, void* pInfo = null, int infoSize = 0)
		{
			switch (feature) // NOLINT(clang-diagnostic-switch-enum)
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
				if (pInfo != null)
				{
					if (infoSize == sizeof(VariableRateShadingFeatureInfo))
					{
						var pVrsInfo = (VariableRateShadingFeatureInfo*)(pInfo);
						/*readonly ref*/ var tileExtent = ref m_Context.shadingRateProperties.minFragmentShadingRateAttachmentTexelSize;
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


		public override FormatSupport queryFormatSupport(Format format)
		{
			VkFormat vulkanFormat = convertFormat(format);

			VkFormatProperties props = .();
			vkGetPhysicalDeviceFormatProperties(m_Context.physicalDevice, vulkanFormat, &props);

			FormatSupport result = FormatSupport.None;

			if (props.bufferFeatures != .None)
				result = result | FormatSupport.Buffer;

			if (format == Format.R32_UINT || format == Format.R16_UINT)
			{
				// There is no explicit bit in VkFormatFeatureFlags for index buffers
				result = result | FormatSupport.IndexBuffer;
			}

			if (props.bufferFeatures & VkFormatFeatureFlags.eVertexBufferBit != 0)
				result = result | FormatSupport.VertexBuffer;

			if (props.optimalTilingFeatures != .None)
				result = result | FormatSupport.Texture;

			if (props.optimalTilingFeatures & VkFormatFeatureFlags.eDepthStencilAttachmentBit != 0)
				result = result | FormatSupport.DepthStencil;

			if (props.optimalTilingFeatures & VkFormatFeatureFlags.eColorAttachmentBit != 0)
				result = result | FormatSupport.RenderTarget;

			if (props.optimalTilingFeatures & VkFormatFeatureFlags.eColorAttachmentBlendBit != 0)
				result = result | FormatSupport.Blendable;

			if ((props.optimalTilingFeatures & VkFormatFeatureFlags.eSampledImageBit != 0) ||
				(props.bufferFeatures & VkFormatFeatureFlags.eUniformTexelBufferBit != 0))
			{
				result = result | FormatSupport.ShaderLoad;
			}

			if (props.optimalTilingFeatures & VkFormatFeatureFlags.eSampledImageFilterLinearBit != 0)
				result = result | FormatSupport.ShaderSample;

			if ((props.optimalTilingFeatures & VkFormatFeatureFlags.eStorageImageBit != 0) ||
				(props.bufferFeatures & VkFormatFeatureFlags.eStorageTexelBufferBit != 0))
			{
				result = result | FormatSupport.ShaderUavLoad;
				result = result | FormatSupport.ShaderUavStore;
			}

			if ((props.optimalTilingFeatures & VkFormatFeatureFlags.eStorageImageAtomicBit != 0) ||
				(props.bufferFeatures & VkFormatFeatureFlags.eStorageTexelBufferAtomicBit != 0))
			{
				result = result | FormatSupport.ShaderAtomic;
			}

			return result;
		}

		public override NativeObject getNativeQueue(ObjectType objectType, CommandQueue queue)
		{
			if (objectType != ObjectType.VK_Queue)
				return null;

			if (queue >= CommandQueue.Count)
				return null;

			return NativeObject(m_Queues[uint32(queue)].getVkQueue());
		}

		public override IMessageCallback getMessageCallback()  { return m_Context.messageCallback; }

		// nvrhi.vulkanIDevice implementation
		public override VkSemaphore getQueueSemaphore(CommandQueue queueID)
		{
			Queue queue = m_Queues[uint32(queueID)];

			return queue.trackingSemaphore;
		}
		public override void queueWaitForSemaphore(CommandQueue waitQueueID, VkSemaphore semaphore, uint64 value)
		{
			Queue waitQueue = m_Queues[uint32(waitQueueID)];

			waitQueue.addWaitSemaphore(semaphore, value);
		}

		public override void queueSignalSemaphore(CommandQueue executionQueueID, VkSemaphore semaphore, uint64 value)
		{
			Queue executionQueue = m_Queues[uint32(executionQueueID)];

			executionQueue.addSignalSemaphore(semaphore, value);
		}

		public override uint64 queueGetCompletedInstance(CommandQueue queue)
		{
			uint64 value = 0;
			VkResult  res =  vkGetSemaphoreCounterValue(m_Context.device, getQueueSemaphore(queue), &value);
			ASSERT_VK_OK!(res);

			return value;
		}

		public override FramebufferHandle createHandleForNativeFramebuffer(VkRenderPass renderPass, VkFramebuffer framebuffer,
			FramebufferDesc desc, bool transferOwnership)
		{
			Framebuffer fb = new Framebuffer(m_Context);
			fb.desc = desc;
			fb.framebufferInfo = FramebufferInfo(desc);
			fb.renderPass = renderPass;
			fb.framebuffer = framebuffer;
			fb.managed = transferOwnership;

			for ( /*readonly ref*/var rt in ref desc.colorAttachments)
			{
				if (rt.valid())
					fb.resources.Add(rt.texture);
			}

			if (desc.depthAttachment.valid())
			{
				fb.resources.Add(desc.depthAttachment.texture);
			}

			return FramebufferHandle.Attach(fb);
		}


		private VulkanContext* m_Context;
		private VulkanAllocator m_Allocator;

		private VkQueryPool m_TimerQueryPool = null;
		private nvrhi.utils.BitSetAllocator m_TimerQueryAllocator;

		private Monitor m_Mutex = new .() ~ delete _;

		// array of submission queues
		private Queue[(uint32)CommandQueue.Count] m_Queues = .();

		private void* mapBuffer(IBuffer _buffer, CpuAccessMode flags, uint64 offset, int size)
		{
			Buffer buffer = checked_cast<Buffer, IBuffer>(_buffer);

			Runtime.Assert(flags != CpuAccessMode.None);

			// If the buffer has been used in a command list before, wait for that CL to complete
			if (buffer.lastUseCommandListID != 0)
			{
				var queue = m_Queues[uint32(buffer.lastUseQueue)];
				queue.waitCommandList(buffer.lastUseCommandListID, ~0uL);
			}

			VkAccessFlags accessFlags;

			switch (flags)
			{
			case CpuAccessMode.Read:
				accessFlags = VkAccessFlags.eHostReadBit;
				break;

			case CpuAccessMode.Write:
				accessFlags = VkAccessFlags.eHostWriteBit;
				break;

			case CpuAccessMode.None:
			default:
				utils.InvalidEnum();
				break;
			}

			// TODO: there should be a barrier... But there can't be a command list here
			// buffer.barrier(cmd, VkPipelineStageFlagBits.eHost, accessFlags);

			void* ptr = null;
			readonly VkResult res = vkMapMemory(m_Context.device, buffer.memory, offset, (.)size, 0, &ptr);
			Runtime.Assert(res == VkResult.eVkSuccess);

			return ptr;
		}
	}
}