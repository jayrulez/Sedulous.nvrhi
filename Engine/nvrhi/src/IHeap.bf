namespace nvrhi
{
	abstract class IHeap :  IResource
	{
		public abstract readonly ref HeapDesc getDesc();
	}

	typealias HeapHandle = RefCountPtr<IHeap>;
}