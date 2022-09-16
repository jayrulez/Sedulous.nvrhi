using nvrhi.sampleFramework.SDL;
using nvrhi.deviceManager;
using nvrhi.deviceManager.d3d12;
using nvrhi.deviceManager.vulkan;
using System;
using System.Collections;
using System.IO;
using nvrhi.shaderCompiler.Dxc;
namespace nvrhi.test;

class TestApplication : SampleApplication
{
	private nvrhi.CommandListHandle mCommandList;

	private nvrhi.ShaderHandle mVertexShader;
	private nvrhi.ShaderHandle mPixelShader;

	public this(GraphicsAPI graphicsAPI, System.String windowTitle, uint windowWidth, uint windowHeight)
		: base(graphicsAPI, windowTitle, windowWidth, windowHeight)
	{
	}

	protected override Result<void> OnInitialize()
	{
		if (base.OnInitialize() case .Err)
		{
			return .Err;
		}

		mCommandList = mDeviceManager.GetDevice().createCommandList();

		DxcShaderCompiler shaderCompiler = scope .(Directory.GetCurrentDirectory(.. scope .()));

		var vsByteCode = shaderCompiler.CompileShader(.()
			{
				ShaderPath = "shaders/shaders.hlsl",
				ShaderType = .Vertex,
				EntryPoint = "main_vs",
				OutputType = mDeviceManager.GetGraphicsAPI() == .VULKAN ? .SPIRV : .DXIL
			}, .. scope .());

		var psByteCode = shaderCompiler.CompileShader(.()
			{
				ShaderPath = "shaders/shaders.hlsl",
				ShaderType = .Pixel,
				EntryPoint = "main_ps",
				OutputType = mDeviceManager.GetGraphicsAPI() == .VULKAN ? .SPIRV : .DXIL
			}, .. scope .());

		ShaderFactory shaderFactory = scope .(mDeviceManager.GetDevice(), .. Path.InternalCombine(.. Directory.GetCurrentDirectory(.. scope .()), "shaders"));

		mVertexShader = shaderFactory.CreateShader("shaders.hlsl", vsByteCode, "main_vs", null, nvrhi.ShaderType.Vertex);
		mPixelShader = shaderFactory.CreateShader("shaders.hlsl", psByteCode, "main_ps", null, nvrhi.ShaderType.Pixel);

		return .Ok;
	}

	protected override void OnFinalize()
	{
		mPixelShader?.Release();
		mVertexShader?.Release();
		mCommandList?.Release();

		base.OnFinalize();
	}

	protected override void OnFrame()
	{
		base.OnFrame();

		mDeviceManager.[Friend]BeginFrame();

		var framebuffer = mDeviceManager.GetCurrentFramebuffer();

		// Pipeline
		// only create if null
		if (mPipeline == null)
		{
			nvrhi.GraphicsPipelineDesc psoDesc = .();
			psoDesc.VS = mVertexShader;
			psoDesc.PS = mPixelShader;
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

			mPipeline = mDeviceManager.GetDevice().createGraphicsPipeline(psoDesc, framebuffer);
		}

		// Render
		mCommandList.open();

		nvrhi.utils.ClearColorAttachment(mCommandList, framebuffer, 0, nvrhi.Color(0.f, 0.5f, 0.2f, 1));

		nvrhi.GraphicsState state = .();
		state.pipeline = mPipeline;
		state.framebuffer = framebuffer;
		state.viewport.addViewportAndScissorRect(framebuffer.getFramebufferInfo().getViewport());

		mCommandList.setGraphicsState(state);

		nvrhi.DrawArguments args = .();
		args.vertexCount = 3;
		mCommandList.draw(args);

		mCommandList.close();

		mDeviceManager.GetDevice().executeCommandList(mCommandList);

		// Present
		mDeviceManager.[Friend]Present();

		mDeviceManager.GetDevice().waitForIdle();
	}
}