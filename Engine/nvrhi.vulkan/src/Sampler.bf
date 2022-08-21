using Bulkan;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	class Sampler : /*RefCounter<ISampler>*/ ISampler
	{
		public SamplerDesc desc;

		public VkSamplerCreateInfo samplerInfo;
		public VkSampler sampler;

		public this(VulkanContext* context)
			{ m_Context = context; }

		public ~this()
		{
			vkDestroySampler(m_Context.device, sampler, m_Context.allocationCallbacks);
		}
		public override readonly ref SamplerDesc getDesc()  { return ref desc; }
		public override NativeObject getNativeObject(ObjectType objectType)
		{
			switch (objectType)
			{
			case ObjectType.VK_Sampler:
				return NativeObject(sampler);
			default:
				return null;
			}
		}

		private VulkanContext* m_Context;
	}
}