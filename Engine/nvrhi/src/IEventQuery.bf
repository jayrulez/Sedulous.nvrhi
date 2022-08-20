namespace nvrhi
{
	abstract class IEventQuery :  IResource { }
	typealias EventQueryHandle = RefCountPtr<IEventQuery> ;
}