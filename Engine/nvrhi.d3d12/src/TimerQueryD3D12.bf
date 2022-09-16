using Win32.Graphics.Direct3D12;
namespace nvrhi.d3d12
{
	class TimerQueryD3D12 : RefCounter<ITimerQuery>
	{
		public uint32 beginQueryIndex = 0;
		public uint32 endQueryIndex = 0;

		public D3D12RefCountPtr<ID3D12Fence> fence;
		public uint64 fenceCounter = 0;

		public bool started = false;
		public bool resolved = false;
		public float time = 0.f;

		public this(DeviceResources resources)
			{ m_Resources = resources; }

		public ~this()
		{
			m_Resources.timerQueries.release((int32)(beginQueryIndex) / 2);
		}

		private DeviceResources m_Resources;
	}
}