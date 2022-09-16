using Win32.Graphics.Direct3D12;
using System.Threading;
using System;
namespace nvrhi.d3d12;

class QueueD3D12
{
	public D3D12RefCountPtr<ID3D12CommandQueue> queue = null;
	public D3D12RefCountPtr<ID3D12Fence> fence = null;
	public uint64 lastSubmittedInstance = 0;
	public uint64 lastCompletedInstance = 0;
	private Monitor recordingInstanceInternalMonitor = new .() ~ delete _;
	private uint64 recordingInstanceInternal = 1;
	public /*std::atomic<uint64>*/ uint64 recordingInstance
	{
		get
		{
			using (recordingInstanceInternalMonitor.Enter())
			{
				return recordingInstanceInternal;
			}
		}
		set
		{
			using (recordingInstanceInternalMonitor.Enter())
			{
				recordingInstanceInternal = value;
			}
		}
	}
	public System.Collections.Queue<CommandListInstance> commandListsInFlight = new .() ~ delete _;

	public  this(D3D12Context* context, ID3D12CommandQueue* queue)
	{
		this.queue = queue;
		m_Context = context;

		Runtime.Assert(queue != null);
		m_Context.device.CreateFence(0, D3D12_FENCE_FLAGS.D3D12_FENCE_FLAG_NONE, ID3D12Fence.IID, (void**)&fence);
	}

	public uint64 updateLastCompletedInstance()
	{
		if (lastCompletedInstance < lastSubmittedInstance)
		{
			lastCompletedInstance = fence.GetCompletedValue();
		}
		return lastCompletedInstance;
	}

	private D3D12Context* m_Context;
}