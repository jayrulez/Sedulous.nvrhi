using Bulkan;
using System;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	// underlying vulkan context
	struct VulkanContext
	{
		public this(VkInstance instance,
			VkPhysicalDevice physicalDevice,
			VkDevice device,
			VkAllocationCallbacks* allocationCallbacks = null)
		{
			instance = instance;
			physicalDevice = physicalDevice;
			device = device;
			allocationCallbacks = allocationCallbacks;
			pipelineCache = null;
		}

		public VkInstance instance;
		public VkPhysicalDevice physicalDevice;
		public VkDevice device;
		public VkAllocationCallbacks* allocationCallbacks;
		public VkPipelineCache pipelineCache;

		public struct Extensions
		{
			public bool KHR_maintenance1 = false;
			public bool EXT_debug_report = false;
			public bool EXT_debug_marker = false;
			public bool KHR_acceleration_structure = false;
			public bool KHR_buffer_device_address = false;
			public bool KHR_ray_query = false;
			public bool KHR_ray_tracing_pipeline = false;
			public bool NV_mesh_shader = false;
			public bool KHR_fragment_shading_rate = false;
		}
		public using public Extensions extensions;

		public VkPhysicalDeviceProperties physicalDeviceProperties = .();
		public VkPhysicalDeviceRayTracingPipelinePropertiesKHR rayTracingPipelineProperties = .();
		public VkPhysicalDeviceAccelerationStructurePropertiesKHR accelStructProperties = .();
		public VkPhysicalDeviceFragmentShadingRatePropertiesKHR shadingRateProperties = .();
		public VkPhysicalDeviceFragmentShadingRateFeaturesKHR shadingRateFeatures = .();
		public IMessageCallback messageCallback = null;
#if NVRHI_WITH_RTXMU
		rtxmu.VkAccelStructManager* rtxMemUtil = null;
		RtxMuResources* rtxMuResources = null;
#endif

		public void nameVKObject(void* handle, VkDebugReportObjectTypeEXT objtype, char8* name)
		{
			if (extensions.EXT_debug_marker && name != null && !String.IsNullOrEmpty(scope String(name)) && handle != null)
			{
			    var info = VkDebugMarkerObjectNameInfoEXT()
			        .setObjectType(objtype)
			        .setObject((uint64)(int)handle)
			        .setPObjectName(name);

			    vkDebugMarkerSetObjectNameEXT(device, &info);
			}
		}

		public void error(String message)
		{
        	messageCallback.message(MessageSeverity.Error, message);
		}
	}
}