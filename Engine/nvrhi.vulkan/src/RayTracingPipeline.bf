using Bulkan;
using System.Collections;
using System;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	class RayTracingPipeline : RefCounter<nvrhi.rt.IPipeline>
	{
		public nvrhi.rt.PipelineDesc desc;
		public BindingVector<RefCountPtr<BindingLayout>> pipelineBindingLayouts;
		public VkPipelineLayout pipelineLayout;
		public VkPipeline pipeline;

		public Dictionary<String, uint32> shaderGroups; // name . index
		public List<uint8> shaderGroupHandles;

		public this(VulkanContext* context)
			{ m_Context = context; }

		public ~this()
		{
			if (pipeline != .Null)
			{
				vkDestroyPipeline(m_Context.device, pipeline, m_Context.allocationCallbacks);
				pipeline = null;
			}

			if (pipelineLayout != .Null)
			{
				vkDestroyPipelineLayout(m_Context.device, pipelineLayout, m_Context.allocationCallbacks);
				pipelineLayout = null;
			}
		}
		public override readonly ref nvrhi.rt.PipelineDesc getDesc()  { return ref desc; }
		public override nvrhi.rt.ShaderTableHandle createShaderTable()
		{
			ShaderTable st = new ShaderTable(m_Context, this);
			return nvrhi.rt.ShaderTableHandle.Attach(st);
		}
		public override NativeObject getNativeObject(ObjectType objectType)
		{
			switch (objectType)
			{
			case ObjectType.VK_PipelineLayout:
				return NativeObject(pipelineLayout);
			case ObjectType.VK_Pipeline:
				return NativeObject(pipeline);
			default:
				return null;
			}
		}

		// returns -1 if not found
		public int32 findShaderGroup(String name)
		{
			if (!shaderGroups.ContainsKey(name))
				return -1;

			return int32(shaderGroups[name]);
		}

		private VulkanContext* m_Context;
	}
}