using nvrhi.d3d12;
using System;
using Win32.Graphics.Dxgi;
using Win32.Graphics.Dxgi.Common;
using Win32.Graphics.Direct3D12;
using Win32.Foundation;
using System.Collections;
using Win32.System.Threading;
using Win32.UI.WindowsAndMessaging;
using Win32.Graphics.Direct3D;
using Win32.System.Memory;
using Win32.System.WindowsProgramming;
using System.Diagnostics;
using nvrhi.d3dcommon;

enum DXGI_USAGE : uint32
{
	SHADER_INPUT = 16,
	RENDER_TARGET_OUTPUT = 32,
	BACK_BUFFER = 64,
	SHARED = 128,
	READ_ONLY = 256,
	DISCARD_ON_PRESENT = 512,
	UNORDERED_ACCESS = 1024
}

namespace nvrhi.deviceManager
{
	extension DeviceCreationParameters
	{
		public IDXGIAdapter* adapter = null;
		public DXGI_USAGE swapChainUsage = .SHADER_INPUT | .RENDER_TARGET_OUTPUT;
		public D3D_FEATURE_LEVEL featureLevel = D3D_FEATURE_LEVEL.D3D_FEATURE_LEVEL_11_1;
	}
}

namespace nvrhi.deviceManager.d3d12
{
	public static
	{
		public static mixin HR_RETURN(var hr)
		{
			if (FAILED(hr)) return false;
		}
		 // Adjust window rect so that it is centred on the given adapter.  Clamps to fit if it's too big.
		public static bool MoveWindowOntoAdapter(IDXGIAdapter* targetAdapter, ref RECT rect)
		{
			Runtime.Assert(targetAdapter != null);

			HRESULT hres = S_OK;
			uint32 outputNo = 0;
			while (SUCCEEDED(hres))
			{
				IDXGIOutput* pOutput = null;
				hres = targetAdapter.EnumOutputs(outputNo++, &pOutput);

				if (SUCCEEDED(hres) && pOutput != null)
				{
					DXGI_OUTPUT_DESC OutputDesc = .();
					pOutput.GetDesc(&OutputDesc);
					readonly RECT desktop = OutputDesc.DesktopCoordinates;
					readonly int32 centreX = (int32)desktop.left + (int32)(desktop.right - desktop.left) / 2;
					readonly int32 centreY = (int32)desktop.top + (int32)(desktop.bottom - desktop.top) / 2;
					readonly int32 winW = rect.right - rect.left;
					readonly int32 winH = rect.bottom - rect.top;
					readonly int32 left = centreX - winW / 2;
					readonly int32 right = left + winW;
					readonly int32 top = centreY - winH / 2;
					readonly int32 bottom = top + winH;
					rect.left = Math.Max(left, (int32)desktop.left);
					rect.right = Math.Min(right, (int32)desktop.right);
					rect.bottom = Math.Min(bottom, (int32)desktop.bottom);
					rect.top = Math.Max(top, (int32)desktop.top);

					// If there is more than one output, go with the first found.  Multi-monitor support could go here.
					return true;
				}
			}

			return false;
		}

		 // Find an adapter whose name contains the given string.
		public static D3D12RefCountPtr<IDXGIAdapter> FindAdapter(String targetName)
		{
			D3D12RefCountPtr<IDXGIAdapter> targetAdapter = null;
			D3D12RefCountPtr<IDXGIFactory1> DXGIFactory = null;
			HRESULT hres = CreateDXGIFactory1(IDXGIFactory1.IID, (void**)(&DXGIFactory));
			if (hres != S_OK)
			{
				Debug.WriteLine("ERROR in CreateDXGIFactory.\nFor more info, get log from debug D3D runtime: (1) Install DX SDK, and enable Debug D3D from DX Control Panel Utility. (2) Install and start DbgView. (3) Try running the program again.\n");
				return targetAdapter;
			}

			uint32 adapterNo = 0;
			while (SUCCEEDED(hres))
			{
				D3D12RefCountPtr<IDXGIAdapter> pAdapter = null;
				hres = DXGIFactory.EnumAdapters(adapterNo, &pAdapter);

				if (SUCCEEDED(hres))
				{
					DXGI_ADAPTER_DESC aDesc = .();
					pAdapter.GetDesc(&aDesc);

					// If no name is specified, return the first adapater.  This is the same behaviour as the
					// default specified for D3D11CreateDevice when no adapter is specified.
					if (targetName.Length == 0)
					{
						targetAdapter = pAdapter;
						break;
					}

					String aName = scope String(&aDesc.Description);

					if (aName.Contains(targetName))
					{
						targetAdapter = pAdapter;
						break;
					}
				}

				adapterNo++;
			}

			return targetAdapter;
		}

		public static bool GetSuitableAdapter(out IDXGIAdapter* outAdapter)
		{
			outAdapter = null;

			IDXGIFactory4* m_dxgi_factory = null;

			uint32 flags = 0;
			if (!(CreateDXGIFactory2(flags, IDXGIFactory4.IID, (void**)&m_dxgi_factory) == S_OK))
			{
				return false;
			}

			delegate HRESULT(uint32, ref IDXGIAdapter1*) GetNextAdapter = scope [&] (adapterIndex, adapter) =>
				{
					return m_dxgi_factory.EnumAdapters1(adapterIndex, &adapter);
				};

			IDXGIAdapter1* adapter = null;

			for (uint32 adapterIndex = 0; DXGI_ERROR_NOT_FOUND != GetNextAdapter(adapterIndex, ref adapter); adapterIndex++)
			{
				if (adapter != null)
				{
					outAdapter = adapter;
					return true;
				}
			}


			return true;
		}
	}

	class D3D12DeviceManager : DeviceManager
	{
		private D3D12RefCountPtr<ID3D12Device>                   m_Device12;
		private D3D12RefCountPtr<ID3D12CommandQueue>             m_GraphicsQueue;
		private D3D12RefCountPtr<ID3D12CommandQueue>             m_ComputeQueue;
		private D3D12RefCountPtr<ID3D12CommandQueue>             m_CopyQueue;
		private D3D12RefCountPtr<IDXGISwapChain3>                m_SwapChain;
		private DXGI_SWAP_CHAIN_DESC1                       m_SwapChainDesc = .();
		private DXGI_SWAP_CHAIN_FULLSCREEN_DESC             m_FullScreenDesc = .();
		private D3D12RefCountPtr<IDXGIAdapter>                   m_DxgiAdapter;
		private HWND                                        m_hWnd = 0;
		private bool                                        m_TearingSupported = false;

		private List<D3D12RefCountPtr<ID3D12Resource>>    m_SwapChainBuffers = new .() ~ delete _;
		private List<nvrhi.TextureHandle>           m_RhiSwapChainBuffers = new .() ~ delete _;
		private D3D12RefCountPtr<ID3D12Fence>                    m_FrameFence;
		private List<HANDLE>                         m_FrameFenceEvents = new .() ~ delete _;

		private UINT64                                      m_FrameCount = 1;

		private nvrhi.d3d12.IDeviceD3D12                         m_NvrhiDevice;
		private nvrhi.DeviceHandle                         m_ValidationLayer;

		private String                                 m_RendererString;

		public this(DeviceCreationParameters @params) : base(@params)
		{
		}

		protected override bool CreateDeviceAndSwapChain()
		{
			WINDOW_STYLE windowStyle = m_DeviceParams.startFullscreen
				? (.WS_POPUP | .WS_SYSMENU | .WS_VISIBLE)
				: m_DeviceParams.startMaximized
				? (.WS_OVERLAPPEDWINDOW | .WS_VISIBLE | .WS_MAXIMIZE)
				: (.WS_OVERLAPPEDWINDOW | .WS_VISIBLE);

			RECT rect = .() { left = 0, top = 0, right = (.)(m_DeviceParams.backBufferWidth),  bottom = (.)(m_DeviceParams.backBufferHeight) };
			AdjustWindowRect(&rect, windowStyle, 0);

			D3D12RefCountPtr<IDXGIAdapter> targetAdapter = null;

			if (m_DeviceParams.adapter != null)
			{
				targetAdapter = m_DeviceParams.adapter;
			}
			else
			{
				if (!GetSuitableAdapter(out targetAdapter))
				{
					Debug.WriteLine("Could not find a suitable adapter.");
				}

				/*targetAdapter = FindAdapter(m_DeviceParams.adapterNameSubstring);

				if (targetAdapter == null)
				{
					std.wstring adapterNameStr(m_DeviceParams.adapterNameSubstring.begin(), m_DeviceParams.adapterNameSubstring.end());

					Debug.WriteLine("Could not find an adapter matching {}\n", adapterNameStr);
					return false;
				}*/
			}
			{
				DXGI_ADAPTER_DESC aDesc = .();
				targetAdapter.GetDesc(&aDesc);

				m_RendererString = new String(&aDesc.Description);
			}

			if (MoveWindowOntoAdapter(targetAdapter, ref rect))
			{
				//glfwSetWindowPos(m_Window, rect.left, rect.top);
			}

			m_hWnd = (int)m_DeviceParams.windowHandle;

			HRESULT hr = E_FAIL;

			RECT clientRect = .();
			GetClientRect(m_hWnd, &clientRect);
			int32 width = clientRect.right - clientRect.left;
			int32 height = clientRect.bottom - clientRect.top;

			m_SwapChainDesc = .();
			//ZeroMemory(&m_SwapChainDesc, sizeof(decltype(m_SwapChainDesc)));
			m_SwapChainDesc.Width = (.)width;
			m_SwapChainDesc.Height = (.)height;
			m_SwapChainDesc.SampleDesc.Count = m_DeviceParams.swapChainSampleCount;
			m_SwapChainDesc.SampleDesc.Quality = 0;
			m_SwapChainDesc.BufferUsage = (.)m_DeviceParams.swapChainUsage;
			m_SwapChainDesc.BufferCount = m_DeviceParams.swapChainBufferCount;
			m_SwapChainDesc.SwapEffect = (.)DXGI_SWAP_EFFECT.DXGI_SWAP_EFFECT_FLIP_DISCARD;
			m_SwapChainDesc.Flags = m_DeviceParams.allowModeSwitch ? (.)DXGI_SWAP_CHAIN_FLAG.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH : 0;

			// Special processing for sRGB swap chain formats.
			// DXGI will not create a swap chain with an sRGB format, but its contents will be interpreted as sRGB.
			// So we need to use a non-sRGB format here, but store the true sRGB format for later framebuffer creation.
			switch (m_DeviceParams.swapChainFormat) // NOLINT(clang-diagnostic-switch-enum)
			{
			case nvrhi.Format.SRGBA8_UNORM:
				m_SwapChainDesc.Format = DXGI_FORMAT.DXGI_FORMAT_R8G8B8A8_UNORM;
				break;
			case nvrhi.Format.SBGRA8_UNORM:
				m_SwapChainDesc.Format = DXGI_FORMAT.DXGI_FORMAT_B8G8R8A8_UNORM;
				break;
			default:
				m_SwapChainDesc.Format = nvrhi.d3d12.convertFormat(m_DeviceParams.swapChainFormat);
				break;
			}

			if (m_DeviceParams.enableDebugRuntime)
			{
				D3D12RefCountPtr<ID3D12Debug> pDebug = null;
				hr = D3D12GetDebugInterface(ID3D12Debug.IID, (void**)(&pDebug));
				HR_RETURN!(hr);

				pDebug.EnableDebugLayer();
			}

			D3D12RefCountPtr<IDXGIFactory2> pDxgiFactory = null;
			UINT dxgiFactoryFlags = m_DeviceParams.enableDebugRuntime ? DXGI_CREATE_FACTORY_DEBUG : 0;
			hr = CreateDXGIFactory2(dxgiFactoryFlags, IDXGIFactory2.IID, (void**)(&pDxgiFactory));
			HR_RETURN!(hr);

			D3D12RefCountPtr<IDXGIFactory5> pDxgiFactory5 = null;
			if (SUCCEEDED(pDxgiFactory.QueryInterface(IDXGIFactory5.IID, (void**)(&pDxgiFactory5))))
			{
				BOOL supported = 0;
				if (SUCCEEDED(pDxgiFactory5.CheckFeatureSupport(DXGI_FEATURE.DXGI_FEATURE_PRESENT_ALLOW_TEARING, &supported, sizeof(decltype(supported)))))
					m_TearingSupported = (supported != 0);
			}

			if (m_TearingSupported)
			{
				m_SwapChainDesc.Flags |= (.)DXGI_SWAP_CHAIN_FLAG.DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING;
			}

			hr = D3D12CreateDevice(
				targetAdapter,
				m_DeviceParams.featureLevel,
				ID3D12Device.IID,
				(void**)(&m_Device12));
			HR_RETURN!(hr);

			if (m_DeviceParams.enableDebugRuntime)
			{
				D3D12RefCountPtr<ID3D12InfoQueue> pInfoQueue = null;
				m_Device12.QueryInterface(ID3D12InfoQueue.IID, (void**)&pInfoQueue);

				if (pInfoQueue != null)
				{
#if DEBUG
					pInfoQueue.SetBreakOnSeverity(D3D12_MESSAGE_SEVERITY.D3D12_MESSAGE_SEVERITY_CORRUPTION, 1);
					pInfoQueue.SetBreakOnSeverity(D3D12_MESSAGE_SEVERITY.D3D12_MESSAGE_SEVERITY_ERROR, 1);
#endif

					D3D12_MESSAGE_ID[?] disableMessageIDs = .(
						D3D12_MESSAGE_ID.D3D12_MESSAGE_ID_CLEARDEPTHSTENCILVIEW_MISMATCHINGCLEARVALUE,
						D3D12_MESSAGE_ID.D3D12_MESSAGE_ID_COMMAND_LIST_STATIC_DESCRIPTOR_RESOURCE_DIMENSION_MISMATCH // descriptor validation doesn't understand acceleration structures
						);

					D3D12_INFO_QUEUE_FILTER filter = .();
					filter.DenyList.pIDList = &disableMessageIDs;
					filter.DenyList.NumIDs = sizeof(decltype(disableMessageIDs)) / sizeof(decltype(disableMessageIDs[0]));
					pInfoQueue.AddStorageFilterEntries(&filter);
				}
			}

			m_DxgiAdapter = targetAdapter;

			D3D12_COMMAND_QUEUE_DESC queueDesc = .();
			//ZeroMemory(&queueDesc, sizeof(decltype(queueDesc)));
			queueDesc.Flags = D3D12_COMMAND_QUEUE_FLAGS.D3D12_COMMAND_QUEUE_FLAG_NONE;
			queueDesc.Type = D3D12_COMMAND_LIST_TYPE.D3D12_COMMAND_LIST_TYPE_DIRECT;
			queueDesc.NodeMask = 1;
			hr = m_Device12.CreateCommandQueue(&queueDesc, ID3D12CommandQueue.IID, (void**)(&m_GraphicsQueue));
			HR_RETURN!(hr);
			m_GraphicsQueue.SetName("Graphics Queue".ToScopedNativeWChar!::());

			if (m_DeviceParams.enableComputeQueue)
			{
				queueDesc.Type = D3D12_COMMAND_LIST_TYPE.D3D12_COMMAND_LIST_TYPE_COMPUTE;
				hr = m_Device12.CreateCommandQueue(&queueDesc, ID3D12CommandQueue.IID, (void**)(&m_ComputeQueue));
				HR_RETURN!(hr);
				m_ComputeQueue.SetName("Compute Queue".ToScopedNativeWChar!::());
			}

			if (m_DeviceParams.enableCopyQueue)
			{
				queueDesc.Type = D3D12_COMMAND_LIST_TYPE.D3D12_COMMAND_LIST_TYPE_COPY;
				hr = m_Device12.CreateCommandQueue(&queueDesc, ID3D12CommandQueue.IID, (void**)(&m_CopyQueue));
				HR_RETURN!(hr);
				m_CopyQueue.SetName("Copy Queue".ToScopedNativeWChar!::());
			}

			m_FullScreenDesc = .();
			m_FullScreenDesc.RefreshRate.Numerator = m_DeviceParams.refreshRate;
			m_FullScreenDesc.RefreshRate.Denominator = 1;
			m_FullScreenDesc.ScanlineOrdering = DXGI_MODE_SCANLINE_ORDER.DXGI_MODE_SCANLINE_ORDER_PROGRESSIVE;
			m_FullScreenDesc.Scaling = DXGI_MODE_SCALING.DXGI_MODE_SCALING_UNSPECIFIED;
			m_FullScreenDesc.Windowed = m_DeviceParams.startFullscreen ? 0 : 1;

			D3D12RefCountPtr<IDXGISwapChain1> pSwapChain1 = null;
			hr = pDxgiFactory.CreateSwapChainForHwnd(m_GraphicsQueue, m_hWnd, &m_SwapChainDesc, &m_FullScreenDesc, null, &pSwapChain1);
			HR_RETURN!(hr);

			hr = pSwapChain1.QueryInterface(IDXGISwapChain3.IID, (void**)(&m_SwapChain));
			HR_RETURN!(hr);

			nvrhi.d3d12.D3D12DeviceDesc deviceDesc = .();
			//deviceDesc.errorCB = &DefaultMessageCallback.GetInstance();
			deviceDesc.pDevice = m_Device12;
			deviceDesc.pGraphicsCommandQueue = m_GraphicsQueue;
			deviceDesc.pComputeCommandQueue = m_ComputeQueue;
			deviceDesc.pCopyCommandQueue = m_CopyQueue;

			m_NvrhiDevice = nvrhi.d3d12.createDevice(deviceDesc);

			if (m_DeviceParams.enableNvrhiValidationLayer)
			{
				m_ValidationLayer = nvrhi.validation.createValidationLayer(m_NvrhiDevice);
			}

			if (!CreateRenderTargets())
				return false;

			hr = m_Device12.CreateFence(0, D3D12_FENCE_FLAGS.D3D12_FENCE_FLAG_NONE, ID3D12Fence.IID, (void**)(&m_FrameFence));
			HR_RETURN!(hr);

			for (UINT bufferIndex = 0; bufferIndex < m_SwapChainDesc.BufferCount; bufferIndex++)
			{
				m_FrameFenceEvents.Add(CreateEventA(null, 0, 1, null));
			}

			return true;
		}

		protected override void DestroyDeviceAndSwapChain()
		{
			for(var scb in m_RhiSwapChainBuffers){
				scb?.Release();
			}

			m_RhiSwapChainBuffers.Clear();
			m_RendererString.Clear();
			delete m_RendererString;

			ReleaseRenderTargets();

			m_ValidationLayer?.Release();
			m_ValidationLayer = null;

			m_NvrhiDevice?.Release();
			m_NvrhiDevice = null;

			for (var fenceEvent in m_FrameFenceEvents)
			{
				WaitForSingleObject(fenceEvent, INFINITE);
				CloseHandle(fenceEvent);
			}

			m_FrameFenceEvents.Clear();

			if (m_SwapChain != null)
			{
				m_SwapChain.SetFullscreenState(0, null);
			}

			m_SwapChainBuffers.Clear();

			m_FrameFence?.Release();
			m_FrameFence = null;

			m_SwapChain?.Release();
			m_SwapChain = null;

			m_GraphicsQueue?.Release();
			m_GraphicsQueue = null;

			m_ComputeQueue?.Release();
			m_ComputeQueue = null;

			m_CopyQueue?.Release();
			m_CopyQueue = null;

			m_Device12?.Release();
			m_Device12 = null;

			m_DxgiAdapter?.Release();
			m_DxgiAdapter = null;
		}

		protected override void ResizeSwapChain()
		{
			ReleaseRenderTargets();

			if (m_NvrhiDevice == null)
				return;

			if (m_SwapChain == null)
				return;

			readonly HRESULT hr = m_SwapChain.ResizeBuffers(m_DeviceParams.swapChainBufferCount,
				m_DeviceParams.backBufferWidth,
				m_DeviceParams.backBufferHeight,
				m_SwapChainDesc.Format,
				m_SwapChainDesc.Flags);

			if (FAILED(hr))
			{
				Debug.WriteLine("ResizeBuffers failed: 0x{0:X}", hr);
			}

			bool ret = CreateRenderTargets();
			if (!ret)
			{
				Debug.WriteLine("CreateRenderTarget failed");
			}
		}

		protected override void BeginFrame()
		{
			DXGI_SWAP_CHAIN_DESC1 newSwapChainDesc = .();
			DXGI_SWAP_CHAIN_FULLSCREEN_DESC newFullScreenDesc = .();
			if (SUCCEEDED(m_SwapChain.GetDesc1(&newSwapChainDesc)) && SUCCEEDED(m_SwapChain.GetFullscreenDesc(&newFullScreenDesc)))
			{
				if (m_FullScreenDesc.Windowed != newFullScreenDesc.Windowed)
				{
					BackBufferResizing();

					m_FullScreenDesc = newFullScreenDesc;
					m_SwapChainDesc = newSwapChainDesc;
					m_DeviceParams.backBufferWidth = newSwapChainDesc.Width;
					m_DeviceParams.backBufferHeight = newSwapChainDesc.Height;

					if (newFullScreenDesc.Windowed > 0)
					{
						//glfwSetWindowMonitor(m_Window, nullptr, 50, 50, newSwapChainDesc.Width, newSwapChainDesc.Height, 0);
					}

					ResizeSwapChain();
					BackBufferResized();
				}
			}

			var bufferIndex = m_SwapChain.GetCurrentBackBufferIndex();

			WaitForSingleObject(m_FrameFenceEvents[bufferIndex], INFINITE);
		}

		protected override void Present()
		{
			/*if (!m_windowVisible)
				return;*/

			var bufferIndex = m_SwapChain.GetCurrentBackBufferIndex();

			UINT presentFlags = 0;
			if (!m_DeviceParams.vsyncEnabled && m_FullScreenDesc.Windowed > 0 && m_TearingSupported)
				presentFlags |= DXGI_PRESENT_ALLOW_TEARING;

			m_SwapChain.Present(m_DeviceParams.vsyncEnabled ? 1 : 0, presentFlags);

			m_FrameFence.SetEventOnCompletion(m_FrameCount, m_FrameFenceEvents[bufferIndex]);
			m_GraphicsQueue.Signal(m_FrameFence, m_FrameCount);
			m_FrameCount++;
		}

		public override nvrhi.IDevice GetDevice()
		{
				if (m_ValidationLayer != null)
					return m_ValidationLayer;

				return m_NvrhiDevice;
		}

		public override GraphicsAPI GetGraphicsAPI()
		{
			return nvrhi.GraphicsAPI.D3D12;
		}

		public override ITexture GetCurrentBackBuffer()
		{
			return m_RhiSwapChainBuffers[m_SwapChain.GetCurrentBackBufferIndex()];
		}

		public override ITexture GetBackBuffer(uint32 index)
		{
			if (index < m_RhiSwapChainBuffers.Count)
				return m_RhiSwapChainBuffers[index];
			return null;
		}

		public override uint32 GetCurrentBackBufferIndex()
		{
			return m_SwapChain.GetCurrentBackBufferIndex();
		}

		public override uint32 GetBackBufferCount()
		{
			return m_SwapChainDesc.BufferCount;
		}

		public bool CreateRenderTargets()
		{
			m_SwapChainBuffers.Resize(m_SwapChainDesc.BufferCount);
			m_RhiSwapChainBuffers.Resize(m_SwapChainDesc.BufferCount);

			for (UINT n = 0; n < m_SwapChainDesc.BufferCount; n++)
			{
				readonly HRESULT hr = m_SwapChain.GetBuffer(n, ID3D12Resource.IID, (void**)(&m_SwapChainBuffers[n]));
				HR_RETURN!(hr);

				nvrhi.TextureDesc textureDesc = .();
				textureDesc.width = m_DeviceParams.backBufferWidth;
				textureDesc.height = m_DeviceParams.backBufferHeight;
				textureDesc.sampleCount = m_DeviceParams.swapChainSampleCount;
				textureDesc.sampleQuality = m_DeviceParams.swapChainSampleQuality;
				textureDesc.format = m_DeviceParams.swapChainFormat;
				textureDesc.debugName = "SwapChainBuffer";
				textureDesc.isRenderTarget = true;
				textureDesc.isUAV = false;
				textureDesc.initialState = nvrhi.ResourceStates.Present;
				textureDesc.keepInitialState = true;

				m_RhiSwapChainBuffers[n] = m_NvrhiDevice.createHandleForNativeTexture(nvrhi.ObjectType.D3D12_Resource, nvrhi.NativeObject(m_SwapChainBuffers[n]), textureDesc);
			}

			return true;
		}

		public void ReleaseRenderTargets()
		{
			// Make sure that all frames have finished rendering
			m_NvrhiDevice.waitForIdle();

			// Release all in-flight references to the render targets
			m_NvrhiDevice.runGarbageCollection();

			// Set the events so that WaitForSingleObject in OneFrame will not hang later
			for (var e in m_FrameFenceEvents)
				SetEvent(e);

			// Release the old buffers because ResizeBuffers requires that
			for(var scb in m_RhiSwapChainBuffers){
				scb?.Release();
				scb = null;
			}
			m_RhiSwapChainBuffers.Clear();
			m_SwapChainBuffers.Clear();
		}
	}
}