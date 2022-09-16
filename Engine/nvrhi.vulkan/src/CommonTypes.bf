using Bulkan;
using System.Collections;
using System;
using System.Threading;

namespace nvrhi
{
	extension ObjectType
	{
		case VK_Device                              = 0x00030001;
		case VK_PhysicalDevice                      = 0x00030002;
		case VK_Instance                            = 0x00030003;
		case VK_Queue                               = 0x00030004;
		case VK_CommandBuffer                       = 0x00030005;
		case VK_DeviceMemory                        = 0x00030006;
		case VK_Buffer                              = 0x00030007;
		case VK_Image                               = 0x00030008;
		case VK_ImageView                           = 0x00030009;
		case VK_AccelerationStructureKHR            = 0x0003000a;
		case VK_Sampler                             = 0x0003000b;
		case VK_ShaderModule                        = 0x0003000c;
		case VK_RenderPass                          = 0x0003000d;
		case VK_Framebuffer                         = 0x0003000e;
		case VK_DescriptorPool                      = 0x0003000f;
		case VK_DescriptorSetLayout                 = 0x00030010;
		case VK_DescriptorSet                       = 0x00030011;
		case VK_PipelineLayout                      = 0x00030012;
		case VK_Pipeline                            = 0x00030013;

		
		case Nvrhi_VK_Device = 0x00030101;
	}
}

namespace nvrhi.vulkan
{
	abstract class IDeviceVK :  nvrhi.IDevice
	{
		// Additional Vulkan-specific public methods
		public abstract VkSemaphore getQueueSemaphore(CommandQueue queue);
		public abstract void queueWaitForSemaphore(CommandQueue waitQueue, VkSemaphore semaphore, uint64 value);
		public abstract void queueSignalSemaphore(CommandQueue executionQueue, VkSemaphore semaphore, uint64 value);
		public abstract uint64 queueGetCompletedInstance(CommandQueue queue);
		public abstract FramebufferHandle createHandleForNativeFramebuffer(VkRenderPass renderPass,
			VkFramebuffer framebuffer, FramebufferDesc desc, bool transferOwnership);
	}

	typealias DeviceHandle = RefCounter<nvrhi.vulkan.IDeviceVK>;

	struct ResourceStateMapping : this(ResourceStates nvrhiState, VkPipelineStageFlags stageFlags, VkAccessFlags accessMask, VkImageLayout imageLayout)
	{
	}

	#if NVRHI_WITH_RTXMU
	struct RtxMuResources
	{
		public List<uint64> asBuildsCompleted;
		public Monitor asListMutex;
	}
#endif

	struct TextureSubresourceView
	{
		public TextureVK texture;
		public TextureSubresourceSet subresource = .();

		public VkImageView view = null;
		public VkImageSubresourceRange subresourceRange = .();

		public this(TextureVK texture)
		{
			this.texture = texture;
		}

		public static bool operator ==(TextureSubresourceView a, TextureSubresourceView other)
		{
			return a.texture == other.texture &&
				a.subresource == other.subresource &&
				a.view == other.view &&
				a.subresourceRange == other.subresourceRange;
		}
	}


	/* ----------------------------------------------------------------------------

	The volatile buffer implementation needs some explanation, might as well be here.

	The implementation is designed around a few constraints and assumptions:

	1.  Need to efficiently represent them with core Vulkan API with minimal overhead.
		This rules out a few options:

		- Can't use regular descriptors and update the references to each volatile CB
		  in every descriptor set. That would require versioning of the descriptor
		  sets and tracking of every use of volatile CBs.
		- Can't use push descriptors (vkCmdPushDescriptorSetKHR) because they are not
		  in core Vulkan and are not supported by e.g. AMD drivers at this time. This
		  rules out the DX12 style approach where an upload manager is assigned to a
		  command list and creates buffers as needed - because then one volatile CB
		  might be using different buffer objects for different versions.
		- Any other options that I missed?...

		The only option left is dynamic descriptors. You create a UBO descriptor that
		points to a buffer and then bind it with different offsets within that buffer.
		So all the versions of a volatile CB must live in the same buffer because the
		descriptor may be baked into multiple descriptor sets.

	2.  A volatile buffer may be written into from different command lists, potentially
		those which are recorded concurrently or out of order, and then executed on
		different queues.

		This requirement makes it impossible to put different versions of a CB into a
		single buffer in a round-robin fashion and track their completion with chunks.
		Tracking must be more fine-grained.

	3.  The version tracking implementation should be efficient, which means we shouldn't
		do things like allocating tracking objects for each version or pooling them
		for reuse, and keep iterating over many buffers or versions to a minimum.

	The system designed with these characteristics in mind is following.

	Every volatile buffer has a fixed maximum number of versions specified at creation,
	see BufferDesc::maxVersions. For a typical once-per-frame render pass, something
	like 3-4 versions should be sufficient. Iterative passes may need more, or should
	avoid using volatile CBs in that fashion and switch to push constants or maybe
	structured buffers.

	For each version of a buffer, a tracking object is stored in the Buffer::versionTracking
	array. The object is just a 64-bit word, which contains a bitfield: 

		- c_VersionSubmittedFlag means that the version is used in a submitted 
			command list;

		- (queue & c_VersionQueueMask << c_VersionQueueShift) is the queue index, 
			see nvrhi.CommandQueue for values;

		- (id & c_VersionIDMask) is the instance ID of the command list, either 
			pending or submitted. If pending, it matches the recordingID field of 
			TrackedCommandBuffer, otherwise the submissionID.

	When a buffer version is allocated, it is transitioned into the pending state.
	When the command list containing such pending versions is submitted, all the
	pending versions are transitioned to the submitted state. In the submitted 
	state, they may be reused later if that submitted instance of the command list
	has finished executing, which is determined based on the queue's semaphore.
	Pending versions cannot be reused. Also, pending versions might be transitioned
	to the available state (tracking word == 0) if their command list is abandoned,
	but that is currently not implemented.

	See also:
		- CommandList::writeVolatileBuffer
		- CommandList::flushVolatileBufferWrites
		- CommandList::submitVolatileBuffers

	-----------------------------------------------------------------------------*/


	struct VolatileBufferState
	{
		public int32 latestVersion = 0;
		public int32 minVersion = 0;
		public int32 maxVersion = 0;
		public bool initialized = false;
	}

	// A copyable version of std::atomic to be used in an List
	/*class BufferVersionItem :  std::atomic<uint64>  // NOLINT(cppcoreguidelines-special-member-functions)
	{
	public:
		BufferVersionItem()
			: std::atomic<uint64>()
		{ }

		BufferVersionItem(const BufferVersionItem& other)
		{
			store(other);
		}

		BufferVersionItem& operator=(const uint64 a)
		{
			store(a);
			return *this;
		}
	}*/

	struct BufferVersionItem
	{
		public static implicit operator uint64(Self self) => self.mValue;

		public bool CompareAndExchangeWeak(uint64 original, uint64 @new) mut
		{
			using (mMonitor.Enter())
			{
				return Interlocked.CompareStoreWeak(ref mValue, original, @new);
			}
		}

		public bool CompareAndExchangeStrong(uint64 original, uint64 @new) mut
		{
			using (mMonitor.Enter())
			{
				return Interlocked.CompareExchange(ref mValue, original, @new) == original;
			}
		}

		private uint64 mValue = 0;

		private static Monitor mMonitor = new .() ~ delete _;
	}

	// offset, size in bytes
	struct StagingTextureRegion : this(int64 offset, int size)
	{
	}

	struct BufferChunk
	{
		public BufferHandle buffer;
		public uint64 version = 0;
		public uint64 bufferSize = 0;
		public uint64 writePointer = 0;
		public void* mappedMemory = null;

		public const uint64 c_sizeAlignment = 4096; // GPU page size
	}





	typealias BindingVector<T> = StaticVector<T, const c_MaxBindingLayouts>;
    typealias AttachmentVector<T> = nvrhi.StaticVector<T, const c_MaxRenderTargets + 1>; // render targets + depth

	struct DeviceDesc
	{
	    public IMessageCallback errorCB = null;

	    public VkInstance instance;
	    public VkPhysicalDevice physicalDevice;
	    public VkDevice device;

	    // any of the queues can be null if this context doesn't intend to use them
	    public VkQueue graphicsQueue;
	    public int32 graphicsQueueIndex = -1;
	    public VkQueue transferQueue;
	    public int32 transferQueueIndex = -1;
	    public VkQueue computeQueue;
	    public int32 computeQueueIndex = -1;

	    public VkAllocationCallbacks *allocationCallbacks = null;

	    public char8**instanceExtensions = null;
	    public int numInstanceExtensions = 0;
	    
	    public char8**deviceExtensions = null;
	    public int numDeviceExtensions = 0;

	    public uint32 maxTimerQueries = 256;
	}
}