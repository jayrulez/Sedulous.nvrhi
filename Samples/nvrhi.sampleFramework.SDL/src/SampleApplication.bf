using nvrhi.deviceManager;
using nvrhi.deviceManager.vulkan;
using nvrhi.deviceManager.d3d12;
using System;
namespace nvrhi.sampleFramework.SDL;

class SampleApplication : SDLApplication
{
	protected DeviceManager mDeviceManager;
	protected nvrhi.GraphicsPipelineHandle mPipeline;

	private GraphicsAPI mGraphicsAPI = .VULKAN;

	public this(GraphicsAPI graphicsAPI, System.String windowTitle, uint windowWidth, uint windowHeight)
		: base(windowTitle, windowWidth, windowHeight)
	{
		mGraphicsAPI = graphicsAPI;
	}

	protected override System.Result<void> OnStartup()
	{
		if (base.OnStartup() case .Err)
			return .Err;

		DeviceCreationParameters @params = .()
			{
				windowType = Window.SurfaceInfo.WindowType,
				windowHandle = Window.SurfaceInfo.WindowHandle,
				backBufferWidth = Window.Width,
				backBufferHeight = Window.Height,
				enableNvrhiValidationLayer = true
			};

		if (mGraphicsAPI == .VULKAN)
			mDeviceManager = new VulkanDeviceManager(@params);
		else if (mGraphicsAPI == .D3D12)
			mDeviceManager = new D3D12DeviceManager(@params);
		else if (mGraphicsAPI == .D3D11)
			mDeviceManager = null;
		else
			return .Err;

		mDeviceManager.[Friend]CreateDeviceAndSwapChain();

		// force resize so back buffer resources get created
		mDeviceManager.OnWindowResized(Window.Width, Window.Height, true);

		Window.Resized.Subscribe(new (width, height) =>
			{
				mDeviceManager.OnWindowResized(width, height);
				mPipeline?.Release();
				mPipeline = null;
			});

		return .Ok;
	}

	protected override void OnShutdown()
	{
		mPipeline?.Release();

		if (mDeviceManager != null)
		{
			mDeviceManager.Shutdown();
			delete mDeviceManager;
			mDeviceManager = null;
		}

		base.OnShutdown();
	}
}