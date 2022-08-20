using System;
namespace nvrhi
{
	abstract class IGraphicsPipeline :  IResource 
	{
	    [NoDiscard] public abstract readonly ref GraphicsPipelineDesc getDesc();
	    [NoDiscard] public abstract readonly ref FramebufferInfo getFramebufferInfo();
	}

	typealias GraphicsPipelineHandle = RefCountPtr<IGraphicsPipeline> ;
}