using Win32.Graphics.Direct3D11;
namespace nvrhi.d3d11;

class ComputePipelineD3D11 : RefCounter<IComputePipeline>
{
    public ComputePipelineDesc desc;

    public D3D11RefCountPtr<ID3D11ComputeShader> shader;
    
    public override readonly ref ComputePipelineDesc getDesc() { return ref desc; }
}