using Bulkan;
namespace nvrhi.vulkan
{
	interface MemoryResourceVK
	{
		public bool managed { get; set; }
		public ref VkDeviceMemory memory { get; set; }
	}
}