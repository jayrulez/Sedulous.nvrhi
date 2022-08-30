namespace nvrhi.d3d12
{
	class Framebuffer : RefCounter<IFramebuffer>
	{
		public FramebufferDesc desc;
		public FramebufferInfo framebufferInfo;

		public StaticVector<TextureHandle, const c_MaxRenderTargets + 1> textures;
		public StaticVector<DescriptorIndex, const c_MaxRenderTargets> RTVs;
		public DescriptorIndex DSV = c_InvalidDescriptorIndex;
		public uint32 rtWidth = 0;
		public uint32 rtHeight = 0;

		public this(DeviceResources resources)
			{ m_Resources = resources; }

		public ~this()
		{
			for (DescriptorIndex RTV in RTVs)
				m_Resources.renderTargetViewHeap.releaseDescriptor(RTV);

			if (DSV != c_InvalidDescriptorIndex)
				m_Resources.depthStencilViewHeap.releaseDescriptor(DSV);
		}

		public override readonly ref FramebufferDesc getDesc() { return ref desc; }
		public override readonly ref FramebufferInfo getFramebufferInfo() { return ref framebufferInfo; }

		DeviceResources m_Resources;
	}
}