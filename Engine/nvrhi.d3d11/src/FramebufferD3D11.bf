using Win32.Graphics.Direct3D11;
namespace nvrhi.d3d11;

class FramebufferD3D11 : RefCounter<IFramebuffer>
{
	public FramebufferDesc desc;
	public FramebufferInfo framebufferInfo;
	public StaticVector<D3D11RefCountPtr<ID3D11RenderTargetView>, const c_MaxRenderTargets> RTVs;
	public D3D11RefCountPtr<ID3D11DepthStencilView> DSV;

	public override readonly ref FramebufferDesc getDesc()  { return ref desc; }
	public override readonly ref FramebufferInfo getFramebufferInfo()  { return ref framebufferInfo; }
}