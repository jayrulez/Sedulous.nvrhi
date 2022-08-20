using System;
namespace nvrhi.rt
{
	abstract class IPipeline :  IResource
	{
		[NoDiscard] public abstract readonly ref nvrhi.rt.PipelineDesc getDesc();
		public abstract ShaderTableHandle createShaderTable();
	}
	typealias PipelineHandle = RefCountPtr<IPipeline>;
}