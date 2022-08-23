using System;
using System.Collections;
namespace nvrhi.deviceManager
{
	enum WindowType
	{
		Windows
	}

	struct DeviceCreationParameters
	{
		public bool startMaximized = false;
		public bool startFullscreen = false;
		public bool allowModeSwitch = true;
		public int32 windowPosX = -1; // -1 means use default placement
		public int32 windowPosY = -1;
		public uint32 backBufferWidth = 1280;
		public uint32 backBufferHeight = 720;
		public uint32 refreshRate = 0;
		public uint32 swapChainBufferCount = 3;
		public nvrhi.Format swapChainFormat = nvrhi.Format.SRGBA8_UNORM;
		public uint32 swapChainSampleCount = 1;
		public uint32 swapChainSampleQuality = 0;
		public WindowType windowType = .();
		public void* windowHandle = null;
		public uint32 maxFramesInFlight = 2;
		public bool enableDebugRuntime = false;
		public bool enableNvrhiValidationLayer = false;
		public bool vsyncEnabled = false;
		public bool enableRayTracingExtensions = false; // for vulkan
		public bool enableComputeQueue = false;
		public bool enableCopyQueue = false;

		// Severity of the information log messages from the device manager, like the device name or enabled extensions.
		//log.Severity infoLogSeverity = log.Severity.Info;

	}


	abstract class DeviceManager
	{
		protected DeviceCreationParameters m_DeviceParams;
		protected uint32 m_FrameIndex = 0;
		protected List<nvrhi.FramebufferHandle> m_SwapChainFramebuffers = new .() ~ delete _;
		protected bool m_RequestedVSync = false;

		public this(DeviceCreationParameters @params)
		{
			m_DeviceParams = @params;
		}

		public ~this()
		{

		}

		public void Shutdown()
		{
			for(var sfb in m_SwapChainFramebuffers){
				sfb.Release();
			}

			m_SwapChainFramebuffers.Clear();

			DestroyDeviceAndSwapChain();
		}

		protected void BackBufferResizing()
		{
			for (var sfb in m_SwapChainFramebuffers)
			{
				sfb.Release();
			}
			m_SwapChainFramebuffers.Clear();
		}

		protected void BackBufferResized()
		{
			uint32 backBufferCount = GetBackBufferCount();
			m_SwapChainFramebuffers.Resize(backBufferCount);
			for (uint32 index = 0; index < backBufferCount; index++)
			{
				m_SwapChainFramebuffers[index] = GetDevice().createFramebuffer(
					nvrhi.FramebufferDesc().addColorAttachment(GetBackBuffer(index)));
			}
		}

		public void OnWindowResized(uint32 width, uint32 height, bool forceResize = false)
		{
			if (forceResize || int(m_DeviceParams.backBufferWidth) != width ||
				int(m_DeviceParams.backBufferHeight) != height ||
				(m_DeviceParams.vsyncEnabled != m_RequestedVSync && GetGraphicsAPI() == nvrhi.GraphicsAPI.VULKAN))
			{
				// window is not minimized, and the size has changed

				BackBufferResizing();

				m_DeviceParams.backBufferWidth = width;
				m_DeviceParams.backBufferHeight = height;
				m_DeviceParams.vsyncEnabled = m_RequestedVSync;

				ResizeSwapChain();
				BackBufferResized();
			}

			m_DeviceParams.vsyncEnabled = m_RequestedVSync;
		}

		protected abstract bool CreateDeviceAndSwapChain();
		protected abstract void DestroyDeviceAndSwapChain();
		protected abstract void ResizeSwapChain();
		protected abstract void BeginFrame();
		protected abstract void Present();

		[NoDiscard] public abstract nvrhi.IDevice GetDevice();
		[NoDiscard] public abstract nvrhi.GraphicsAPI GetGraphicsAPI();

		public readonly ref DeviceCreationParameters GetDeviceParams() => ref m_DeviceParams;

		[NoDiscard] public bool IsVsyncEnabled() { return m_DeviceParams.vsyncEnabled; }
		public void SetVsyncEnabled(bool enabled) { m_RequestedVSync = enabled; /* will be processed later */ }
		public void ReportLiveObjects() { }

		[NoDiscard] public uint32 GetFrameIndex() { return m_FrameIndex; }

		public abstract nvrhi.ITexture GetCurrentBackBuffer();

		public abstract nvrhi.ITexture GetBackBuffer(uint32 index);

		public abstract  uint32 GetCurrentBackBufferIndex();

		public abstract  uint32 GetBackBufferCount();


		public nvrhi.IFramebuffer GetCurrentFramebuffer()
		{
			return GetFramebuffer(GetCurrentBackBufferIndex());
		}

		public nvrhi.IFramebuffer GetFramebuffer(uint32 index)
		{
			if (index < m_SwapChainFramebuffers.Count)
				return m_SwapChainFramebuffers[index];

			return null;
		}
	}
}