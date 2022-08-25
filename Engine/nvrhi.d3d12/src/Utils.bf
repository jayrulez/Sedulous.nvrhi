using Win32.Graphics.Dxgi;
using nvrhi.d3dcommon;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Direct3D;
using Win32.Foundation;
using Win32.System.WindowsProgramming;
using Win32.System.Threading;
using System;
namespace nvrhi.d3d12
{
	public static
	{
		public static bool FAILED(HRESULT res)
		{
			return res != S_OK;
		}

		public static bool SUCCEEDED(HRESULT res)
		{
			return res == S_OK;
		}

		public static nvrhi.DeviceHandle createDevice(DeviceDesc desc)
		{
			nvrhi.d3d12.Device device = new .(desc);
			return nvrhi.DeviceHandle.Attach(device);
		}

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

		// helper function for texture subresource calculations
		// https://msdn.microsoft.com/en-us/library/windows/desktop/dn705766(v=vs.85).aspx
		public static uint32 calcSubresource(uint32 MipSlice, uint32 ArraySlice, uint32 PlaneSlice, uint32 MipLevels, uint32 ArraySize)
		{
			return MipSlice + (ArraySlice * MipLevels) + (PlaneSlice * MipLevels * ArraySize);
		}

		public static ResourceType GetNormalizedResourceType(ResourceType type)
		{
			switch (type) // NOLINT(clang-diagnostic-switch-enum)
			{
			case ResourceType.StructuredBuffer_UAV: fallthrough;
			case ResourceType.RawBuffer_UAV:
				return ResourceType.TypedBuffer_UAV;
			case ResourceType.StructuredBuffer_SRV: fallthrough;
			case ResourceType.RawBuffer_SRV:
				return ResourceType.TypedBuffer_SRV;
			default:
				return type;
			}
		}

		public static bool AreResourceTypesCompatible(ResourceType a, ResourceType b)
		{
			var a;
			var b;
			if (a == b)
				return true;

			a = GetNormalizedResourceType(a);
			b = GetNormalizedResourceType(b);

			if (a == ResourceType.TypedBuffer_SRV && b == ResourceType.Texture_SRV ||
				b == ResourceType.TypedBuffer_SRV && a == ResourceType.Texture_SRV ||
				a == ResourceType.TypedBuffer_SRV && b == ResourceType.RayTracingAccelStruct ||
				a == ResourceType.Texture_SRV && b == ResourceType.RayTracingAccelStruct ||
				b == ResourceType.TypedBuffer_SRV && a == ResourceType.RayTracingAccelStruct ||
				b == ResourceType.Texture_SRV && a == ResourceType.RayTracingAccelStruct)
				return true;

			if (a == ResourceType.TypedBuffer_UAV && b == ResourceType.Texture_UAV ||
				b == ResourceType.TypedBuffer_UAV && a == ResourceType.Texture_UAV)
				return true;

			return false;
		}

		public static void fillD3dGeometryDesc(ref D3D12_RAYTRACING_GEOMETRY_DESC outD3dGeometryDesc, nvrhi.rt.GeometryDesc geometryDesc)
		{
			if (geometryDesc.geometryType == nvrhi.rt.GeometryType.Triangles)
			{
				readonly var triangles = /*ref*/ geometryDesc.geometryData.triangles;
				outD3dGeometryDesc.Type = D3D12_RAYTRACING_GEOMETRY_TYPE.TRIANGLES;
				outD3dGeometryDesc.Flags = (D3D12_RAYTRACING_GEOMETRY_FLAGS)geometryDesc.flags;

				if (triangles.indexBuffer != null)
					outD3dGeometryDesc.Triangles.IndexBuffer = checked_cast<Buffer, IBuffer>(triangles.indexBuffer).gpuVA + triangles.indexOffset;
				else
					outD3dGeometryDesc.Triangles.IndexBuffer = 0;

				if (triangles.vertexBuffer != null)
					outD3dGeometryDesc.Triangles.VertexBuffer.StartAddress = checked_cast<Buffer, IBuffer>(triangles.vertexBuffer).gpuVA + triangles.vertexOffset;
				else
					outD3dGeometryDesc.Triangles.VertexBuffer.StartAddress = 0;

				outD3dGeometryDesc.Triangles.VertexBuffer.StrideInBytes = triangles.vertexStride;
				outD3dGeometryDesc.Triangles.IndexFormat = getDxgiFormatMapping(triangles.indexFormat).srvFormat;
				outD3dGeometryDesc.Triangles.VertexFormat = getDxgiFormatMapping(triangles.vertexFormat).srvFormat;
				outD3dGeometryDesc.Triangles.IndexCount = triangles.indexCount;
				outD3dGeometryDesc.Triangles.VertexCount = triangles.vertexCount;
				outD3dGeometryDesc.Triangles.Transform3x4 = 0;
			}
			else
			{
				readonly var aabbs = /*ref*/ geometryDesc.geometryData.aabbs;
				outD3dGeometryDesc.Type = D3D12_RAYTRACING_GEOMETRY_TYPE.PROCEDURAL_PRIMITIVE_AABBS;
				outD3dGeometryDesc.Flags = (D3D12_RAYTRACING_GEOMETRY_FLAGS)geometryDesc.flags;

				if (aabbs.buffer != null)
					outD3dGeometryDesc.AABBs.AABBs.StartAddress = checked_cast<Buffer, IBuffer>(aabbs.buffer).gpuVA + aabbs.offset;
				else
					outD3dGeometryDesc.AABBs.AABBs.StartAddress = 0;

				outD3dGeometryDesc.AABBs.AABBs.StrideInBytes = aabbs.stride;
				outD3dGeometryDesc.AABBs.AABBCount = aabbs.count;
			}
		}

		public static DX12_ViewportState convertViewportState(RasterState rasterState, FramebufferInfo framebufferInfo, ViewportState vpState)
		{
			DX12_ViewportState ret = .();

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
				if (rasterState.scissorEnable)
				{
					ret.scissorRects[rt].left = (.)vpState.scissorRects[rt].minX;
					ret.scissorRects[rt].top = (.)vpState.scissorRects[rt].minY;
					ret.scissorRects[rt].right = (.)vpState.scissorRects[rt].maxX;
					ret.scissorRects[rt].bottom = (.)vpState.scissorRects[rt].maxY;
				}
				else
				{
					ret.scissorRects[rt].left = (.)vpState.viewports[rt].minX;
					ret.scissorRects[rt].top = (.)vpState.viewports[rt].minY;
					ret.scissorRects[rt].right = (.)vpState.viewports[rt].maxX;
					ret.scissorRects[rt].bottom = (.)vpState.viewports[rt].maxY;

					if (framebufferInfo.width > 0)
					{
						ret.scissorRects[rt].left = Math.Max(ret.scissorRects[rt].left, 0);
						ret.scissorRects[rt].top = Math.Max(ret.scissorRects[rt].top, 0);
						ret.scissorRects[rt].right = Math.Min(ret.scissorRects[rt].right, (.)framebufferInfo.width);
						ret.scissorRects[rt].bottom = Math.Min(ret.scissorRects[rt].bottom, (.)framebufferInfo.height);
					}
				}
			}

			return ret;
		}

		public static void TranslateBlendState(BlendState inState, ref D3D12_BLEND_DESC outState)
		{
			outState.AlphaToCoverageEnable = inState.alphaToCoverageEnable ? 1 : 0;
			outState.IndependentBlendEnable = 1;

			for (uint32 i = 0; i < c_MaxRenderTargets; i++)
			{
				readonly ref BlendState.RenderTarget src = ref inState.targets[i];
				ref D3D12_RENDER_TARGET_BLEND_DESC dst = ref outState.RenderTarget[i];

				dst.BlendEnable = src.blendEnable ? 1 : 0;
				dst.SrcBlend = convertBlendValue(src.srcBlend);
				dst.DestBlend = convertBlendValue(src.destBlend);
				dst.BlendOp = convertBlendOp(src.blendOp);
				dst.SrcBlendAlpha = convertBlendValue(src.srcBlendAlpha);
				dst.DestBlendAlpha = convertBlendValue(src.destBlendAlpha);
				dst.BlendOpAlpha = convertBlendOp(src.blendOpAlpha);
				dst.RenderTargetWriteMask = (.)(D3D12_COLOR_WRITE_ENABLE)src.colorWriteMask;
			}
		}

		public static void TranslateDepthStencilState(DepthStencilState inState, ref D3D12_DEPTH_STENCIL_DESC outState)
		{
			outState.DepthEnable = inState.depthTestEnable ? 1 : 0;
			outState.DepthWriteMask = inState.depthWriteEnable ? D3D12_DEPTH_WRITE_MASK.ALL : D3D12_DEPTH_WRITE_MASK.ZERO;
			outState.DepthFunc = convertComparisonFunc(inState.depthFunc);
			outState.StencilEnable = inState.stencilEnable ? 1 : 0;
			outState.StencilReadMask = (uint8)inState.stencilReadMask;
			outState.StencilWriteMask = (uint8)inState.stencilWriteMask;
			outState.FrontFace.StencilFailOp = convertStencilOp(inState.frontFaceStencil.failOp);
			outState.FrontFace.StencilDepthFailOp = convertStencilOp(inState.frontFaceStencil.depthFailOp);
			outState.FrontFace.StencilPassOp = convertStencilOp(inState.frontFaceStencil.passOp);
			outState.FrontFace.StencilFunc = convertComparisonFunc(inState.frontFaceStencil.stencilFunc);
			outState.BackFace.StencilFailOp = convertStencilOp(inState.backFaceStencil.failOp);
			outState.BackFace.StencilDepthFailOp = convertStencilOp(inState.backFaceStencil.depthFailOp);
			outState.BackFace.StencilPassOp = convertStencilOp(inState.backFaceStencil.passOp);
			outState.BackFace.StencilFunc = convertComparisonFunc(inState.backFaceStencil.stencilFunc);
		}

		public static void TranslateRasterizerState(RasterState inState, ref D3D12_RASTERIZER_DESC outState)
		{
			switch (inState.fillMode)
			{
			case RasterFillMode.Solid:
				outState.FillMode = D3D12_FILL_MODE.SOLID;
				break;
			case RasterFillMode.Wireframe:
				outState.FillMode = D3D12_FILL_MODE.WIREFRAME;
				break;
			default:
				nvrhi.utils.InvalidEnum();
				break;
			}

			switch (inState.cullMode)
			{
			case RasterCullMode.Back:
				outState.CullMode = D3D12_CULL_MODE.BACK;
				break;
			case RasterCullMode.Front:
				outState.CullMode = D3D12_CULL_MODE.FRONT;
				break;
			case RasterCullMode.None:
				outState.CullMode = D3D12_CULL_MODE.NONE;
				break;
			default:
				nvrhi.utils.InvalidEnum();
				break;
			}

			outState.FrontCounterClockwise = inState.frontCounterClockwise ? 1 : 0;
			outState.DepthBias = inState.depthBias;
			outState.DepthBiasClamp = inState.depthBiasClamp;
			outState.SlopeScaledDepthBias = inState.slopeScaledDepthBias;
			outState.DepthClipEnable = inState.depthClipEnable ? 1 : 0;
			outState.MultisampleEnable = inState.multisampleEnable ? 1 : 0;
			outState.AntialiasedLineEnable = inState.antialiasedLineEnable ? 1 : 0;
			outState.ConservativeRaster = inState.conservativeRasterEnable ? D3D12_CONSERVATIVE_RASTERIZATION_MODE.ON : D3D12_CONSERVATIVE_RASTERIZATION_MODE.OFF;
			outState.ForcedSampleCount = inState.forcedSampleCount;
		}

		public static D3D12_RESOURCE_DESC convertTextureDesc(TextureDesc d)
		{
		    readonly var formatMapping = getDxgiFormatMapping(d.format);
		    readonly ref FormatInfo formatInfo = ref getFormatInfo(d.format);

		    D3D12_RESOURCE_DESC desc = .();
		    desc.Width = d.width;
		    desc.Height = d.height;
		    desc.MipLevels = uint16(d.mipLevels);
		    desc.Format = d.isTypeless ? formatMapping.resourceFormat : formatMapping.rtvFormat;
		    desc.SampleDesc.Count = d.sampleCount;
		    desc.SampleDesc.Quality = d.sampleQuality;

		    switch (d.dimension)
		    {
		    case TextureDimension.Texture1D: fallthrough;
		    case TextureDimension.Texture1DArray:
		        desc.Dimension = D3D12_RESOURCE_DIMENSION.TEXTURE1D;
		        desc.DepthOrArraySize = uint16(d.arraySize);
		        break;
		    case TextureDimension.Texture2D: fallthrough;
		    case TextureDimension.Texture2DArray: fallthrough;
		    case TextureDimension.TextureCube: fallthrough;
		    case TextureDimension.TextureCubeArray: fallthrough;
		    case TextureDimension.Texture2DMS: fallthrough;
		    case TextureDimension.Texture2DMSArray:
		        desc.Dimension = D3D12_RESOURCE_DIMENSION.TEXTURE2D;
		        desc.DepthOrArraySize = uint16(d.arraySize);
		        break;
		    case TextureDimension.Texture3D:
		        desc.Dimension = D3D12_RESOURCE_DIMENSION.TEXTURE3D;
		        desc.DepthOrArraySize = uint16(d.depth);
		        break;
		    case TextureDimension.Unknown: fallthrough;
		    default:
		        nvrhi.utils.InvalidEnum();
		        break;
		    }

		    if (d.isRenderTarget)
		    {
		        if (formatInfo.hasDepth || formatInfo.hasStencil)
		            desc.Flags |= D3D12_RESOURCE_FLAGS.ALLOW_DEPTH_STENCIL;
		        else
		            desc.Flags |= D3D12_RESOURCE_FLAGS.ALLOW_RENDER_TARGET;
		    }

		    if (d.isUAV)
		        desc.Flags |= D3D12_RESOURCE_FLAGS.ALLOW_UNORDERED_ACCESS;

		    return desc;
		}

		public static D3D12_CLEAR_VALUE convertTextureClearValue(TextureDesc d)
		{
		    readonly var formatMapping = getDxgiFormatMapping(d.format);
		    readonly ref FormatInfo formatInfo = ref getFormatInfo(d.format);
		    D3D12_CLEAR_VALUE clearValue = .();
		    clearValue.Format = formatMapping.rtvFormat;
		    if (formatInfo.hasDepth || formatInfo.hasStencil)
		    {
		        clearValue.DepthStencil.Depth = d.clearValue.r;
		        clearValue.DepthStencil.Stencil = uint8(d.clearValue.g);
		    }
		    else
		    {
		        clearValue.Color[0] = d.clearValue.r;
		        clearValue.Color[1] = d.clearValue.g;
		        clearValue.Color[2] = d.clearValue.b;
		        clearValue.Color[3] = d.clearValue.a;
		    }

		    return clearValue;
		}
	}

	public static
	{
		public static mixin D3D12_ENCODE_BASIC_FILTER(var min, var mag, var mip, UINT reduction)
		{
			(D3D12_FILTER)((uint32)(
				((((uint32)min) & D3D12_FILTER_TYPE_MASK) << D3D12_MIN_FILTER_SHIFT) |
				((((uint32)mag) & D3D12_FILTER_TYPE_MASK) << D3D12_MAG_FILTER_SHIFT) |
				((((uint32)mip) & D3D12_FILTER_TYPE_MASK) << D3D12_MIP_FILTER_SHIFT) |
				(((reduction) & D3D12_FILTER_REDUCTION_TYPE_MASK) << D3D12_FILTER_REDUCTION_TYPE_SHIFT)))
		}

		public static mixin D3D12_ENCODE_ANISOTROPIC_FILTER(var reduction)
		{
			((D3D12_FILTER)(
				(D3D12_FILTER)D3D12_ANISOTROPIC_FILTERING_BIT |
				D3D12_ENCODE_BASIC_FILTER!(
				(uint32)D3D12_FILTER_TYPE.LINEAR,
				(uint32)D3D12_FILTER_TYPE.LINEAR,
				(uint32)D3D12_FILTER_TYPE.LINEAR,
				reduction)))
		}
		public static mixin D3D12_DECODE_MIN_FILTER(var D3D12Filter)
		{
			(D3D12_FILTER_TYPE)((uint32)
				(((D3D12Filter) >> D3D12_MIN_FILTER_SHIFT) & D3D12_FILTER_TYPE_MASK))
		}

		public static mixin D3D12_DECODE_MAG_FILTER(var D3D12Filter)
		{
			(D3D12_FILTER_TYPE)((uint32)
				(((D3D12Filter) >> D3D12_MAG_FILTER_SHIFT) & D3D12_FILTER_TYPE_MASK))
		}

		public static mixin D3D12_DECODE_MIP_FILTER(var D3D12Filter)
		{
			(D3D12_FILTER_TYPE)((uint32)
				(((D3D12Filter) >> D3D12_MIP_FILTER_SHIFT) & D3D12_FILTER_TYPE_MASK))
		}

		public static mixin D3D12_DECODE_FILTER_REDUCTION(var D3D12Filter)
		{
			(D3D12_FILTER_REDUCTION_TYPE)((uint32)
				(((D3D12Filter) >> D3D12_FILTER_REDUCTION_TYPE_SHIFT) & D3D12_FILTER_REDUCTION_TYPE_MASK))
		}

		public static mixin D3D12_DECODE_IS_COMPARISON_FILTER(var D3D12Filter)
		{
			(D3D12_DECODE_FILTER_REDUCTION!(D3D12Filter) == D3D12_FILTER_REDUCTION_TYPE.COMPARISON)
		}

		public static mixin D3D12_DECODE_IS_ANISOTROPIC_FILTER(var D3D12Filter)
		{
			(((D3D12Filter) & D3D12_ANISOTROPIC_FILTERING_BIT) &&
				(D3D12_FILTER_TYPE.LINEAR == D3D12_DECODE_MIN_FILTER!(D3D12Filter)) &&
				(D3D12_FILTER_TYPE.LINEAR == D3D12_DECODE_MAG_FILTER!(D3D12Filter)) &&
				(D3D12_FILTER_TYPE.LINEAR == D3D12_DECODE_MIP_FILTER!(D3D12Filter)))
		}
	}
}