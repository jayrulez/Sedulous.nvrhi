using System.Collections;
using Win32.Graphics.Dxgi;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Dxgi.Common;
using nvrhi.d3dcommon;
namespace nvrhi.d3d12
{
	class DeviceResources
	{
		public StaticDescriptorHeap renderTargetViewHeap ~ delete _;
		public StaticDescriptorHeap depthStencilViewHeap ~ delete _;
		public StaticDescriptorHeap shaderResourceViewHeap ~ delete _;
		public StaticDescriptorHeap samplerHeap ~ delete _;
		public nvrhi.utils.BitSetAllocator timerQueries ~ delete _;
#if NVRHI_WITH_RTXMU
		public Monitor asListMutex;
		public List<uint64> asBuildsCompleted;
#endif

		// The cache does not own the RS objects, so store weak references
		public Dictionary<int, RootSignature> rootsigCache = new .() ~ {
			for(var entry in _){
				entry.value?.Release();
			}
			delete _;
		};

		public this(D3D12Context* context, D3D12DeviceDesc desc)
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
			if(!m_DxgiFormatPlaneCounts.ContainsKey(format))
				m_DxgiFormatPlaneCounts[format] = 0;
			ref uint8 planeCount = ref m_DxgiFormatPlaneCounts[format];
			if (planeCount == 0)
			{
				D3D12_FEATURE_DATA_FORMAT_INFO formatInfo = .() { Format =  format, PlaneCount = 1 };
				if (FAILED(m_Context.device.CheckFeatureSupport(D3D12_FEATURE.D3D12_FEATURE_FORMAT_INFO, &formatInfo, sizeof(decltype(formatInfo)))))
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

		private D3D12Context* m_Context;
		private Dictionary<DXGI_FORMAT, uint8> m_DxgiFormatPlaneCounts = new .() ~ delete _;
	}
}