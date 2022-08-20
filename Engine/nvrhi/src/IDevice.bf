using System;
using System.Collections;
namespace nvrhi
{
	//////////////////////////////////////////////////////////////////////////
	// IDevice
	//////////////////////////////////////////////////////////////////////////

	abstract class IDevice :  IResource
	{
		public abstract HeapHandle createHeap(HeapDesc d);

		public abstract TextureHandle createTexture(TextureDesc d);
		public abstract MemoryRequirements getTextureMemoryRequirements(ITexture texture);
		public abstract bool bindTextureMemory(ITexture texture, IHeap heap, uint64 offset);

		public abstract TextureHandle createHandleForNativeTexture(ObjectType objectType, NativeObject texture, TextureDesc desc);

		public abstract StagingTextureHandle createStagingTexture(TextureDesc d, CpuAccessMode cpuAccess);
		public abstract void* mapStagingTexture(IStagingTexture tex, TextureSlice slice, CpuAccessMode cpuAccess, int* outRowPitch);
		public abstract void unmapStagingTexture(IStagingTexture tex);

		public abstract BufferHandle createBuffer(BufferDesc d);
		public abstract void* mapBuffer(IBuffer buffer, CpuAccessMode cpuAccess);
		public abstract void unmapBuffer(IBuffer buffer);
		public abstract MemoryRequirements getBufferMemoryRequirements(IBuffer buffer);
		public abstract bool bindBufferMemory(IBuffer buffer, IHeap heap, uint64 offset);

		public abstract BufferHandle createHandleForNativeBuffer(ObjectType objectType, NativeObject buffer, BufferDesc desc);

		public abstract ShaderHandle createShader(ShaderDesc d, void* binary, int binarySize);
		public abstract ShaderHandle createShaderSpecialization(IShader baseShader, ShaderSpecialization* constants, uint32 numConstants);
		public abstract ShaderLibraryHandle createShaderLibrary(void* binary, int binarySize);

		public abstract SamplerHandle createSampler(SamplerDesc d);

		// Note: vertexShader is only necessary on D3D11, otherwise it may be null
		public abstract InputLayoutHandle createInputLayout(VertexAttributeDesc* d, uint32 attributeCount, IShader vertexShader);

		// Event queries
		public abstract EventQueryHandle createEventQuery();
		public abstract void setEventQuery(IEventQuery query, CommandQueue queue);
		public abstract bool pollEventQuery(IEventQuery query);
		public abstract void waitEventQuery(IEventQuery query);
		public abstract void resetEventQuery(IEventQuery query);

		// Timer queries - see also begin/endTimerQuery in ICommandList
		public abstract TimerQueryHandle createTimerQuery();
		public abstract bool pollTimerQuery(ITimerQuery query);
		// returns time in seconds
		public abstract float getTimerQueryTime(ITimerQuery query);
		public abstract void resetTimerQuery(ITimerQuery query);

		// Returns the API kind that the RHI backend is running on top of.
		public abstract GraphicsAPI getGraphicsAPI();

		public abstract FramebufferHandle createFramebuffer(FramebufferDesc desc);

		public abstract GraphicsPipelineHandle createGraphicsPipeline(GraphicsPipelineDesc desc, IFramebuffer fb);

		public abstract ComputePipelineHandle createComputePipeline(ComputePipelineDesc desc);

		public abstract MeshletPipelineHandle createMeshletPipeline(MeshletPipelineDesc desc, IFramebuffer fb);

		public abstract nvrhi.rt.PipelineHandle createRayTracingPipeline(nvrhi.rt.PipelineDesc desc);

		public abstract BindingLayoutHandle createBindingLayout(BindingLayoutDesc desc);
		public abstract BindingLayoutHandle createBindlessLayout(BindlessLayoutDesc desc);

		public abstract BindingSetHandle createBindingSet(BindingSetDesc desc, IBindingLayout layout);
		public abstract DescriptorTableHandle createDescriptorTable(IBindingLayout layout);

		public abstract void resizeDescriptorTable(IDescriptorTable descriptorTable, uint32 newSize, bool keepContents = true);
		public abstract bool writeDescriptorTable(IDescriptorTable descriptorTable, BindingSetItem item);

		public abstract nvrhi.rt.AccelStructHandle createAccelStruct(nvrhi.rt.AccelStructDesc desc);
		public abstract MemoryRequirements getAccelStructMemoryRequirements(nvrhi.rt.IAccelStruct @as);
		public abstract bool bindAccelStructMemory(nvrhi.rt.IAccelStruct @as, IHeap heap, uint64 offset);

		public abstract CommandListHandle createCommandList(CommandListParameters @params = CommandListParameters());
		public abstract uint64 executeCommandLists(Span<ICommandList> pCommandLists, CommandQueue executionQueue = CommandQueue.Graphics);
		public abstract void queueWaitForCommandList(CommandQueue waitQueue, CommandQueue executionQueue, uint64 instance);
		public abstract void waitForIdle();

		// Releases the resources that were referenced in the command lists that have finished executing.
		// IMPORTANT: Call this method at least once per frame.
		public abstract void runGarbageCollection();

		public abstract bool queryFeatureSupport(Feature feature, void* pInfo = null, int infoSize = 0);

		public abstract FormatSupport queryFormatSupport(Format format);

		public abstract NativeObject getNativeQueue(ObjectType objectType, CommandQueue queue);

		public abstract IMessageCallback* getMessageCallback();

		// Front-end for executeCommandLists(..., 1) for compatibility and convenience
		public uint64 executeCommandList(ICommandList commandList, CommandQueue executionQueue = CommandQueue.Graphics)
		{
			return executeCommandLists(scope List<ICommandList>() { commandList }, executionQueue);
		}
	}

	typealias DeviceHandle = RefCountPtr<IDevice>;
}