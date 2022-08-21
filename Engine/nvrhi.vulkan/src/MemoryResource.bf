using Bulkan;
namespace nvrhi.vulkan
{
	interface MemoryResource
	{
		public bool managed { get; set; }
		public ref VkDeviceMemory memory { get; set; }
	}
}