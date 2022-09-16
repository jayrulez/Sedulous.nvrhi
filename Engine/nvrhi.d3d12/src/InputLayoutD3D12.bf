using System.Collections;
using Win32.Graphics.Direct3D12;
namespace nvrhi.d3d12
{
	class InputLayoutD3D12 : RefCounter<IInputLayout>
	{
		public List<VertexAttributeDesc> attributes;
		public List<D3D12_INPUT_ELEMENT_DESC> inputElements;

		// maps a binding slot to an element stride
		public Dictionary<uint32, uint32> elementStrides;

		public override uint32 getNumAttributes()
		{
			return uint32(attributes.Count);
		}
		public override VertexAttributeDesc* getAttributeDesc(uint32 index)
		{
			if (index < uint32(attributes.Count)) return &attributes[index];
			else return null;
		}
	}
}