using Win32.Graphics.Direct3D11;
using System.Collections;
namespace nvrhi.d3d11;

class Shader : RefCounter<IShader>
{
    public ShaderDesc desc;
    public D3D11RefCountPtr<ID3D11VertexShader> VS;
    public D3D11RefCountPtr<ID3D11HullShader> HS;
    public D3D11RefCountPtr<ID3D11DomainShader> DS;
    public D3D11RefCountPtr<ID3D11GeometryShader> GS;
    public D3D11RefCountPtr<ID3D11PixelShader> PS;
    public D3D11RefCountPtr<ID3D11ComputeShader> CS;
    public List<char8> bytecode;
    
    public override readonly ref ShaderDesc getDesc() { return ref desc; }

    public override void getBytecode(void** ppBytecode, int* pSize)
    {
        if (ppBytecode != null) *ppBytecode = bytecode.Ptr;
        if (pSize != null) *pSize = bytecode.Count;
    }
}