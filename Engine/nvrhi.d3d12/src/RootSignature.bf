using Win32.Graphics.Direct3D12;
namespace nvrhi.d3d12
{
	class RootSignature : RefCounter<IRootSignature>
	{
		public int hash = 0;
		public StaticVector<(BindingLayoutHandle layout, RootParameterIndex index), const c_MaxBindingLayouts> pipelineLayouts;
		public D3D12RefCountPtr<ID3D12RootSignature> handle;
		public uint32 pushConstantByteSize = 0;
		public RootParameterIndex rootParameterPushConstants = ~0u;

		public this(DeviceResources resources)
			{ m_Resources = resources; }

		public ~this()
		{
			// Remove the root signature from the cache
			if (m_Resources.rootsigCache.ContainsKey(hash))
			{
				m_Resources.rootsigCache.Remove(hash);
			}
		}

		public override NativeObject getNativeObject(ObjectType objectType)
		{
			switch (objectType)
			{
			case ObjectType.D3D12_RootSignature:
				return NativeObject(handle);
			default:
				return null;
			}
		}

		private DeviceResources m_Resources;
	}
}