using nvrhi.deviceManager;
using Bulkan;
using System.Collections;
using System;
using System.Diagnostics;
using static Bulkan.VulkanNative;

namespace nvrhi.deviceManager
{
	extension DeviceCreationParameters
	{
		public List<String> requiredVulkanInstanceExtensions;
		public List<String> requiredVulkanDeviceExtensions;
		public List<String> requiredVulkanLayers;
		public List<String> optionalVulkanInstanceExtensions;
		public List<String> optionalVulkanDeviceExtensions;
		public List<String> optionalVulkanLayers;
		public List<int> ignoredVulkanValidationMessageLocations;
		public function void(void* info) deviceCreateInfoCallback = null;
	}
}

namespace nvrhi.deviceManager.vulkan
{
	public static
	{
		public static mixin CHECK(var a)
		{
			if (!(a)) { return false; }
		}

		class VulkanDeviceManager : DeviceManager
		{
			private struct VulkanExtensionSet
			{
				public HashSet<String> instance;
				public HashSet<String> layers;
				public HashSet<String> device;

				public void Dispose()
				{
					if (instance != null)
						DeleteContainerAndItems!(instance);

					if (layers != null)
						DeleteContainerAndItems!(layers);

					if (device != null)
						DeleteContainerAndItems!(device);
				}
			}

			// minimal set of required extensions
			private VulkanExtensionSet enabledExtensions = .()
				{
					instance = new .()
						{
							new .(VulkanNative.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME)
						},
					layers = new .() { },
					device = new .()
						{
							new .(VulkanNative.VK_KHR_SWAPCHAIN_EXTENSION_NAME),
							new .(VulkanNative.VK_KHR_MAINTENANCE1_EXTENSION_NAME)
						}
				} ~ _.Dispose();

			// optional extensions
			private VulkanExtensionSet optionalExtensions = .()
				{
					instance = new .()
						{
							new .(VulkanNative.VK_EXT_SAMPLER_FILTER_MINMAX_EXTENSION_NAME),
							new .(VulkanNative.VK_EXT_DEBUG_UTILS_EXTENSION_NAME)
						},
					layers = new .() { },
					device = new .()
						{
							new .(VulkanNative.VK_EXT_DEBUG_MARKER_EXTENSION_NAME),
							new .(VulkanNative.VK_EXT_DESCRIPTOR_INDEXING_EXTENSION_NAME),
							new .(VulkanNative.VK_KHR_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME),
							new .(VulkanNative.VK_NV_MESH_SHADER_EXTENSION_NAME),
							new .(VulkanNative.VK_KHR_FRAGMENT_SHADING_RATE_EXTENSION_NAME)
						}
				} ~ _.Dispose();

			private HashSet<String> m_RayTracingExtensions = new .()
				{
					new .(VulkanNative.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME),
					new .(VulkanNative.VK_KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME),
					new .(VulkanNative.VK_KHR_PIPELINE_LIBRARY_EXTENSION_NAME),
					new .(VulkanNative.VK_KHR_RAY_QUERY_EXTENSION_NAME),
					new .(VulkanNative.VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME)
				} ~ DeleteContainerAndItems!(_);

			private String m_RendererString = new .() ~ delete _;

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

			private List<SwapChainImage> m_SwapChainImages = new .() ~ delete _;
			private uint32 m_SwapChainIndex = uint32(-1);

			private nvrhi.vulkan.DeviceHandle m_NvrhiDevice;
			private nvrhi.DeviceHandle m_ValidationLayer;

			private nvrhi.CommandListHandle m_BarrierCommandList;
			private VkSemaphore m_PresentSemaphore;

			private System.Collections.Queue<nvrhi.EventQueryHandle> m_FramesInFlight = new .()  ~ DeleteContainerAndItems!(_);
			private List<nvrhi.EventQueryHandle> m_QueryPool = new .() ~ DeleteContainerAndItems!(_);

			public this(DeviceCreationParameters @params) : base(@params)
			{
			}

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
				readonly VkResult res = vkAcquireNextImageKHR(m_VulkanDevice, m_SwapChain,
					uint64.MaxValue, // timeout
					m_PresentSemaphore,
					.Null,
					&m_SwapChainIndex);

				Runtime.Assert(res == VkResult.eVkSuccess);

				m_NvrhiDevice.queueWaitForSemaphore(nvrhi.CommandQueue.Graphics, m_PresentSemaphore, 0);
			}

			protected override void Present()
			{
				m_NvrhiDevice.queueSignalSemaphore(nvrhi.CommandQueue.Graphics, m_PresentSemaphore, 0);

				m_BarrierCommandList.open(); // umm...
				m_BarrierCommandList.close();
				m_NvrhiDevice.executeCommandList(m_BarrierCommandList);

				VkPresentInfoKHR info = VkPresentInfoKHR()
					.setWaitSemaphoreCount(1)
					.setPWaitSemaphores(&m_PresentSemaphore)
					.setSwapchainCount(1)
					.setPSwapchains(&m_SwapChain)
					.setPImageIndices(&m_SwapChainIndex);

				readonly VkResult res = vkQueuePresentKHR(m_PresentQueue, &info);
				Runtime.Assert(res == VkResult.eVkSuccess || res == VkResult.eVkErrorOutOfDateKHR);

				if (m_DeviceParams.enableDebugRuntime)
				{
					// according to vulkan-tutorial.com, "the validation layer implementation expects
					// the application to explicitly synchronize with the GPU"
					vkQueueWaitIdle(m_PresentQueue);
				}
				else
				{
#if !BF_PLATFORM_WINDOWS
					if (m_DeviceParams.vsyncEnabled)
					{
						vkQueueWaitIdle(m_PresentQueue);
					}
#endif

					while (m_FramesInFlight.Count > m_DeviceParams.maxFramesInFlight)
					{
						var query = m_FramesInFlight.Front;
						m_FramesInFlight.PopFront();

						m_NvrhiDevice.waitEventQuery(query);

						m_QueryPool.Add(query);
					}

					nvrhi.EventQueryHandle query;
					if (!m_QueryPool.IsEmpty)
					{
						query = m_QueryPool.Back;
						m_QueryPool.PopBack();
					}
					else
					{
						query = m_NvrhiDevice.createEventQuery();
					}

					m_NvrhiDevice.resetEventQuery(query);
					m_NvrhiDevice.setEventQuery(query, nvrhi.CommandQueue.Graphics);
					m_FramesInFlight.Add(query);
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

			/*

			public typealias PFN_vkDebugReportCallbackEXT = function VkBool32(
			uint32 flags,
			VkDebugReportObjectTypeEXT objectType,
			uint64 object,
			uint location,
			int32 messageCode,
			char8* pLayerPrefix,
			char8* pMessage,
			void* pUserData);


			*/

			private static VkBool32 vulkanDebugCallback( /*VkDebugReportFlagsEXT*/uint32 flags,
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
					const auto& ignored = manager.m_DeviceParams.ignoredVulkanValidationMessageLocations;
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
				return enabledExtensions.instance.Contains(scope String(extensionName));
			}

			private bool IsVulkanDeviceExtensionEnabled(char8* extensionName)
			{
				return enabledExtensions.device.Contains(scope String(extensionName));
			}

			private bool IsVulkanLayerEnabled(char8* layerName)
			{
				return enabledExtensions.layers.Contains(scope String(layerName));
			}

			private void GetEnabledVulkanInstanceExtensions(List<String> extensions)
			{
				for (var ext in enabledExtensions.instance)
					extensions.Add(ext);
			}

			private void GetEnabledVulkanDeviceExtensions(List<String> extensions)
			{
				for (var ext in enabledExtensions.device)
					extensions.Add(ext);
			}

			private void GetEnabledVulkanLayers(List<String> layers)
			{
				for (var ext in enabledExtensions.layers)
					layers.Add(ext);
			}

			private bool createInstance()
			{
				// add any required extensions
				enabledExtensions.instance.Add(new .(VulkanNative.VK_KHR_SURFACE_EXTENSION_NAME));
#if BF_PLATFORM_WINDOWS
				enabledExtensions.instance.Add(new .(VulkanNative.VK_KHR_WIN32_SURFACE_EXTENSION_NAME));
#endif

				// add instance extensions requested by the user
				if (m_DeviceParams.requiredVulkanInstanceExtensions != null)
				{
					for (var name in m_DeviceParams.requiredVulkanInstanceExtensions)
					{
						enabledExtensions.instance.Add(name);
					}
				}
				if (m_DeviceParams.optionalVulkanInstanceExtensions != null)
				{
					for (var name in m_DeviceParams.optionalVulkanInstanceExtensions)
					{
						optionalExtensions.instance.Add(name);
					}
				}

				// add layers requested by the user
				if (m_DeviceParams.requiredVulkanLayers != null)
				{
					for (var name in m_DeviceParams.requiredVulkanLayers)
					{
						enabledExtensions.layers.Add(name);
					}
				}
				if (m_DeviceParams.optionalVulkanLayers != null)
				{
					for (var name in m_DeviceParams.optionalVulkanLayers)
					{
						optionalExtensions.layers.Add(name);
					}
				}

				HashSet<String> requiredExtensions = scope .();
				for (var instanceExtension in enabledExtensions.instance)
				{
					requiredExtensions.Add(instanceExtension);
				}

				// figure out which optional extensions are supported
				uint32 instanceExtensionCount = 0;
				vkEnumerateInstanceExtensionProperties(null, &instanceExtensionCount, null);
				List<VkExtensionProperties> instanceExtensions = scope .() { Count = instanceExtensionCount };
				vkEnumerateInstanceExtensionProperties(null, &instanceExtensionCount, instanceExtensions.Ptr);

				for (var instanceExt in instanceExtensions)
				{
					String name = scope:: .(&instanceExt.extensionName);
					if (optionalExtensions.instance.Contains(name))
					{
						enabledExtensions.instance.Add(new .(name));
					}

					requiredExtensions.Remove(name);
				}

				if (!requiredExtensions.IsEmpty)
				{
					String ss = scope .();
					ss.Append("Cannot create a Vulkan instance because the following required extension(s) are not supported:");
					for (var ext in requiredExtensions)
						ss.AppendF("\n  - {}",  ext);

					Debug.WriteLine(ss);
					return false;
				}

				Debug.WriteLine("Enabled Vulkan instance extensions:");
				for (var ext in enabledExtensions.instance)
				{
					Debug.WriteLine("    {}", ext);
				}

				HashSet<String> requiredLayers = scope .();
				for (var instanceLayer in enabledExtensions.layers)
				{
					requiredLayers.Add(instanceLayer);
				}

				uint32 instanceLayerCount = 0;
				vkEnumerateInstanceLayerProperties(&instanceLayerCount, null);
				List<VkLayerProperties> instanceLayerProperties = scope .() { Count = instanceLayerCount };
				vkEnumerateInstanceLayerProperties(&instanceLayerCount, instanceLayerProperties.Ptr);

				for (var layer in instanceLayerProperties)
				{
					String name = scope:: .(&layer.layerName);
					if (optionalExtensions.layers.Contains(name))
					{
						enabledExtensions.layers.Add(new .(name));
					}

					requiredLayers.Remove(name);
				}

				if (!requiredLayers.IsEmpty)
				{
					String ss = scope .();
					ss.Append("Cannot create a Vulkan instance because the following required layer(s) are not supported:");
					for (var ext in requiredLayers)
						ss.AppendF("\n  - ",  ext);

					Debug.WriteLine(ss);
					return false;
				}

				Debug.WriteLine("Enabled Vulkan layers:");
				for (var layer in enabledExtensions.layers)
				{
					Debug.WriteLine("    {}", layer);
				}

				var instanceExtVec = StringListToCStringList(enabledExtensions.instance, .. scope .());
				var layerVec = StringListToCStringList(enabledExtensions.layers, .. scope .());

				var applicationInfo = VkApplicationInfo()
					.setApiVersion(VulkanNative.VK_API_VERSION_1_2);

				// create the vulkan instance
				VkInstanceCreateInfo info = VkInstanceCreateInfo()
					.setEnabledLayerCount(uint32(layerVec.Count))
					.setPpEnabledLayerNames(layerVec.Ptr)
					.setEnabledExtensionCount(uint32(instanceExtVec.Count))
					.setPpEnabledExtensionNames(instanceExtVec.Ptr)
					.setPApplicationInfo(&applicationInfo);

				readonly VkResult res = vkCreateInstance(&info, null, &m_VulkanInstance);
				if (res != VkResult.eVkSuccess)
				{
					Debug.WriteLine("Failed to create a Vulkan instance, error code = {}", nvrhi.vulkan.resultToString(res));
					return false;
				}

				return true;
			}

			private void installDebugCallback()
			{
				PFN_vkDebugReportCallbackEXT debugCallback = => vulkanDebugCallback;

				var info = VkDebugReportCallbackCreateInfoEXT()
					.setFlags(VkDebugReportFlagsEXT.eErrorBitEXT |
					VkDebugReportFlagsEXT.eWarningBitEXT | //VkDebugReportFlagsEXT.eInformationBitEXT |
					VkDebugReportFlagsEXT.ePerformanceWarningBitEXT)
					.setPfnCallback(debugCallback)
					.setPUserData(Internal.UnsafeCastToPtr(this));

				VkResult res = vkCreateDebugReportCallbackEXT(m_VulkanInstance, &info, null, &m_DebugReportCallback);
				Runtime.Assert(res == VkResult.eVkSuccess);
			}

			private bool pickPhysicalDevice()
			{
				VkFormat requestedFormat = nvrhi.vulkan.convertFormat(m_DeviceParams.swapChainFormat);
				VkExtent2D requestedExtent = .(m_DeviceParams.backBufferWidth, m_DeviceParams.backBufferHeight);

				uint32 physicalDeviceCount = 0;
				vkEnumeratePhysicalDevices(m_VulkanInstance, &physicalDeviceCount, null);
				List<VkPhysicalDevice> devices = scope .() { Count = physicalDeviceCount };
				vkEnumeratePhysicalDevices(m_VulkanInstance, &physicalDeviceCount, devices.Ptr);

				// Start building an error message in case we cannot find a device.
				String errorStream = scope .();
				errorStream.Append("Cannot find a Vulkan device that supports all the required extensions and properties.");

				// build a list of GPUs
				List<VkPhysicalDevice> discreteGPUs = scope .();
				List<VkPhysicalDevice> otherGPUs = scope .();
				for (var dev in devices)
				{
					VkPhysicalDeviceProperties prop = .();
					vkGetPhysicalDeviceProperties(dev, &prop);

					errorStream.AppendF("\n{}:", scope String(&prop.deviceName));

					// check that all required device extensions are present
					HashSet<String> requiredExtensions = scope .();
					for (var requiredDeviceExtension in enabledExtensions.device)
					{
						requiredExtensions.Add(requiredDeviceExtension);
					}
					uint32 deviceExtensionCount = 0;
					vkEnumerateDeviceExtensionProperties(dev, null, &deviceExtensionCount, null);
					List<VkExtensionProperties> deviceExtensions = scope .() { Count = deviceExtensionCount };
					vkEnumerateDeviceExtensionProperties(dev, null, &deviceExtensionCount, deviceExtensions.Ptr);
					for (var ext in deviceExtensions)
					{
						requiredExtensions.Remove(scope String(&ext.extensionName));
					}

					bool deviceIsGood = true;

					if (!requiredExtensions.IsEmpty)
					{
						// device is missing one or more required extensions
						for (var ext in requiredExtensions)
						{
							errorStream.AppendF("\n  - missing {}",  ext);
						}
						deviceIsGood = false;
					}

					VkPhysicalDeviceFeatures deviceFeatures = .();
					vkGetPhysicalDeviceFeatures(dev, &deviceFeatures);
					if (!deviceFeatures.samplerAnisotropy)
					{
						// device is a toaster oven
						errorStream.Append("\n  - does not support samplerAnisotropy");
						deviceIsGood = false;
					}
					if (!deviceFeatures.textureCompressionBC)
					{
						errorStream.Append("  - does not support textureCompressionBC");
						deviceIsGood = false;
					}

					// check that this device supports our intended swap chain creation parameters
					VkSurfaceCapabilitiesKHR surfaceCaps = .();
					vkGetPhysicalDeviceSurfaceCapabilitiesKHR(dev, m_WindowSurface, &surfaceCaps);

					uint32 formatCount = 0;
					vkGetPhysicalDeviceSurfaceFormatsKHR(dev, m_WindowSurface, &formatCount, null);
					List<VkSurfaceFormatKHR> surfaceFmts = scope .() { Count = formatCount };
					vkGetPhysicalDeviceSurfaceFormatsKHR(dev, m_WindowSurface, &formatCount, surfaceFmts.Ptr);

					uint32 modeCount = 0;
					vkGetPhysicalDeviceSurfacePresentModesKHR(dev, m_WindowSurface, &modeCount, null);
					List<VkPresentModeKHR> surfacePModes = scope .() { Count = modeCount };
					vkGetPhysicalDeviceSurfacePresentModesKHR(dev, m_WindowSurface, &modeCount, surfacePModes.Ptr);

					if (surfaceCaps.minImageCount > m_DeviceParams.swapChainBufferCount ||
						(surfaceCaps.maxImageCount < m_DeviceParams.swapChainBufferCount && surfaceCaps.maxImageCount > 0))
					{
						errorStream.Append("\n  - cannot support the requested swap chain image count:");
						errorStream.AppendF(" requested {}, available {} - {}", m_DeviceParams.swapChainBufferCount, surfaceCaps.minImageCount, surfaceCaps.maxImageCount);
						deviceIsGood = false;
					}

					if (surfaceCaps.minImageExtent.width > requestedExtent.width ||
						surfaceCaps.minImageExtent.height > requestedExtent.height ||
						surfaceCaps.maxImageExtent.width < requestedExtent.width ||
						surfaceCaps.maxImageExtent.height < requestedExtent.height)
					{
						errorStream.Append("\n  - cannot support the requested swap chain size:");
						errorStream.AppendF(" requested {}x{}, ", requestedExtent.width, requestedExtent.height);
						errorStream.AppendF(" available {}x{}", surfaceCaps.minImageExtent.width, surfaceCaps.minImageExtent.height);
						errorStream.AppendF(" - {}x{}", surfaceCaps.maxImageExtent.width,  surfaceCaps.maxImageExtent.height);
						deviceIsGood = false;
					}

					bool surfaceFormatPresent = false;
					for (readonly ref VkSurfaceFormatKHR surfaceFmt in ref surfaceFmts)
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
						errorStream.Append("\n  - does not support the requested swap chain format");
						deviceIsGood = false;
					}

					if (!findQueueFamilies(dev))
					{
						// device doesn't have all the queue families we need
						errorStream.Append("\n  - does not support the necessary queue types");
						deviceIsGood = false;
					}

					// check that we can present from the graphics queue
					VkBool32 canPresent = false;
					vkGetPhysicalDeviceSurfaceSupportKHR(dev, (.)m_GraphicsQueueFamily, m_WindowSurface, &canPresent);
					if (!canPresent)
					{
						errorStream.Append("\n  - cannot present");
						deviceIsGood = false;
					}

					if (!deviceIsGood)
						continue;

					if (prop.deviceType == VkPhysicalDeviceType.eDiscreteGpu)
					{
						discreteGPUs.Add(dev);
					} else
					{
						otherGPUs.Add(dev);
					}
				}

				// pick the first discrete GPU if it exists, otherwise the first integrated GPU
				if (!discreteGPUs.IsEmpty)
				{
					m_VulkanPhysicalDevice = discreteGPUs[0];
					return true;
				}

				if (!otherGPUs.IsEmpty)
				{
					m_VulkanPhysicalDevice = otherGPUs[0];
					return true;
				}

				Debug.WriteLine(errorStream);

				return false;
			}

			private bool findQueueFamilies(VkPhysicalDevice physicalDevice)
			{
				List<VkQueueFamilyProperties> props = scope .();
				uint32 queueFamilyCount = 0;
				vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, null);
				props.Resize(queueFamilyCount);
				vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, props.Ptr);

				for (int i = 0; i < int(props.Count); i++)
				{
					var queueFamily = ref props[i];

					if (m_GraphicsQueueFamily == -1)
					{
						if (queueFamily.queueCount > 0 &&
							(queueFamily.queueFlags & VkQueueFlags.eGraphicsBit != 0))
						{
							m_GraphicsQueueFamily = (.)i;
						}
					}

					if (m_ComputeQueueFamily == -1)
					{
						if (queueFamily.queueCount > 0 &&
							(queueFamily.queueFlags & VkQueueFlags.eComputeBit != 0) &&
							!(queueFamily.queueFlags & VkQueueFlags.eGraphicsBit != 0))
						{
							m_ComputeQueueFamily = (.)i;
						}
					}

					if (m_TransferQueueFamily == -1)
					{
						if (queueFamily.queueCount > 0 &&
							(queueFamily.queueFlags & VkQueueFlags.eTransferBit != 0) &&
							!(queueFamily.queueFlags & VkQueueFlags.eComputeBit != 0) &&
							!(queueFamily.queueFlags & VkQueueFlags.eGraphicsBit != 0))
						{
							m_TransferQueueFamily = (.)i;
						}
					}

					if (m_PresentQueueFamily == -1)
					{
						/*if (queueFamily.queueCount > 0 && 
							glfwGetPhysicalDevicePresentationSupport(m_VulkanInstance, physicalDevice, i))
						{
							m_PresentQueueFamily = (.)i;
						}*/

						if (m_GraphicsQueueFamily != -1)
						{
							m_PresentQueueFamily = m_GraphicsQueueFamily;
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

			private void StringListToCStringList(HashSet<String> input, List<char8*> output)
			{
				for (var item in input)
				{
					output.Add(item);
				}
			};

			private bool createDevice()
			{
				// figure out which optional extensions are supported
				uint32 devicePropertyCount = 0;
				vkEnumerateDeviceExtensionProperties(m_VulkanPhysicalDevice, null, &devicePropertyCount, null);
				List<VkExtensionProperties> deviceExtensions = scope .() { Count = devicePropertyCount };
				vkEnumerateDeviceExtensionProperties(m_VulkanPhysicalDevice, null, &devicePropertyCount, deviceExtensions.Ptr);
				for (var ext in deviceExtensions)
				{
					readonly String name = scope:: String(&ext.extensionName);
					if (optionalExtensions.device.Contains(name))
					{
						enabledExtensions.device.Add(new .(name));
					}

					if (m_DeviceParams.enableRayTracingExtensions && m_RayTracingExtensions.Contains(name))
					{
						enabledExtensions.device.Add(new .(name));
					}
				}

				bool accelStructSupported = false;
				bool bufferAddressSupported = false;
				bool rayPipelineSupported = false;
				bool rayQuerySupported = false;
				bool meshletsSupported = false;
				bool vrsSupported = false;

				Debug.WriteLine("Enabled Vulkan device extensions:");
				for (var ext in enabledExtensions.device)
				{
					Debug.WriteLine("    {}", ext);

					if (String.Equals(ext,  VulkanNative.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME))
						accelStructSupported = true;
					else if (String.Equals(ext, VulkanNative.VK_KHR_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME))
						bufferAddressSupported = true;
					else if (String.Equals(ext, VulkanNative.VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME))
						rayPipelineSupported = true;
					else if (String.Equals(ext, VulkanNative.VK_KHR_RAY_QUERY_EXTENSION_NAME))
						rayQuerySupported = true;
					else if (String.Equals(ext, VulkanNative.VK_NV_MESH_SHADER_EXTENSION_NAME))
						meshletsSupported = true;
					else if (String.Equals(ext, VulkanNative.VK_KHR_FRAGMENT_SHADING_RATE_EXTENSION_NAME))
						vrsSupported = true;
				}

				HashSet<int> uniqueQueueFamilies = scope .()
					{
						m_GraphicsQueueFamily,
						m_PresentQueueFamily
					};

				if (m_DeviceParams.enableComputeQueue)
					uniqueQueueFamilies.Add(m_ComputeQueueFamily);

				if (m_DeviceParams.enableCopyQueue)
					uniqueQueueFamilies.Add(m_TransferQueueFamily);

				float priority = 1.f;
				List<VkDeviceQueueCreateInfo> queueDesc = scope .();
				for (int queueFamily in uniqueQueueFamilies)
				{
					queueDesc.Add(VkDeviceQueueCreateInfo()
						.setQueueFamilyIndex((.)queueFamily)
						.setQueueCount(1)
						.setPQueuePriorities(&priority));
				}

				var accelStructFeatures = VkPhysicalDeviceAccelerationStructureFeaturesKHR()
					.setAccelerationStructure(true);
				var bufferAddressFeatures = VkPhysicalDeviceBufferDeviceAddressFeaturesEXT()
					.setBufferDeviceAddress(true);
				var rayPipelineFeatures = VkPhysicalDeviceRayTracingPipelineFeaturesKHR()
					.setRayTracingPipeline(true)
					.setRayTraversalPrimitiveCulling(true);
				var rayQueryFeatures = VkPhysicalDeviceRayQueryFeaturesKHR()
					.setRayQuery(true);
				var meshletFeatures = VkPhysicalDeviceMeshShaderFeaturesNV()
					.setTaskShader(true)
					.setMeshShader(true);
				var vrsFeatures = VkPhysicalDeviceFragmentShadingRateFeaturesKHR()
					.setPipelineFragmentShadingRate(true)
					.setPrimitiveFragmentShadingRate(true)
					.setAttachmentFragmentShadingRate(true);

				void* pNext = null;

	/*#define APPEND_EXTENSION(condition, desc) if (condition) { (desc).pNext = pNext; pNext = &(desc); }  // NOLINT(cppcoreguidelines-macro-usage)
				APPEND_EXTENSION(accelStructSupported, accelStructFeatures)
				APPEND_EXTENSION(bufferAddressSupported, bufferAddressFeatures)
				APPEND_EXTENSION(rayPipelineSupported, rayPipelineFeatures)
				APPEND_EXTENSION(rayQuerySupported, rayQueryFeatures)
				APPEND_EXTENSION(meshletsSupported, meshletFeatures)
				APPEND_EXTENSION(vrsSupported, vrsFeatures)
				#undef APPEND_EXTENSION*/



				void AppendExtension<T>(bool condition, ref T desc) where T : var
				{
					if (condition)
					{
						desc.pNext = pNext;
						pNext = &desc;
					}
				}

				AppendExtension(accelStructSupported, ref accelStructFeatures);
				AppendExtension(bufferAddressSupported, ref bufferAddressFeatures);
				AppendExtension(rayPipelineSupported, ref rayPipelineFeatures);
				AppendExtension(rayQuerySupported, ref rayQueryFeatures);
				AppendExtension(meshletsSupported, ref meshletFeatures);
				AppendExtension(vrsSupported, ref vrsFeatures);

				var deviceFeatures = VkPhysicalDeviceFeatures()
					.setShaderImageGatherExtended(true)
					.setSamplerAnisotropy(true)
					.setTessellationShader(true)
					.setTextureCompressionBC(true)
					.setGeometryShader(true)
					.setImageCubeArray(true)
					.setDualSrcBlend(true);

				var vulkan12features = VkPhysicalDeviceVulkan12Features()
					.setDescriptorIndexing(true)
					.setRuntimeDescriptorArray(true)
					.setDescriptorBindingPartiallyBound(true)
					.setDescriptorBindingVariableDescriptorCount(true)
					.setTimelineSemaphore(true)
					.setShaderSampledImageArrayNonUniformIndexing(true)
					.setPNext(pNext);

				List<char8*> layerVec = StringListToCStringList(enabledExtensions.layers, .. scope .());
				List<char8*> extVec = StringListToCStringList(enabledExtensions.device, .. scope .());

				var deviceDesc = VkDeviceCreateInfo()
					.setPQueueCreateInfos(queueDesc.Ptr)
					.setQueueCreateInfoCount(uint32(queueDesc.Count))
					.setPEnabledFeatures(&deviceFeatures)
					.setEnabledExtensionCount(uint32(extVec.Count))
					.setPpEnabledExtensionNames(extVec.Ptr)
					.setEnabledLayerCount(uint32(layerVec.Count))
					.setPpEnabledLayerNames(layerVec.Ptr)
					.setPNext(&vulkan12features);

				if (m_DeviceParams.deviceCreateInfoCallback != null)
					m_DeviceParams.deviceCreateInfoCallback(&deviceDesc);

				readonly VkResult res = vkCreateDevice(m_VulkanPhysicalDevice, &deviceDesc, null, &m_VulkanDevice);
				if (res != VkResult.eVkSuccess)
				{
					Debug.WriteLine("Failed to create a Vulkan physical device, error code = %s", nvrhi.vulkan.resultToString(res));
					return false;
				}

				vkGetDeviceQueue(m_VulkanDevice, (.)m_GraphicsQueueFamily, 0, &m_GraphicsQueue);
				if (m_DeviceParams.enableComputeQueue)
					vkGetDeviceQueue(m_VulkanDevice, (.)m_ComputeQueueFamily, 0, &m_ComputeQueue);
				if (m_DeviceParams.enableCopyQueue)
					vkGetDeviceQueue(m_VulkanDevice, (.)m_TransferQueueFamily, 0, &m_TransferQueue);
				vkGetDeviceQueue(m_VulkanDevice, (.)m_PresentQueueFamily, 0, &m_PresentQueue);

				//VULKAN_HPP_DEFAULT_DISPATCHER.init(m_VulkanDevice);

				// stash the renderer string
				VkPhysicalDeviceProperties prop = .();
				vkGetPhysicalDeviceProperties(m_VulkanPhysicalDevice, &prop);

				m_RendererString.Set(scope  String(&prop.deviceName));

				Debug.WriteLine(scope $"Created Vulkan device: {m_RendererString}");

				return true;
			}

			private bool createWindowSurface()
			{
				VkResult result = .eVkSuccess;
				if (m_DeviceParams.windowType == .Windows)
				{
					VkWin32SurfaceCreateInfoKHR win32SurfaceInfo = .() { };
					win32SurfaceInfo.sType = .VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR;
					win32SurfaceInfo.hwnd = /*(HWND)*/ m_DeviceParams.windowHandle;
					result = vkCreateWin32SurfaceKHR(m_VulkanInstance, &win32SurfaceInfo, null, &m_WindowSurface);
					if (result != .eVkSuccess)
					{
						Debug.WriteLine("Failed to create a window surface, error code = {}", nvrhi.vulkan.resultToString(result));
						return false;
					}

					return true;
				}

				return false;
			}

			private bool createSwapChain()
			{
				destroySwapChain();

				m_SwapChainFormat = .()
					{
						format = nvrhi.vulkan.convertFormat(m_DeviceParams.swapChainFormat),
						colorSpace = VkColorSpaceKHR.eSrgbNonlinearKHR
					};

				VkExtent2D extent = VkExtent2D(m_DeviceParams.backBufferWidth, m_DeviceParams.backBufferHeight);

				HashSet<uint32> uniqueQueues = scope .()
					{
						uint32(m_GraphicsQueueFamily),
						uint32(m_PresentQueueFamily)
					};

				List<uint32> queues = scope .()
					..AddRange(uniqueQueues);

				readonly bool enableSwapChainSharing = queues.Count > 1;

				var desc = VkSwapchainCreateInfoKHR()
					.setSurface(m_WindowSurface)
					.setMinImageCount(m_DeviceParams.swapChainBufferCount)
					.setImageFormat(m_SwapChainFormat.format)
					.setImageColorSpace(m_SwapChainFormat.colorSpace)
					.setImageExtent(extent)
					.setImageArrayLayers(1)
					.setImageUsage(VkImageUsageFlags.eColorAttachmentBit | VkImageUsageFlags.eTransferDstBit | VkImageUsageFlags.eSampledBit)
					.setImageSharingMode(enableSwapChainSharing ? VkSharingMode.eConcurrent : VkSharingMode.eExclusive)
					.setQueueFamilyIndexCount(enableSwapChainSharing ? uint32(queues.Count) : 0)
					.setPQueueFamilyIndices(enableSwapChainSharing ? queues.Ptr : null)
					.setPreTransform(VkSurfaceTransformFlagsKHR.eIdentityBitKHR)
					.setCompositeAlpha(VkCompositeAlphaFlagsKHR.eOpaqueBitKHR)
					.setPresentMode(m_DeviceParams.vsyncEnabled ? VkPresentModeKHR.eFifoKHR : VkPresentModeKHR.eImmediateKHR)
					.setClipped(true)
					.setOldSwapchain(null);

				readonly VkResult res = vkCreateSwapchainKHR(m_VulkanDevice, &desc, null, &m_SwapChain);
				if (res != VkResult.eVkSuccess)
				{
					Debug.WriteLine("Failed to create a Vulkan swap chain, error code = {}", nvrhi.vulkan.resultToString(res));
					return false;
				}

				// retrieve swap chain images
				uint32 scImageCount = 0;
				vkGetSwapchainImagesKHR(m_VulkanDevice, m_SwapChain, &scImageCount, null);
				List<VkImage> images = scope .() { Count = scImageCount };
				vkGetSwapchainImagesKHR(m_VulkanDevice, m_SwapChain, &scImageCount, images.Ptr);
				for (var image in images)
				{
					SwapChainImage sci = .();
					sci.image = image;

					nvrhi.TextureDesc textureDesc = .();
					textureDesc.width = m_DeviceParams.backBufferWidth;
					textureDesc.height = m_DeviceParams.backBufferHeight;
					textureDesc.format = m_DeviceParams.swapChainFormat;
					textureDesc.debugName = "Swap chain image";
					textureDesc.initialState = nvrhi.ResourceStates.Present;
					textureDesc.keepInitialState = true;
					textureDesc.isRenderTarget = true;

					sci.rhiHandle = m_NvrhiDevice.createHandleForNativeTexture(nvrhi.ObjectType.VK_Image, nvrhi.NativeObject(sci.image), textureDesc);
					m_SwapChainImages.Add(sci);
				}

				m_SwapChainIndex = 0;

				return true;
			}

			private void destroySwapChain()
			{
				if (m_VulkanDevice != .Null)
				{
					vkDeviceWaitIdle(m_VulkanDevice);
				}

				if (m_SwapChain != .Null)
				{
					vkDestroySwapchainKHR(m_VulkanDevice, m_SwapChain, null);
					m_SwapChain = .Null;
				}

				for (var scImage in m_SwapChainImages)
				{
					scImage.rhiHandle.Release();
				}

				m_SwapChainImages.Clear();
			}

			protected override bool CreateDeviceAndSwapChain()
			{
				if (m_DeviceParams.enableDebugRuntime)
				{
					enabledExtensions.instance.Add("VK_EXT_debug_report");
					enabledExtensions.layers.Add("VK_LAYER_KHRONOS_validation");
				}

				VulkanNative.Initialize();

				VulkanNative.LoadPreInstanceFunctions();

				CHECK!(createInstance());

				VulkanNative.LoadInstanceFunctions(m_VulkanInstance);

				VulkanNative.LoadPostInstanceFunctions();


				if (m_DeviceParams.enableDebugRuntime)
				{
					installDebugCallback();
				}

				if (m_DeviceParams.swapChainFormat == nvrhi.Format.SRGBA8_UNORM)
					m_DeviceParams.swapChainFormat = nvrhi.Format.SBGRA8_UNORM;
				else if (m_DeviceParams.swapChainFormat == nvrhi.Format.RGBA8_UNORM)
					m_DeviceParams.swapChainFormat = nvrhi.Format.BGRA8_UNORM;

				// add device extensions requested by the user
				if (m_DeviceParams.requiredVulkanDeviceExtensions != null)
				{
					for (var name in m_DeviceParams.requiredVulkanDeviceExtensions)
					{
						enabledExtensions.device.Add(name);
					}
				}
				if (m_DeviceParams.optionalVulkanDeviceExtensions != null)
				{
					for (var name in m_DeviceParams.optionalVulkanDeviceExtensions)
					{
						optionalExtensions.device.Add(name);
					}
				}

				CHECK!(createWindowSurface());
				CHECK!(pickPhysicalDevice());
				CHECK!(findQueueFamilies(m_VulkanPhysicalDevice));
				CHECK!(createDevice());

				var vecInstanceExt = StringListToCStringList(enabledExtensions.instance, .. scope .());
				//var vecLayers = StringListToCStringList(enabledExtensions.layers, .. scope .()); // nvrhi doesn't make use of this
				var vecDeviceExt = StringListToCStringList(enabledExtensions.device, .. scope .());

				nvrhi.vulkan.DeviceDesc deviceDesc = .();
				deviceDesc.errorCB = null; //DefaultMessageCallback.GetInstance(); // todo
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
				deviceDesc.instanceExtensions = vecInstanceExt.Ptr;
				deviceDesc.numInstanceExtensions = vecInstanceExt.Count;
				deviceDesc.deviceExtensions = vecDeviceExt.Ptr;
				deviceDesc.numDeviceExtensions = vecDeviceExt.Count;

				m_NvrhiDevice = nvrhi.vulkan.createDevice(deviceDesc);

				if (m_DeviceParams.enableNvrhiValidationLayer)
				{
					m_ValidationLayer = nvrhi.validation.createValidationLayer(m_NvrhiDevice);
				}

				CHECK!(createSwapChain());

				m_BarrierCommandList = m_NvrhiDevice.createCommandList();

				var semaphoreCreateInfo = VkSemaphoreCreateInfo();
				VkResult res = vkCreateSemaphore(m_VulkanDevice, &semaphoreCreateInfo, null, &m_PresentSemaphore);

				return true;
			}

			protected override void DestroyDeviceAndSwapChain()
			{
				destroySwapChain();

				vkDestroySemaphore(m_VulkanDevice, m_PresentSemaphore, null);
				m_PresentSemaphore = .Null;

				m_BarrierCommandList.Release();
				m_BarrierCommandList = null;

				m_NvrhiDevice.Release();
				m_NvrhiDevice = null;

				m_ValidationLayer?.Release();
				m_ValidationLayer = null;
				m_RendererString.Clear();

				if (m_DebugReportCallback != .Null)
				{
					vkDestroyDebugReportCallbackEXT(m_VulkanInstance, m_DebugReportCallback, null);
				}

				if (m_VulkanDevice != .Null)
				{
					vkDestroyDevice(m_VulkanDevice, null);
					m_VulkanDevice = .Null;
				}

				if (m_WindowSurface != .Null)
				{
					Runtime.Assert(m_VulkanInstance != .Null);
					vkDestroySurfaceKHR(m_VulkanInstance, m_WindowSurface, null);
					m_WindowSurface = .Null;
				}

				if (m_VulkanInstance != .Null)
				{
					vkDestroyInstance(m_VulkanInstance, null);
					m_VulkanInstance = .Null;
				}
			}
		}
	}
}