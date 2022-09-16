using Bulkan;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	class DescriptorTableVK : RefCounter<IDescriptorTable>
	{
		public BindingLayoutHandle layout;
		public uint32 capacity = 0;

		public VkDescriptorPool descriptorPool;
		public VkDescriptorSet descriptorSet;

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
		public override BindingSetDesc* getDesc() { return null; }
		public override IBindingLayout getLayout()  { return layout; }
		public override uint32 getCapacity()  { return capacity; }
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