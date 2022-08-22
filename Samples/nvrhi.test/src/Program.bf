using System;
using nvrhi.device_manager;
using nvrhi.vulkan.device_manager;
namespace nvrhi.test
{
	
	/*abstract class ITexture : IResource
	{
	}

	typealias TextureHandle = RefCountPtr<ITexture>;

	class VKTexture : ITexture
	{
	}*/

	class Program
	{
		public static void Main()
		{
			
			/*var texture = new VKTexture();
			var textureHandle = TextureHandle.Attach(texture);

			textureHandle.Release();*/

			DeviceManager deviceManager = new VulkanDeviceManager();

			defer delete deviceManager;

			deviceManager.[Friend]CreateDeviceAndSwapChain();

			Console.Read();
		}
	}
}