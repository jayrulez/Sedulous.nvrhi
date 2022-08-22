using Bulkan;
using System.Collections;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	// contains a VkDescriptorSet
	class BindingSet : RefCounter<IBindingSet>
	{
		public BindingSetDesc desc;
		public BindingLayoutHandle layout;

		// TODO: move pool to the context instead
		public VkDescriptorPool descriptorPool;
		public VkDescriptorSet descriptorSet;

		public List<ResourceHandle> resources;
		public StaticVector<Buffer, const c_MaxVolatileConstantBuffersPerLayout> volatileConstantBuffers;

		public List<uint16> bindingsThatNeedTransitions;

		public this(VulkanContext* context)
			{ m_Context = context; }

		public ~this()
		{
			if (descriptorPool != .Null)
			{
				vkDestroyDescriptorPool(m_Context.device, descriptorPool, m_Context.allocationCallbacks);
				descriptorPool = .Null;
				descriptorSet = .Null;
			}
		}
		public override BindingSetDesc* getDesc()  { return &desc; }
		public override IBindingLayout getLayout()  { return layout; }
		public override NativeObject getNativeObject(ObjectType objectType)
		{
			switch (objectType)
			{
			case ObjectType.VK_DescriptorPool:
				return NativeObject(descriptorPool);
			case ObjectType.VK_DescriptorSet:
				return NativeObject(descriptorSet);
			default:
				return null;
			}
		}

		private VulkanContext* m_Context;
	}
}