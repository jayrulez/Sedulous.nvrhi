using Win32.Graphics.Direct3D12;
using System;
namespace nvrhi.d3d12
{
	struct Context : IDisposable
	{
		public D3D12RefCountPtr<ID3D12Device> device;
		public D3D12RefCountPtr<ID3D12Device2> device2;
		public D3D12RefCountPtr<ID3D12Device5> device5;
#if NVRHI_WITH_RTXMU
		public rtxmu.DxAccelStructManager* rtxMemUtil;
#endif

		public D3D12RefCountPtr<ID3D12CommandSignature> drawIndirectSignature;
		public D3D12RefCountPtr<ID3D12CommandSignature> dispatchIndirectSignature;
		public D3D12RefCountPtr<ID3D12QueryHeap> timerQueryHeap;
		public RefCountPtr<Buffer> timerQueryResolveBuffer;

		public IMessageCallback messageCallback = null;
		public void error(String message)
		{
			messageCallback?.message(MessageSeverity.Error, message);
		}

		public void Dispose()
		{

		}
	}
}