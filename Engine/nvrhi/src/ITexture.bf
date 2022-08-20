using System;
namespace nvrhi
{
	abstract class ITexture :  IResource
	{
		[NoDiscard] public abstract readonly ref TextureDesc getDesc();

		// Similar to getNativeObject, returns a native view for a specified set of subresources. Returns null if unavailable.
		// TODO: on D3D12, the views might become invalid later if the view heap is grown/reallocated, we should do something about that.
		public abstract NativeObject getNativeView(ObjectType objectType,
			Format format = Format.UNKNOWN,
			TextureSubresourceSet subresources = AllSubresources,
			TextureDimension dimension = TextureDimension.Unknown,
			bool isReadOnlyDSV = false);
	}
	typealias TextureHandle = RefCountPtr<ITexture>;
}