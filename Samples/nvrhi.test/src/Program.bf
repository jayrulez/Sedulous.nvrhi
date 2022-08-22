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
			uint width = 1280;
			uint height = 720;

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
					windowHandle = NativeWindow
				};

			DeviceManager deviceManager = new VulkanDeviceManager(@params);

			defer delete deviceManager;

			deviceManager.[Friend]CreateDeviceAndSwapChain();

			Console.Read();



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