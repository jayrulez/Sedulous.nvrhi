using Win32.Graphics.Dxgi;
using nvrhi.d3dcommon;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Direct3D;
using Win32.Foundation;
using Win32.System.WindowsProgramming;
using Win32.System.Threading;
namespace nvrhi.d3d12
{
	public static
	{
		public static bool FAILED(HRESULT res)
		{
			return res != S_OK;
		}

		/*nvrhi.DeviceHandle createDevice(DeviceDesc desc)
		{
			nvrhi.d3d12.Device device = new .(desc);
			return nvrhi.DeviceHandle.Attach(device);
		}*/

		public static DXGI_FORMAT convertFormat(nvrhi.Format format)
		{
			return getDxgiFormatMapping(format).srvFormat;
		}

		public static D3D12_SHADER_VISIBILITY convertShaderStage(ShaderType s)
		{
			switch (s) // NOLINT(clang-diagnostic-switch-enum)
			{
			case ShaderType.Vertex:
				return D3D12_SHADER_VISIBILITY.VERTEX;
			case ShaderType.Hull:
				return D3D12_SHADER_VISIBILITY.HULL;
			case ShaderType.Domain:
				return D3D12_SHADER_VISIBILITY.DOMAIN;
			case ShaderType.Geometry:
				return D3D12_SHADER_VISIBILITY.GEOMETRY;
			case ShaderType.Pixel:
				return D3D12_SHADER_VISIBILITY.PIXEL;
			case ShaderType.Amplification:
				return D3D12_SHADER_VISIBILITY.AMPLIFICATION;
			case ShaderType.Mesh:
				return D3D12_SHADER_VISIBILITY.MESH;

			default:
				// catch-all case - actually some of the bitfield combinations are unrepresentable in DX12
				return D3D12_SHADER_VISIBILITY.ALL;
			}
		}

		public static D3D12_BLEND convertBlendValue(BlendFactor value)
		{
			switch (value)
			{
			case BlendFactor.Zero:
				return D3D12_BLEND.ZERO;
			case BlendFactor.One:
				return D3D12_BLEND.ONE;
			case BlendFactor.SrcColor:
				return D3D12_BLEND.SRC_COLOR;
			case BlendFactor.InvSrcColor:
				return D3D12_BLEND.INV_SRC_COLOR;
			case BlendFactor.SrcAlpha:
				return D3D12_BLEND.SRC_ALPHA;
			case BlendFactor.InvSrcAlpha:
				return D3D12_BLEND.INV_SRC_ALPHA;
			case BlendFactor.DstAlpha:
				return D3D12_BLEND.DEST_ALPHA;
			case BlendFactor.InvDstAlpha:
				return D3D12_BLEND.INV_DEST_ALPHA;
			case BlendFactor.DstColor:
				return D3D12_BLEND.DEST_COLOR;
			case BlendFactor.InvDstColor:
				return D3D12_BLEND.INV_DEST_COLOR;
			case BlendFactor.SrcAlphaSaturate:
				return D3D12_BLEND.SRC_ALPHA_SAT;
			case BlendFactor.ConstantColor:
				return D3D12_BLEND.BLEND_FACTOR;
			case BlendFactor.InvConstantColor:
				return D3D12_BLEND.INV_BLEND_FACTOR;
			case BlendFactor.Src1Color:
				return D3D12_BLEND.SRC1_COLOR;
			case BlendFactor.InvSrc1Color:
				return D3D12_BLEND.INV_SRC1_COLOR;
			case BlendFactor.Src1Alpha:
				return D3D12_BLEND.SRC1_ALPHA;
			case BlendFactor.InvSrc1Alpha:
				return D3D12_BLEND.INV_SRC1_ALPHA;
			default:
				utils.InvalidEnum();
				return D3D12_BLEND.ZERO;
			}
		}

		public static D3D12_BLEND_OP convertBlendOp(BlendOp value)
		{
			switch (value)
			{
			case BlendOp.Add:
				return D3D12_BLEND_OP.ADD;
			case BlendOp.Subrtact:
				return D3D12_BLEND_OP.SUBTRACT;
			case BlendOp.ReverseSubtract:
				return D3D12_BLEND_OP.REV_SUBTRACT;
			case BlendOp.Min:
				return D3D12_BLEND_OP.MIN;
			case BlendOp.Max:
				return D3D12_BLEND_OP.MAX;
			default:
				utils.InvalidEnum();
				return D3D12_BLEND_OP.ADD;
			}
		}

		public static D3D12_STENCIL_OP convertStencilOp(StencilOp value)
		{
			switch (value)
			{
			case StencilOp.Keep:
				return D3D12_STENCIL_OP.KEEP;
			case StencilOp.Zero:
				return D3D12_STENCIL_OP.ZERO;
			case StencilOp.Replace:
				return D3D12_STENCIL_OP.REPLACE;
			case StencilOp.IncrementAndClamp:
				return D3D12_STENCIL_OP.INCR_SAT;
			case StencilOp.DecrementAndClamp:
				return D3D12_STENCIL_OP.DECR_SAT;
			case StencilOp.Invert:
				return D3D12_STENCIL_OP.INVERT;
			case StencilOp.IncrementAndWrap:
				return D3D12_STENCIL_OP.INCR;
			case StencilOp.DecrementAndWrap:
				return D3D12_STENCIL_OP.DECR;
			default:
				utils.InvalidEnum();
				return D3D12_STENCIL_OP.KEEP;
			}
		}

		public static D3D12_COMPARISON_FUNC convertComparisonFunc(ComparisonFunc value)
		{
			switch (value)
			{
			case ComparisonFunc.Never:
				return D3D12_COMPARISON_FUNC.NEVER;
			case ComparisonFunc.Less:
				return D3D12_COMPARISON_FUNC.LESS;
			case ComparisonFunc.Equal:
				return D3D12_COMPARISON_FUNC.EQUAL;
			case ComparisonFunc.LessOrEqual:
				return D3D12_COMPARISON_FUNC.LESS_EQUAL;
			case ComparisonFunc.Greater:
				return D3D12_COMPARISON_FUNC.GREATER;
			case ComparisonFunc.NotEqual:
				return D3D12_COMPARISON_FUNC.NOT_EQUAL;
			case ComparisonFunc.GreaterOrEqual:
				return D3D12_COMPARISON_FUNC.GREATER_EQUAL;
			case ComparisonFunc.Always:
				return D3D12_COMPARISON_FUNC.ALWAYS;
			default:
				utils.InvalidEnum();
				return D3D12_COMPARISON_FUNC.NEVER;
			}
		}
		public static D3D_PRIMITIVE_TOPOLOGY convertPrimitiveType(PrimitiveType pt, uint32 controlPoints)
		{
			switch (pt)
			{
			case PrimitiveType.PointList:
				return D3D_PRIMITIVE_TOPOLOGY.D3D_PRIMITIVE_TOPOLOGY_POINTLIST;
			case PrimitiveType.LineList:
				return D3D_PRIMITIVE_TOPOLOGY.D3D_PRIMITIVE_TOPOLOGY_LINELIST;
			case PrimitiveType.TriangleList:
				return D3D_PRIMITIVE_TOPOLOGY.D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST;
			case PrimitiveType.TriangleStrip:
				return D3D_PRIMITIVE_TOPOLOGY.D3D_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP;
			case PrimitiveType.TriangleFan:
				utils.NotSupported();
				return D3D_PRIMITIVE_TOPOLOGY.D3D_PRIMITIVE_TOPOLOGY_UNDEFINED;
			case PrimitiveType.TriangleListWithAdjacency:
				return D3D_PRIMITIVE_TOPOLOGY.D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST_ADJ;
			case PrimitiveType.TriangleStripWithAdjacency:
				return D3D_PRIMITIVE_TOPOLOGY.D3D_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP_ADJ;
			case PrimitiveType.PatchList:
				if (controlPoints == 0 || controlPoints > 32)
				{
					utils.InvalidEnum();
					return D3D_PRIMITIVE_TOPOLOGY.D3D_PRIMITIVE_TOPOLOGY_UNDEFINED;
				}
				return (D3D_PRIMITIVE_TOPOLOGY)D3D_PRIMITIVE_TOPOLOGY.D3D_PRIMITIVE_TOPOLOGY_1_CONTROL_POINT_PATCHLIST + (controlPoints - 1);
			default:
				return D3D_PRIMITIVE_TOPOLOGY.D3D_PRIMITIVE_TOPOLOGY_UNDEFINED;
			}
		}

		public static D3D12_TEXTURE_ADDRESS_MODE convertSamplerAddressMode(SamplerAddressMode mode)
		{
			switch (mode)
			{
			case SamplerAddressMode.Clamp:
				return D3D12_TEXTURE_ADDRESS_MODE.CLAMP;
			case SamplerAddressMode.Wrap:
				return D3D12_TEXTURE_ADDRESS_MODE.WRAP;
			case SamplerAddressMode.Border:
				return D3D12_TEXTURE_ADDRESS_MODE.BORDER;
			case SamplerAddressMode.Mirror:
				return D3D12_TEXTURE_ADDRESS_MODE.MIRROR;
			case SamplerAddressMode.MirrorOnce:
				return D3D12_TEXTURE_ADDRESS_MODE.MIRROR_ONCE;
			default:
				utils.InvalidEnum();
				return D3D12_TEXTURE_ADDRESS_MODE.CLAMP;
			}
		}

		public static /*UINT*/ D3D12_FILTER_REDUCTION_TYPE convertSamplerReductionType(SamplerReductionType reductionType)
		{
			switch (reductionType)
			{
			case SamplerReductionType.Standard:
				return D3D12_FILTER_REDUCTION_TYPE.STANDARD;
			case SamplerReductionType.Comparison:
				return D3D12_FILTER_REDUCTION_TYPE.COMPARISON;
			case SamplerReductionType.Minimum:
				return D3D12_FILTER_REDUCTION_TYPE.MINIMUM;
			case SamplerReductionType.Maximum:
				return D3D12_FILTER_REDUCTION_TYPE.MAXIMUM;
			default:
				utils.InvalidEnum();
				return D3D12_FILTER_REDUCTION_TYPE.STANDARD;
			}
		}

		public static D3D12_RESOURCE_STATES convertResourceStates(ResourceStates stateBits)
		{
			if (stateBits == ResourceStates.Common)
				return D3D12_RESOURCE_STATES.COMMON;

			D3D12_RESOURCE_STATES result = D3D12_RESOURCE_STATES.COMMON; // also 0

			if ((stateBits & ResourceStates.ConstantBuffer) != 0) result |= D3D12_RESOURCE_STATES.VERTEX_AND_CONSTANT_BUFFER;
			if ((stateBits & ResourceStates.VertexBuffer) != 0) result |= D3D12_RESOURCE_STATES.VERTEX_AND_CONSTANT_BUFFER;
			if ((stateBits & ResourceStates.IndexBuffer) != 0) result |= D3D12_RESOURCE_STATES.INDEX_BUFFER;
			if ((stateBits & ResourceStates.IndirectArgument) != 0) result |= D3D12_RESOURCE_STATES.INDIRECT_ARGUMENT;
			if ((stateBits & ResourceStates.ShaderResource) != 0) result |= D3D12_RESOURCE_STATES.PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATES.NON_PIXEL_SHADER_RESOURCE;
			if ((stateBits & ResourceStates.UnorderedAccess) != 0) result |= D3D12_RESOURCE_STATES.UNORDERED_ACCESS;
			if ((stateBits & ResourceStates.RenderTarget) != 0) result |= D3D12_RESOURCE_STATES.RENDER_TARGET;
			if ((stateBits & ResourceStates.DepthWrite) != 0) result |= D3D12_RESOURCE_STATES.DEPTH_WRITE;
			if ((stateBits & ResourceStates.DepthRead) != 0) result |= D3D12_RESOURCE_STATES.DEPTH_READ;
			if ((stateBits & ResourceStates.StreamOut) != 0) result |= D3D12_RESOURCE_STATES.STREAM_OUT;
			if ((stateBits & ResourceStates.CopyDest) != 0) result |= D3D12_RESOURCE_STATES.COPY_DEST;
			if ((stateBits & ResourceStates.CopySource) != 0) result |= D3D12_RESOURCE_STATES.COPY_SOURCE;
			if ((stateBits & ResourceStates.ResolveDest) != 0) result |= D3D12_RESOURCE_STATES.RESOLVE_DEST;
			if ((stateBits & ResourceStates.ResolveSource) != 0) result |= D3D12_RESOURCE_STATES.RESOLVE_SOURCE;
			if ((stateBits & ResourceStates.Present) != 0) result |= D3D12_RESOURCE_STATES.PRESENT;
			if ((stateBits & ResourceStates.AccelStructRead) != 0) result |= D3D12_RESOURCE_STATES.RAYTRACING_ACCELERATION_STRUCTURE;
			if ((stateBits & ResourceStates.AccelStructWrite) != 0) result |= D3D12_RESOURCE_STATES.RAYTRACING_ACCELERATION_STRUCTURE;
			if ((stateBits & ResourceStates.AccelStructBuildInput) != 0) result |= D3D12_RESOURCE_STATES.NON_PIXEL_SHADER_RESOURCE;
			if ((stateBits & ResourceStates.AccelStructBuildBlas) != 0) result |= D3D12_RESOURCE_STATES.RAYTRACING_ACCELERATION_STRUCTURE;
			if ((stateBits & ResourceStates.ShadingRateSurface) != 0) result |= D3D12_RESOURCE_STATES.SHADING_RATE_SOURCE;

			return result;
		}

		public static D3D12_SHADING_RATE convertPixelShadingRate(VariableShadingRate shadingRate)
		{
			switch (shadingRate)
			{
			case VariableShadingRate.e1x2:
				return D3D12_SHADING_RATE._1X2;
			case VariableShadingRate.e2x1:
				return D3D12_SHADING_RATE._2X1;
			case VariableShadingRate.e2x2:
				return D3D12_SHADING_RATE._2X2;
			case VariableShadingRate.e2x4:
				return D3D12_SHADING_RATE._2X4;
			case VariableShadingRate.e4x2:
				return D3D12_SHADING_RATE._4X2;
			case VariableShadingRate.e4x4:
				return D3D12_SHADING_RATE._4X4;
			case VariableShadingRate.e1x1: fallthrough;
			default:
				return D3D12_SHADING_RATE._1X1;
			}
		}

		public static D3D12_SHADING_RATE_COMBINER convertShadingRateCombiner(ShadingRateCombiner combiner)
		{
			switch (combiner)
			{
			case ShadingRateCombiner.Override:
				return D3D12_SHADING_RATE_COMBINER.OVERRIDE;
			case ShadingRateCombiner.Min:
				return D3D12_SHADING_RATE_COMBINER.MIN;
			case ShadingRateCombiner.Max:
				return D3D12_SHADING_RATE_COMBINER.MAX;
			case ShadingRateCombiner.ApplyRelative:
				return D3D12_SHADING_RATE_COMBINER.SUM;
			case ShadingRateCombiner.Passthrough: fallthrough;
			default:
				return D3D12_SHADING_RATE_COMBINER.PASSTHROUGH;
			}
		}

		public static void WaitForFence(ID3D12Fence* fence, uint64 value, HANDLE event)
		{
			// Test if the fence has been reached
			if (fence.GetCompletedValue() < value)
			{
				// If it's not, wait for it to finish using an event
				ResetEvent(event);
				fence.SetEventOnCompletion(value, event);
				WaitForSingleObject(event, INFINITE);
			}
		}
	}
}