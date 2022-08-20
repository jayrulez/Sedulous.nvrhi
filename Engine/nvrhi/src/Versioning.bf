namespace nvrhi
{
	public static
	{
		/*
		Version words are used to track the usage of upload buffers, scratch buffers,
		and volatile constant buffers across multiple command lists and their instances.

		Versioned objects are initially allocated in the "pending" state, meaing they have
		the submitted flag set to zero, but the instance is nonzero. When the command list
		instance using the object is executed, the objects with a matching version are
		transitioned into the "submitted" state. Later, when the command list instance has
		finished executing, the objects are transitioned into the "available" state, i.e. 0.
		 */

		public const uint64 c_VersionSubmittedFlag = 0x8000000000000000;
		public const uint32 c_VersionQueueShift = 60;
		public const uint32 c_VersionQueueMask = 0x7;
		public const uint64 c_VersionIDMask = 0x0FFFFFFFFFFFFFFF;

		public static uint64 MakeVersion(uint64 id, CommandQueue queue, bool submitted)
		{
		    uint64 result = (id & c_VersionIDMask) | (uint64(queue) << c_VersionQueueShift);
		    if (submitted) result |= c_VersionSubmittedFlag;
		    return result;
		}

		public static uint64 VersionGetInstance(uint64 version)
		{
		    return version & c_VersionIDMask;
		}

		public static CommandQueue VersionGetQueue(uint64 version)
		{
		    return (CommandQueue)((version >> c_VersionQueueShift) & c_VersionQueueMask);
		}

		public static bool VersionGetSubmitted(uint64 version)
		{
		    return (version & c_VersionSubmittedFlag) != 0;
		}
	}
}