using Bulkan;
using System.Collections;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	class Framebuffer : RefCounter<IFramebuffer>
	{
		public FramebufferDesc desc;
		public FramebufferInfo framebufferInfo;

		public VkRenderPass renderPass = .Null;
		public VkFramebuffer framebuffer = .Null;

		public List<ResourceHandle> resources = new .() ~ delete _;

		public bool managed = true;

		public this(VulkanContext* context)
			{ m_Context = context; }

		public ~this()
		{
			if (framebuffer != .Null && managed)
			{
				vkDestroyFramebuffer(m_Context.device, framebuffer, m_Context.allocationCallbacks);
				framebuffer = null;
			}

			if (renderPass != .Null && managed)
			{
				vkDestroyRenderPass(m_Context.device, renderPass, m_Context.allocationCallbacks);
				renderPass = null;
			}
		}

		public override readonly ref FramebufferDesc getDesc()  { return ref desc; }
		public override readonly ref FramebufferInfo getFramebufferInfo() { return ref framebufferInfo; }
		public override NativeObject getNativeObject(ObjectType objectType)
		{
			switch (objectType)
			{
			case ObjectType.VK_RenderPass:
				return NativeObject(renderPass);
			case ObjectType.VK_Framebuffer:
				return NativeObject(framebuffer);
			default:
				return null;
			}
		}

		private VulkanContext* m_Context;
	}
}