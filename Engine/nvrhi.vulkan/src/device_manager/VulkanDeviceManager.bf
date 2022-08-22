using nvrhi.device_manager;
using Bulkan;
using System.Collections;
using System;
namespace nvrhi.vulkan.device_manager
{
	class VulkanDeviceManager : DeviceManager
	{
		private struct VulkanExtensionSet
		{
		    public HashSet<String> instance;
		    public HashSet<String> layers;
		    public HashSet<String> device;
		}

		// minimal set of required extensions
		private VulkanExtensionSet enabledExtensions = .(){
		    instance = scope .(){
		        scope .(VulkanNative.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME)
		    },
		    layers = scope .(){ },
		    device = scope .(){ 
		        scope .(VulkanNative.VK_KHR_SWAPCHAIN_EXTENSION_NAME),
		        scope .(VulkanNative.VK_KHR_MAINTENANCE1_EXTENSION_NAME)
		    },
		};

		// optional extensions
		private VulkanExtensionSet optionalExtensions = .(){
		    instance = scope .(){ 
		        scope .(VulkanNative.VK_EXT_SAMPLER_FILTER_MINMAX_EXTENSION_NAME),
		        scope .(VulkanNative.VK_EXT_DEBUG_UTILS_EXTENSION_NAME)
		    },
		    layers = scope .(){ },
		    device = scope .(){ 
		         scope .(VulkanNative.VK_EXT_DEBUG_MARKER_EXTENSION_NAME),
		         scope .(VulkanNative.VK_EXT_DESCRIPTOR_INDEXING_EXTENSION_NAME),
		         scope .(VulkanNative.VK_KHR_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME),
		         scope .(VulkanNative.VK_NV_MESH_SHADER_EXTENSION_NAME),
		         scope .(VulkanNative.VK_KHR_FRAGMENT_SHADING_RATE_EXTENSION_NAME)
		    } ,
		};

		private HashSet<String> m_RayTracingExtensions = new .(){
		    new .(VulkanNative.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME),
		     new .(VulkanNative.VK_KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME),
		     new .(VulkanNative.VK_KHR_PIPELINE_LIBRARY_EXTENSION_NAME),
		     new .(VulkanNative.VK_KHR_RAY_QUERY_EXTENSION_NAME),
		     new .(VulkanNative.VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME)
		} ~ DeleteContainerAndItems!(_);

		private VkInstance m_VulkanInstance;
		private VkDebugReportCallbackEXT m_DebugReportCallback;

		private VkPhysicalDevice m_VulkanPhysicalDevice;
		private int32 m_GraphicsQueueFamily = -1;
		private int32 m_ComputeQueueFamily = -1;
		private int32 m_TransferQueueFamily = -1;
		private int32 m_PresentQueueFamily = -1;

		private VkDevice m_VulkanDevice;
		private VkQueue m_GraphicsQueue;
		private VkQueue m_ComputeQueue;
		private VkQueue m_TransferQueue;
		private VkQueue m_PresentQueue;

		private VkSurfaceKHR m_WindowSurface;

		private VkSurfaceFormatKHR m_SwapChainFormat;
		private VkSwapchainKHR m_SwapChain;

		private struct SwapChainImage
		{
		    public VkImage image;
		    public nvrhi.TextureHandle rhiHandle;
		}

		private List<SwapChainImage> m_SwapChainImages;
		private uint32 m_SwapChainIndex = uint32(-1);

		private nvrhi.vulkan.DeviceHandle m_NvrhiDevice;
		private nvrhi.DeviceHandle m_ValidationLayer;

		private nvrhi.CommandListHandle m_BarrierCommandList;
		private VkSemaphore m_PresentSemaphore;

		private System.Collections.Queue<nvrhi.EventQueryHandle> m_FramesInFlight;
		private List<nvrhi.EventQueryHandle> m_QueryPool;

		protected override void ResizeSwapChain()
		{
			if (m_VulkanDevice != .Null)
			{
			    destroySwapChain();
			    createSwapChain();
			}
		}

		protected override void BeginFrame()
		{
			const vk::Result res = m_VulkanDevice.acquireNextImageKHR(m_SwapChain,
			                                                  std::numeric_limits<uint64_t>::max(), // timeout
			                                                  m_PresentSemaphore,
			                                                  vk::Fence(),
			                                                  &m_SwapChainIndex);

			assert(res == vk::Result::eSuccess);

			m_NvrhiDevice->queueWaitForSemaphore(nvrhi::CommandQueue::Graphics, m_PresentSemaphore, 0);
		}

		protected override void Present()
		{
			m_NvrhiDevice->queueSignalSemaphore(nvrhi::CommandQueue::Graphics, m_PresentSemaphore, 0);

			m_BarrierCommandList->open(); // umm...
			m_BarrierCommandList->close();
			m_NvrhiDevice->executeCommandList(m_BarrierCommandList);

			vk::PresentInfoKHR info = vk::PresentInfoKHR()
			                            .setWaitSemaphoreCount(1)
			                            .setPWaitSemaphores(&m_PresentSemaphore)
			                            .setSwapchainCount(1)
			                            .setPSwapchains(&m_SwapChain)
			                            .setPImageIndices(&m_SwapChainIndex);

			const vk::Result res = m_PresentQueue.presentKHR(&info);
			assert(res == vk::Result::eSuccess || res == vk::Result::eErrorOutOfDateKHR);

			if (m_DeviceParams.enableDebugRuntime)
			{
			    // according to vulkan-tutorial.com, "the validation layer implementation expects
			    // the application to explicitly synchronize with the GPU"
			    m_PresentQueue.waitIdle();
			}
			else
			{
#ifndef _WIN32
			    if (m_DeviceParams.vsyncEnabled)
			    {
			        m_PresentQueue.waitIdle();
			    }
#endif

			    while (m_FramesInFlight.size() > m_DeviceParams.maxFramesInFlight)
			    {
			        auto query = m_FramesInFlight.front();
			        m_FramesInFlight.pop();

			        m_NvrhiDevice->waitEventQuery(query);

			        m_QueryPool.push_back(query);
			    }

			    nvrhi::EventQueryHandle query;
			    if (!m_QueryPool.empty())
			    {
			        query = m_QueryPool.back();
			        m_QueryPool.pop_back();
			    }
			    else
			    {
			        query = m_NvrhiDevice->createEventQuery();
			    }

			    m_NvrhiDevice->resetEventQuery(query);
			    m_NvrhiDevice->setEventQuery(query, nvrhi::CommandQueue::Graphics);
			    m_FramesInFlight.push(query);
			}
		}

		public override nvrhi.IDevice GetDevice()
		{
			if (m_ValidationLayer != null)
			    return m_ValidationLayer;

			return m_NvrhiDevice;
		}

		public override GraphicsAPI GetGraphicsAPI()
		{
			return .VULKAN;
		}

		public override ITexture GetCurrentBackBuffer()
		{
			return m_SwapChainImages[m_SwapChainIndex].rhiHandle;
		}

		public override ITexture GetBackBuffer(uint32 index)
		{
			if (index < m_SwapChainImages.Count)
			    return m_SwapChainImages[index].rhiHandle;
			return null;
		}

		public override uint32 GetCurrentBackBufferIndex()
		{
			return m_SwapChainIndex;
		}

		public override uint32 GetBackBufferCount()
		{
			 return uint32(m_SwapChainImages.Count);
		}


		/////////////////////////////////////////////////////////////////////////////

		private static VkBool32 vulkanDebugCallback(
        VkDebugReportFlagsEXT flags,
        VkDebugReportObjectTypeEXT objType,
        uint64 obj,
        uint location,
        int32 code,
        char8* layerPrefix,
        char8* msg,
        void* userData)
    {
        VulkanDeviceManager manager = (.)Internal.UnsafeCastToObject(userData);

        /*if (manager != null)
        {
            const auto& ignored = manager->m_DeviceParams.ignoredVulkanValidationMessageLocations;
            const auto found = std::find(ignored.begin(), ignored.end(), location);
            if (found != ignored.end())
                return VK_FALSE;
        }

        log::warning("[Vulkan: location=0x%zx code=%d, layerPrefix='%s'] %s", location, code, layerPrefix, msg);

        return VK_FALSE;*/
		return false;
    }

		private bool IsVulkanInstanceExtensionEnabled(char8* extensionName)
		{
		    return enabledExtensions.instance.find(extensionName) != enabledExtensions.instance.end();
		}

		private bool IsVulkanDeviceExtensionEnabled(char8* extensionName)
		{
		    return enabledExtensions.device.find(extensionName) != enabledExtensions.device.end();
		}

		private bool IsVulkanLayerEnabled(char8* layerName)
		{
		    return enabledExtensions.layers.find(layerName) != enabledExtensions.layers.end();
		}

		private void GetEnabledVulkanInstanceExtensions(List<String> extensions)
		{
		    for (const auto& ext : enabledExtensions.instance)
		        extensions.push_back(ext);
		}

		private void GetEnabledVulkanDeviceExtensions(List<String> extensions)
		{
		    for (const auto& ext : enabledExtensions.device)
		        extensions.push_back(ext);
		}

		private void GetEnabledVulkanLayers(List<String> layers)
		{
		    for (const auto& ext : enabledExtensions.layers)
		        layers.push_back(ext);
		}

		private bool createInstance(){
			if (!glfwVulkanSupported())
			{
			    return false;
			}

			// add any extensions required by GLFW
			uint32_t glfwExtCount;
			const char **glfwExt = glfwGetRequiredInstanceExtensions(&glfwExtCount);
			assert(glfwExt);

			for(uint32_t i = 0; i < glfwExtCount; i++)
			{
			    enabledExtensions.instance.insert(std::string(glfwExt[i]));
			}

			// add instance extensions requested by the user
			for (const std::string& name : m_DeviceParams.requiredVulkanInstanceExtensions)
			{
			    enabledExtensions.instance.insert(name);
			}
			for (const std::string& name : m_DeviceParams.optionalVulkanInstanceExtensions)
			{
			    optionalExtensions.instance.insert(name);
			}

			// add layers requested by the user
			for (const std::string& name : m_DeviceParams.requiredVulkanLayers)
			{
			    enabledExtensions.layers.insert(name);
			}
			for (const std::string& name : m_DeviceParams.optionalVulkanLayers)
			{
			    optionalExtensions.layers.insert(name);
			}

			std::unordered_set<std::string> requiredExtensions = enabledExtensions.instance;

			// figure out which optional extensions are supported
			for(const auto& instanceExt : vk::enumerateInstanceExtensionProperties())
			{
			    const std::string name = instanceExt.extensionName;
			    if (optionalExtensions.instance.find(name) != optionalExtensions.instance.end())
			    {
			        enabledExtensions.instance.insert(name);
			    }

			    requiredExtensions.erase(name);
			}

			if (!requiredExtensions.empty())
			{
			    std::stringstream ss;
			    ss << "Cannot create a Vulkan instance because the following required extension(s) are not supported:";
			    for (const auto& ext : requiredExtensions)
			        ss << std::endl << "  - " << ext;

			    log::error("%s", ss.str().c_str());
			    return false;
			}

			log::message(m_DeviceParams.infoLogSeverity, "Enabled Vulkan instance extensions:");
			for (const auto& ext : enabledExtensions.instance)
			{
			    log::message(m_DeviceParams.infoLogSeverity, "    %s", ext.c_str());
			}

			std::unordered_set<std::string> requiredLayers = enabledExtensions.layers;

			for(const auto& layer : vk::enumerateInstanceLayerProperties())
			{
			    const std::string name = layer.layerName;
			    if (optionalExtensions.layers.find(name) != optionalExtensions.layers.end())
			    {
			        enabledExtensions.layers.insert(name);
			    }

			    requiredLayers.erase(name);
			}

			if (!requiredLayers.empty())
			{
			    std::stringstream ss;
			    ss << "Cannot create a Vulkan instance because the following required layer(s) are not supported:";
			    for (const auto& ext : requiredLayers)
			        ss << std::endl << "  - " << ext;

			    log::error("%s", ss.str().c_str());
			    return false;
			}

			log::message(m_DeviceParams.infoLogSeverity, "Enabled Vulkan layers:");
			for (const auto& layer : enabledExtensions.layers)
			{
			    log::message(m_DeviceParams.infoLogSeverity, "    %s", layer.c_str());
			}

			auto instanceExtVec = stringSetToVector(enabledExtensions.instance);
			auto layerVec = stringSetToVector(enabledExtensions.layers);

			auto applicationInfo = vk::ApplicationInfo()
			    .setApiVersion(VK_MAKE_VERSION(1, 2, 0));

			// create the vulkan instance
			vk::InstanceCreateInfo info = vk::InstanceCreateInfo()
			    .setEnabledLayerCount(uint32_t(layerVec.size()))
			    .setPpEnabledLayerNames(layerVec.data())
			    .setEnabledExtensionCount(uint32_t(instanceExtVec.size()))
			    .setPpEnabledExtensionNames(instanceExtVec.data())
			    .setPApplicationInfo(&applicationInfo);

			const vk::Result res = vk::createInstance(&info, nullptr, &m_VulkanInstance);
			if (res != vk::Result::eSuccess)
			{
			    log::error("Failed to create a Vulkan instance, error code = %s", nvrhi::vulkan::resultToString(res));
			    return false;
			}

			VULKAN_HPP_DEFAULT_DISPATCHER.init(m_VulkanInstance);

			return true;
		}

		private void installDebugCallback(){
			auto info = vk::DebugReportCallbackCreateInfoEXT()
			                .setFlags(vk::DebugReportFlagBitsEXT::eError |
			                          vk::DebugReportFlagBitsEXT::eWarning |
			                        //   vk::DebugReportFlagBitsEXT::eInformation |
			                          vk::DebugReportFlagBitsEXT::ePerformanceWarning)
			                .setPfnCallback(vulkanDebugCallback)
			                .setPUserData(this);

			vk::Result res = m_VulkanInstance.createDebugReportCallbackEXT(&info, nullptr, &m_DebugReportCallback);
			assert(res == vk::Result::eSuccess);
		}

		private bool pickPhysicalDevice(){
			vk::Format requestedFormat = nvrhi::vulkan::convertFormat(m_DeviceParams.swapChainFormat);
			vk::Extent2D requestedExtent(m_DeviceParams.backBufferWidth, m_DeviceParams.backBufferHeight);

			auto devices = m_VulkanInstance.enumeratePhysicalDevices();

			// Start building an error message in case we cannot find a device.
			std::stringstream errorStream;
			errorStream << "Cannot find a Vulkan device that supports all the required extensions and properties.";

			// build a list of GPUs
			std::vector<vk::PhysicalDevice> discreteGPUs;
			std::vector<vk::PhysicalDevice> otherGPUs;
			for(const auto& dev : devices)
			{
			    auto prop = dev.getProperties();

			    errorStream << std::endl << prop.deviceName.data() << ":";

			    // check that all required device extensions are present
			    std::unordered_set<std::string> requiredExtensions = enabledExtensions.device;
			    auto deviceExtensions = dev.enumerateDeviceExtensionProperties();
			    for(const auto& ext : deviceExtensions)
			    {
			        requiredExtensions.erase(std::string(ext.extensionName.data()));
			    }

			    bool deviceIsGood = true;

			    if (!requiredExtensions.empty())
			    {
			        // device is missing one or more required extensions
			        for (const auto& ext : requiredExtensions)
			        {
			            errorStream << std::endl << "  - missing " << ext;
			        }
			        deviceIsGood = false;
			    }

			    auto deviceFeatures = dev.getFeatures();
			    if (!deviceFeatures.samplerAnisotropy)
			    {
			        // device is a toaster oven
			        errorStream << std::endl << "  - does not support samplerAnisotropy";
			        deviceIsGood = false;
			    }
			    if (!deviceFeatures.textureCompressionBC)
			    {
			        errorStream << std::endl << "  - does not support textureCompressionBC";
			        deviceIsGood = false;
			    }

			    // check that this device supports our intended swap chain creation parameters
			    auto surfaceCaps = dev.getSurfaceCapabilitiesKHR(m_WindowSurface);
			    auto surfaceFmts = dev.getSurfaceFormatsKHR(m_WindowSurface);
			    auto surfacePModes = dev.getSurfacePresentModesKHR(m_WindowSurface);

			    if (surfaceCaps.minImageCount > m_DeviceParams.swapChainBufferCount ||
			        (surfaceCaps.maxImageCount < m_DeviceParams.swapChainBufferCount && surfaceCaps.maxImageCount > 0))
			    {
			        errorStream << std::endl << "  - cannot support the requested swap chain image count:";
			        errorStream << " requested " << m_DeviceParams.swapChainBufferCount << ", available " << surfaceCaps.minImageCount << " - " << surfaceCaps.maxImageCount;
			        deviceIsGood = false;
			    }

			    if (surfaceCaps.minImageExtent.width > requestedExtent.width ||
			        surfaceCaps.minImageExtent.height > requestedExtent.height ||
			        surfaceCaps.maxImageExtent.width < requestedExtent.width ||
			        surfaceCaps.maxImageExtent.height < requestedExtent.height)
			    {
			        errorStream << std::endl << "  - cannot support the requested swap chain size:";
			        errorStream << " requested " << requestedExtent.width << "x" << requestedExtent.height << ", ";
			        errorStream << " available " << surfaceCaps.minImageExtent.width << "x" << surfaceCaps.minImageExtent.height;
			        errorStream << " - " << surfaceCaps.maxImageExtent.width << "x" << surfaceCaps.maxImageExtent.height;
			        deviceIsGood = false;
			    }

			    bool surfaceFormatPresent = false;
			    for (const vk::SurfaceFormatKHR& surfaceFmt : surfaceFmts)
			    {
			        if (surfaceFmt.format == requestedFormat)
			        {
			            surfaceFormatPresent = true;
			            break;
			        }
			    }

			    if (!surfaceFormatPresent)
			    {
			        // can't create a swap chain using the format requested
			        errorStream << std::endl << "  - does not support the requested swap chain format";
			        deviceIsGood = false;
			    }

			    if (!findQueueFamilies(dev))
			    {
			        // device doesn't have all the queue families we need
			        errorStream << std::endl << "  - does not support the necessary queue types";
			        deviceIsGood = false;
			    }

			    // check that we can present from the graphics queue
			    uint32_t canPresent = dev.getSurfaceSupportKHR(m_GraphicsQueueFamily, m_WindowSurface);
			    if (!canPresent)
			    {
			        errorStream << std::endl << "  - cannot present";
			        deviceIsGood = false;
			    }

			    if (!deviceIsGood)
			        continue;

			    if (prop.deviceType == vk::PhysicalDeviceType::eDiscreteGpu)
			    {
			        discreteGPUs.push_back(dev);
			    } else {
			        otherGPUs.push_back(dev);
			    }
			}

			// pick the first discrete GPU if it exists, otherwise the first integrated GPU
			if (!discreteGPUs.empty())
			{
			    m_VulkanPhysicalDevice = discreteGPUs[0];
			    return true;
			}

			if (!otherGPUs.empty())
			{
			    m_VulkanPhysicalDevice = otherGPUs[0];
			    return true;
			}

			log::error("%s", errorStream.str().c_str());

			return false;
		}

		private bool findQueueFamilies(VkPhysicalDevice physicalDevice){
			auto props = physicalDevice.getQueueFamilyProperties();

			for(int i = 0; i < int(props.size()); i++)
			{
			    const auto& queueFamily = props[i];

			    if (m_GraphicsQueueFamily == -1)
			    {
			        if (queueFamily.queueCount > 0 &&
			            (queueFamily.queueFlags & vk::QueueFlagBits::eGraphics))
			        {
			            m_GraphicsQueueFamily = i;
			        }
			    }

			    if (m_ComputeQueueFamily == -1)
			    {
			        if (queueFamily.queueCount > 0 &&
			            (queueFamily.queueFlags & vk::QueueFlagBits::eCompute) &&
			            !(queueFamily.queueFlags & vk::QueueFlagBits::eGraphics))
			        {
			            m_ComputeQueueFamily = i;
			        }
			    }

			    if (m_TransferQueueFamily == -1)
			    {
			        if (queueFamily.queueCount > 0 &&
			            (queueFamily.queueFlags & vk::QueueFlagBits::eTransfer) && 
			            !(queueFamily.queueFlags & vk::QueueFlagBits::eCompute) &&
			            !(queueFamily.queueFlags & vk::QueueFlagBits::eGraphics))
			        {
			            m_TransferQueueFamily = i;
			        }
			    }

			    if (m_PresentQueueFamily == -1)
			    {
			        if (queueFamily.queueCount > 0 &&
			            glfwGetPhysicalDevicePresentationSupport(m_VulkanInstance, physicalDevice, i))
			        {
			            m_PresentQueueFamily = i;
			        }
			    }
			}

			if (m_GraphicsQueueFamily == -1 || 
			    m_PresentQueueFamily == -1 ||
			    (m_ComputeQueueFamily == -1 && m_DeviceParams.enableComputeQueue) || 
			    (m_TransferQueueFamily == -1 && m_DeviceParams.enableCopyQueue))
			{
			    return false;
			}

			return true;
		}

		private bool createDevice(){
			// figure out which optional extensions are supported
			auto deviceExtensions = m_VulkanPhysicalDevice.enumerateDeviceExtensionProperties();
			for(const auto& ext : deviceExtensions)
			{
			    const std::string name = ext.extensionName;
			    if (optionalExtensions.device.find(name) != optionalExtensions.device.end())
			    {
			        enabledExtensions.device.insert(name);
			    }

			    if (m_DeviceParams.enableRayTracingExtensions && m_RayTracingExtensions.find(name) != m_RayTracingExtensions.end())
			    {
			        enabledExtensions.device.insert(name);
			    }
			}

			bool accelStructSupported = false;
			bool bufferAddressSupported = false;
			bool rayPipelineSupported = false;
			bool rayQuerySupported = false;
			bool meshletsSupported = false;
			bool vrsSupported = false;

			log::message(m_DeviceParams.infoLogSeverity, "Enabled Vulkan device extensions:");
			for (const auto& ext : enabledExtensions.device)
			{
			    log::message(m_DeviceParams.infoLogSeverity, "    %s", ext.c_str());

			    if (ext == VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME)
			        accelStructSupported = true;
			    else if (ext == VK_KHR_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME)
			        bufferAddressSupported = true;
			    else if (ext == VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME)
			        rayPipelineSupported = true;
			    else if (ext == VK_KHR_RAY_QUERY_EXTENSION_NAME)
			        rayQuerySupported = true;
			    else if (ext == VK_NV_MESH_SHADER_EXTENSION_NAME)
			        meshletsSupported = true;
			    else if (ext == VK_KHR_FRAGMENT_SHADING_RATE_EXTENSION_NAME)
			        vrsSupported = true;
			}

			std::unordered_set<int> uniqueQueueFamilies = {
			    m_GraphicsQueueFamily,
			    m_PresentQueueFamily };

			if (m_DeviceParams.enableComputeQueue)
			    uniqueQueueFamilies.insert(m_ComputeQueueFamily);

			if (m_DeviceParams.enableCopyQueue)
			    uniqueQueueFamilies.insert(m_TransferQueueFamily);

			float priority = 1.f;
			std::vector<vk::DeviceQueueCreateInfo> queueDesc;
			for(int queueFamily : uniqueQueueFamilies)
			{
			    queueDesc.push_back(vk::DeviceQueueCreateInfo()
			                            .setQueueFamilyIndex(queueFamily)
			                            .setQueueCount(1)
			                            .setPQueuePriorities(&priority));
			}

			auto accelStructFeatures = vk::PhysicalDeviceAccelerationStructureFeaturesKHR()
			    .setAccelerationStructure(true);
			auto bufferAddressFeatures = vk::PhysicalDeviceBufferAddressFeaturesEXT()
			    .setBufferDeviceAddress(true);
			auto rayPipelineFeatures = vk::PhysicalDeviceRayTracingPipelineFeaturesKHR()
			    .setRayTracingPipeline(true)
			    .setRayTraversalPrimitiveCulling(true);
			auto rayQueryFeatures = vk::PhysicalDeviceRayQueryFeaturesKHR()
			    .setRayQuery(true);
			auto meshletFeatures = vk::PhysicalDeviceMeshShaderFeaturesNV()
			    .setTaskShader(true)
			    .setMeshShader(true);
			auto vrsFeatures = vk::PhysicalDeviceFragmentShadingRateFeaturesKHR()
			    .setPipelineFragmentShadingRate(true)
			    .setPrimitiveFragmentShadingRate(true)
			    .setAttachmentFragmentShadingRate(true);

			void* pNext = nullptr;
#define APPEND_EXTENSION(condition, desc) if (condition) { (desc).pNext = pNext; pNext = &(desc); }  // NOLINT(cppcoreguidelines-macro-usage)
			APPEND_EXTENSION(accelStructSupported, accelStructFeatures)
			APPEND_EXTENSION(bufferAddressSupported, bufferAddressFeatures)
			APPEND_EXTENSION(rayPipelineSupported, rayPipelineFeatures)
			APPEND_EXTENSION(rayQuerySupported, rayQueryFeatures)
			APPEND_EXTENSION(meshletsSupported, meshletFeatures)
			APPEND_EXTENSION(vrsSupported, vrsFeatures)
#undef APPEND_EXTENSION

			auto deviceFeatures = vk::PhysicalDeviceFeatures()
			    .setShaderImageGatherExtended(true)
			    .setSamplerAnisotropy(true)
			    .setTessellationShader(true)
			    .setTextureCompressionBC(true)
			    .setGeometryShader(true)
			    .setImageCubeArray(true)
			    .setDualSrcBlend(true);

			auto vulkan12features = vk::PhysicalDeviceVulkan12Features()
			    .setDescriptorIndexing(true)
			    .setRuntimeDescriptorArray(true)
			    .setDescriptorBindingPartiallyBound(true)
			    .setDescriptorBindingVariableDescriptorCount(true)
			    .setTimelineSemaphore(true)
			    .setShaderSampledImageArrayNonUniformIndexing(true)
			    .setPNext(pNext);

			auto layerVec = stringSetToVector(enabledExtensions.layers);
			auto extVec = stringSetToVector(enabledExtensions.device);

			auto deviceDesc = vk::DeviceCreateInfo()
			    .setPQueueCreateInfos(queueDesc.data())
			    .setQueueCreateInfoCount(uint32_t(queueDesc.size()))
			    .setPEnabledFeatures(&deviceFeatures)
			    .setEnabledExtensionCount(uint32_t(extVec.size()))
			    .setPpEnabledExtensionNames(extVec.data())
			    .setEnabledLayerCount(uint32_t(layerVec.size()))
			    .setPpEnabledLayerNames(layerVec.data())
			    .setPNext(&vulkan12features);

			if (m_DeviceParams.deviceCreateInfoCallback)
			    m_DeviceParams.deviceCreateInfoCallback(deviceDesc);

			const vk::Result res = m_VulkanPhysicalDevice.createDevice(&deviceDesc, nullptr, &m_VulkanDevice);
			if (res != vk::Result::eSuccess)
			{
			    log::error("Failed to create a Vulkan physical device, error code = %s", nvrhi::vulkan::resultToString(res));
			    return false;
			}

			m_VulkanDevice.getQueue(m_GraphicsQueueFamily, 0, &m_GraphicsQueue);
			if (m_DeviceParams.enableComputeQueue)
			    m_VulkanDevice.getQueue(m_ComputeQueueFamily, 0, &m_ComputeQueue);
			if (m_DeviceParams.enableCopyQueue)
			    m_VulkanDevice.getQueue(m_TransferQueueFamily, 0, &m_TransferQueue);
			m_VulkanDevice.getQueue(m_PresentQueueFamily, 0, &m_PresentQueue);

			VULKAN_HPP_DEFAULT_DISPATCHER.init(m_VulkanDevice);

			// stash the renderer string
			auto prop = m_VulkanPhysicalDevice.getProperties();
			m_RendererString = std::string(prop.deviceName.data());

			log::message(m_DeviceParams.infoLogSeverity, "Created Vulkan device: %s", m_RendererString.c_str());

			return true;
		}

		private bool createWindowSurface(){
			const VkResult res = glfwCreateWindowSurface(m_VulkanInstance, m_Window, nullptr, (VkSurfaceKHR *)&m_WindowSurface);
			if (res != VK_SUCCESS)
			{
			    log::error("Failed to create a GLFW window surface, error code = %s", nvrhi::vulkan::resultToString(res));
			    return false;
			}

			return true;
		}

		private bool createSwapChain(){
			destroySwapChain();

			m_SwapChainFormat = {
			    vk::Format(nvrhi::vulkan::convertFormat(m_DeviceParams.swapChainFormat)),
			    vk::ColorSpaceKHR::eSrgbNonlinear
			};

			vk::Extent2D extent = vk::Extent2D(m_DeviceParams.backBufferWidth, m_DeviceParams.backBufferHeight);

			std::unordered_set<uint32_t> uniqueQueues = {
			    uint32_t(m_GraphicsQueueFamily),
			    uint32_t(m_PresentQueueFamily) };

			std::vector<uint32_t> queues = setToVector(uniqueQueues);

			const bool enableSwapChainSharing = queues.size() > 1;

			auto desc = vk::SwapchainCreateInfoKHR()
			                .setSurface(m_WindowSurface)
			                .setMinImageCount(m_DeviceParams.swapChainBufferCount)
			                .setImageFormat(m_SwapChainFormat.format)
			                .setImageColorSpace(m_SwapChainFormat.colorSpace)
			                .setImageExtent(extent)
			                .setImageArrayLayers(1)
			                .setImageUsage(vk::ImageUsageFlagBits::eColorAttachment | vk::ImageUsageFlagBits::eTransferDst | vk::ImageUsageFlagBits::eSampled)
			                .setImageSharingMode(enableSwapChainSharing ? vk::SharingMode::eConcurrent : vk::SharingMode::eExclusive)
			                .setQueueFamilyIndexCount(enableSwapChainSharing ? uint32_t(queues.size()) : 0)
			                .setPQueueFamilyIndices(enableSwapChainSharing ? queues.data() : nullptr)
			                .setPreTransform(vk::SurfaceTransformFlagBitsKHR::eIdentity)
			                .setCompositeAlpha(vk::CompositeAlphaFlagBitsKHR::eOpaque)
			                .setPresentMode(m_DeviceParams.vsyncEnabled ? vk::PresentModeKHR::eFifo : vk::PresentModeKHR::eImmediate)
			                .setClipped(true)
			                .setOldSwapchain(nullptr);

			const vk::Result res = m_VulkanDevice.createSwapchainKHR(&desc, nullptr, &m_SwapChain);
			if (res != vk::Result::eSuccess)
			{
			    log::error("Failed to create a Vulkan swap chain, error code = %s", nvrhi::vulkan::resultToString(res));
			    return false;
			}

			// retrieve swap chain images
			auto images = m_VulkanDevice.getSwapchainImagesKHR(m_SwapChain);
			for(auto image : images)
			{
			    SwapChainImage sci;
			    sci.image = image;
			    
			    nvrhi::TextureDesc textureDesc;
			    textureDesc.width = m_DeviceParams.backBufferWidth;
			    textureDesc.height = m_DeviceParams.backBufferHeight;
			    textureDesc.format = m_DeviceParams.swapChainFormat;
			    textureDesc.debugName = "Swap chain image";
			    textureDesc.initialState = nvrhi::ResourceStates::Present;
			    textureDesc.keepInitialState = true;
			    textureDesc.isRenderTarget = true;

			    sci.rhiHandle = m_NvrhiDevice->createHandleForNativeTexture(nvrhi::ObjectTypes::VK_Image, nvrhi::Object(sci.image), textureDesc);
			    m_SwapChainImages.push_back(sci);
			}

			m_SwapChainIndex = 0;

			return true;
		}

		private void destroySwapChain(){
			
			if (m_VulkanDevice)
			{
			    m_VulkanDevice.waitIdle();
			}

			if (m_SwapChain)
			{
			    m_VulkanDevice.destroySwapchainKHR(m_SwapChain);
			    m_SwapChain = nullptr;
			}

			m_SwapChainImages.clear();
		}

		protected override bool CreateDeviceAndSwapChain()
		{
			if (m_DeviceParams.enableDebugRuntime)
			{
			    enabledExtensions.instance.insert("VK_EXT_debug_report");
			    enabledExtensions.layers.insert("VK_LAYER_KHRONOS_validation");
			}

			const vk::DynamicLoader dl;
			const PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr =   // NOLINT(misc-misplaced-const)
			    dl.getProcAddress<PFN_vkGetInstanceProcAddr>("vkGetInstanceProcAddr");
			VULKAN_HPP_DEFAULT_DISPATCHER.init(vkGetInstanceProcAddr);

#define CHECK(a) if (!(a)) { return false; }

			CHECK(createInstance())

			if (m_DeviceParams.enableDebugRuntime)
			{
			    installDebugCallback();
			}

			if (m_DeviceParams.swapChainFormat == nvrhi::Format::SRGBA8_UNORM)
			    m_DeviceParams.swapChainFormat = nvrhi::Format::SBGRA8_UNORM;
			else if (m_DeviceParams.swapChainFormat == nvrhi::Format::RGBA8_UNORM)
			    m_DeviceParams.swapChainFormat = nvrhi::Format::BGRA8_UNORM;

			// add device extensions requested by the user
			for (const std::string& name : m_DeviceParams.requiredVulkanDeviceExtensions)
			{
			    enabledExtensions.device.insert(name);
			}
			for (const std::string& name : m_DeviceParams.optionalVulkanDeviceExtensions)
			{
			    optionalExtensions.device.insert(name);
			}

			CHECK(createWindowSurface())
			CHECK(pickPhysicalDevice())
			CHECK(findQueueFamilies(m_VulkanPhysicalDevice))
			CHECK(createDevice())

			auto vecInstanceExt = stringSetToVector(enabledExtensions.instance);
			auto vecLayers = stringSetToVector(enabledExtensions.layers);
			auto vecDeviceExt = stringSetToVector(enabledExtensions.device);

			nvrhi::vulkan::DeviceDesc deviceDesc;
			deviceDesc.errorCB = &DefaultMessageCallback::GetInstance();
			deviceDesc.instance = m_VulkanInstance;
			deviceDesc.physicalDevice = m_VulkanPhysicalDevice;
			deviceDesc.device = m_VulkanDevice;
			deviceDesc.graphicsQueue = m_GraphicsQueue;
			deviceDesc.graphicsQueueIndex = m_GraphicsQueueFamily;
			if (m_DeviceParams.enableComputeQueue)
			{
			    deviceDesc.computeQueue = m_ComputeQueue;
			    deviceDesc.computeQueueIndex = m_ComputeQueueFamily;
			}
			if (m_DeviceParams.enableCopyQueue)
			{
			    deviceDesc.transferQueue = m_TransferQueue;
			    deviceDesc.transferQueueIndex = m_TransferQueueFamily;
			}
			deviceDesc.instanceExtensions = vecInstanceExt.data();
			deviceDesc.numInstanceExtensions = vecInstanceExt.size();
			deviceDesc.deviceExtensions = vecDeviceExt.data();
			deviceDesc.numDeviceExtensions = vecDeviceExt.size();

			m_NvrhiDevice = nvrhi::vulkan::createDevice(deviceDesc);

			if (m_DeviceParams.enableNvrhiValidationLayer)
			{
			    m_ValidationLayer = nvrhi::validation::createValidationLayer(m_NvrhiDevice);
			}

			CHECK(createSwapChain())

			m_BarrierCommandList = m_NvrhiDevice->createCommandList();

			m_PresentSemaphore = m_VulkanDevice.createSemaphore(vk::SemaphoreCreateInfo());

#undef CHECK

			return true;
		}

		protected override void DestroyDeviceAndSwapChain()
		{
			destroySwapChain();

			m_VulkanDevice.destroySemaphore(m_PresentSemaphore);
			m_PresentSemaphore = vk::Semaphore();

			m_BarrierCommandList = nullptr;

			m_NvrhiDevice = nullptr;
			m_ValidationLayer = nullptr;
			m_RendererString.clear();

			if (m_DebugReportCallback)
			{
			    m_VulkanInstance.destroyDebugReportCallbackEXT(m_DebugReportCallback);
			}

			if (m_VulkanDevice)
			{
			    m_VulkanDevice.destroy();
			    m_VulkanDevice = nullptr;
			}

			if (m_WindowSurface)
			{
			    assert(m_VulkanInstance);
			    m_VulkanInstance.destroySurfaceKHR(m_WindowSurface);
			    m_WindowSurface = nullptr;
			}

			if (m_VulkanInstance)
			{
			    m_VulkanInstance.destroy();
			    m_VulkanInstance = nullptr;
			}
		}
	}
}