using Bulkan;
using System.Collections;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	// command buffer with resource tracking
	class TrackedCommandBuffer
	{
		// the command buffer itself
		public VkCommandBuffer cmdBuf = .Null;
		public VkCommandPool cmdPool = .Null;

		public List<RefCountPtr<IResource>> referencedResources = new .() ~ delete _; // to keep them alive
		public List<RefCountPtr<Buffer>> referencedStagingBuffers = new .() ~ delete _; // to allow synchronous mapBuffer

		public uint64 recordingID = 0;
		public uint64 submissionID = 0;

#if NVRHI_WITH_RTXMU
		List<uint64> rtxmuBuildIds;
		List<uint64> rtxmuCompactionIds;
#endif

		public  this(VulkanContext* context)
			{ m_Context = context; }

		public ~this()
		{
			vkDestroyCommandPool(m_Context.device, cmdPool, m_Context.allocationCallbacks);
		}

		private VulkanContext* m_Context;
	}

	typealias TrackedCommandBufferPtr = TrackedCommandBuffer;
}