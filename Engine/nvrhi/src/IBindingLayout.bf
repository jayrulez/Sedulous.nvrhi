using System;
namespace nvrhi
{
	abstract class IBindingLayout :  IResource
	{
		[NoDiscard] public abstract BindingLayoutDesc* getDesc(); // returns null for bindless layouts
		[NoDiscard] public abstract BindlessLayoutDesc* getBindlessDesc(); // returns null for regular layouts
	}

	typealias BindingLayoutHandle = RefCountPtr<IBindingLayout>;
}