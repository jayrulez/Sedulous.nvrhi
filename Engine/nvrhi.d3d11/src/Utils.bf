using nvrhi.d3dcommon;
using Win32.Graphics.Dxgi.Common;
using Win32.Graphics.Direct3D11;
using Win32.Graphics.Direct3D;
using System;
namespace nvrhi.d3d11;

public static
{
	public static UINT D3D11CalcSubresource(UINT MipSlice, UINT ArraySlice, UINT MipLevels)
		{ return MipSlice + ArraySlice * MipLevels; }

	public static void SetDebugName(ID3D11DeviceChild* pObject, char8* name)
	{
		var nameStr = scope String(name);
		(pObject).SetPrivateData(WKPDID_D3DDebugObjectName, (.)nameStr.Length, nameStr.ToScopedNativeWChar!());
	}

	public static DXGI_FORMAT convertFormat(nvrhi.Format format)
	{
		return getDxgiFormatMapping(format).srvFormat;
	}

	public static D3D11_BLEND convertBlendValue(BlendFactor value)
	{
		switch (value)
		{
		case BlendFactor.Zero:
			return .D3D11_BLEND_ZERO;
		case BlendFactor.One:
			return .D3D11_BLEND_ONE;
		case BlendFactor.SrcColor:
			return .D3D11_BLEND_SRC_COLOR;
		case BlendFactor.InvSrcColor:
			return .D3D11_BLEND_INV_SRC_COLOR;
		case BlendFactor.SrcAlpha:
			return .D3D11_BLEND_SRC_ALPHA;
		case BlendFactor.InvSrcAlpha:
			return .D3D11_BLEND_INV_SRC_ALPHA;
		case BlendFactor.DstAlpha:
			return .D3D11_BLEND_DEST_ALPHA;
		case BlendFactor.InvDstAlpha:
			return .D3D11_BLEND_INV_DEST_ALPHA;
		case BlendFactor.DstColor:
			return .D3D11_BLEND_DEST_COLOR;
		case BlendFactor.InvDstColor:
			return .D3D11_BLEND_INV_DEST_COLOR;
		case BlendFactor.SrcAlphaSaturate:
			return .D3D11_BLEND_SRC_ALPHA_SAT;
		case BlendFactor.ConstantColor:
			return .D3D11_BLEND_BLEND_FACTOR;
		case BlendFactor.InvConstantColor:
			return .D3D11_BLEND_INV_BLEND_FACTOR;
		case BlendFactor.Src1Color:
			return .D3D11_BLEND_SRC1_COLOR;
		case BlendFactor.InvSrc1Color:
			return .D3D11_BLEND_INV_SRC1_COLOR;
		case BlendFactor.Src1Alpha:
			return .D3D11_BLEND_SRC1_ALPHA;
		case BlendFactor.InvSrc1Alpha:
			return .D3D11_BLEND_INV_SRC1_ALPHA;
		default:
			nvrhi.utils.InvalidEnum();
			return .D3D11_BLEND_ZERO;
		}
	}

	public static D3D11_BLEND_OP convertBlendOp(BlendOp value)
	{
		switch (value)
		{
		case BlendOp.Add:
			return .D3D11_BLEND_OP_ADD;
		case BlendOp.Subrtact:
			return .D3D11_BLEND_OP_SUBTRACT;
		case BlendOp.ReverseSubtract:
			return .D3D11_BLEND_OP_REV_SUBTRACT;
		case BlendOp.Min:
			return .D3D11_BLEND_OP_MIN;
		case BlendOp.Max:
			return .D3D11_BLEND_OP_MAX;
		default:
			nvrhi.utils.InvalidEnum();
			return .D3D11_BLEND_OP_ADD;
		}
	}

	public static D3D11_STENCIL_OP convertStencilOp(StencilOp value)
	{
		switch (value)
		{
		case StencilOp.Keep:
			return .D3D11_STENCIL_OP_KEEP;
		case StencilOp.Zero:
			return .D3D11_STENCIL_OP_ZERO;
		case StencilOp.Replace:
			return .D3D11_STENCIL_OP_REPLACE;
		case StencilOp.IncrementAndClamp:
			return .D3D11_STENCIL_OP_INCR_SAT;
		case StencilOp.DecrementAndClamp:
			return .D3D11_STENCIL_OP_DECR_SAT;
		case StencilOp.Invert:
			return .D3D11_STENCIL_OP_INVERT;
		case StencilOp.IncrementAndWrap:
			return .D3D11_STENCIL_OP_INCR;
		case StencilOp.DecrementAndWrap:
			return .D3D11_STENCIL_OP_DECR;
		default:
			nvrhi.utils.InvalidEnum();
			return .D3D11_STENCIL_OP_KEEP;
		}
	}

	public static D3D11_COMPARISON_FUNC convertComparisonFunc(ComparisonFunc value)
	{
		switch (value)
		{
		case ComparisonFunc.Never:
			return .D3D11_COMPARISON_NEVER;
		case ComparisonFunc.Less:
			return .D3D11_COMPARISON_LESS;
		case ComparisonFunc.Equal:
			return .D3D11_COMPARISON_EQUAL;
		case ComparisonFunc.LessOrEqual:
			return .D3D11_COMPARISON_LESS_EQUAL;
		case ComparisonFunc.Greater:
			return .D3D11_COMPARISON_GREATER;
		case ComparisonFunc.NotEqual:
			return .D3D11_COMPARISON_NOT_EQUAL;
		case ComparisonFunc.GreaterOrEqual:
			return .D3D11_COMPARISON_GREATER_EQUAL;
		case ComparisonFunc.Always:
			return .D3D11_COMPARISON_ALWAYS;
		default:
			nvrhi.utils.InvalidEnum();
			return .D3D11_COMPARISON_NEVER;
		}
	}

	public static D3D_PRIMITIVE_TOPOLOGY convertPrimType(PrimitiveType pt, uint32 controlPoints)
	{
		//setup the primitive type
		switch (pt)
		{
		case PrimitiveType.PointList:
			return .D3D_PRIMITIVE_TOPOLOGY_POINTLIST;
		case PrimitiveType.LineList:
			return .D3D11_PRIMITIVE_TOPOLOGY_LINELIST;
		case PrimitiveType.TriangleList:
			return .D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST;
		case PrimitiveType.TriangleStrip:
			return .D3D_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP;
		case PrimitiveType.TriangleFan:
			nvrhi.utils.NotSupported();
			return .D3D_PRIMITIVE_TOPOLOGY_UNDEFINED;
		case PrimitiveType.TriangleListWithAdjacency:
			return .D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST_ADJ;
		case PrimitiveType.TriangleStripWithAdjacency:
			return .D3D_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP_ADJ;
		case PrimitiveType.PatchList:
			if (controlPoints == 0 || controlPoints > 32)
			{
				nvrhi.utils.InvalidEnum();
				return .D3D_PRIMITIVE_TOPOLOGY_UNDEFINED;
			}
			return (D3D_PRIMITIVE_TOPOLOGY)D3D_PRIMITIVE_TOPOLOGY.D3D_PRIMITIVE_TOPOLOGY_1_CONTROL_POINT_PATCHLIST + (controlPoints - 1);
		default:
			nvrhi.utils.InvalidEnum();
			return .D3D_PRIMITIVE_TOPOLOGY_UNDEFINED;
		}
	}

	public static D3D11_TEXTURE_ADDRESS_MODE convertSamplerAddressMode(SamplerAddressMode mode)
	{
		switch (mode)
		{
		case SamplerAddressMode.Clamp:
			return .D3D11_TEXTURE_ADDRESS_CLAMP;
		case SamplerAddressMode.Wrap:
			return .D3D11_TEXTURE_ADDRESS_WRAP;
		case SamplerAddressMode.Border:
			return .D3D11_TEXTURE_ADDRESS_BORDER;
		case SamplerAddressMode.Mirror:
			return .D3D11_TEXTURE_ADDRESS_MIRROR;
		case SamplerAddressMode.MirrorOnce:
			return .D3D11_TEXTURE_ADDRESS_MIRROR_ONCE;
		default:
			nvrhi.utils.InvalidEnum();
			return .D3D11_TEXTURE_ADDRESS_CLAMP;
		}
	}

	public static UINT convertSamplerReductionType(SamplerReductionType reductionType)
	{
		switch (reductionType)
		{
		case SamplerReductionType.Standard:
			return (.)D3D11_FILTER_REDUCTION_TYPE.D3D11_FILTER_REDUCTION_TYPE_STANDARD;
		case SamplerReductionType.Comparison:
			return (.)D3D11_FILTER_REDUCTION_TYPE.D3D11_FILTER_REDUCTION_TYPE_COMPARISON;
		case SamplerReductionType.Minimum:
			return (.)D3D11_FILTER_REDUCTION_TYPE.D3D11_FILTER_REDUCTION_TYPE_MINIMUM;
		case SamplerReductionType.Maximum:
			return (.)D3D11_FILTER_REDUCTION_TYPE.D3D11_FILTER_REDUCTION_TYPE_MAXIMUM;
		default:
			nvrhi.utils.InvalidEnum();
			return (.)D3D11_FILTER_REDUCTION_TYPE.D3D11_FILTER_REDUCTION_TYPE_STANDARD;
		}
	}

	public static DX11_ViewportState convertViewportState(ViewportState vpState)
	{
		DX11_ViewportState ret = .();

		ret.numViewports = UINT(vpState.viewports.Count);
		for (int rt = 0; rt < vpState.viewports.Count; rt++)
		{
			ret.viewports[rt].TopLeftX = vpState.viewports[rt].minX;
			ret.viewports[rt].TopLeftY = vpState.viewports[rt].minY;
			ret.viewports[rt].Width = vpState.viewports[rt].maxX - vpState.viewports[rt].minX;
			ret.viewports[rt].Height = vpState.viewports[rt].maxY - vpState.viewports[rt].minY;
			ret.viewports[rt].MinDepth = vpState.viewports[rt].minZ;
			ret.viewports[rt].MaxDepth = vpState.viewports[rt].maxZ;
		}

		ret.numScissorRects = UINT(vpState.scissorRects.Count);
		for (int rt = 0; rt < vpState.scissorRects.Count; rt++)
		{
			ret.scissorRects[rt].left = (.)vpState.scissorRects[rt].minX;
			ret.scissorRects[rt].top = (.)vpState.scissorRects[rt].minY;
			ret.scissorRects[rt].right = (.)vpState.scissorRects[rt].maxX;
			ret.scissorRects[rt].bottom = (.)vpState.scissorRects[rt].maxY;
		}

		return ret;
	}

	public static DeviceHandle createDevice(D3D11DeviceDesc desc)
	{
		DeviceD3D11 device = new DeviceD3D11(desc);
		return DeviceHandle.Attach(device);
	}
}

public static
{
	public const uint32 D3D11_FILTER_REDUCTION_TYPE_MASK = 0x3;
	public const uint32 D3D11_FILTER_REDUCTION_TYPE_SHIFT = 7;
	public const uint32 D3D11_FILTER_TYPE_MASK = 0x3;
	public const uint32 D3D11_MIN_FILTER_SHIFT = 4;
	public const uint32 D3D11_MAG_FILTER_SHIFT = 2;
	public const uint32 D3D11_MIP_FILTER_SHIFT = 0;

	public const uint32 D3D11_COMPARISON_FILTERING_BIT	= 0x80;

	public const uint32 D3D11_ANISOTROPIC_FILTERING_BIT	= 0x40;

	public static D3D11_FILTER D3D11_ENCODE_BASIC_FILTER(D3D11_FILTER_TYPE min, D3D11_FILTER_TYPE mag, D3D11_FILTER_TYPE mip, uint32 reduction)
	{
		return ((D3D11_FILTER)(
			((((uint32)min) & D3D11_FILTER_TYPE_MASK) << D3D11_MIN_FILTER_SHIFT) |
			((((uint32)mag) & D3D11_FILTER_TYPE_MASK) << D3D11_MAG_FILTER_SHIFT) |
			((((uint32)mip) & D3D11_FILTER_TYPE_MASK) << D3D11_MIP_FILTER_SHIFT) |
			(((reduction) & D3D11_FILTER_REDUCTION_TYPE_MASK) << D3D11_FILTER_REDUCTION_TYPE_SHIFT)));
	}

	public static D3D11_FILTER D3D11_ENCODE_ANISOTROPIC_FILTER(uint32 reduction)
	{
		return ((D3D11_FILTER)(
			(.)D3D11_ANISOTROPIC_FILTERING_BIT |
			D3D11_ENCODE_BASIC_FILTER(.D3D11_FILTER_TYPE_LINEAR, .D3D11_FILTER_TYPE_LINEAR, .D3D11_FILTER_TYPE_LINEAR, reduction)));
	}
}