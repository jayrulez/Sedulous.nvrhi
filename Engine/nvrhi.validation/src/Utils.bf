namespace nvrhi.validation
{
	public static
	{
		public static DeviceHandle createValidationLayer(IDevice underlyingDevice){
			DeviceWrapper wrapper = new DeviceWrapper(underlyingDevice);
			return DeviceHandle.Attach(wrapper);
		}

		public static bool textureDimensionsCompatible(TextureDimension resourceDimension, TextureDimension viewDimension)
		{
		    if (resourceDimension == viewDimension)
		        return true;

		    if (resourceDimension == TextureDimension.Texture3D)
		        return viewDimension == TextureDimension.Texture2DArray;

		    if (resourceDimension == TextureDimension.TextureCube || resourceDimension == TextureDimension.TextureCubeArray)
		        return viewDimension == TextureDimension.Texture2DArray;

		    return false;
		}
	}
}