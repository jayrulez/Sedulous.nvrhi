using Win32.Graphics.Direct3D12;
namespace nvrhi.d3d12
{
	class Heap : RefCounter<IHeap>
	{
	    public HeapDesc desc;
	    public D3D12RefCountPtr<ID3D12Heap> heap;

	    public override readonly ref HeapDesc getDesc() { return ref desc; }
	}
}