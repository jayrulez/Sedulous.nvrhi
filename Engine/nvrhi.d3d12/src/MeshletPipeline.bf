using Win32.Graphics.Direct3D12;
namespace nvrhi.d3d12
{
	class MeshletPipeline : RefCounter<IMeshletPipeline>
	{
		public MeshletPipelineDesc desc;
		public FramebufferInfo framebufferInfo;

		public RefCountPtr<RootSignature> rootSignature;
		public D3D12RefCountPtr<ID3D12PipelineState> pipelineState;

		public DX12_ViewportState viewportState;

		public bool requiresBlendFactor = false;

		public override readonly ref MeshletPipelineDesc getDesc() { return ref desc; }
		public  override readonly ref FramebufferInfo getFramebufferInfo() { return ref framebufferInfo; }
		public override NativeObject getNativeObject(ObjectType objectType)
		{
			switch (objectType)
			{
			case ObjectType.D3D12_RootSignature:
				return rootSignature.getNativeObject(objectType);
			case ObjectType.D3D12_PipelineState:
				return NativeObject(pipelineState);
			default:
				return null;
			}
		}
	}
}