using System;
namespace nvrhi
{
	abstract class IInputLayout :  IResource
	{
		[NoDiscard] public abstract uint32 getNumAttributes();
		[NoDiscard] public abstract VertexAttributeDesc* getAttributeDesc(uint32 index);
	}

	typealias InputLayoutHandle = RefCountPtr<IInputLayout>;
}