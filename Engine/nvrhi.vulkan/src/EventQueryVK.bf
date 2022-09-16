namespace nvrhi.vulkan
{
	class EventQueryVK :  RefCounter<IEventQuery>
	{
	    public CommandQueue queue = CommandQueue.Graphics;
	    public uint64 commandListID = 0;
	}
}