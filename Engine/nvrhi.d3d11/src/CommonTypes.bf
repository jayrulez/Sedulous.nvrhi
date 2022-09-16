using Win32.Graphics.Direct3D11;
using System;
using Win32.Foundation;
namespace nvrhi
{
	extension ObjectType
	{
		case D3D11_Device                           = 0x00010001;
		case D3D11_DeviceContext                    = 0x00010002;
		case D3D11_Resource                         = 0x00010003;
		case D3D11_Buffer                           = 0x00010004;
		case D3D11_RenderTargetView                 = 0x00010005;
		case D3D11_DepthStencilView                 = 0x00010006;
		case D3D11_ShaderResourceView               = 0x00010007;
		case D3D11_UnorderedAccessView              = 0x00010008;

		case Nvrhi_D3D11_Device = 0x00010101;
	}
}

namespace nvrhi.d3d11
{
	
	typealias D3D11_RECT = RECT;
	typealias D3D11RefCountPtr<T> = T*;

	struct DX11_ViewportState
	{
	    public uint32 numViewports = 0;
	    public D3D11_VIEWPORT[D3D11_VIEWPORT_AND_SCISSORRECT_MAX_INDEX] viewports = .();
	    public uint32 numScissorRects = 0;
	    public D3D11_RECT[D3D11_VIEWPORT_AND_SCISSORRECT_MAX_INDEX] scissorRects = .();
	}

	struct DeviceDesc
	{
	    public IMessageCallback messageCallback = null;
	    public ID3D11DeviceContext* context = null;
	}
}