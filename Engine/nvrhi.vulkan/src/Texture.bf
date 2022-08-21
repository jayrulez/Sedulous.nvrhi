using System;
using Bulkan;
using System.Collections;
using System.Threading;
using static Bulkan.VulkanNative;
namespace nvrhi.vulkan
{
	class Texture :  MemoryResource, ITexture /*RefCounter<ITexture>*/, TextureStateExtension
	{
	    public enum TextureSubresourceViewType // see getSubresourceView()
	    {
	        AllAspects,
	        DepthOnly,
	        StencilOnly
	    }

	    public struct TextureSubresourcesViewKey 
	        : this(TextureSubresourceSet subresources, TextureSubresourceViewType viewType, TextureDimension dimension)
	        , IHashable
	    {
	        public int GetHashCode ()
	        {
	            int hash = 0;

	            hash_combine(ref hash, subresources.baseMipLevel);
	            hash_combine(ref hash, subresources.numMipLevels);
	            hash_combine(ref hash, subresources.baseArraySlice);
	            hash_combine(ref hash, subresources.numArraySlices);
	            hash_combine(ref hash, viewType);
	            hash_combine(ref hash, dimension);

	            return hash;
	        }
	    }

	    
	    public TextureDesc desc;

	    public VkImageCreateInfo imageInfo;
	    public VkImage image;

	    public HeapHandle heap;
	    
	    // contains subresource views for this texture
	    // note that we only create the views that the app uses, and that multiple views may map to the same subresources
	    public Dictionary<TextureSubresourcesViewKey, TextureSubresourceView> subresourceViews;

	    public this(VulkanContext* context, VulkanAllocator allocator)
	    {
	        m_Context = context;
	        m_Allocator = allocator;
	    }

	    // returns a subresource view for an arbitrary range of mip levels and array layers.
	    // 'viewtype' only matters when asking for a depthstencil view; in situations where only depth or stencil can be bound
	    // (such as an SRV with ImageLayout::eShaderReadOnlyOptimal), but not both, then this specifies which of the two aspect bits is to be set.
	    public ref TextureSubresourceView getSubresourceView(TextureSubresourceSet subresource, TextureDimension dimension, TextureSubresourceViewType viewtype = TextureSubresourceViewType.AllAspects)
    {
		var dimension;
        // This function is called from createBindingSet etc. and therefore free-threaded.
        // It modifies the subresourceViews map associated with the texture.
        m_Mutex.Enter(); defer m_Mutex.Exit();

        if (dimension == TextureDimension.Unknown)
            dimension = desc.dimension;

        TextureSubresourcesViewKey cachekey = .(subresource,viewtype, dimension);
        if (subresourceViews.ContainsKey(cachekey))
        {
            return ref subresourceViews[cachekey];
        }

        subresourceViews.Add(cachekey, .(this));
        var view = ref subresourceViews[cachekey];

        view.subresource = subresource;

        var vkformat = nvrhi.vulkan.convertFormat(desc.format);

        VkImageAspectFlags aspectflags = guessSubresourceImageAspectFlags(vkformat, viewtype);
        view.subresourceRange = VkImageSubresourceRange()
                                    .setAspectMask(aspectflags)
                                    .setBaseMipLevel(subresource.baseMipLevel)
                                    .setLevelCount(subresource.numMipLevels)
                                    .setBaseArrayLayer(subresource.baseArraySlice)
                                    .setLayerCount(subresource.numArraySlices);

        VkImageViewType imageViewType = textureDimensionToImageViewType(dimension);

        var viewInfo = VkImageViewCreateInfo()
                            .setImage(image)
                            .setViewType(imageViewType)
                            .setFormat(vkformat)
                            .setSubresourceRange(view.subresourceRange);

        if (viewtype == TextureSubresourceViewType.StencilOnly)
        {
            // D3D / HLSL puts stencil values in the second component to keep the illusion of combined depth/stencil.
            // Set a component swizzle so we appear to do the same.
            viewInfo.components.setG(VkComponentSwizzle.eR);
        }

        readonly VkResult res = vkCreateImageView(m_Context.device, &viewInfo, m_Context.allocationCallbacks, &view.view);
        ASSERT_VK_OK!(res);

        readonly String debugName = scope $"ImageView for: {utils.DebugNameToString(desc.debugName)}";
        m_Context.nameVKObject(VkImageView(view.view), VkDebugReportObjectTypeEXT.eImageViewExt, debugName);

        return ref view;
    }
	    
	    public uint32 getNumSubresources()
    {
        return desc.mipLevels * desc.arraySize;
    }
	    public uint32 getSubresourceIndex(uint32 mipLevel, uint32 arrayLayer)
    {
        return mipLevel * desc.arraySize + arrayLayer;
    }

	    public ~this() {
			for (var viewIter in subresourceViews)
			{
			    var view = ref viewIter.value.view;
			    vkDestroyImageView(m_Context.device, view, m_Context.allocationCallbacks);
			    view = .Null;
			}
			subresourceViews.Clear();

			if (managed)
			{
			    if (image != .Null)
			    {
			        vkDestroyImage(m_Context.device, image, m_Context.allocationCallbacks);
			        image = .Null;
			    }

			    if (memory != .Null)
			    {
			        m_Allocator.freeTextureMemory(this);
			        memory = .Null;
			    }
			}
	    }

	    public override readonly ref TextureDesc getDesc() { return ref desc; }
	    public override NativeObject getNativeObject(ObjectType objectType)
    {
        switch (objectType)
        {
        case ObjectType.VK_Image:
            return NativeObject(image);
        case ObjectType.VK_DeviceMemory:
            return NativeObject(memory);
        default:
            return null;
        }
    }
	    public override NativeObject getNativeView(ObjectType objectType, Format format, TextureSubresourceSet subresources, TextureDimension dimension, bool isReadOnlyDSV = false)
    {
		var format;
        switch (objectType)
        {
        case ObjectType.VK_ImageView: 
        {
            if (format == Format.UNKNOWN)
                format = desc.format;

            readonly ref FormatInfo formatInfo = ref getFormatInfo(format);

            TextureSubresourceViewType viewType = TextureSubresourceViewType.AllAspects;
            if (formatInfo.hasDepth && !formatInfo.hasStencil)
                viewType = TextureSubresourceViewType.DepthOnly;
            else if(!formatInfo.hasDepth && formatInfo.hasStencil)
                viewType = TextureSubresourceViewType.StencilOnly;

            return NativeObject(getSubresourceView(subresources, dimension, viewType).view);
        }
        default:
            return null;
        }
    }

	    private VulkanContext* m_Context;
	    private VulkanAllocator m_Allocator;
	    private Monitor m_Mutex = new .() ~ delete _;

		public ResourceStates permanentState {get; set;} = .Unknown;

		public bool stateInitialized {get; set;} = false;

		public bool managed{get; set;} = true;

		public ref VkDeviceMemory memory{get; set;} = .Null;

		public int GetHashCode()
		{
			return (int)(Internal.UnsafeCastToPtr(this));
		}
	}
}