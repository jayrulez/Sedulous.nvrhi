using System;
namespace nvrhi
{
	abstract class IComputePipeline :  IResource
	{
		[NoDiscard] public abstract readonly ref ComputePipelineDesc getDesc();
	}

	typealias ComputePipelineHandle = RefCountPtr<IComputePipeline>;
}