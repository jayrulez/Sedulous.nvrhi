using Bulkan;
namespace nvrhi.vulkan
{
	public static
	{
		public static nvrhi.vulkan.DeviceHandle createDevice(DeviceDesc desc)
		{
			// todo: initialization stuff
			// instance
			// device

			Device device = new Device(desc);
			return nvrhi.vulkan.DeviceHandle.Attach(device);
		}

		public static VkMemoryPropertyFlags pickBufferMemoryProperties(BufferDesc d)
		{
			VkMemoryPropertyFlags flags = .None;

			switch (d.cpuAccess)
			{
			case CpuAccessMode.None:
				flags = VkMemoryPropertyFlags.eDeviceLocalBit;
				break;
			case CpuAccessMode.Read:
				flags = VkMemoryPropertyFlags.eHostVisibleBit | VkMemoryPropertyFlags.eHostCachedBit;
				break;
			case CpuAccessMode.Write:
				flags = VkMemoryPropertyFlags.eHostVisibleBit;
				break;
			}

			return flags;
		}
	}
}