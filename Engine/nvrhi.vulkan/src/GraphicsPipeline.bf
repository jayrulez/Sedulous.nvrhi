using Bulkan;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	class GraphicsPipeline : RefCounter<IGraphicsPipeline>
	{
		public GraphicsPipelineDesc desc;
		public FramebufferInfo framebufferInfo;
		public ShaderType shaderMask = ShaderType.None;
		public BindingVector<RefCountPtr<BindingLayout>> pipelineBindingLayouts;
		public VkPipelineLayout pipelineLayout;
		public VkPipeline pipeline;
		public bool usesBlendConstants = false;

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

		public override readonly ref GraphicsPipelineDesc getDesc() { return ref desc; }
		public override readonly ref FramebufferInfo getFramebufferInfo() { return ref framebufferInfo; }
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

		private VulkanContext* m_Context;
	}
}