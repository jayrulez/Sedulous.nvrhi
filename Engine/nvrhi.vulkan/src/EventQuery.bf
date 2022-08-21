namespace nvrhi.vulkan
{
	class EventQuery :  /*RefCounter<IEventQuery>*/IEventQuery
	{
	    public CommandQueue queue = CommandQueue.Graphics;
	    public uint64 commandListID = 0;
	}
}