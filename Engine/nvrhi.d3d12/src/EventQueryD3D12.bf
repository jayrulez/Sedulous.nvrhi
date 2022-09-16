using Win32.Graphics.Direct3D12;
namespace nvrhi.d3d12
{
	class EventQueryD3D12 : RefCounter<IEventQuery>
	{
	    public D3D12RefCountPtr<ID3D12Fence> fence;
	    public uint64 fenceCounter = 0;
	    public bool started = false;
	    public bool resolved = false;
	}
}