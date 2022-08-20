using System;
namespace nvrhi
{
	abstract class IFramebuffer :  IResource 
	{
	    [NoDiscard] public abstract readonly ref FramebufferDesc getDesc();
	    [NoDiscard] public abstract readonly ref FramebufferInfo getFramebufferInfo();
	}

	typealias FramebufferHandle = RefCountPtr<IFramebuffer> ;
}