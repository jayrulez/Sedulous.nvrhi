using Win32.Graphics.Direct3D12;
using System;
using Win32.Foundation;
using System.Collections;
using nvrhi.d3dcommon;

namespace nvrhi.d3d12;

class UploadManager
{
	public this(Context* context, Queue pQueue, int defaultChunkSize, uint64 memoryLimit, bool isScratchBuffer)
	{
		m_Context = context;
		m_Queue = pQueue;
		m_DefaultChunkSize = defaultChunkSize;
		m_MemoryLimit = memoryLimit;
		m_IsScratchBuffer = isScratchBuffer;

		Runtime.Assert(pQueue != null);
	}

	public bool suballocateBuffer(uint64 size, ID3D12GraphicsCommandList* pCommandList, ID3D12Resource** pBuffer, int* pOffset, void** pCpuVA,
		D3D12_GPU_VIRTUAL_ADDRESS* pGpuVA, uint64 currentVersion, uint32 alignment = 256)
	{
		// Scratch allocations need a command list, upload ones don't
		Runtime.Assert(!m_IsScratchBuffer || pCommandList != null);

		BufferChunk chunkToRetire = null;

		// Try to allocate from the current chunk first
		if (m_CurrentChunk != null)
		{
			uint64 alignedOffset = align(m_CurrentChunk.writePointer, (uint64)alignment);
			uint64 endOfDataInChunk = alignedOffset + size;

			if (endOfDataInChunk <= m_CurrentChunk.bufferSize)
			{
				// The buffer can fit into the current chunk - great, we're done
				m_CurrentChunk.writePointer = endOfDataInChunk;

				if (pBuffer != null) *pBuffer = m_CurrentChunk.buffer;
				if (pOffset != null) *pOffset = (.)alignedOffset;
				if (pCpuVA != null && m_CurrentChunk.cpuVA != null)
					*pCpuVA = (char8*)m_CurrentChunk.cpuVA + alignedOffset;
				if (pGpuVA != null && m_CurrentChunk.gpuVA != 0)
					*pGpuVA = m_CurrentChunk.gpuVA + alignedOffset;

				return true;
			}

			chunkToRetire = m_CurrentChunk;
			m_CurrentChunk = null;
		}

		uint64 completedInstance = m_Queue.lastCompletedInstance;

		// Try to find a chunk in the pool that's no longer used and is large enough to allocate our buffer
		for (int i = 0; i < m_ChunkPool.Count; i++)
		{
			BufferChunk chunk = m_ChunkPool[i];

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
			uint64 sizeToAllocate = align(Math.Max(size, (uint64)m_DefaultChunkSize), BufferChunk.c_sizeAlignment);

			// See if we're allowed to allocate more memory
			if ((m_MemoryLimit > 0) && (m_AllocatedMemory + sizeToAllocate > m_MemoryLimit))
			{
				if (m_IsScratchBuffer)
				{
					// Nope, need to reuse something.
					// Find the largest least recently used chunk that can fit our buffer.

					BufferChunk bestChunk = null;
					for (var candidateChunk in m_ChunkPool)
					{
						if (candidateChunk.bufferSize >= sizeToAllocate)
						{
							// Pick the first fitting chunk if we have nothing so far
							if (bestChunk == null)
							{
								bestChunk = candidateChunk;
								continue;
							}

							bool candidateSubmitted = VersionGetSubmitted(candidateChunk.version);
							bool bestSubmitted = VersionGetSubmitted(bestChunk.version);
							uint64 candidateInstance = VersionGetInstance(candidateChunk.version);
							uint64 bestInstance = VersionGetInstance(bestChunk.version);

							// Compare chunks: submitted is better than current, old is better than new, large is better than small
							if (candidateSubmitted && !bestSubmitted ||
								candidateSubmitted == bestSubmitted && candidateInstance < bestInstance ||
								candidateSubmitted == bestSubmitted && candidateInstance == bestInstance
								&& candidateChunk.bufferSize > bestChunk.bufferSize)
							{
								bestChunk = candidateChunk;
							}
						}
					}

					if (bestChunk == null)
					{
						// No chunk found that can be reused. And we can't allocate. :(
						return false;
					}

					// Move the found chunk from the pool to the current chunk
					//m_ChunkPool.erase(std::find(m_ChunkPool.begin(), m_ChunkPool.end(), bestChunk));
					m_ChunkPool.Remove(bestChunk);
					m_CurrentChunk = bestChunk;

					// Place a UAV barrier on the chunk.
					D3D12_RESOURCE_BARRIER barrier = .();
					barrier.Type = D3D12_RESOURCE_BARRIER_TYPE.D3D12_RESOURCE_BARRIER_TYPE_UAV;
					barrier.UAV.pResource = bestChunk.buffer;
					pCommandList.ResourceBarrier(1, &barrier);
				}
				else // !m_IsScratchBuffer
				{
					// Can't reuse in-flight buffers for uploads.
					// But uploads have no memory limit, so this should never execute.
					return false;
				}
			}
			else
			{
				m_CurrentChunk = createChunk((.)sizeToAllocate);
			}
		}

		m_CurrentChunk.version = currentVersion;
		m_CurrentChunk.writePointer = size;

		if (pBuffer != null) *pBuffer = m_CurrentChunk.buffer;
		if (pOffset != null) *pOffset = 0;
		if (pCpuVA != null) *pCpuVA = m_CurrentChunk.cpuVA;
		if (pGpuVA != null) *pGpuVA = m_CurrentChunk.gpuVA;

		return true;
	}

	public void submitChunks(uint64 currentVersion, uint64 submittedVersion)
	{
		if (m_CurrentChunk != null)
		{
			m_ChunkPool.Add(m_CurrentChunk);
			m_CurrentChunk = null;
		}

		for (var chunk in m_ChunkPool)
		{
			if (chunk.version == currentVersion)
				chunk.version = submittedVersion;
		}
	}

	private Context* m_Context;
	private Queue m_Queue;
	private int m_DefaultChunkSize = 0;
	private uint64 m_MemoryLimit = 0;
	private uint64 m_AllocatedMemory = 0;
	private bool m_IsScratchBuffer = false;

	private /*System.Collections.Queue*/ List<BufferChunk> m_ChunkPool = new .() ~ delete _;
	private BufferChunk m_CurrentChunk;

	[NoDiscard] private BufferChunk createChunk(int size)
	{
		var size;
		var chunk = new BufferChunk();

		size = align(size, (int)BufferChunk.c_sizeAlignment);

		D3D12_HEAP_PROPERTIES heapProps = .();
		heapProps.Type = m_IsScratchBuffer ? D3D12_HEAP_TYPE.D3D12_HEAP_TYPE_DEFAULT : D3D12_HEAP_TYPE.D3D12_HEAP_TYPE_UPLOAD;

		D3D12_RESOURCE_DESC bufferDesc = .();
		bufferDesc.Dimension = D3D12_RESOURCE_DIMENSION.D3D12_RESOURCE_DIMENSION_BUFFER;
		bufferDesc.Width = (.)size;
		bufferDesc.Height = 1;
		bufferDesc.DepthOrArraySize = 1;
		bufferDesc.MipLevels = 1;
		bufferDesc.SampleDesc.Count = 1;
		bufferDesc.Layout = D3D12_TEXTURE_LAYOUT.D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
		if (m_IsScratchBuffer) bufferDesc.Flags = D3D12_RESOURCE_FLAGS.D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;

		HRESULT hr = m_Context.device.CreateCommittedResource(
			&heapProps,
			D3D12_HEAP_FLAGS.D3D12_HEAP_FLAG_NONE,
			&bufferDesc,
			m_IsScratchBuffer ? D3D12_RESOURCE_STATES.D3D12_RESOURCE_STATE_UNORDERED_ACCESS : D3D12_RESOURCE_STATES.D3D12_RESOURCE_STATE_GENERIC_READ,
			null,
			ID3D12Resource.IID, (void**)&chunk.buffer);

		if (FAILED(hr))
			return null;

		if (!m_IsScratchBuffer)
		{
			hr = chunk.buffer.Map(0, null, &chunk.cpuVA);

			if (FAILED(hr))
				return null;
		}

		chunk.bufferSize = (.)size;
		chunk.gpuVA = chunk.buffer.GetGPUVirtualAddress();
		chunk.identifier = uint32(m_ChunkPool.Count);

		String name = scope .();
		if (m_IsScratchBuffer)
			name.AppendF("DXR Scratch Buffer {}", chunk.identifier);
		else
			name.AppendF("Upload Buffer {}", chunk.identifier);
		chunk.buffer.SetName(name.ToScopedNativeWChar!());

		return chunk;
	}
}