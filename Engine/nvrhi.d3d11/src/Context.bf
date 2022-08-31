using Win32.Graphics.Direct3D11;
using System;
namespace nvrhi.d3d11;

struct Context
{
	public D3D11RefCountPtr<ID3D11Device> device;
	public D3D11RefCountPtr<ID3D11DeviceContext> immediateContext;
	public D3D11RefCountPtr<ID3D11Buffer> pushConstantBuffer;
	public IMessageCallback messageCallback = null;
	public bool nvapiAvailable = false;

	public void error(String message)
	{
		messageCallback.message(MessageSeverity.Error, message);
	}
}