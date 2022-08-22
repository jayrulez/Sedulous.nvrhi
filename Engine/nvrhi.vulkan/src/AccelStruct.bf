using System.Collections;
using Bulkan;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	class AccelStruct : RefCounter<nvrhi.rt.IAccelStruct>
	{
		public BufferHandle dataBuffer;
		public List<VkAccelerationStructureInstanceKHR> instances;
		public VkAccelerationStructureKHR accelStruct;
		public VkDeviceAddress accelStructDeviceAddress = 0;
		public nvrhi.rt.AccelStructDesc desc;
		public bool allowUpdate = false;
		public bool compacted = false;
		public int rtxmuId = (.)~0uL;
		public VkBuffer rtxmuBuffer;


		public this(VulkanContext* context)
		{
			m_Context = context;
		}

		public ~this()
		{
			#if NVRHI_WITH_RTXMU
			bool isManaged = desc.isTopLevel;
#else
			bool isManaged = true;
#endif

			if (accelStruct != .Null && isManaged)
			{
				vkDestroyAccelerationStructureKHR(m_Context.device, accelStruct, m_Context.allocationCallbacks);
				accelStruct = null;
			}
		}

		public override NativeObject getNativeObject(ObjectType objectType)
		{
			switch (objectType)
			{
			case ObjectType.VK_Buffer: fallthrough;
			case ObjectType.VK_DeviceMemory:
				if (dataBuffer != null)
					return dataBuffer->getNativeObject(objectType);
				return null;
			case ObjectType.VK_AccelerationStructureKHR:
				return NativeObject(accelStruct);
			default:
				return null;
			}
		}
		public override readonly ref nvrhi.rt.AccelStructDesc getDesc() { return ref desc; }
		public override bool isCompacted()  { return compacted; }
		public override uint64 getDeviceAddress()
		{
#if NVRHI_WITH_RTXMU
			if (!desc.isTopLevel)
				return m_Context.rtxMemUtil.GetDeviceAddress(rtxmuId);
#endif
			return getBufferAddress(dataBuffer, 0).deviceAddress;
		}

		private VulkanContext* m_Context;
	}
}