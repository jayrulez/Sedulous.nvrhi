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
	}
}