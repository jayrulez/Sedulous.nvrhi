using System;
namespace nvrhi
{
	abstract class IBindingSet :  IResource
	{
		[NoDiscard] public abstract BindingSetDesc* getDesc(); // returns null for descriptor tables
		[NoDiscard] public abstract IBindingLayout getLayout();
	}

	typealias BindingSetHandle = RefCountPtr<IBindingSet>;
}