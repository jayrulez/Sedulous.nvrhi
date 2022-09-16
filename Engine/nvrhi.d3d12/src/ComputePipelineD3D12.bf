using Win32.Graphics.Direct3D12;
namespace nvrhi.d3d12
{
	class ComputePipelineD3D12 : RefCounter<IComputePipeline>
	{
		public ComputePipelineDesc desc;

		public RefCountPtr<RootSignature> rootSignature;
		public D3D12RefCountPtr<ID3D12PipelineState> pipelineState;

		public override readonly ref ComputePipelineDesc getDesc() { return ref desc; }
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