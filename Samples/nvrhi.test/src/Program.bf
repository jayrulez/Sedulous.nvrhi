using System;
using SDL2;
using nvrhi.deviceManager.vulkan;
using nvrhi.deviceManager;
using System.IO;
using System.Diagnostics;
using nvrhi.shaderCompiler.Dxc;
using nvrhi.deviceManager.d3d12;
namespace nvrhi.test;

class Program
{
	public static void Main()
	{
		var app = scope TestApplication(.D3D12, "Hello", 1280, 720);
		app.Run();
	}
}