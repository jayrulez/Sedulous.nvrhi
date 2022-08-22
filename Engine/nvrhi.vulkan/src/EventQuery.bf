namespace nvrhi.vulkan
{
	class EventQuery :  RefCounter<IEventQuery>
	{
	    public CommandQueue queue = CommandQueue.Graphics;
	    public uint64 commandListID = 0;
	}
}