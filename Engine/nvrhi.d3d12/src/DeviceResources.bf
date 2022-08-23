using System.Collections;
using Win32.Graphics.Dxgi;
using Win32.Graphics.Direct3D12;
namespace nvrhi.d3d12
{
	class DeviceResources
	{
		public StaticDescriptorHeap renderTargetViewHeap;
		public StaticDescriptorHeap depthStencilViewHeap;
		public StaticDescriptorHeap shaderResourceViewHeap;
		public StaticDescriptorHeap samplerHeap;
		public nvrhi.utils.BitSetAllocator timerQueries;
#if NVRHI_WITH_RTXMU
		public Monitor asListMutex;
		public List<uint64> asBuildsCompleted;
#endif

		// The cache does not own the RS objects, so store weak references
		public Dictionary<int, RootSignature> rootsigCache;

		public this(Context* context, DeviceDesc desc)
		{
			renderTargetViewHeap = new .(context);
			depthStencilViewHeap = new .(context);
			shaderResourceViewHeap = new .(context);
			samplerHeap = new .(context);
			timerQueries = new .(desc.maxTimerQueries, true);
			m_Context = context;
		}

		public uint8 getFormatPlaneCount(DXGI_FORMAT format)
		{
			ref uint8 planeCount = ref m_DxgiFormatPlaneCounts[format];
			if (planeCount == 0)
			{
				D3D12_FEATURE_DATA_FORMAT_INFO formatInfo = .() { Format =  format, PlaneCount = 1 };
				if (FAILED(m_Context.device.CheckFeatureSupport(D3D12_FEATURE.FORMAT_INFO, &formatInfo, sizeof(decltype(formatInfo)))))
				{
					// Format not supported - store a special value in the cache to avoid querying later
					planeCount = 255;
				}
				else
				{
					// Format supported - store the plane count in the cache
					planeCount = formatInfo.PlaneCount;
				}
			}

			if (planeCount == 255)
				return 0;

			return planeCount;
		}

		private Context* m_Context;
		private Dictionary<DXGI_FORMAT, uint8> m_DxgiFormatPlaneCounts;
	}
}