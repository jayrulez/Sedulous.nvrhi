namespace nvrhi.d3d12;

class DescriptorTable : RefCounter<IDescriptorTable>
{
	public uint32 capacity = 0;
	public DescriptorIndex firstDescriptor = 0;

	public this(DeviceResources resources)
		{ m_Resources = resources; }

	public ~this()
	{
		m_Resources.shaderResourceViewHeap.releaseDescriptors(firstDescriptor, capacity);
	}

	public override BindingSetDesc* getDesc() { return null; }
	public override IBindingLayout getLayout()  { return null; }
	public override uint32 getCapacity()  { return capacity; }

	private DeviceResources m_Resources;
}