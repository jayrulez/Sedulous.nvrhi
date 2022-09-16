using System;
using SDL2;
namespace nvrhi.sampleFramework.SDL;

class SDLApplication : Application
{
	public Window Window { get; private set; } ~ delete _;

	private bool mSDLInitialized = false;

	public this(String windowTitle, uint windowWidth, uint windowHeight)
		: base()
	{
		if (SDL.Init(.Everything) < 0)
		{
			Runtime.FatalError(scope $"SDL initialization failed: {SDL.GetError()}");
		}
		mSDLInitialized = true;

		Window = new SDLWindow(windowTitle, (.)windowWidth, (.)windowHeight);

		SDL.PumpEvents();
	}

	protected override Result<void> OnInitialize() => .Ok;

	protected override void OnFrame()
	{
		if (let sdlWindow = Window as SDLWindow)
		{
			while (SDL.PollEvent(let ev) != 0)
			{
				sdlWindow.[Friend]OnEvent(ev);

				if (ev.type == .Quit)
				{
					Stop();
				}
			}
		}
	}

	public ~this()
	{
		if (mSDLInitialized)
		{
			SDL.Quit();
		}
	}
}