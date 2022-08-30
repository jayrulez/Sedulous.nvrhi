using Bulkan;
using System.Collections;
using System;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	class Buffer : MemoryResource, RefCounter<IBuffer>, BufferStateExtension
	{
		public BufferDesc desc;

		public VkBuffer buffer;
		public VkDeviceAddress deviceAddress = 0;

		public HeapHandle heap;

		public Dictionary<VkFormat, VkBufferView> viewCache;

		public List<BufferVersionItem> versionTracking;
		public void* mappedMemory = null;
		public uint32 versionSearchStart = 0;

		// For staging buffers only
		public CommandQueue lastUseQueue = CommandQueue.Graphics;
		public uint64 lastUseCommandListID = 0;

		public this(VulkanContext* context, VulkanAllocator allocator)
		{
			m_Context = context;
			m_Allocator = allocator;
		}

		public ~this()
		{
			if (mappedMemory != null)
			{
				vkUnmapMemory(m_Context.device, memory);
				mappedMemory = null;
			}

			for (var iter in viewCache)
			{
				vkDestroyBufferView(m_Context.device, iter.value, m_Context.allocationCallbacks);
			}

			viewCache.Clear();

			if (managed)
			{
				Runtime.Assert(buffer != .Null);

				vkDestroyBuffer(m_Context.device, buffer, m_Context.allocationCallbacks);
				buffer = .Null;

				if (memory != .Null)
				{
					m_Allocator.freeBufferMemory(this);
					memory = .Null;
				}
			}
		}

		public override readonly ref BufferDesc getDesc() { return ref desc; }
		public override NativeObject getNativeObject(ObjectType objectType)
		{
			switch (objectType)
			{
			case ObjectType.VK_Buffer:
				return NativeObject(buffer);
			case ObjectType.VK_DeviceMemory:
				return NativeObject(memory);
			default:
				return null;
			}
		}

		private VulkanContext* m_Context;
		private VulkanAllocator m_Allocator;

		public ResourceStates permanentState { get; set; } = .Unknown;

		public bool stateInitialized { get; set; } = false;

		public bool managed { get; set; } = true;

		public ref VkDeviceMemory memory { get; set; } = .Null;

		public override int GetHashCode()
		{
			return (int)(Internal.UnsafeCastToPtr(this));
		}
	}
}