using Win32.Graphics.Direct3D11;
namespace nvrhi.d3d11;

class SamplerD3D11 : RefCounter<ISampler>
{
    public SamplerDesc desc;
    public D3D11RefCountPtr<ID3D11SamplerState> sampler;
    
    public override readonly ref SamplerDesc getDesc() { return ref desc; }
}