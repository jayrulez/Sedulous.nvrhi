using System.Collections;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Dxgi;
using Win32.Graphics.Dxgi.Common;
namespace nvrhi.d3d12
{
	class AccelStructD3D12 : RefCounter<nvrhi.rt.IAccelStruct>
	{
		public RefCountPtr<nvrhi.d3d12.BufferD3D12> dataBuffer;
		public List<nvrhi.rt.AccelStructHandle> bottomLevelASes;
		public List<D3D12_RAYTRACING_INSTANCE_DESC> dxrInstances = new .() ~ delete _;
		public nvrhi.rt.AccelStructDesc desc;
		public bool allowUpdate = false;
		public bool compacted = false;
		public int rtxmuId = (.)~0uL;
#if NVRHI_WITH_RTXMU
		public D3D12_GPU_VIRTUAL_ADDRESS rtxmuGpuVA = 0;
#endif

		public this(D3D12Context* context)
			{ m_Context = context; }

		public void createSRV(int descriptor)
		{
			D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc = .();
			srvDesc.Format = DXGI_FORMAT.DXGI_FORMAT_UNKNOWN;
			srvDesc.ViewDimension = D3D12_SRV_DIMENSION.D3D12_SRV_DIMENSION_RAYTRACING_ACCELERATION_STRUCTURE;
			srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
			srvDesc.RaytracingAccelerationStructure.Location = dataBuffer.gpuVA;

			m_Context.device.CreateShaderResourceView(null, &srvDesc, .() { ptr = (.)descriptor });
		}

		public override NativeObject getNativeObject(ObjectType objectType)
		{
			if (dataBuffer != null)
				return dataBuffer.getNativeObject(objectType);

			return null;
		}

		public override readonly ref nvrhi.rt.AccelStructDesc getDesc() { return ref desc; }

		public override bool isCompacted() { return compacted; }

		public override uint64 getDeviceAddress()
		{
#if NVRHI_WITH_RTXMU
			if (!desc.isTopLevel)
				return m_Context.rtxMemUtil.GetAccelStructGPUVA(rtxmuId);
#endif
			return dataBuffer.gpuVA;
		}

		private D3D12Context* m_Context;
	}
}