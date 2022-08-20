using Bulkan;
namespace nvrhi
{
	extension ObjectType
	{
		case Nvrhi_VK_Device = 0x00030101;
	}
}

namespace nvrhi.vulkan
{
	abstract class IDevice :  nvrhi.IDevice
	{
		// Additional Vulkan-specific public methods
		public abstract VkSemaphore getQueueSemaphore(CommandQueue queue);
		public abstract void queueWaitForSemaphore(CommandQueue waitQueue, VkSemaphore semaphore, uint64 value);
		public abstract void queueSignalSemaphore(CommandQueue executionQueue, VkSemaphore semaphore, uint64 value);
		public abstract uint64 queueGetCompletedInstance(CommandQueue queue);
		public abstract FramebufferHandle createHandleForNativeFramebuffer(VkRenderPass renderPass,
			VkFramebuffer framebuffer, FramebufferDesc desc, bool transferOwnership);
	}

	typealias DeviceHandle = RefCountPtr<nvrhi.vulkan.IDevice>;
}