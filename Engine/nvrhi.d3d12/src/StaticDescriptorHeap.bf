using Win32.Graphics.Direct3D12;
using System.Collections;
using System.Threading;
using Win32.Foundation;
using System;
using nvrhi.d3dcommon;
namespace nvrhi.d3d12
{
	class StaticDescriptorHeap : IDescriptorHeap
	{
		private D3D12Context* m_Context;
		private D3D12RefCountPtr<ID3D12DescriptorHeap> m_Heap;
		private D3D12RefCountPtr<ID3D12DescriptorHeap> m_ShaderVisibleHeap;
		private D3D12_DESCRIPTOR_HEAP_TYPE m_HeapType = D3D12_DESCRIPTOR_HEAP_TYPE.D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
		private D3D12_CPU_DESCRIPTOR_HANDLE m_StartCpuHandle = .();
		private D3D12_CPU_DESCRIPTOR_HANDLE m_StartCpuHandleShaderVisible = .();
		private D3D12_GPU_DESCRIPTOR_HANDLE m_StartGpuHandleShaderVisible = .();
		private uint32 m_Stride = 0;
		private uint32 m_NumDescriptors = 0;
		private List<bool> m_AllocatedDescriptors = new .() ~ delete _;
		private DescriptorIndex m_SearchStart = 0;
		private uint32 m_NumAllocatedDescriptors = 0;
		private Monitor m_Mutex = new .() ~ delete _;

		private static uint32 nextPowerOf2(uint32 v)
		{
			// https://graphics.stanford.edu/~seander/bithacks.html#RoundUpPowerOf2
			var v;
			v--;
			v |= v >> 1;
			v |= v >> 2;
			v |= v >> 4;
			v |= v >> 8;
			v |= v >> 16;
			v++;

			return v;
		}

		private HRESULT Grow(uint32 minRequiredSize)
		{
			uint32 oldSize = m_NumDescriptors;
			uint32 newSize = nextPowerOf2(minRequiredSize);

			D3D12RefCountPtr<ID3D12DescriptorHeap> oldHeap = m_Heap;

			HRESULT hr = allocateResources(m_HeapType, newSize, m_ShaderVisibleHeap != null);

			if (FAILED(hr))
				return hr;

			m_Context.device.CopyDescriptorsSimple(oldSize, m_StartCpuHandle, oldHeap.GetCPUDescriptorHandleForHeapStart(), m_HeapType);

			if (m_ShaderVisibleHeap != null)
			{
				m_Context.device.CopyDescriptorsSimple(oldSize, m_StartCpuHandleShaderVisible, oldHeap.GetCPUDescriptorHandleForHeapStart(), m_HeapType);
			}

			return S_OK;
		}

		public this(D3D12Context* context)
		{
			m_Context = context;
		}

		public HRESULT allocateResources(D3D12_DESCRIPTOR_HEAP_TYPE heapType, uint32 numDescriptors, bool shaderVisible)
		{
			m_Heap = null;
			m_ShaderVisibleHeap = null;

			D3D12_DESCRIPTOR_HEAP_DESC heapDesc = .();
			heapDesc.Type = heapType;
			heapDesc.NumDescriptors = numDescriptors;
			heapDesc.Flags = D3D12_DESCRIPTOR_HEAP_FLAGS.D3D12_DESCRIPTOR_HEAP_FLAG_NONE;

			HRESULT hr = m_Context.device.CreateDescriptorHeap(&heapDesc, ID3D12DescriptorHeap.IID, (void**)&m_Heap);

			if (FAILED(hr))
				return hr;

			if (shaderVisible)
			{
				heapDesc.Flags = D3D12_DESCRIPTOR_HEAP_FLAGS.D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;

				hr = m_Context.device.CreateDescriptorHeap(&heapDesc, ID3D12DescriptorHeap.IID, (void**)&m_ShaderVisibleHeap);

				if (FAILED(hr))
					return hr;

				m_StartCpuHandleShaderVisible = m_ShaderVisibleHeap.GetCPUDescriptorHandleForHeapStart();
				m_StartGpuHandleShaderVisible = m_ShaderVisibleHeap.GetGPUDescriptorHandleForHeapStart();
			}

			m_NumDescriptors = heapDesc.NumDescriptors;
			m_HeapType = heapDesc.Type;
			m_StartCpuHandle = m_Heap.GetCPUDescriptorHandleForHeapStart();
			m_Stride = m_Context.device.GetDescriptorHandleIncrementSize(heapDesc.Type);
			m_AllocatedDescriptors.Resize(m_NumDescriptors);

			return S_OK;
		}

		public void copyToShaderVisibleHeap(DescriptorIndex index, uint32 count = 1)
		{
			m_Context.device.CopyDescriptorsSimple(count, getCpuHandleShaderVisible(index), getCpuHandle(index), m_HeapType);
		}

		public override DescriptorIndex allocateDescriptors(uint32 count)
		{
			m_Mutex.Enter();
			defer m_Mutex.Exit();

			DescriptorIndex foundIndex = 0;
			uint32 freeCount = 0;
			bool found = false;

			// Find a contiguous range of 'count' indices for which m_AllocatedDescriptors[index] is false

			for (DescriptorIndex index = m_SearchStart; index < m_NumDescriptors; index++)
			{
				if (m_AllocatedDescriptors[index])
					freeCount = 0;
				else
					freeCount += 1;

				if (freeCount >= count)
				{
					foundIndex = index - count + 1;
					found = true;
					break;
				}
			}

			if (!found)
			{
				foundIndex = m_NumDescriptors;

				if (FAILED(Grow(m_NumDescriptors + count)))
				{
					m_Context.error("Failed to grow a descriptor heap!");
					return c_InvalidDescriptorIndex;
				}
			}

			for (DescriptorIndex index = foundIndex; index < foundIndex + count; index++)
			{
				m_AllocatedDescriptors[index] = true;
			}

			m_NumAllocatedDescriptors += count;

			m_SearchStart = foundIndex + count;
			return foundIndex;
		}

		public override DescriptorIndex allocateDescriptor()
		{
			return allocateDescriptors(1);
		}

		public override void releaseDescriptors(DescriptorIndex baseIndex, uint32 count)
		{
			m_Mutex.Enter();
			defer m_Mutex.Exit();

			if (count == 0)
				return;

			for (DescriptorIndex index = baseIndex; index < baseIndex + count; index++)
			{
#if DEBUG
				if (!m_AllocatedDescriptors[index])
				{
					m_Context.error("Attempted to release an un-allocated descriptor");
				}
#endif

				m_AllocatedDescriptors[index] = false;
			}

			m_NumAllocatedDescriptors -= count;

			if (m_SearchStart > baseIndex)
				m_SearchStart = baseIndex;
		}

		public override void releaseDescriptor(DescriptorIndex index)
		{
			releaseDescriptors(index, 1);
		}

		public override D3D12_CPU_DESCRIPTOR_HANDLE getCpuHandle(DescriptorIndex index)
		{
			D3D12_CPU_DESCRIPTOR_HANDLE handle = m_StartCpuHandle;
			handle.ptr += index * m_Stride;
			return handle;
		}

		public override D3D12_CPU_DESCRIPTOR_HANDLE getCpuHandleShaderVisible(DescriptorIndex index)
		{
			D3D12_CPU_DESCRIPTOR_HANDLE handle = m_StartCpuHandleShaderVisible;
			handle.ptr += index * m_Stride;
			return handle;
		}

		public override D3D12_GPU_DESCRIPTOR_HANDLE getGpuHandle(DescriptorIndex index)
		{
			D3D12_GPU_DESCRIPTOR_HANDLE handle = m_StartGpuHandleShaderVisible;
			handle.ptr += index * m_Stride;
			return handle;
		}

		[NoDiscard] public override ID3D12DescriptorHeap* getHeap()
		{
			return m_Heap;
		}

		[NoDiscard] public override ID3D12DescriptorHeap* getShaderVisibleHeap()
		{
			return m_ShaderVisibleHeap;
		}
	}
}