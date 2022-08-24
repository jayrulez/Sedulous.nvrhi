using System;
using SDL2;
using nvrhi.deviceManager.vulkan;
using nvrhi.deviceManager;
using System.IO;
using System.Diagnostics;
using nvrhi.shaderCompiler.Dxc;
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
					backBufferHeight = height,
					enableNvrhiValidationLayer = true
				};

			DeviceManager deviceManager = new VulkanDeviceManager(@params);

			defer delete deviceManager;

			deviceManager.[Friend]CreateDeviceAndSwapChain();

			defer deviceManager.Shutdown();

			DxcShaderCompiler shaderCompiler = scope .(Directory.GetCurrentDirectory(.. scope .()));

			var vsByteCode = shaderCompiler.CompileShader(.()
				{
					ShaderPath = "shaders/shaders.hlsl",
					ShaderType = .Vertex,
					EntryPoint = "main_vs",
					OutputType = deviceManager.GetGraphicsAPI() == .VULKAN ? .SPIRV : .DXIL
				}, ..scope .());

			var psByteCode = shaderCompiler.CompileShader(.()
				{
					ShaderPath = "shaders/shaders.hlsl",
					ShaderType = .Pixel,
					EntryPoint = "main_ps",
					OutputType = deviceManager.GetGraphicsAPI() == .VULKAN ? .SPIRV : .DXIL
				}, ..scope .());

			ShaderFactory shaderFactory = scope .(deviceManager.GetDevice(), .. Path.InternalCombine(.. Directory.GetCurrentDirectory(.. scope .()), "shaders"));
			//nvrhi.ShaderHandle vertexShader = shaderFactory.CreateShader("shaders.hlsl", "main_vs", null, nvrhi.ShaderType.Vertex);
			nvrhi.ShaderHandle vertexShader = shaderFactory.CreateShader("shaders.hlsl", vsByteCode, "main_vs", null, nvrhi.ShaderType.Vertex);
			defer vertexShader.Release();

			//nvrhi.ShaderHandle pixelShader = shaderFactory.CreateShader("shaders.hlsl", "main_ps", null, nvrhi.ShaderType.Pixel);
			nvrhi.ShaderHandle pixelShader = shaderFactory.CreateShader("shaders.hlsl", psByteCode, "main_ps", null, nvrhi.ShaderType.Pixel);
			defer pixelShader.Release();

			// force resize so back buffer resources get created
			deviceManager.OnWindowResized((.)width, (.)height, true);

			nvrhi.CommandListHandle commandList = deviceManager.GetDevice().createCommandList();
			defer commandList.Release();


			nvrhi.GraphicsPipelineHandle pipeline = null;

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

								pipeline?.Release();
								pipeline = null;
							}
						}

						if (ev.type == .Quit)
						{
							mQuitRequested = true;
						}
					}
				}

				var framebuffer = deviceManager.GetCurrentFramebuffer();

				// Pipeline
				// only create if null
				if (pipeline == null)
				{
					nvrhi.GraphicsPipelineDesc psoDesc = .();
					psoDesc.VS = vertexShader;
					psoDesc.PS = pixelShader;
					psoDesc.primType = nvrhi.PrimitiveType.TriangleList;
					psoDesc.renderState.depthStencilState.depthTestEnable = false;

					// Note: Latest beef has .InitAll for sized arrays, use it wherever necessary.
					//// None of this should be necessary. Perhaps there is a beef bug here. I need to ask in the discord.
					//// I expect that all nested struct members should be initialzed automatically when nvrhi.GraphicsPipelineDesc psoDesc = .();
					//// is called. For some reason, the members of the static array of render targets initializer fields are not called
					/*psoDesc.renderState.blendState = .();
					for (int i = 0; i < psoDesc.renderState.blendState.targets.Count; i++)
					{
						psoDesc.renderState.blendState.targets[i] = .();
					}*/
					////

					pipeline = deviceManager.GetDevice().createGraphicsPipeline(psoDesc, framebuffer);
				}

				// Render

				commandList.open();

				nvrhi.utils.ClearColorAttachment(commandList, framebuffer, 0, nvrhi.Color(0.f, 0.5f, 0.2f, 1));

				nvrhi.GraphicsState state = .();
				state.pipeline = pipeline;
				state.framebuffer = framebuffer;
				state.viewport.addViewportAndScissorRect(framebuffer.getFramebufferInfo().getViewport());

				commandList.setGraphicsState(state);

				nvrhi.DrawArguments args = .();
				args.vertexCount = 3;
				commandList.draw(args);

				commandList.close();

				deviceManager.GetDevice().executeCommandList(commandList);


				// Present
				deviceManager.[Friend]Present();

				deviceManager.GetDevice().waitForIdle();
			}

			pipeline?.Release();

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