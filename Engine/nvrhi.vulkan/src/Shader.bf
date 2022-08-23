using Bulkan;
using System.Collections;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	class Shader : RefCounter<IShader>
	{
		public ShaderDesc desc;

		public VkShaderModule shaderModule;
		public VkShaderStageFlags stageFlagBits = .None;

		// Shader specializations are just references to the original shader module
		// plus the specialization constant array.
		public ResourceHandle baseShader; // Could be a Shader or ShaderLibrary
		public List<ShaderSpecialization> specializationConstants = new .() ~ delete _;

		public this(VulkanContext* context)
		{
			desc = .() { shaderType = ShaderType.None };
			m_Context = context;
		}

		public ~this()
		{
			delete desc.entryName;

			if (shaderModule != .Null && baseShader == null) // do not destroy the module if this is a derived specialization shader or a library entry
			{
				vkDestroyShaderModule(m_Context.device, shaderModule, m_Context.allocationCallbacks);
				shaderModule = .Null;
			}
		}

		public override readonly ref ShaderDesc getDesc()  { return ref desc; }
		public override void getBytecode(void** ppBytecode, int* pSize)
		{
			// we don't save these for vulkan
			if (ppBytecode != null) *ppBytecode = null;
			if (pSize != null) *pSize = 0;
		}
		public override NativeObject getNativeObject(ObjectType objectType)
		{
			switch (objectType)
			{
			case ObjectType.VK_ShaderModule:
				return NativeObject(shaderModule);
			default:
				return null;
			}
		}

		private VulkanContext* m_Context;
	}
}