using System;
namespace nvrhi
{
	abstract class IBuffer :  IResource
	{
		[NoDiscard] public abstract readonly ref BufferDesc getDesc();
	}

	typealias BufferHandle = RefCountPtr<IBuffer>;
}