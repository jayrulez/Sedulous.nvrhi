using Win32.Graphics.Direct3D11;
using nvrhi.d3dcommon;
using Win32.Foundation;
using System;
namespace nvrhi.d3d11;

class Texture : RefCounter<ITexture>
{
	public TextureDesc desc;
	public D3D11RefCountPtr<ID3D11Resource> resource;

	public this(Context* context) { m_Context = context; }
	public override readonly ref TextureDesc getDesc() { return ref desc; }
	public override NativeObject getNativeObject(ObjectType objectType)
	{
		switch (objectType)
		{
		case ObjectType.D3D11_Resource:
			return NativeObject(resource);
		default:
			return null;
		}
	}

	public override NativeObject getNativeView(ObjectType objectType, Format format, TextureSubresourceSet subresources, TextureDimension dimension, bool isReadOnlyDSV = false)
	{
		switch (objectType)
		{
		case ObjectType.D3D11_RenderTargetView:
			return getRTV(format, subresources);
		case ObjectType.D3D11_DepthStencilView:
			return getDSV(subresources, isReadOnlyDSV);
		case ObjectType.D3D11_ShaderResourceView:
			return getSRV(format, subresources, dimension);
		case ObjectType.D3D11_UnorderedAccessView:
			return getUAV(format, subresources, dimension);
		default:
			return null;
		}
	}

	public ID3D11ShaderResourceView* getSRV(Format format, TextureSubresourceSet subresources, TextureDimension dimension)
	{
		var format;
		var dimension;
		var subresources;

		if (format == Format.UNKNOWN)
		{
			format = desc.format;
		}

		if (dimension == TextureDimension.Unknown)
		{
			dimension = desc.dimension;
		}

		subresources = subresources.resolve(desc, false);

		ref D3D11RefCountPtr<ID3D11ShaderResourceView> srvPtr = ref m_ShaderResourceViews[TextureBindingKey(subresources, format)];
		if (srvPtr == null)
		{
			//we haven't seen this one before
			D3D11_SHADER_RESOURCE_VIEW_DESC viewDesc;
			viewDesc.Format = getDxgiFormatMapping(format).srvFormat;

			switch (dimension) // NOLINT(clang-diagnostic-switch-enum)
			{
			case TextureDimension.Texture1D:
				viewDesc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURE1D;
				viewDesc.Texture1D.MostDetailedMip = subresources.baseMipLevel;
				viewDesc.Texture1D.MipLevels = subresources.numMipLevels;
				break;
			case TextureDimension.Texture1DArray:
				viewDesc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURE1DARRAY;
				viewDesc.Texture1DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture1DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture1DArray.MostDetailedMip = subresources.baseMipLevel;
				viewDesc.Texture1DArray.MipLevels = subresources.numMipLevels;
				break;
			case TextureDimension.Texture2D:
				viewDesc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURE2D;
				viewDesc.Texture2D.MostDetailedMip = subresources.baseMipLevel;
				viewDesc.Texture2D.MipLevels = subresources.numMipLevels;
				break;
			case TextureDimension.Texture2DArray:
				viewDesc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURE2DARRAY;
				viewDesc.Texture2DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture2DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture2DArray.MostDetailedMip = subresources.baseMipLevel;
				viewDesc.Texture2DArray.MipLevels = subresources.numMipLevels;
				break;
			case TextureDimension.TextureCube:
				viewDesc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURECUBE;
				viewDesc.TextureCube.MostDetailedMip = subresources.baseMipLevel;
				viewDesc.TextureCube.MipLevels = subresources.numMipLevels;
				break;
			case TextureDimension.TextureCubeArray:
				viewDesc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURECUBEARRAY;
				viewDesc.TextureCubeArray.First2DArrayFace = subresources.baseArraySlice;
				viewDesc.TextureCubeArray.NumCubes = subresources.numArraySlices / 6;
				viewDesc.TextureCubeArray.MostDetailedMip = subresources.baseMipLevel;
				viewDesc.TextureCubeArray.MipLevels = subresources.numMipLevels;
				break;
			case TextureDimension.Texture2DMS:
				viewDesc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURE2DMS;
				break;
			case TextureDimension.Texture2DMSArray:
				viewDesc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURE2DMSARRAY;
				viewDesc.Texture2DMSArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture2DMSArray.ArraySize = subresources.numArraySlices;
				break;
			case TextureDimension.Texture3D:
				viewDesc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURE3D;
				viewDesc.Texture3D.MostDetailedMip = subresources.baseMipLevel;
				viewDesc.Texture3D.MipLevels = subresources.numMipLevels;
				break;
			default:
				{
					String message = scope $"Texture {nvrhi.utils.DebugNameToString(desc.debugName)} has unsupported dimension for SRV: {nvrhi.utils.TextureDimensionToString(desc.dimension)}";
					m_Context.error(message);
					return null;
				}
			}

			readonly HRESULT res = m_Context.device.CreateShaderResourceView(resource, &viewDesc, &srvPtr);
			if (FAILED(res))
			{
				String message = scope $"CreateShaderResourceView call failed for texture {nvrhi.utils.DebugNameToString(desc.debugName)}, HRESULT = 0x{res}";
				m_Context.error(message);
			}
		}
		return srvPtr;
	}

	public ID3D11RenderTargetView* getRTV(Format format, TextureSubresourceSet subresources)
	{
		var format;
		var subresources;

		if (format == Format.UNKNOWN)
		{
			format = desc.format;
		}

		subresources = subresources.resolve(desc, true);

		ref D3D11RefCountPtr<ID3D11RenderTargetView> rtvPtr = ref m_RenderTargetViews[TextureBindingKey(subresources, format)];
		if (rtvPtr == null)
		{
			//we haven't seen this one before
			D3D11_RENDER_TARGET_VIEW_DESC viewDesc;
			viewDesc.Format = getDxgiFormatMapping(format).rtvFormat;

			switch (desc.dimension) // NOLINT(clang-diagnostic-switch-enum)
			{
			case TextureDimension.Texture1D:
				viewDesc.ViewDimension = .D3D11_RTV_DIMENSION_TEXTURE1D;
				viewDesc.Texture1D.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture1DArray:
				viewDesc.ViewDimension = .D3D11_RTV_DIMENSION_TEXTURE1DARRAY;
				viewDesc.Texture1DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture1DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture1DArray.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2D:
				viewDesc.ViewDimension = .D3D11_RTV_DIMENSION_TEXTURE2D;
				viewDesc.Texture2D.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2DArray: fallthrough;
			case TextureDimension.TextureCube: fallthrough;
			case TextureDimension.TextureCubeArray:
				viewDesc.ViewDimension = .D3D11_RTV_DIMENSION_TEXTURE2DARRAY;
				viewDesc.Texture2DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture2DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture2DArray.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2DMS:
				viewDesc.ViewDimension = .D3D11_RTV_DIMENSION_TEXTURE2DMS;
				break;
			case TextureDimension.Texture2DMSArray:
				viewDesc.ViewDimension = .D3D11_RTV_DIMENSION_TEXTURE2DMSARRAY;
				viewDesc.Texture2DMSArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture2DMSArray.ArraySize = subresources.numArraySlices;
				break;
			case TextureDimension.Texture3D:
				viewDesc.ViewDimension = .D3D11_RTV_DIMENSION_TEXTURE3D;
				viewDesc.Texture3D.FirstWSlice = subresources.baseArraySlice;
				viewDesc.Texture3D.WSize = subresources.numArraySlices;
				viewDesc.Texture3D.MipSlice = subresources.baseMipLevel;
				break;
			default:
				{
					String message = scope $"Texture {nvrhi.utils.DebugNameToString(desc.debugName)} has unsupported dimension for RTV: {nvrhi.utils.TextureDimensionToString(desc.dimension)}";
					m_Context.error(message);
					return null;
				}
			}

			readonly HRESULT res = m_Context.device.CreateRenderTargetView(resource, &viewDesc, &rtvPtr);
			if (FAILED(res))
			{
				String message = scope $"CreateRenderTargetView call failed for texture {nvrhi.utils.DebugNameToString(desc.debugName)}, HRESULT = 0x{res}";
				m_Context.error(message);
			}
		}
		return rtvPtr;
	}

	public ID3D11DepthStencilView* getDSV(TextureSubresourceSet subresources, bool isReadOnly = false)
	{
		var subresources;

		subresources = subresources.resolve(desc, true);


		ref D3D11RefCountPtr<ID3D11DepthStencilView> dsvPtr = ref m_DepthStencilViews[TextureBindingKey(subresources, desc.format, isReadOnly)];
		if (dsvPtr == null)
		{
			//we haven't seen this one before
			D3D11_DEPTH_STENCIL_VIEW_DESC viewDesc;
			viewDesc.Format = getDxgiFormatMapping(desc.format).rtvFormat;
			viewDesc.Flags = 0;

			if (isReadOnly)
			{
				viewDesc.Flags |= (.)D3D11_DSV_FLAG.D3D11_DSV_READ_ONLY_DEPTH;
				if (viewDesc.Format == .DXGI_FORMAT_D24_UNORM_S8_UINT || viewDesc.Format == .DXGI_FORMAT_D32_FLOAT_S8X24_UINT)
					viewDesc.Flags |= (.)D3D11_DSV_FLAG.D3D11_DSV_READ_ONLY_STENCIL;
			}

			switch (desc.dimension) // NOLINT(clang-diagnostic-switch-enum)
			{
			case TextureDimension.Texture1D:
				viewDesc.ViewDimension = D3D11_DSV_DIMENSION.D3D11_DSV_DIMENSION_TEXTURE1D;
				viewDesc.Texture1D.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture1DArray:
				viewDesc.ViewDimension = .D3D11_DSV_DIMENSION_TEXTURE1DARRAY;
				viewDesc.Texture1DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture1DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture1DArray.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2D:
				viewDesc.ViewDimension = .D3D11_DSV_DIMENSION_TEXTURE2D;
				viewDesc.Texture2D.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2DArray: fallthrough;
			case TextureDimension.TextureCube: fallthrough;
			case TextureDimension.TextureCubeArray:
				viewDesc.ViewDimension = .D3D11_DSV_DIMENSION_TEXTURE2DARRAY;
				viewDesc.Texture2DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture2DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture2DArray.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2DMS:
				viewDesc.ViewDimension = .D3D11_DSV_DIMENSION_TEXTURE2DMS;
				break;
			case TextureDimension.Texture2DMSArray:
				viewDesc.ViewDimension = .D3D11_DSV_DIMENSION_TEXTURE2DMSARRAY;
				viewDesc.Texture2DMSArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture2DMSArray.ArraySize = subresources.numArraySlices;
				break;
			default:
				{
					String message = scope $"Texture {nvrhi.utils.DebugNameToString(desc.debugName)} has unsupported dimension for DSV: {nvrhi.utils.TextureDimensionToString(desc.dimension)}";
					m_Context.error(message);
					return null;
				}
			}

			readonly HRESULT res = m_Context.device.CreateDepthStencilView(resource, &viewDesc, &dsvPtr);
			if (FAILED(res))
			{
				String message = scope $"CreateDepthStencilView call failed for texture {nvrhi.utils.DebugNameToString(desc.debugName)}, HRESULT = 0x{res}";
				m_Context.error(message);
			}
		}
		return dsvPtr;
	}

	public ID3D11UnorderedAccessView* getUAV(Format format, TextureSubresourceSet subresources, TextureDimension dimension)
	{
		var format;
		var dimension;
		var subresources;

		if (format == Format.UNKNOWN)
		{
			format = desc.format;
		}

		if (dimension == TextureDimension.Unknown)
		{
			dimension = desc.dimension;
		}

		subresources = subresources.resolve(desc, true);

		ref D3D11RefCountPtr<ID3D11UnorderedAccessView> uavPtr = ref m_UnorderedAccessViews[TextureBindingKey(subresources, format)];
		if (uavPtr == null)
		{
			D3D11_UNORDERED_ACCESS_VIEW_DESC viewDesc;
			viewDesc.Format = getDxgiFormatMapping(format).srvFormat;

			switch (dimension) // NOLINT(clang-diagnostic-switch-enum)
			{
			case TextureDimension.Texture1D:
				viewDesc.ViewDimension = .D3D11_UAV_DIMENSION_TEXTURE1D;
				viewDesc.Texture1D.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture1DArray:
				viewDesc.ViewDimension = .D3D11_UAV_DIMENSION_TEXTURE1DARRAY;
				viewDesc.Texture1DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture1DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture1DArray.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2D:
				viewDesc.ViewDimension = .D3D11_UAV_DIMENSION_TEXTURE2D;
				viewDesc.Texture2D.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2DArray: fallthrough;
			case TextureDimension.TextureCube: fallthrough;
			case TextureDimension.TextureCubeArray:
				viewDesc.ViewDimension = .D3D11_UAV_DIMENSION_TEXTURE2DARRAY;
				viewDesc.Texture2DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture2DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture2DArray.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture3D:
				viewDesc.ViewDimension = .D3D11_UAV_DIMENSION_TEXTURE3D;
				viewDesc.Texture3D.FirstWSlice = 0;
				viewDesc.Texture3D.WSize = desc.depth;
				viewDesc.Texture3D.MipSlice = subresources.baseMipLevel;
				break;
			default:
				{
					String message = scope $"Texture {nvrhi.utils.DebugNameToString(desc.debugName)} has unsupported dimension for UAV: {nvrhi.utils.TextureDimensionToString(desc.dimension)}";
					m_Context.error(message);
					return null;
				}
			}

			readonly HRESULT res = m_Context.device.CreateUnorderedAccessView(resource, &viewDesc, &uavPtr);
			if (FAILED(res))
			{
				String message = scope $"CreateUnorderedAccessView call failed for texture {nvrhi.utils.DebugNameToString(desc.debugName)}, HRESULT = 0x{res}";
				m_Context.error(message);
			}
		}
		return uavPtr;
	}

	private Context* m_Context;
	private TextureBindingKey_HashMap<D3D11RefCountPtr<ID3D11ShaderResourceView>> m_ShaderResourceViews;
	private TextureBindingKey_HashMap<D3D11RefCountPtr<ID3D11RenderTargetView>> m_RenderTargetViews;
	private TextureBindingKey_HashMap<D3D11RefCountPtr<ID3D11DepthStencilView>> m_DepthStencilViews;
	private TextureBindingKey_HashMap<D3D11RefCountPtr<ID3D11UnorderedAccessView>> m_UnorderedAccessViews;
}