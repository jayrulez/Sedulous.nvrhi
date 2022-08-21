using System.Collections;
using Bulkan;
namespace nvrhi.vulkan
{
	class InputLayout : /*RefCounter<IInputLayout>*/ IInputLayout
	{
		public List<VertexAttributeDesc> inputDesc;

		public List<VkVertexInputBindingDescription> bindingDesc;
		public List<VkVertexInputAttributeDescription> attributeDesc;

		public override uint32 getNumAttributes()
		{
			return uint32(inputDesc.Count);
		}
		public override VertexAttributeDesc* getAttributeDesc(uint32 index)
		{
			if (index < uint32(inputDesc.Count))
				return &inputDesc[index];
			else
				return null;
		}
	}
}