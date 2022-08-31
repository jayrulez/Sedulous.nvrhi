using Win32.Graphics.Direct3D11;
using nvrhi.d3dcommon;
using Win32.Graphics.Direct3D;
namespace nvrhi.d3d11;

class GraphicsPipeline : RefCounter<IGraphicsPipeline>
{
    public GraphicsPipelineDesc desc;
    public ShaderType shaderMask = ShaderType.None;
    public FramebufferInfo framebufferInfo;

    public D3D_PRIMITIVE_TOPOLOGY primitiveTopology = .D3D_PRIMITIVE_TOPOLOGY_UNDEFINED;
    public InputLayout inputLayout = null;

    public ID3D11RasterizerState *pRS = null;

    public ID3D11BlendState *pBlendState = null;
    public ID3D11DepthStencilState *pDepthStencilState = null;
    public UINT stencilRef = 0;
    public bool requiresBlendFactor = false;
    public bool pixelShaderHasUAVs = false;

    public D3D11RefCountPtr<ID3D11VertexShader> pVS;
    public D3D11RefCountPtr<ID3D11HullShader> pHS;
    public D3D11RefCountPtr<ID3D11DomainShader> pDS;
    public D3D11RefCountPtr<ID3D11GeometryShader> pGS;
    public D3D11RefCountPtr<ID3D11PixelShader> pPS;
    
    public override readonly ref GraphicsPipelineDesc getDesc()  { return ref desc; }
    public override readonly ref FramebufferInfo getFramebufferInfo() { return ref framebufferInfo; }
}