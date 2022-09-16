using Win32.Graphics.Direct3D11;
namespace nvrhi.d3d11;

class EventQueryD3D11 : RefCounter<IEventQuery>
{
    public D3D11RefCountPtr<ID3D11Query> query;
    public bool resolved = false;
}