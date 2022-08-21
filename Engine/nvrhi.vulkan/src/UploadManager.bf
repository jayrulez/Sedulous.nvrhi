using System;
namespace nvrhi.vulkan
{
	class UploadManager
	{
		public this(Device pParent, uint64 defaultChunkSize, uint64 memoryLimit, bool isScratchBuffer)
		{
			m_Device = pParent;
			m_DefaultChunkSize = defaultChunkSize;
			m_MemoryLimit = memoryLimit;
			m_IsScratchBuffer = isScratchBuffer;
		}

		public BufferChunk* CreateChunk(uint64 size)
		{
			BufferChunk* chunk = new BufferChunk();

			if (m_IsScratchBuffer)
			{
				BufferDesc desc = .();
				desc.byteSize = size;
				desc.cpuAccess = CpuAccessMode.None;
				desc.debugName = "ScratchBufferChunk";
				desc.canHaveUAVs = true;

				chunk.buffer = m_Device.createBuffer(desc);
				chunk.mappedMemory = null;
				chunk.bufferSize = size;
			}
			else
			{
				BufferDesc desc = .();
				desc.byteSize = size;
				desc.cpuAccess = CpuAccessMode.Write;
				desc.debugName = "UploadChunk";

				// The upload manager buffers are used in buildTopLevelAccelStruct to store instance data
				desc.isAccelStructBuildInput = m_Device.queryFeatureSupport(Feature.RayTracingAccelStruct);

				chunk.buffer = m_Device.createBuffer(desc);
				chunk.mappedMemory = m_Device.mapBuffer(chunk.buffer, CpuAccessMode.Write);
				chunk.bufferSize = size;
			}

			return chunk;
		}

		public bool suballocateBuffer(uint64 size, Buffer* pBuffer, uint64* pOffset, void** pCpuVA,
			uint64 currentVersion, uint32 alignment = 256)
		{
			BufferChunk* chunkToRetire = null;

			if (m_CurrentChunk != null)
			{
				uint64 alignedOffset = align(m_CurrentChunk.writePointer, (uint64)alignment);
				uint64 endOfDataInChunk = alignedOffset + size;

				if (endOfDataInChunk <= m_CurrentChunk.bufferSize)
				{
					m_CurrentChunk.writePointer = endOfDataInChunk;

					*pBuffer = checked_cast<Buffer, IBuffer>(m_CurrentChunk.buffer.Get<IBuffer>());
					*pOffset = alignedOffset;
					if (pCpuVA != null && m_CurrentChunk.mappedMemory != null)
						*pCpuVA = (char8*)m_CurrentChunk.mappedMemory + alignedOffset;

					return true;
				}

				chunkToRetire = m_CurrentChunk;
				m_CurrentChunk = null;
			}

			CommandQueue queue = VersionGetQueue(currentVersion);
			uint64 completedInstance = m_Device.queueGetCompletedInstance(queue);

			for (int i = 0; i < m_ChunkPool.Count; i++)
			{
				BufferChunk* chunk = m_ChunkPool[i];

				if (VersionGetSubmitted(chunk.version)
					&& VersionGetInstance(chunk.version) <= completedInstance)
				{
					chunk.version = 0;
				}

				if (chunk.version == 0 && chunk.bufferSize >= size)
				{
					m_ChunkPool.RemoveAt(i--);
					m_CurrentChunk = chunk;
					break;
				}
			}

			if (chunkToRetire != null)
			{
				m_ChunkPool.Add(chunkToRetire);
			}

			if (m_CurrentChunk == null)
			{
				uint64 sizeToAllocate = align(Math.Max(size, m_DefaultChunkSize), BufferChunk.c_sizeAlignment);

				if ((m_MemoryLimit > 0) && (m_AllocatedMemory + sizeToAllocate > m_MemoryLimit))
					return false;

				m_CurrentChunk = CreateChunk(sizeToAllocate);
			}

			m_CurrentChunk.version = currentVersion;
			m_CurrentChunk.writePointer = size;

			*pBuffer = checked_cast<Buffer, IBuffer>(m_CurrentChunk.buffer.Get<IBuffer>());
			*pOffset = 0;
			if (pCpuVA != null)
				*pCpuVA = m_CurrentChunk.mappedMemory;

			return true;
		}
		public void submitChunks(uint64 currentVersion, uint64 submittedVersion)
		{
			if (m_CurrentChunk != null)
			{
				m_ChunkPool.Add(m_CurrentChunk);
				m_CurrentChunk = null;
			}

			for ( /*readonly ref*/var chunk in ref m_ChunkPool)
			{
				if (chunk.version == currentVersion)
					chunk.version = submittedVersion;
			}
		}

		private Device m_Device;
		private uint64 m_DefaultChunkSize = 0;
		private uint64 m_MemoryLimit = 0;
		private uint64 m_AllocatedMemory = 0;
		private bool m_IsScratchBuffer = false;

		private System.Collections.Queue<BufferChunk*> m_ChunkPool;
		private BufferChunk* m_CurrentChunk;
	}
}