namespace nvrhi
{
	abstract class ITimerQuery :  IResource { }
	typealias TimerQueryHandle = RefCountPtr<ITimerQuery> ;
}