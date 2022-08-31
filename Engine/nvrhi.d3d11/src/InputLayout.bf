using System.Collections;
using Win32.Graphics.Direct3D11;
namespace nvrhi.d3d11;

class InputLayout : RefCounter<IInputLayout>
{
	public D3D11RefCountPtr<ID3D11InputLayout> layout;
	public List<VertexAttributeDesc> attributes;
	// maps a binding slot number to a stride
	public Dictionary<uint32, uint32> elementStrides;

	public override uint32 getNumAttributes() { return uint32(attributes.Count); }
	public override VertexAttributeDesc* getAttributeDesc(uint32 index)
	{
		if (index < uint32(attributes.Count))
			return &attributes[index];

		return null;
	}
}