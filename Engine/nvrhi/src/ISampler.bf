using System;
namespace nvrhi
{
	abstract class ISampler :  IResource
	{
		[NoDiscard] public abstract readonly ref SamplerDesc getDesc();
	}

	typealias SamplerHandle = RefCountPtr<ISampler>;
}