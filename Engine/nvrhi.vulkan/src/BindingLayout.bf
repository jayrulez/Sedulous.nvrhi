using System.Collections;
using Bulkan;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	class BindingLayout : /*RefCounter<IBindingLayout>*/ IBindingLayout
	{
		public BindingLayoutDesc desc;
		public BindlessLayoutDesc bindlessDesc;
		public bool isBindless;

		public List<VkDescriptorSetLayoutBinding> vulkanLayoutBindings;

		public VkDescriptorSetLayout descriptorSetLayout;

		// descriptor pool size information per binding set
		public List<VkDescriptorPoolSize> descriptorPoolSizeInfo;

		public this(VulkanContext* context, BindingLayoutDesc _desc)
		{
			desc = _desc;
			isBindless = false;
			m_Context = context;

			VkShaderStageFlags shaderStageFlags = convertShaderTypeToShaderStageFlagBits(desc.visibility);

			// iterate over all binding types and add to map
			for (readonly ref BindingLayoutItem binding in ref desc.bindings)
			{
				VkDescriptorType descriptorType;
				uint32 descriptorCount = 1;
				uint32 registerOffset;

				switch (binding.type)
				{
				case ResourceType.Texture_SRV:
					registerOffset = _desc.bindingOffsets.shaderResource;
					descriptorType = VkDescriptorType.eSampledImage;
					break;

				case ResourceType.Texture_UAV:
					registerOffset = _desc.bindingOffsets.unorderedAccess;
					descriptorType = VkDescriptorType.eStorageImage;
					break;

				case ResourceType.TypedBuffer_SRV:
					registerOffset = _desc.bindingOffsets.shaderResource;
					descriptorType = VkDescriptorType.eUniformTexelBuffer;
					break;

				case ResourceType.StructuredBuffer_SRV: fallthrough;
				case ResourceType.RawBuffer_SRV:
					registerOffset = _desc.bindingOffsets.shaderResource;
					descriptorType = VkDescriptorType.eStorageBuffer;
					break;

				case ResourceType.TypedBuffer_UAV:
					registerOffset = _desc.bindingOffsets.unorderedAccess;
					descriptorType = VkDescriptorType.eStorageTexelBuffer;
					break;

				case ResourceType.StructuredBuffer_UAV: fallthrough;
				case ResourceType.RawBuffer_UAV:
					registerOffset = _desc.bindingOffsets.unorderedAccess;
					descriptorType = VkDescriptorType.eStorageBuffer;
					break;

				case ResourceType.ConstantBuffer:
					registerOffset = _desc.bindingOffsets.constantBuffer;
					descriptorType = VkDescriptorType.eUniformBuffer;
					break;

				case ResourceType.VolatileConstantBuffer:
					registerOffset = _desc.bindingOffsets.constantBuffer;
					descriptorType = VkDescriptorType.eUniformBufferDynamic;
					break;

				case ResourceType.Sampler:
					registerOffset = _desc.bindingOffsets.sampler;
					descriptorType = VkDescriptorType.eSampler;
					break;

				case ResourceType.PushConstants:
					// don't need any descriptors for the push constants, but the vulkanLayoutBindings array 
					// must match the binding layout items for further processing within nvrhi --
					// so set descriptorCount to 0 instead of skipping it
					registerOffset = _desc.bindingOffsets.constantBuffer;
					descriptorType = VkDescriptorType.eUniformBuffer;
					descriptorCount = 0;
					break;

				case ResourceType.RayTracingAccelStruct:
					registerOffset = _desc.bindingOffsets.shaderResource;
					descriptorType = VkDescriptorType.eAccelerationStructureKHR;
					break;

				case ResourceType.None: fallthrough;
				case ResourceType.Count: fallthrough;
				default:
					utils.InvalidEnum();
					continue;
				}

				readonly var bindingLocation = registerOffset + binding.slot;

				VkDescriptorSetLayoutBinding descriptorSetLayoutBinding = VkDescriptorSetLayoutBinding()
					.setBinding(bindingLocation)
					.setDescriptorCount(descriptorCount)
					.setDescriptorType(descriptorType)
					.setStageFlags(shaderStageFlags);

				vulkanLayoutBindings.Add(descriptorSetLayoutBinding);
			}
		}

		public this(VulkanContext* context, BindlessLayoutDesc _desc)
		{
			bindlessDesc = _desc;
			isBindless = true;
			m_Context = context;

			desc.visibility = bindlessDesc.visibility;
			VkShaderStageFlags shaderStageFlags = convertShaderTypeToShaderStageFlagBits(bindlessDesc.visibility);
			uint32 bindingPoint = 0;
			uint32 arraySize = bindlessDesc.maxCapacity;

			// iterate over all binding types and add to map
			for (readonly ref BindingLayoutItem space in ref bindlessDesc.registerSpaces)
			{
				VkDescriptorType descriptorType;

				switch (space.type)
				{
				case ResourceType.Texture_SRV:
					descriptorType = VkDescriptorType.eSampledImage;
					break;

				case ResourceType.Texture_UAV:
					descriptorType = VkDescriptorType.eStorageImage;
					break;

				case ResourceType.TypedBuffer_SRV:
					descriptorType = VkDescriptorType.eUniformTexelBuffer;
					break;

				case ResourceType.TypedBuffer_UAV:
					descriptorType = VkDescriptorType.eStorageTexelBuffer;
					break;

				case ResourceType.StructuredBuffer_SRV: fallthrough;
				case ResourceType.StructuredBuffer_UAV: fallthrough;
				case ResourceType.RawBuffer_SRV: fallthrough;
				case ResourceType.RawBuffer_UAV:
					descriptorType = VkDescriptorType.eStorageBuffer;
					break;

				case ResourceType.ConstantBuffer:
					descriptorType = VkDescriptorType.eUniformBuffer;
					break;

				case ResourceType.VolatileConstantBuffer:
					m_Context.error("Volatile constant buffers are not supported in bindless layouts");
					descriptorType = VkDescriptorType.eUniformBufferDynamic;
					break;

				case ResourceType.Sampler:
					descriptorType = VkDescriptorType.eSampler;
					break;

				case ResourceType.PushConstants:
					continue;

				case ResourceType.RayTracingAccelStruct:
					descriptorType = VkDescriptorType.eAccelerationStructureKHR;
					break;

				case ResourceType.None: fallthrough;
				case ResourceType.Count: fallthrough;
				default:
					utils.InvalidEnum();
					continue;
				}

				VkDescriptorSetLayoutBinding descriptorSetLayoutBinding = VkDescriptorSetLayoutBinding()
					.setBinding(bindingPoint)
					.setDescriptorCount(arraySize)
					.setDescriptorType(descriptorType)
					.setStageFlags(shaderStageFlags);

				vulkanLayoutBindings.Add(descriptorSetLayoutBinding);

				++bindingPoint;
			}
		}
		public ~this()
		{
			if (descriptorSetLayout != .Null)
			{
				vkDestroyDescriptorSetLayout(m_Context.device, descriptorSetLayout, m_Context.allocationCallbacks);
				descriptorSetLayout = .Null;
			}
		}
		public override BindingLayoutDesc* getDesc()  { return isBindless ? null : &desc; }
		public override BindlessLayoutDesc* getBindlessDesc() { return isBindless ? &bindlessDesc : null; }
		public override NativeObject getNativeObject(ObjectType objectType)
		{
			switch (objectType)
			{
			case ObjectType.VK_DescriptorSetLayout:
				return NativeObject(descriptorSetLayout);
			default:
				return null;
			}
		}

		// generate the descriptor set layout
		public VkResult bake()
		{
			// create the descriptor set layout object

			var descriptorSetLayoutInfo = VkDescriptorSetLayoutCreateInfo()
				.setBindingCount(uint32(vulkanLayoutBindings.Count))
				.setPBindings(vulkanLayoutBindings.Ptr);

			List<VkDescriptorBindingFlags> bindFlag = scope .() { Count = vulkanLayoutBindings.Count }..Fill(VkDescriptorBindingFlags.ePartiallyBoundBit);

			var extendedInfo = VkDescriptorSetLayoutBindingFlagsCreateInfo()
				.setBindingCount(uint32(vulkanLayoutBindings.Count))
				.setPBindingFlags(bindFlag.Ptr);

			if (isBindless)
			{
				descriptorSetLayoutInfo.setPNext(&extendedInfo);
			}

			readonly VkResult res = vkCreateDescriptorSetLayout(m_Context.device, &descriptorSetLayoutInfo,
				m_Context.allocationCallbacks,
				&descriptorSetLayout);
			CHECK_VK_RETURN!(res);

			// count the number of descriptors required per type
			Dictionary<VkDescriptorType, uint32> poolSizeMap = scope .();
			for (var layoutBinding in vulkanLayoutBindings)
			{
				if (!poolSizeMap.ContainsKey(layoutBinding.descriptorType))
				{
					poolSizeMap[layoutBinding.descriptorType] = 0;
				}

				poolSizeMap[layoutBinding.descriptorType] += layoutBinding.descriptorCount;
			}

			// compute descriptor pool size info
			for (var poolSizeIter in poolSizeMap)
			{
				if (poolSizeIter.value > 0)
				{
					descriptorPoolSizeInfo.Add(VkDescriptorPoolSize()
						.setType(poolSizeIter.key)
						.setDescriptorCount(poolSizeIter.value));
				}
			}

			return VkResult.eVkSuccess;
		}

		private VulkanContext* m_Context;
	}
}