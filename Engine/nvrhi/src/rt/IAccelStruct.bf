using System;
namespace nvrhi.rt
{
	//////////////////////////////////////////////////////////////////////////
	// nvrhi.rt.AccelStruct
	//////////////////////////////////////////////////////////////////////////

	abstract class IAccelStruct :  IResource
	{
		[NoDiscard] public abstract readonly ref AccelStructDesc getDesc();
		[NoDiscard] public abstract bool isCompacted();
		[NoDiscard] public abstract uint64 getDeviceAddress();
	}

	typealias AccelStructHandle = RefCountPtr<IAccelStruct>;
}