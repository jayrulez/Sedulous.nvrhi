using Bulkan;
using System;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	class ShaderLibrary :  RefCounter<IShaderLibrary>
	{
	    public VkShaderModule shaderModule;

	    public this(VulkanContext* context)
	    {m_Context = context; }

	    public ~this() {
			if (shaderModule != .Null)
			{
			    vkDestroyShaderModule(m_Context.device, shaderModule, m_Context.allocationCallbacks);
			    shaderModule = .Null;
			}
	    }

	    public override void getBytecode(void** ppBytecode, int* pSize) {
			
			if (ppBytecode != null) *ppBytecode = null;
			if (pSize != null) *pSize = 0;
	    }

	    public override ShaderHandle getShader(char8* entryName, ShaderType shaderType) {
			ShaderVK newShader = new ShaderVK(m_Context);
			newShader.desc.entryName = new String(entryName);
			newShader.desc.shaderType = shaderType;
			newShader.shaderModule = shaderModule;
			newShader.baseShader = this;
			newShader.stageFlagBits = convertShaderTypeToShaderStageFlagBits(shaderType);

			return ShaderHandle.Attach(newShader);
	    }

	    private VulkanContext* m_Context;
	}
}