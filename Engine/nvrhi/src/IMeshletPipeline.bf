using System;
namespace nvrhi
{
	abstract class IMeshletPipeline :  IResource
	{
		[NoDiscard] public abstract readonly ref MeshletPipelineDesc getDesc();
		[NoDiscard] public abstract readonly ref FramebufferInfo getFramebufferInfo();
	}

	typealias MeshletPipelineHandle = RefCountPtr<IMeshletPipeline>;
}