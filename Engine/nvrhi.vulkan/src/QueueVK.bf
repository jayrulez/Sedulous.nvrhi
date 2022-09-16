using System.Collections;
using System.Threading;
using Bulkan;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	// represents a hardware queue
	class QueueVK
	{
		public VkSemaphore trackingSemaphore;

		public this(VulkanContext* context, CommandQueue queueID, VkQueue queue, uint32 queueFamilyIndex)
		{
			m_Context = context;
			m_Queue = queue;
			m_QueueID = queueID;
			m_QueueFamilyIndex = queueFamilyIndex;

			var semaphoreTypeInfo = VkSemaphoreTypeCreateInfo()
				.setSemaphoreType(VkSemaphoreType.eTimeline);

			var semaphoreInfo = VkSemaphoreCreateInfo()
				.setPNext(&semaphoreTypeInfo);

			vkCreateSemaphore(context.device, &semaphoreInfo, context.allocationCallbacks, &trackingSemaphore);
		}

		public ~this()
		{
			vkDestroySemaphore(m_Context.device, trackingSemaphore, m_Context.allocationCallbacks);
			trackingSemaphore = .Null;
		}

		// creates a command buffer and its synchronization resources
		public TrackedCommandBufferPtr createCommandBuffer()
		{
			VkResult res;

			TrackedCommandBufferPtr ret = new TrackedCommandBuffer(m_Context);

			var cmdPoolInfo = VkCommandPoolCreateInfo()
				.setQueueFamilyIndex(m_QueueFamilyIndex)
				.setFlags(VkCommandPoolCreateFlags.eResetCommandBufferBit |
				VkCommandPoolCreateFlags.eTransientBit);

			res = vkCreateCommandPool(m_Context.device, &cmdPoolInfo, m_Context.allocationCallbacks, &ret.cmdPool);
			CHECK_VK_FAIL!(res);

			// allocate command buffer
			var allocInfo = VkCommandBufferAllocateInfo()
				.setLevel(VkCommandBufferLevel.ePrimary)
				.setCommandPool(ret.cmdPool)
				.setCommandBufferCount(1);

			res = vkAllocateCommandBuffers(m_Context.device, &allocInfo, &ret.cmdBuf);
			CHECK_VK_FAIL!(res);

			return ret;
		}

		public TrackedCommandBufferPtr getOrCreateCommandBuffer()
		{
			m_Mutex.Enter(); defer m_Mutex.Exit(); // this is called from CommandList::open, so free-threaded

			uint64 recordingID = ++m_LastRecordingID;

			TrackedCommandBufferPtr cmdBuf;
			if (m_CommandBuffersPool.IsEmpty)
			{
				cmdBuf = createCommandBuffer();
			}
			else
			{
				cmdBuf = m_CommandBuffersPool.Front;
				m_CommandBuffersPool.PopFront();
			}

			cmdBuf.recordingID = recordingID;
			return cmdBuf;
		}

		public void addWaitSemaphore(VkSemaphore semaphore, uint64 value)
		{
			if (semaphore == .Null)
				return;

			m_WaitSemaphores.Add(semaphore);
			m_WaitSemaphoreValues.Add(value);
		}
		public void addSignalSemaphore(VkSemaphore semaphore, uint64 value)
		{
			if (semaphore == .Null)
				return;

			m_SignalSemaphores.Add(semaphore);
			m_SignalSemaphoreValues.Add(value);
		}

		// submits a command buffer to this queue, returns submissionID
		public uint64 submit(ICommandList* ppCmd, int numCmd)
		{
			List<VkPipelineStageFlags> waitStageArray = scope .() { Count = m_WaitSemaphores.Count };
			List<VkCommandBuffer> commandBuffers = scope .() { Count = numCmd };

			for (int i = 0; i < m_WaitSemaphores.Count; i++)
			{
				waitStageArray[i] = VkPipelineStageFlags.eTopOfPipeBit;
			}

			m_LastSubmittedID++;

			for (int i = 0; i < numCmd; i++)
			{
				CommandListVK commandList = checked_cast<CommandListVK, ICommandList>(ppCmd[i]);
				TrackedCommandBufferPtr commandBuffer = commandList.getCurrentCmdBuf();

				commandBuffers[i] = commandBuffer.cmdBuf;
				m_CommandBuffersInFlight.Add(commandBuffer);

				// beef error here
				for (BufferVK buffer in commandBuffer.referencedStagingBuffers)
				{
					buffer.lastUseQueue = m_QueueID;
					buffer.lastUseCommandListID = m_LastSubmittedID;
				}
			}

			m_SignalSemaphores.Add(trackingSemaphore);
			m_SignalSemaphoreValues.Add(m_LastSubmittedID);

			var timelineSemaphoreInfo = VkTimelineSemaphoreSubmitInfo()
				.setSignalSemaphoreValueCount(uint32(m_SignalSemaphoreValues.Count))
				.setPSignalSemaphoreValues(m_SignalSemaphoreValues.Ptr);

			if (!m_WaitSemaphoreValues.IsEmpty)
			{
				timelineSemaphoreInfo.setWaitSemaphoreValueCount(uint32(m_WaitSemaphoreValues.Count));
				timelineSemaphoreInfo.setPWaitSemaphoreValues(m_WaitSemaphoreValues.Ptr);
			}

			var submitInfo = VkSubmitInfo()
				.setPNext(&timelineSemaphoreInfo)
				.setCommandBufferCount(uint32(numCmd))
				.setPCommandBuffers(commandBuffers.Ptr)
				.setWaitSemaphoreCount(uint32(m_WaitSemaphores.Count))
				.setPWaitSemaphores(m_WaitSemaphores.Ptr)
				.setPWaitDstStageMask(waitStageArray.Ptr)
				.setSignalSemaphoreCount(uint32(m_SignalSemaphores.Count))
				.setPSignalSemaphores(m_SignalSemaphores.Ptr);

			vkQueueSubmit(m_Queue, 1, &submitInfo, .Null);

			m_WaitSemaphores.Clear();
			m_WaitSemaphoreValues.Clear();
			m_SignalSemaphores.Clear();
			m_SignalSemaphoreValues.Clear();

			return m_LastSubmittedID;
		}

		// retire any command buffers that have finished execution from the pending execution list
		public void retireCommandBuffers()
		{
			Queue<TrackedCommandBufferPtr> submissions = m_CommandBuffersInFlight;

			uint64 lastFinishedID = updateLastFinishedID();

			for (readonly TrackedCommandBufferPtr cmd in submissions)
			{
				if (cmd.submissionID <= lastFinishedID)
				{
					cmd.referencedResources.Clear();
					cmd.referencedStagingBuffers.Clear();
					cmd.submissionID = 0;
					m_CommandBuffersPool.Add(cmd);

#if NVRHI_WITH_RTXMU
					if (!cmd.rtxmuBuildIds.empty())
					{
						m_Context.rtxMuResources.asListMutex.Enter();
						defer m_Context.rtxMuResources.asListMutex.Exit();
					
						m_Context.rtxMuResources.asBuildsCompleted.insert(m_Context.rtxMuResources.asBuildsCompleted.end(),
							cmd.rtxmuBuildIds.begin(), cmd.rtxmuBuildIds.end());

						cmd.rtxmuBuildIds.Clear();
					}
					if (!cmd.rtxmuCompactionIds.IsEmpty)
					{
						m_Context.rtxMemUtil.GarbageCollection(cmd.rtxmuCompactionIds);
						cmd.rtxmuCompactionIds.Clear();
					}
#endif
				}
				else
				{
					m_CommandBuffersInFlight.Add(cmd);
				}
			}
		}

		public TrackedCommandBufferPtr getCommandBufferInFlight(uint64 submissionID)
		{
			for (readonly TrackedCommandBufferPtr cmd in m_CommandBuffersInFlight)
			{
				if (cmd.submissionID == submissionID)
					return cmd;
			}

			return null;
		}

		public uint64 updateLastFinishedID()
		{
			VkResult res =  vkGetSemaphoreCounterValue(m_Context.device, trackingSemaphore, &m_LastFinishedID);
			ASSERT_VK_OK!(res);

			return m_LastFinishedID;
		}
		public uint64 getLastSubmittedID() { return m_LastSubmittedID; }
		public uint64 getLastFinishedID() { return m_LastFinishedID; }
		public CommandQueue getQueueID() { return m_QueueID; }
		public VkQueue getVkQueue() { return m_Queue; }

		public bool pollCommandList(uint64 commandListID)
		{
			if (commandListID > m_LastSubmittedID || commandListID == 0)
				return false;

			bool completed = getLastFinishedID() >= commandListID;
			if (completed)
				return true;

			completed = updateLastFinishedID() >= commandListID;
			return completed;
		}
		public bool waitCommandList(uint64 commandListID, uint64 timeout)
		{
			if (commandListID > m_LastSubmittedID || commandListID == 0)
				return false;

			if (pollCommandList(commandListID))
				return true;

			VkSemaphore[1] semaphores = .(trackingSemaphore);
			uint64[1] waitValues = .(commandListID);

			var waitInfo = VkSemaphoreWaitInfo()
				.setPSemaphores(&semaphores)
				.setPValues(&waitValues);

			VkResult result = vkWaitSemaphores(m_Context.device, &waitInfo, timeout);

			return (result == VkResult.VK_SUCCESS);
		}

		private VulkanContext* m_Context;

		private VkQueue m_Queue;
		private CommandQueue m_QueueID;
		private uint32 m_QueueFamilyIndex = uint32(-1);

		private Monitor m_Mutex = new .() ~ delete _;
		private List<VkSemaphore> m_WaitSemaphores = new .() ~ delete _;
		private List<uint64> m_WaitSemaphoreValues = new .() ~ delete _;
		private List<VkSemaphore> m_SignalSemaphores = new .() ~ delete _;
		private List<uint64> m_SignalSemaphoreValues = new .() ~ delete _;

		private uint64 m_LastRecordingID = 0;
		private uint64 m_LastSubmittedID = 0;
		private uint64 m_LastFinishedID = 0;

		// tracks the list of command buffers in flight on this queue
		private Queue<TrackedCommandBufferPtr> m_CommandBuffersInFlight = new .() ~ DeleteContainerAndItems!(_);
		private Queue<TrackedCommandBufferPtr> m_CommandBuffersPool = new .() ~ DeleteContainerAndItems!(_);
	}
}