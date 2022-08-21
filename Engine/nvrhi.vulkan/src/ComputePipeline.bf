using Bulkan;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	class ComputePipeline : /*RefCounter<IComputePipeline>*/ IComputePipeline
	{
		public ComputePipelineDesc desc;

		public BindingVector<RefCountPtr<BindingLayout>> pipelineBindingLayouts;
		public VkPipelineLayout pipelineLayout;
		public VkPipeline pipeline;

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
		public override readonly ref ComputePipelineDesc getDesc() { return ref desc; }
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