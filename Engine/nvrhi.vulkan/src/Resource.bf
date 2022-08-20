namespace nvrhi
{
	extension ObjectType
	{
		case VK_Device                              = 0x00030001;
		case VK_PhysicalDevice                      = 0x00030002;
		case VK_Instance                            = 0x00030003;
		case VK_Queue                               = 0x00030004;
		case VK_CommandBuffer                       = 0x00030005;
		case VK_DeviceMemory                        = 0x00030006;
		case VK_Buffer                              = 0x00030007;
		case VK_Image                               = 0x00030008;
		case VK_ImageView                           = 0x00030009;
		case VK_AccelerationStructureKHR            = 0x0003000a;
		case VK_Sampler                             = 0x0003000b;
		case VK_ShaderModule                        = 0x0003000c;
		case VK_RenderPass                          = 0x0003000d;
		case VK_Framebuffer                         = 0x0003000e;
		case VK_DescriptorPool                      = 0x0003000f;
		case VK_DescriptorSetLayout                 = 0x00030010;
		case VK_DescriptorSet                       = 0x00030011;
		case VK_PipelineLayout                      = 0x00030012;
		case VK_Pipeline                            = 0x00030013;
	}
}