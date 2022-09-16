namespace nvrhi.vulkan
{
	class TimerQueryVK : RefCounter<ITimerQuery>
	{
		public int32 beginQueryIndex = -1;
		public int32 endQueryIndex = -1;

		public bool started = false;
		public bool resolved = false;
		public float time = 0.f;

		public this(nvrhi.utils.BitSetAllocator allocator)
		{
			m_QueryAllocator = allocator;
		}

		public ~this()
		{
			m_QueryAllocator.release(beginQueryIndex / 2);
			beginQueryIndex = -1;
			endQueryIndex = -1;
		}

		private nvrhi.utils.BitSetAllocator m_QueryAllocator;
	}
}