using Bulkan;
using System;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	class VulkanAllocator
	{
		public this(VulkanContext* context)
			{ m_Context = context; }

		public VkResult allocateBufferMemory(BufferVK buffer, bool enableDeviceAddress)
		{
			// figure out memory requirements
			VkMemoryRequirements memRequirements = .();
			vkGetBufferMemoryRequirements(m_Context.device, buffer.buffer, &memRequirements);

			// allocate memory
			readonly VkResult res = allocateMemory(buffer, memRequirements, pickBufferMemoryProperties(buffer.desc), enableDeviceAddress);
			CHECK_VK_RETURN!(res);

			vkBindBufferMemory(m_Context.device, buffer.buffer, buffer.memory, 0);

			return VkResult.eVkSuccess;
		}
		public void freeBufferMemory(BufferVK buffer)
		{
			freeMemory(buffer);
		}

		public VkResult allocateTextureMemory(TextureVK texture)
		{
			// grab the image memory requirements
			VkMemoryRequirements memRequirements = .();
			vkGetImageMemoryRequirements(m_Context.device, texture.image, &memRequirements);

			// allocate memory
			readonly VkMemoryPropertyFlags memProperties = VkMemoryPropertyFlags.eDeviceLocalBit;
			readonly VkResult res = allocateMemory(texture, memRequirements, memProperties);
			CHECK_VK_RETURN!(res);

			vkBindImageMemory(m_Context.device, texture.image, texture.memory, 0);

			return VkResult.eVkSuccess;
		}
		public void freeTextureMemory(TextureVK texture)
		{
			freeMemory(texture);
		}

		public VkResult allocateMemory(MemoryResourceVK res,
			VkMemoryRequirements memRequirements,
			VkMemoryPropertyFlags memPropertyFlags,
			bool enableDeviceAddress = false)
		{
			res.managed = true;

			// find a memory space that satisfies the requirements
			VkPhysicalDeviceMemoryProperties memProperties = .();
			vkGetPhysicalDeviceMemoryProperties(m_Context.physicalDevice, &memProperties);

			uint32 memTypeIndex;
			for (memTypeIndex = 0; memTypeIndex < memProperties.memoryTypeCount; memTypeIndex++)
			{
				if ((memRequirements.memoryTypeBits & (1 << memTypeIndex) != 0) &&
					((memProperties.memoryTypes[memTypeIndex].propertyFlags & memPropertyFlags) == memPropertyFlags))
				{
					break;
				}
			}

			if (memTypeIndex == memProperties.memoryTypeCount)
			{
				// xxxnsubtil: this is incorrect; need better error reporting
				return VkResult.eVkErrorOutOfDeviceMemory;
			}

			// allocate memory
			var allocFlags = VkMemoryAllocateFlagsInfo();
			if (enableDeviceAddress)
				allocFlags.flags |= VkMemoryAllocateFlags.eDeviceAddressBit;

			var allocInfo = VkMemoryAllocateInfo()
				.setAllocationSize(memRequirements.size)
				.setMemoryTypeIndex(memTypeIndex);
			allocInfo.setPNext(&allocFlags);

			return vkAllocateMemory(m_Context.device, &allocInfo, m_Context.allocationCallbacks, &res.memory);
		}
		public void freeMemory(MemoryResourceVK res)
		{
			Runtime.Assert(res.managed);

			vkFreeMemory(m_Context.device, res.memory, m_Context.allocationCallbacks);
			res.memory = VkDeviceMemory(null);
		}

		private VulkanContext* m_Context;
	}
}