namespace nvrhi.vulkan
{
	class HeapVK : MemoryResourceVK, nvrhi.RefCounter<IHeap>
	{
		public this(VulkanContext* context, VulkanAllocator allocator)
		{
			m_Context = context;
			m_Allocator = allocator;
		}

		public ~this()
		{
			if (memory != .Null && managed)
			{
				m_Allocator.freeMemory(this);
				memory = .Null;
			}
		}

		public HeapDesc desc;

		public override readonly ref HeapDesc getDesc() { return ref desc; }

		private VulkanContext* m_Context;
		private VulkanAllocator m_Allocator;

		public bool managed { get; set; }

		public ref Bulkan.VkDeviceMemory memory { get; set; }
	}
}