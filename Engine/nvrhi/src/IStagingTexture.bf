using System;
namespace nvrhi
{
	abstract class IStagingTexture :  IResource
	{
	    [NoDiscard] public abstract readonly ref TextureDesc getDesc();
	}
	typealias StagingTextureHandle =  RefCountPtr<IStagingTexture>;
}