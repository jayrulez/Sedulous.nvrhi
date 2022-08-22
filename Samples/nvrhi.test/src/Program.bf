using System;
using SDL2;
using nvrhi.deviceManager.vulkan;
using nvrhi.deviceManager;
namespace nvrhi.test
{

	/*abstract class ITexture : IResource
	{
	}

	typealias TextureHandle = RefCountPtr<ITexture>;

	class VKTexture : ITexture
	{
	}*/

	class Program
	{
		private static bool mSDLInitialized = false;
		private static SDL.Window* SDLNativeWindow;
		private static void* NativeWindow;
		private static bool mQuitRequested = false;

		public static void Main()
		{

			/*var texture = new VKTexture();
			var textureHandle = TextureHandle.Attach(texture);

			textureHandle.Release();*/

			if (SDL.Init(.Everything) < 0)
			{
				Runtime.FatalError(scope $"SDL initialization failed: {SDL.GetError()}");
			}
			mSDLInitialized = true;

			//Window = new SDLWindow(windowTitle, (.)windowWidth, (.)windowHeight);

			SDL.PumpEvents();

			String title = scope .("Hello");
			uint32 width = 1280;
			uint32 height = 720;

			SDL.WindowFlags flags = .Shown | SDL.WindowFlags.Resizable | SDL.WindowFlags.Vulkan;
			SDLNativeWindow = SDL.CreateWindow(title.Ptr, .Undefined, .Undefined, (int32)width, (int32)height, flags);

			if (SDLNativeWindow == null)
			{
				Runtime.FatalError("Failed to create SDL window.");
			}

			SDL.SDL_SysWMinfo info = .();
			SDL.GetVersion(out info.version);
			SDL.GetWindowWMInfo(SDLNativeWindow, ref info);
			SDL.SDL_SYSWM_TYPE subsystem = info.subsystem;
			switch (subsystem) {
			case SDL.SDL_SYSWM_TYPE.SDL_SYSWM_WINDOWS:
				NativeWindow = (void*)(int)info.info.win.window;
				break;

			case SDL.SDL_SYSWM_TYPE.SDL_SYSWM_UNKNOWN: fallthrough;
			default:
				Runtime.FatalError("Subsystem not currently supported.");
			}

			DeviceCreationParameters @params = .()
				{
					windowType = .Windows,
					windowHandle = NativeWindow,
					backBufferWidth = width,
					backBufferHeight = height
				};

			DeviceManager deviceManager = new VulkanDeviceManager(@params);

			defer delete deviceManager;

			deviceManager.[Friend]CreateDeviceAndSwapChain();

			// force resize so back buffer resources get created
			deviceManager.OnWindowResized((.)width, (.)height, true);

			var commandList = deviceManager.GetDevice().createCommandList();
			defer commandList.Release();

			while (!mQuitRequested)
			{
				deviceManager.[Friend]BeginFrame();

				// poll events
				{
					while (SDL.PollEvent(let ev) != 0)
					{
						if (ev.type == SDL.EventType.WindowEvent)
						{
							var windowEvent = ev.window;
							if (windowEvent.windowEvent != .SizeChanged)
							{
								switch (windowEvent.windowEvent) {
								case .FocusGained:
									//OnFocusGained();
									break;

								case .Focus_lost:
									//OnFocusLost();
									break;

								case .Close:
									//OnClosing();
									break;

								default:
									break;
								}
							} else
							{
								SDL.GetWindowSize(SDLNativeWindow, var newWidth, var newHeight);

								width = (uint32)width;
								height = (uint32)height;

								deviceManager.OnWindowResized((.)newWidth, (.)newHeight);
							}
						}

						if (ev.type == .Quit)
						{
							mQuitRequested = true;
						}
					}
				}

				// Render

				commandList.open();

				var fb = deviceManager.GetCurrentFramebuffer();

				nvrhi.utils.ClearColorAttachment(commandList, fb, 0, nvrhi.Color(0.f));

				commandList.close();

				deviceManager.GetDevice().executeCommandList(commandList);


				// Present
				deviceManager.[Friend]Present();

				deviceManager.GetDevice().waitForIdle();
			}

			deviceManager.Shutdown();

			if (SDLNativeWindow != null)
			{
				SDL.DestroyWindow(SDLNativeWindow);
				SDLNativeWindow = null;
			}

			if (mSDLInitialized)
			{
				SDL.Quit();
			}
		}
	}
}