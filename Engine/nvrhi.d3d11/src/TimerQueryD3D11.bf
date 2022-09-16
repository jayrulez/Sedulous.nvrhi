using Win32.Graphics.Direct3D11;
namespace nvrhi.d3d11;

class TimerQueryD3D11 : RefCounter<ITimerQuery>
{
    public D3D11RefCountPtr<ID3D11Query> start;
    public D3D11RefCountPtr<ID3D11Query> end;
    public D3D11RefCountPtr<ID3D11Query> disjoint;

    public bool resolved = false;
    public float time = 0.f;
}