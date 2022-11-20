using Bulkan;
using System;
using System.Collections;
namespace nvrhi.vulkan
{
	public static
	{
		public static mixin CHECK_VK_RETURN(var res) { if ((res) != VkResult.VK_SUCCESS) { return res; } }
		public static mixin CHECK_VK_FAIL(var res) { if ((res) != VkResult.VK_SUCCESS) { return null; } }
		public static mixin  ASSERT_VK_OK(var res)
		{
#if DEBUG
			Runtime.Assert((res) == VkResult.VK_SUCCESS);
#endif
		}

		public static nvrhi.vulkan.IDeviceVK createDevice(DeviceDesc desc)
		{
			DeviceVK device = new DeviceVK(desc);
			return nvrhi.vulkan.DeviceHandle.Attach(device);
		}

		public static VkMemoryPropertyFlags pickBufferMemoryProperties(BufferDesc d)
		{
			VkMemoryPropertyFlags flags = .None;

			switch (d.cpuAccess)
			{
			case CpuAccessMode.None:
				flags = VkMemoryPropertyFlags.eDeviceLocalBit;
				break;
			case CpuAccessMode.Read:
				flags = VkMemoryPropertyFlags.eHostVisibleBit | VkMemoryPropertyFlags.eHostCachedBit;
				break;
			case CpuAccessMode.Write:
				flags = VkMemoryPropertyFlags.eHostVisibleBit;
				break;
			}

			return flags;
		}

		public static VkSamplerAddressMode convertSamplerAddressMode(SamplerAddressMode mode)
		{
			switch (mode)
			{
			case SamplerAddressMode.ClampToEdge:
				return VkSamplerAddressMode.eClampToEdge;

			case SamplerAddressMode.Repeat:
				return VkSamplerAddressMode.eRepeat;

			case SamplerAddressMode.ClampToBorder:
				return VkSamplerAddressMode.eClampToBorder;

			case SamplerAddressMode.MirroredRepeat:
				return VkSamplerAddressMode.eMirroredRepeat;

			case SamplerAddressMode.MirrorClampToEdge:
				return VkSamplerAddressMode.eMirrorClampToEdge;

			default:
				utils.InvalidEnum();
				return (VkSamplerAddressMode)0;
			}
		}

		public static VkPipelineStageFlags convertShaderTypeToPipelineStageFlagBits(ShaderType shaderType)
		{
			if (shaderType == ShaderType.All)
				return VkPipelineStageFlags.eAllCommandsBit;

			uint32 result = 0;

			if ((shaderType & ShaderType.Compute) != 0)        result |= uint32(VkPipelineStageFlags.eComputeShaderBit);
			if ((shaderType & ShaderType.Vertex) != 0)         result |= uint32(VkPipelineStageFlags.eVertexShaderBit);
			if ((shaderType & ShaderType.Hull) != 0)           result |= uint32(VkPipelineStageFlags.eTessellationControlShaderBit);
			if ((shaderType & ShaderType.Domain) != 0)         result |= uint32(VkPipelineStageFlags.eTessellationEvaluationShaderBit);
			if ((shaderType & ShaderType.Geometry) != 0)       result |= uint32(VkPipelineStageFlags.eGeometryShaderBit);
			if ((shaderType & ShaderType.Pixel) != 0)          result |= uint32(VkPipelineStageFlags.eFragmentShaderBit);
			if ((shaderType & ShaderType.Amplification) != 0)  result |= uint32(VkPipelineStageFlags.eTaskShaderBitNV);
			if ((shaderType & ShaderType.Mesh) != 0)           result |= uint32(VkPipelineStageFlags.eMeshShaderBitNV);
			if ((shaderType & ShaderType.AllRayTracing) != 0)  result |= uint32(VkPipelineStageFlags.eRayTracingShaderBitKHR); // or eRayTracingShaderNV, they have the same value

			return (VkPipelineStageFlags)result;
		}

		public static VkShaderStageFlags convertShaderTypeToShaderStageFlagBits(ShaderType shaderType)
		{
			if (shaderType == ShaderType.All)
				return VkShaderStageFlags.eAll;


			uint32 result = 0;

			if ((shaderType & ShaderType.Compute) != 0)        result |= uint32(VkShaderStageFlags.eComputeBit);
			if ((shaderType & ShaderType.Vertex) != 0)         result |= uint32(VkShaderStageFlags.eVertexBit);
			if ((shaderType & ShaderType.Hull) != 0)           result |= uint32(VkShaderStageFlags.eTessellationControlBit);
			if ((shaderType & ShaderType.Domain) != 0)         result |= uint32(VkShaderStageFlags.eTessellationEvaluationBit);
			if ((shaderType & ShaderType.Geometry) != 0)       result |= uint32(VkShaderStageFlags.eGeometryBit);
			if ((shaderType & ShaderType.Pixel) != 0)          result |= uint32(VkShaderStageFlags.eFragmentBit);
			if ((shaderType & ShaderType.Amplification) != 0)  result |= uint32(VkShaderStageFlags.eTaskBitNV);
			if ((shaderType & ShaderType.Mesh) != 0)           result |= uint32(VkShaderStageFlags.eMeshBitNV);
			if ((shaderType & ShaderType.RayGeneration) != 0)  result |= uint32(VkShaderStageFlags.eRaygenBitKHR); // or eRaygenNV, they have the same value
			if ((shaderType & ShaderType.Miss) != 0)           result |= uint32(VkShaderStageFlags.eMissBitKHR); // same etc...
			if ((shaderType & ShaderType.ClosestHit) != 0)     result |= uint32(VkShaderStageFlags.eClosestHitBitKHR);
			if ((shaderType & ShaderType.AnyHit) != 0)         result |= uint32(VkShaderStageFlags.eAnyHitBitKHR);
			if ((shaderType & ShaderType.Intersection) != 0)   result |= uint32(VkShaderStageFlags.eIntersectionBitKHR);

			return (VkShaderStageFlags)result;
		}

		public const ResourceStateMapping[?] g_ResourceStateMap =
			.(
			.(ResourceStates.Common,
			VkPipelineStageFlags.eTopOfPipeBit,
			VkAccessFlags(),
			VkImageLayout.eUndefined),
			.(ResourceStates.ConstantBuffer,
			VkPipelineStageFlags.eAllCommandsBit,
			VkAccessFlags.eUniformReadBit,
			VkImageLayout.eUndefined),
			.(ResourceStates.VertexBuffer,
			VkPipelineStageFlags.eVertexInputBit,
			VkAccessFlags.eVertexAttributeReadBit,
			VkImageLayout.eUndefined),
			.(ResourceStates.IndexBuffer,
			VkPipelineStageFlags.eVertexInputBit,
			VkAccessFlags.eIndexReadBit,
			VkImageLayout.eUndefined),
			.(ResourceStates.IndirectArgument,
			VkPipelineStageFlags.eDrawIndirectBit,
			VkAccessFlags.eIndirectCommandReadBit,
			VkImageLayout.eUndefined),
			.(ResourceStates.ShaderResource,
			VkPipelineStageFlags.eAllCommandsBit,
			VkAccessFlags.eShaderReadBit,
			VkImageLayout.eShaderReadOnlyOptimal),
			.(ResourceStates.UnorderedAccess,
			VkPipelineStageFlags.eAllCommandsBit,
			VkAccessFlags.eShaderReadBit | VkAccessFlags.eShaderWriteBit,
			VkImageLayout.eGeneral),
			.(ResourceStates.RenderTarget,
			VkPipelineStageFlags.eColorAttachmentOutputBit,
			VkAccessFlags.eColorAttachmentReadBit | VkAccessFlags.eColorAttachmentWriteBit,
			VkImageLayout.eColorAttachmentOptimal),
			.(ResourceStates.DepthWrite,
			VkPipelineStageFlags.eEarlyFragmentTestsBit | VkPipelineStageFlags.eLateFragmentTestsBit,
			VkAccessFlags.eDepthStencilAttachmentReadBit | VkAccessFlags.eDepthStencilAttachmentWriteBit,
			VkImageLayout.eDepthStencilAttachmentOptimal),
			.(ResourceStates.DepthRead,
			VkPipelineStageFlags.eEarlyFragmentTestsBit | VkPipelineStageFlags.eLateFragmentTestsBit,
			VkAccessFlags.eDepthStencilAttachmentReadBit,
			VkImageLayout.eDepthStencilAttachmentOptimal),
			.(ResourceStates.StreamOut,
			VkPipelineStageFlags.eTransformFeedbackBitEXT,
			VkAccessFlags.eTransformFeedbackWriteBitEXT,
			VkImageLayout.eUndefined),
			.(ResourceStates.CopyDest,
			VkPipelineStageFlags.eTransferBit,
			VkAccessFlags.eTransferWriteBit,
			VkImageLayout.eTransferDstOptimal),
			.(ResourceStates.CopySource,
			VkPipelineStageFlags.eTransferBit,
			VkAccessFlags.eTransferReadBit,
			VkImageLayout.eTransferSrcOptimal),
			.(ResourceStates.ResolveDest,
			VkPipelineStageFlags.eTransferBit,
			VkAccessFlags.eTransferWriteBit,
			VkImageLayout.eTransferDstOptimal),
			.(ResourceStates.ResolveSource,
			VkPipelineStageFlags.eTransferBit,
			VkAccessFlags.eTransferReadBit,
			VkImageLayout.eTransferSrcOptimal),
			.(ResourceStates.Present,
			VkPipelineStageFlags.eAllCommandsBit,
			VkAccessFlags.eMemoryReadBit,
			VkImageLayout.ePresentSrcKHR),
			.(ResourceStates.AccelStructRead,
			VkPipelineStageFlags.eRayTracingShaderBitKHR | VkPipelineStageFlags.eComputeShaderBit,
			VkAccessFlags.eAccelerationStructureReadBitKHR,
			VkImageLayout.eUndefined),
			.(ResourceStates.AccelStructWrite,
			VkPipelineStageFlags.eAccelerationStructureBuildBitKHR,
			VkAccessFlags.eAccelerationStructureWriteBitKHR,
			VkImageLayout.eUndefined),
			.(ResourceStates.AccelStructBuildInput,
			VkPipelineStageFlags.eAccelerationStructureBuildBitKHR,
			VkAccessFlags.eAccelerationStructureReadBitKHR,
			VkImageLayout.eUndefined),
			.(ResourceStates.AccelStructBuildBlas,
			VkPipelineStageFlags.eAccelerationStructureBuildBitKHR,
			VkAccessFlags.eAccelerationStructureReadBitKHR,
			VkImageLayout.eUndefined),
			.(ResourceStates.ShadingRateSurface,
			VkPipelineStageFlags.eFragmentShadingRateAttachmentBitKHR,
			VkAccessFlags.eFragmentShadingRateAttachmentReadBitKHR,
			VkImageLayout.eFragmentShadingRateAttachmentOptimalKHR)
			);

		public static ResourceStateMapping convertResourceState(ResourceStates state)
		{
			ResourceStateMapping result = default;

			const uint32 numStateBits = g_ResourceStateMap.Count;

			uint32 stateTmp = uint32(state);
			uint32 bitIndex = 0;

			while (stateTmp != 0 && bitIndex < numStateBits)
			{
				uint32 bit = (1 << bitIndex);

				if (stateTmp & bit != 0)
				{
					readonly ResourceStateMapping mapping = g_ResourceStateMap[bitIndex];

					Runtime.Assert(uint32(mapping.nvrhiState) == bit);
					Runtime.Assert(result.imageLayout == VkImageLayout.eUndefined || mapping.imageLayout == VkImageLayout.eUndefined || result.imageLayout == mapping.imageLayout);

					result.nvrhiState = (ResourceStates)result.nvrhiState | mapping.nvrhiState;
					result.accessMask |= mapping.accessMask;
					result.stageFlags |= mapping.stageFlags;
					if (mapping.imageLayout != VkImageLayout.eUndefined)
						result.imageLayout = mapping.imageLayout;

					stateTmp &= ~bit;
				}

				bitIndex++;
			}

			Runtime.Assert(result.nvrhiState == state);

			return result;
		}

		public static VkPrimitiveTopology convertPrimitiveTopology(PrimitiveType topology)
		{
			switch (topology)
			{
			case PrimitiveType.PointList:
				return VkPrimitiveTopology.ePointList;

			case PrimitiveType.LineList:
				return VkPrimitiveTopology.eLineList;

			case PrimitiveType.TriangleList:
				return VkPrimitiveTopology.eTriangleList;

			case PrimitiveType.TriangleStrip:
				return VkPrimitiveTopology.eTriangleStrip;

			case PrimitiveType.TriangleFan:
				return VkPrimitiveTopology.eTriangleFan;

			case PrimitiveType.TriangleListWithAdjacency:
				return VkPrimitiveTopology.eTriangleListWithAdjacency;

			case PrimitiveType.TriangleStripWithAdjacency:
				return VkPrimitiveTopology.eTriangleStripWithAdjacency;

			case PrimitiveType.PatchList:
				return VkPrimitiveTopology.ePatchList;

			default:
				Runtime.Assert(false);
				return VkPrimitiveTopology.eTriangleList;
			}
		}

		public static VkPolygonMode convertFillMode(RasterFillMode mode)
		{
			switch (mode)
			{
			case RasterFillMode.Fill:
				return VkPolygonMode.eFill;

			case RasterFillMode.Line:
				return VkPolygonMode.eLine;

			default:
				Runtime.Assert(false);
				return VkPolygonMode.eFill;
			}
		}

		public static VkCullModeFlags convertCullMode(RasterCullMode mode)
		{
			switch (mode)
			{
			case RasterCullMode.Back:
				return VkCullModeFlags.eBackBit;

			case RasterCullMode.Front:
				return VkCullModeFlags.eFrontBit;

			case RasterCullMode.None:
				return VkCullModeFlags.eNone;

			default:
				Runtime.Assert(false);
				return VkCullModeFlags.eNone;
			}
		}

		public static VkCompareOp convertCompareOp(ComparisonFunc op)
		{
			switch (op)
			{
			case ComparisonFunc.Never:
				return VkCompareOp.eNever;

			case ComparisonFunc.Less:
				return VkCompareOp.eLess;

			case ComparisonFunc.Equal:
				return VkCompareOp.eEqual;

			case ComparisonFunc.LessOrEqual:
				return VkCompareOp.eLessOrEqual;

			case ComparisonFunc.Greater:
				return VkCompareOp.eGreater;

			case ComparisonFunc.NotEqual:
				return VkCompareOp.eNotEqual;

			case ComparisonFunc.GreaterOrEqual:
				return VkCompareOp.eGreaterOrEqual;

			case ComparisonFunc.Always:
				return VkCompareOp.eAlways;

			default:
				utils.InvalidEnum();
				return VkCompareOp.eAlways;
			}
		}

		public static VkStencilOp convertStencilOp(StencilOp op)
		{
			switch (op)
			{
			case StencilOp.Keep:
				return VkStencilOp.eKeep;

			case StencilOp.Zero:
				return VkStencilOp.eZero;

			case StencilOp.Replace:
				return VkStencilOp.eReplace;

			case StencilOp.IncrementAndClamp:
				return VkStencilOp.eIncrementAndClamp;

			case StencilOp.DecrementAndClamp:
				return VkStencilOp.eDecrementAndClamp;

			case StencilOp.Invert:
				return VkStencilOp.eInvert;

			case StencilOp.IncrementAndWrap:
				return VkStencilOp.eIncrementAndWrap;

			case StencilOp.DecrementAndWrap:
				return VkStencilOp.eDecrementAndWrap;

			default:
				utils.InvalidEnum();
				return VkStencilOp.eKeep;
			}
		}

		public static VkStencilOpState convertStencilState(DepthStencilState depthStencilState, DepthStencilState.StencilOpDesc desc)
		{
			return VkStencilOpState()
				.setFailOp(convertStencilOp(desc.failOp))
				.setPassOp(convertStencilOp(desc.passOp))
				.setDepthFailOp(convertStencilOp(desc.depthFailOp))
				.setCompareOp(convertCompareOp(desc.stencilFunc))
				.setCompareMask(depthStencilState.stencilReadMask)
				.setWriteMask(depthStencilState.stencilWriteMask)
				.setReference(depthStencilState.stencilRefValue);
		}

		public static VkBlendFactor convertBlendValue(BlendFactor value)
		{
			switch (value)
			{
			case BlendFactor.Zero:
				return VkBlendFactor.eZero;

			case BlendFactor.One:
				return VkBlendFactor.eOne;

			case BlendFactor.SrcColor:
				return VkBlendFactor.eSrcColor;

			case BlendFactor.OneMinusSrcColor:
				return VkBlendFactor.eOneMinusSrcColor;

			case BlendFactor.SrcAlpha:
				return VkBlendFactor.eSrcAlpha;

			case BlendFactor.OneMinusSrcAlpha:
				return VkBlendFactor.eOneMinusSrcAlpha;

			case BlendFactor.DstAlpha:
				return VkBlendFactor.eDstAlpha;

			case BlendFactor.OneMinusDstAlpha:
				return VkBlendFactor.eOneMinusDstAlpha;

			case BlendFactor.DstColor:
				return VkBlendFactor.eDstColor;

			case BlendFactor.OneMinusDstColor:
				return VkBlendFactor.eOneMinusDstColor;

			case BlendFactor.SrcAlphaSaturate:
				return VkBlendFactor.eSrcAlphaSaturate;

			case BlendFactor.ConstantColor:
				return VkBlendFactor.eConstantColor;

			case BlendFactor.OneMinusConstantColor:
				return VkBlendFactor.eOneMinusConstantColor;

			case BlendFactor.Src1Color:
				return VkBlendFactor.eSrc1Color;

			case BlendFactor.OneMinusSrc1Color:
				return VkBlendFactor.eOneMinusSrc1Color;

			case BlendFactor.Src1Alpha:
				return VkBlendFactor.eSrc1Alpha;

			case BlendFactor.OneMinusSrc1Alpha:
				return VkBlendFactor.eOneMinusSrc1Alpha;

			default:
				Runtime.Assert(false);
				return VkBlendFactor.eZero;
			}
		}
		public static VkBlendOp convertBlendOp(BlendOp op)
		{
			switch (op)
			{
			case BlendOp.Add:
				return VkBlendOp.eAdd;

			case BlendOp.Subrtact:
				return VkBlendOp.eSubtract;

			case BlendOp.ReverseSubtract:
				return VkBlendOp.eReverseSubtract;

			case BlendOp.Min:
				return VkBlendOp.eMin;

			case BlendOp.Max:
				return VkBlendOp.eMax;

			default:
				Runtime.Assert(false);
				return VkBlendOp.eAdd;
			}
		}
		public static VkColorComponentFlags convertColorMask(ColorMask mask)
		{
			return (VkColorComponentFlags)uint8(mask);
		}
		public static VkPipelineColorBlendAttachmentState convertBlendState(BlendState.RenderTarget state)
		{
			return VkPipelineColorBlendAttachmentState()
				.setBlendEnable(state.blendEnable)
				.setSrcColorBlendFactor(convertBlendValue(state.srcBlend))
				.setDstColorBlendFactor(convertBlendValue(state.destBlend))
				.setColorBlendOp(convertBlendOp(state.blendOp))
				.setSrcAlphaBlendFactor(convertBlendValue(state.srcBlendAlpha))
				.setDstAlphaBlendFactor(convertBlendValue(state.destBlendAlpha))
				.setAlphaBlendOp(convertBlendOp(state.blendOpAlpha))
				.setColorWriteMask(convertColorMask(state.colorWriteMask));
		}

		public static VkBuildAccelerationStructureFlagsKHR convertAccelStructBuildFlags(nvrhi.rt.AccelStructBuildFlags buildFlags)
		{
			VkBuildAccelerationStructureFlagsKHR flags = (VkBuildAccelerationStructureFlagsKHR)0;
			if ((buildFlags & nvrhi.rt.AccelStructBuildFlags.AllowUpdate) != 0)
				flags |= VkBuildAccelerationStructureFlagsKHR.eAllowUpdateBitKHR;
			if ((buildFlags & nvrhi.rt.AccelStructBuildFlags.AllowCompaction) != 0)
				flags |= VkBuildAccelerationStructureFlagsKHR.eAllowCompactionBitKHR;
			if ((buildFlags & nvrhi.rt.AccelStructBuildFlags.PreferFastTrace) != 0)
				flags |= VkBuildAccelerationStructureFlagsKHR.ePreferFastTraceBitKHR;
			if ((buildFlags & nvrhi.rt.AccelStructBuildFlags.PreferFastBuild) != 0)
				flags |= VkBuildAccelerationStructureFlagsKHR.ePreferFastBuildBitKHR;
			if ((buildFlags & nvrhi.rt.AccelStructBuildFlags.MinimizeMemory) != 0)
				flags |= VkBuildAccelerationStructureFlagsKHR.eLowMemoryBitKHR;
			return flags;
		}

		public static VkGeometryInstanceFlagsKHR convertInstanceFlags(nvrhi.rt.InstanceFlags instanceFlags)
		{
#if ENABLE_SHORTCUT_CONVERSIONS
			Compiler.Assert(uint32(nvrhi.rt.InstanceFlags.TriangleCullDisable) == uint32(VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR));
			Compiler.Assert(uint32(nvrhi.rt.InstanceFlags.TriangleFrontCounterclockwise) == uint32(VK_GEOMETRY_INSTANCE_TRIANGLE_FRONT_COUNTERCLOCKWISE_BIT_KHR));
			Compiler.Assert(uint32(nvrhi.rt.InstanceFlags.ForceOpaque) == uint32(VK_GEOMETRY_INSTANCE_FORCE_OPAQUE_BIT_KHR));
			Compiler.Assert(uint32(nvrhi.rt.InstanceFlags.ForceNonOpaque) == uint32(VK_GEOMETRY_INSTANCE_FORCE_NO_OPAQUE_BIT_KHR));

			return VkGeometryInstanceFlagsKHR(uint32(instanceFlags) & 0x0f);
#else
			VkGeometryInstanceFlagsKHR flags = (VkGeometryInstanceFlagsKHR)0;
			if ((instanceFlags & nvrhi.rt.InstanceFlags.ForceNonOpaque) != 0)
				flags |= VkGeometryInstanceFlagsKHR.eForceNoOpaqueBitKHR;
			if ((instanceFlags & nvrhi.rt.InstanceFlags.ForceOpaque) != 0)
				flags |= VkGeometryInstanceFlagsKHR.eForceOpaqueBitKHR;
			if ((instanceFlags & nvrhi.rt.InstanceFlags.TriangleCullDisable) != 0)
				flags |= VkGeometryInstanceFlagsKHR.eTriangleFacingCullDisableBitKHR;
			if ((instanceFlags & nvrhi.rt.InstanceFlags.TriangleFrontCounterclockwise) != 0)
				flags |= VkGeometryInstanceFlagsKHR.eTriangleFrontCounterclockwiseBitKHR;
			return flags;
#endif
		}

		public static VkExtent2D convertFragmentShadingRate(VariableShadingRate shadingRate)
		{
			switch (shadingRate)
			{
			case VariableShadingRate.e1x2:
				return VkExtent2D().setWidth(1).setHeight(2);
			case VariableShadingRate.e2x1:
				return VkExtent2D().setWidth(2).setHeight(1);
			case VariableShadingRate.e2x2:
				return VkExtent2D().setWidth(2).setHeight(2);
			case VariableShadingRate.e2x4:
				return VkExtent2D().setWidth(2).setHeight(4);
			case VariableShadingRate.e4x2:
				return VkExtent2D().setWidth(4).setHeight(2);
			case VariableShadingRate.e4x4:
				return VkExtent2D().setWidth(4).setHeight(4);
			case VariableShadingRate.e1x1: fallthrough;
			default:
				return VkExtent2D().setWidth(1).setHeight(1);
			}
		}

		public static VkFragmentShadingRateCombinerOpKHR convertShadingRateCombiner(ShadingRateCombiner combiner)
		{
			switch (combiner)
			{
			case ShadingRateCombiner.Override:
				return VkFragmentShadingRateCombinerOpKHR.eReplaceKHR;
			case ShadingRateCombiner.Min:
				return VkFragmentShadingRateCombinerOpKHR.eMinKHR;
			case ShadingRateCombiner.Max:
				return VkFragmentShadingRateCombinerOpKHR.eMaxKHR;
			case ShadingRateCombiner.ApplyRelative:
				return VkFragmentShadingRateCombinerOpKHR.eMulKHR;
			case ShadingRateCombiner.Passthrough: fallthrough;
			default:
				return VkFragmentShadingRateCombinerOpKHR.eKeepKHR;
			}
		}

		public static void countSpecializationConstants(
			ShaderVK shader,
			ref int numShaders,
			ref int numShadersWithSpecializations,
			ref int numSpecializationConstants)
		{
			if (shader == null)
				return;

			numShaders += 1;

			if (shader.specializationConstants.IsEmpty)
				return;

			numShadersWithSpecializations += 1;
			numSpecializationConstants += shader.specializationConstants.Count;
		}

		public static VkPipelineShaderStageCreateInfo makeShaderStageCreateInfo(
			ShaderVK shader,
			List<VkSpecializationInfo> specInfos,
			List<VkSpecializationMapEntry> specMapEntries,
			List<uint32> specData)
		{
			var shaderStageCreateInfo = VkPipelineShaderStageCreateInfo()
				.setStage(shader.stageFlagBits)
				.setModule(shader.shaderModule)
				.setPName(shader.desc.entryName);

			if (!shader.specializationConstants.IsEmpty)
			{
				// For specializations, this functions allocates:
				//  - One entry in specInfos per shader
				//  - One entry in specMapEntries and specData each per constant
				// The vectors are pre-allocated, so it's safe to use .data() before writing the data

				Runtime.Assert(specInfos.Ptr != null);
				Runtime.Assert(specMapEntries.Ptr != null);
				Runtime.Assert(specData.Ptr != null);

				shaderStageCreateInfo.setPSpecializationInfo(specInfos.Ptr + specInfos.Count);

				var specInfo = VkSpecializationInfo()
					.setPMapEntries(specMapEntries.Ptr + specMapEntries.Count)
					.setMapEntryCount((uint32)(shader.specializationConstants.Count))
					.setPData(specData.Ptr + specData.Count)
					.setDataSize((.)shader.specializationConstants.Count * sizeof(uint32));

				int dataOffset = 0;
				for ( /*readonly ref*/var constant in ref shader.specializationConstants)
				{
					var specMapEntry = VkSpecializationMapEntry()
						.setConstantID(constant.constantID)
						.setOffset((uint32)(dataOffset))
						.setSize(sizeof(uint32));

					specMapEntries.Add(specMapEntry);
					specData.Add(constant.value.u);
					dataOffset += (.)specMapEntry.size;
				}

				specInfos.Add(specInfo);
			}

			return shaderStageCreateInfo;
		}

		struct FormatMapping : this(nvrhi.Format rhiFormat, VkFormat vkFormat)
		{
		}

		public const FormatMapping[int(Format.COUNT)] c_FormatMap = .(
			.(Format.UNKNOWN,           VkFormat.VK_FORMAT_UNDEFINED                ),
			.(Format.R8_UINT,           VkFormat.VK_FORMAT_R8_UINT                  ),
			.(Format.R8_SINT,           VkFormat.VK_FORMAT_R8_SINT                  ),
			.(Format.R8_UNORM,          VkFormat.VK_FORMAT_R8_UNORM                 ),
			.(Format.R8_SNORM,          VkFormat.VK_FORMAT_R8_SNORM                 ),
			.(Format.RG8_UINT,          VkFormat.VK_FORMAT_R8G8_UINT                ),
			.(Format.RG8_SINT,          VkFormat.VK_FORMAT_R8G8_SINT                ),
			.(Format.RG8_UNORM,         VkFormat.VK_FORMAT_R8G8_UNORM               ),
			.(Format.RG8_SNORM,         VkFormat.VK_FORMAT_R8G8_SNORM               ),
			.(Format.R16_UINT,          VkFormat.VK_FORMAT_R16_UINT                 ),
			.(Format.R16_SINT,          VkFormat.VK_FORMAT_R16_SINT                 ),
			.(Format.R16_UNORM,         VkFormat.VK_FORMAT_R16_UNORM                ),
			.(Format.R16_SNORM,         VkFormat.VK_FORMAT_R16_SNORM                ),
			.(Format.R16_FLOAT,         VkFormat.VK_FORMAT_R16_SFLOAT               ),
			.(Format.BGRA4_UNORM,       VkFormat.VK_FORMAT_B4G4R4A4_UNORM_PACK16    ),
			.(Format.B5G6R5_UNORM,      VkFormat.VK_FORMAT_B5G6R5_UNORM_PACK16      ),
			.(Format.B5G5R5A1_UNORM,    VkFormat.VK_FORMAT_B5G5R5A1_UNORM_PACK16    ),
			.(Format.RGBA8_UINT,        VkFormat.VK_FORMAT_R8G8B8A8_UINT            ),
			.(Format.RGBA8_SINT,        VkFormat.VK_FORMAT_R8G8B8A8_SINT            ),
			.(Format.RGBA8_UNORM,       VkFormat.VK_FORMAT_R8G8B8A8_UNORM           ),
			.(Format.RGBA8_SNORM,       VkFormat.VK_FORMAT_R8G8B8A8_SNORM           ),
			.(Format.BGRA8_UNORM,       VkFormat.VK_FORMAT_B8G8R8A8_UNORM           ),
			.(Format.SRGBA8_UNORM,      VkFormat.VK_FORMAT_R8G8B8A8_SRGB            ),
			.(Format.SBGRA8_UNORM,      VkFormat.VK_FORMAT_B8G8R8A8_SRGB            ),
			.(Format.R10G10B10A2_UNORM, VkFormat.VK_FORMAT_A2B10G10R10_UNORM_PACK32),
			.(Format.R11G11B10_FLOAT,   VkFormat.VK_FORMAT_B10G11R11_UFLOAT_PACK32  ),
			.(Format.RG16_UINT,         VkFormat.VK_FORMAT_R16G16_UINT              ),
			.(Format.RG16_SINT,         VkFormat.VK_FORMAT_R16G16_SINT              ),
			.(Format.RG16_UNORM,        VkFormat.VK_FORMAT_R16G16_UNORM             ),
			.(Format.RG16_SNORM,        VkFormat.VK_FORMAT_R16G16_SNORM             ),
			.(Format.RG16_FLOAT,        VkFormat.VK_FORMAT_R16G16_SFLOAT            ),
			.(Format.R32_UINT,          VkFormat.VK_FORMAT_R32_UINT                 ),
			.(Format.R32_SINT,          VkFormat.VK_FORMAT_R32_SINT                 ),
			.(Format.R32_FLOAT,         VkFormat.VK_FORMAT_R32_SFLOAT               ),
			.(Format.RGBA16_UINT,       VkFormat.VK_FORMAT_R16G16B16A16_UINT        ),
			.(Format.RGBA16_SINT,       VkFormat.VK_FORMAT_R16G16B16A16_SINT        ),
			.(Format.RGBA16_FLOAT,      VkFormat.VK_FORMAT_R16G16B16A16_SFLOAT      ),
			.(Format.RGBA16_UNORM,      VkFormat.VK_FORMAT_R16G16B16A16_UNORM       ),
			.(Format.RGBA16_SNORM,      VkFormat.VK_FORMAT_R16G16B16A16_SNORM       ),
			.(Format.RG32_UINT,         VkFormat.VK_FORMAT_R32G32_UINT              ),
			.(Format.RG32_SINT,         VkFormat.VK_FORMAT_R32G32_SINT              ),
			.(Format.RG32_FLOAT,        VkFormat.VK_FORMAT_R32G32_SFLOAT            ),
			.(Format.RGB32_UINT,        VkFormat.VK_FORMAT_R32G32B32_UINT           ),
			.(Format.RGB32_SINT,        VkFormat.VK_FORMAT_R32G32B32_SINT           ),
			.(Format.RGB32_FLOAT,       VkFormat.VK_FORMAT_R32G32B32_SFLOAT         ),
			.(Format.RGBA32_UINT,       VkFormat.VK_FORMAT_R32G32B32A32_UINT        ),
			.(Format.RGBA32_SINT,       VkFormat.VK_FORMAT_R32G32B32A32_SINT        ),
			.(Format.RGBA32_FLOAT,      VkFormat.VK_FORMAT_R32G32B32A32_SFLOAT      ),
			.(Format.D16,               VkFormat.VK_FORMAT_D16_UNORM                ),
			.(Format.D24S8,             VkFormat.VK_FORMAT_D24_UNORM_S8_UINT        ),
			.(Format.X24G8_UINT,        VkFormat.VK_FORMAT_D24_UNORM_S8_UINT        ),
			.(Format.D32,               VkFormat.VK_FORMAT_D32_SFLOAT               ),
			.(Format.D32S8,             VkFormat.VK_FORMAT_D32_SFLOAT_S8_UINT       ),
			.(Format.X32G8_UINT,        VkFormat.VK_FORMAT_D32_SFLOAT_S8_UINT       ),
			.(Format.BC1_UNORM,         VkFormat.VK_FORMAT_BC1_RGB_UNORM_BLOCK      ),
			.(Format.BC1_UNORM_SRGB,    VkFormat.VK_FORMAT_BC1_RGB_SRGB_BLOCK       ),
			.(Format.BC2_UNORM,         VkFormat.VK_FORMAT_BC2_UNORM_BLOCK          ),
			.(Format.BC2_UNORM_SRGB,    VkFormat.VK_FORMAT_BC2_SRGB_BLOCK           ),
			.(Format.BC3_UNORM,         VkFormat.VK_FORMAT_BC3_UNORM_BLOCK          ),
			.(Format.BC3_UNORM_SRGB,    VkFormat.VK_FORMAT_BC3_SRGB_BLOCK           ),
			.(Format.BC4_UNORM,         VkFormat.VK_FORMAT_BC4_UNORM_BLOCK          ),
			.(Format.BC4_SNORM,         VkFormat.VK_FORMAT_BC4_SNORM_BLOCK          ),
			.(Format.BC5_UNORM,         VkFormat.VK_FORMAT_BC5_UNORM_BLOCK          ),
			.(Format.BC5_SNORM,         VkFormat.VK_FORMAT_BC5_SNORM_BLOCK          ),
			.(Format.BC6H_UFLOAT,       VkFormat.VK_FORMAT_BC6H_UFLOAT_BLOCK        ),
			.(Format.BC6H_SFLOAT,       VkFormat.VK_FORMAT_BC6H_SFLOAT_BLOCK        ),
			.(Format.BC7_UNORM,         VkFormat.VK_FORMAT_BC7_UNORM_BLOCK          ),
			.(Format.BC7_UNORM_SRGB,    VkFormat.VK_FORMAT_BC7_SRGB_BLOCK           )
			);

		public static VkFormat convertFormat(nvrhi.Format format)
		{
			Runtime.Assert(format < nvrhi.Format.COUNT);
			Runtime.Assert(c_FormatMap[uint32(format)].rhiFormat == format);

			return c_FormatMap[uint32(format)].vkFormat;
		}

		public static char8* resultToString(VkResult result)
		{
			switch (result)
			{
			case .VK_SUCCESS:
				return "VK_SUCCESS";
			case .VK_NOT_READY:
				return "VK_NOT_READY";
			case .VK_TIMEOUT:
				return "VK_TIMEOUT";
			case .VK_EVENT_SET:
				return "VK_EVENT_SET";
			case .VK_EVENT_RESET:
				return "VK_EVENT_RESET";
			case .VK_INCOMPLETE:
				return "VK_INCOMPLETE";
			case .VK_ERROR_OUT_OF_HOST_MEMORY:
				return "VK_ERROR_OUT_OF_HOST_MEMORY";
			case .VK_ERROR_OUT_OF_DEVICE_MEMORY:
				return "VK_ERROR_OUT_OF_DEVICE_MEMORY";
			case .VK_ERROR_INITIALIZATION_FAILED:
				return "VK_ERROR_INITIALIZATION_FAILED";
			case .VK_ERROR_DEVICE_LOST:
				return "VK_ERROR_DEVICE_LOST";
			case .VK_ERROR_MEMORY_MAP_FAILED:
				return "VK_ERROR_MEMORY_MAP_FAILED";
			case .VK_ERROR_LAYER_NOT_PRESENT:
				return "VK_ERROR_LAYER_NOT_PRESENT";
			case .VK_ERROR_EXTENSION_NOT_PRESENT:
				return "VK_ERROR_EXTENSION_NOT_PRESENT";
			case .VK_ERROR_FEATURE_NOT_PRESENT:
				return "VK_ERROR_FEATURE_NOT_PRESENT";
			case .VK_ERROR_INCOMPATIBLE_DRIVER:
				return "VK_ERROR_INCOMPATIBLE_DRIVER";
			case .VK_ERROR_TOO_MANY_OBJECTS:
				return "VK_ERROR_TOO_MANY_OBJECTS";
			case .VK_ERROR_FORMAT_NOT_SUPPORTED:
				return "VK_ERROR_FORMAT_NOT_SUPPORTED";
			case .VK_ERROR_FRAGMENTED_POOL:
				return "VK_ERROR_FRAGMENTED_POOL";
			case .VK_ERROR_UNKNOWN:
				return "VK_ERROR_UNKNOWN";
			case .VK_ERROR_OUT_OF_POOL_MEMORY:
				return "VK_ERROR_OUT_OF_POOL_MEMORY";
			case .VK_ERROR_INVALID_EXTERNAL_HANDLE:
				return "VK_ERROR_INVALID_EXTERNAL_HANDLE";
			case .VK_ERROR_FRAGMENTATION:
				return "VK_ERROR_FRAGMENTATION";
			case .VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS:
				return "VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS";
			case .VK_ERROR_SURFACE_LOST_KHR:
				return "VK_ERROR_SURFACE_LOST_KHR";
			case .VK_ERROR_NATIVE_WINDOW_IN_USE_KHR:
				return "VK_ERROR_NATIVE_WINDOW_IN_USE_KHR";
			case .VK_SUBOPTIMAL_KHR:
				return "VK_SUBOPTIMAL_KHR";
			case .VK_ERROR_OUT_OF_DATE_KHR:
				return "VK_ERROR_OUT_OF_DATE_KHR";
			case .VK_ERROR_INCOMPATIBLE_DISPLAY_KHR:
				return "VK_ERROR_INCOMPATIBLE_DISPLAY_KHR";
			case .VK_ERROR_VALIDATION_FAILED_EXT:
				return "VK_ERROR_VALIDATION_FAILED_EXT";
			case .VK_ERROR_INVALID_SHADER_NV:
				return "VK_ERROR_INVALID_SHADER_NV";
			case .VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT:
				return "VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT";
			case .VK_ERROR_NOT_PERMITTED_KHR:
				return "VK_ERROR_NOT_PERMITTED_EXT";
			case .VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT:
				return "VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT";
			case .VK_THREAD_IDLE_KHR:
				return "VK_THREAD_IDLE_KHR";
			case .VK_THREAD_DONE_KHR:
				return "VK_THREAD_DONE_KHR";
			case .VK_OPERATION_DEFERRED_KHR:
				return "VK_OPERATION_DEFERRED_KHR";
			case .VK_OPERATION_NOT_DEFERRED_KHR:
				return "VK_OPERATION_NOT_DEFERRED_KHR";
			case .VK_PIPELINE_COMPILE_REQUIRED:
				return "VK_PIPELINE_COMPILE_REQUIRED_EXT";

			default:
				{
				// Print the value into a static buffer - this is not thread safe but that shouldn't matter
					static char8[24] buf = .();
				//snprintf(buf, sizeof(buf), "Unknown (%d)", result);
					String msg = scope .();
					msg.AppendF("Unknown ({})", result);
					Internal.MemCpy(&buf, msg.Ptr, msg.Length);
					buf[msg.Length] = '\0';
					return &buf;
				}
			}
		}

		public static VkImageType textureDimensionToImageType(TextureDimension dimension)
		{
			switch (dimension)
			{
			case TextureDimension.Texture1D: fallthrough;
			case TextureDimension.Texture1DArray:
				return VkImageType.e1d;

			case TextureDimension.Texture2D: fallthrough;
			case TextureDimension.Texture2DArray: fallthrough;
			case TextureDimension.TextureCube: fallthrough;
			case TextureDimension.TextureCubeArray: fallthrough;
			case TextureDimension.Texture2DMS: fallthrough;
			case TextureDimension.Texture2DMSArray:
				return VkImageType.e2d;

			case TextureDimension.Texture3D:
				return VkImageType.e3d;

			case TextureDimension.Unknown: fallthrough;
			default:
				utils.InvalidEnum();
				return VkImageType.e2d;
			}
		}


		public static VkImageViewType textureDimensionToImageViewType(TextureDimension dimension)
		{
			switch (dimension)
			{
			case TextureDimension.Texture1D:
				return VkImageViewType.e1d;

			case TextureDimension.Texture1DArray:
				return VkImageViewType.e1dArray;

			case TextureDimension.Texture2D: fallthrough;
			case TextureDimension.Texture2DMS:
				return VkImageViewType.e2d;

			case TextureDimension.Texture2DArray: fallthrough;
			case TextureDimension.Texture2DMSArray:
				return VkImageViewType.e2dArray;

			case TextureDimension.TextureCube:
				return VkImageViewType.eCube;

			case TextureDimension.TextureCubeArray:
				return VkImageViewType.eCubeArray;

			case TextureDimension.Texture3D:
				return VkImageViewType.e3d;

			case TextureDimension.Unknown: fallthrough;
			default:
				utils.InvalidEnum();
				return VkImageViewType.e2d;
			}
		}

		public static VkExtent3D pickImageExtent(TextureDesc d)
		{
			return VkExtent3D() { width = d.width, height = d.height, depth = d.depth };
		}

		static uint32 pickImageLayers(TextureDesc d)
		{
			return d.arraySize;
		}

		public static VkImageUsageFlags pickImageUsage(TextureDesc d)
		{
			readonly ref FormatInfo formatInfo = ref getFormatInfo(d.format);

			// xxxnsubtil: may want to consider exposing this through nvrhi instead
			VkImageUsageFlags ret = VkImageUsageFlags.eTransferSrcBit |
				VkImageUsageFlags.eTransferDstBit |
				VkImageUsageFlags.eSampledBit;

			if (d.isRenderTarget)
			{
				if (formatInfo.hasDepth || formatInfo.hasStencil)
				{
					ret |= VkImageUsageFlags.eDepthStencilAttachmentBit;
				} else
				{
					ret |= VkImageUsageFlags.eColorAttachmentBit;
				}
			}

			if (d.isUAV)
				ret |= VkImageUsageFlags.eStorageBit;

			if (d.isShadingRateSurface)
				ret |= VkImageUsageFlags.eFragmentShadingRateAttachmentBitKHR;

			return ret;
		}

		public static VkSampleCountFlags pickImageSampleCount(TextureDesc d)
		{
			switch (d.sampleCount)
			{
			case 1:
				return VkSampleCountFlags.e1Bit;

			case 2:
				return VkSampleCountFlags.e2Bit;

			case 4:
				return VkSampleCountFlags.e4Bit;

			case 8:
				return VkSampleCountFlags.e8Bit;

			case 16:
				return VkSampleCountFlags.e16Bit;

			case 32:
				return VkSampleCountFlags.e32Bit;

			case 64:
				return VkSampleCountFlags.e64Bit;

			default:
				utils.InvalidEnum();
				return VkSampleCountFlags.e1Bit;
			}
		}

		// infer aspect flags for a given image format
		public static VkImageAspectFlags guessImageAspectFlags(VkFormat format)
		{
			switch (format) // NOLINT(clang-diagnostic-switch-enum)
			{
			case VkFormat.eD16Unorm: fallthrough;
			case VkFormat.eX8D24UnormPacK32: fallthrough;
			case VkFormat.eD32Sfloat:
				return VkImageAspectFlags.eDepthBit;

			case VkFormat.eS8Uint:
				return VkImageAspectFlags.eStencilBit;

			case VkFormat.eD16UnormS8Uint: fallthrough;
			case VkFormat.eD24UnormS8Uint: fallthrough;
			case VkFormat.eD32SfloatS8Uint:
				return VkImageAspectFlags.eDepthBit | VkImageAspectFlags.eStencilBit;

			default:
				return VkImageAspectFlags.eColorBit;
			}
		}

		// a subresource usually shouldn't have both stencil and depth aspect flag bits set; this enforces that depending on viewType param
		public static VkImageAspectFlags guessSubresourceImageAspectFlags(VkFormat format, TextureVK.TextureSubresourceViewType viewType)
		{
			VkImageAspectFlags flags = guessImageAspectFlags(format);
			if ((flags & (VkImageAspectFlags.eDepthBit | VkImageAspectFlags.eStencilBit))
				== (VkImageAspectFlags.eDepthBit | VkImageAspectFlags.eStencilBit))
			{
				if (viewType == TextureVK.TextureSubresourceViewType.DepthOnly)
				{
					flags = flags & (~VkImageAspectFlags.eStencilBit);
				}
				else if (viewType == TextureVK.TextureSubresourceViewType.StencilOnly)
				{
					flags = flags & (~VkImageAspectFlags.eDepthBit);
				}
			}
			return flags;
		}

		public static VkImageCreateFlags pickImageFlags(TextureDesc d)
		{
			switch (d.dimension)
			{
			case TextureDimension.TextureCube: fallthrough;
			case TextureDimension.TextureCubeArray:
				return VkImageCreateFlags.eCubeCompatibleBit;

			case TextureDimension.Texture2DArray: fallthrough;
			case TextureDimension.Texture2DMSArray: fallthrough;
			case TextureDimension.Texture1DArray: fallthrough;
			case TextureDimension.Texture1D: fallthrough;
			case TextureDimension.Texture2D: fallthrough;
			case TextureDimension.Texture3D: fallthrough;
			case TextureDimension.Texture2DMS:
				return (VkImageCreateFlags)0;

			case TextureDimension.Unknown: fallthrough;
			default:
				utils.InvalidEnum();
				return (VkImageCreateFlags)0;
			}
		}

		// fills out all info fields in Texture based on a TextureDesc
		public static void fillTextureInfo(TextureVK texture, TextureDesc desc)
		{
			texture.desc = desc;

			VkImageType type = textureDimensionToImageType(desc.dimension);
			VkExtent3D extent = pickImageExtent(desc);
			uint32 numLayers = pickImageLayers(desc);
			VkFormat format = (VkFormat)convertFormat(desc.format);
			VkImageUsageFlags usage = pickImageUsage(desc);
			VkSampleCountFlags sampleCount = pickImageSampleCount(desc);
			VkImageCreateFlags flags = pickImageFlags(desc);

			texture.imageInfo = VkImageCreateInfo()
				.setImageType(type)
				.setExtent(extent)
				.setMipLevels(desc.mipLevels)
				.setArrayLayers(numLayers)
				.setFormat(format)
				.setInitialLayout(VkImageLayout.eUndefined)
				.setUsage(usage)
				.setSharingMode(VkSharingMode.eExclusive)
				.setSamples(sampleCount)
				.setFlags(flags);
		}

		public static int64 alignBufferOffset(int64 off)
		{
			const int64 bufferAlignmentBytes = 4;
			return ((off + (bufferAlignmentBytes - 1)) / bufferAlignmentBytes) * bufferAlignmentBytes;
		}

		public static VkDeviceOrHostAddressConstKHR getBufferAddress(IBuffer _buffer, uint64 offset)
		{
			if (_buffer == null)
				return VkDeviceOrHostAddressConstKHR();

			BufferVK buffer = checked_cast<BufferVK, IBuffer>(_buffer);

			return VkDeviceOrHostAddressConstKHR().setDeviceAddress(buffer.deviceAddress + int(offset));
		}

		public static void convertBottomLevelGeometry(nvrhi.rt.GeometryDesc src, ref VkAccelerationStructureGeometryKHR dst,
			ref uint32 maxPrimitiveCount, VkAccelerationStructureBuildRangeInfoKHR* pRange, VulkanContext* context)
		{
			switch (src.geometryType)
			{
			case nvrhi.rt.GeometryType.Triangles:
				{
					readonly ref nvrhi.rt.GeometryTriangles srct = ref src.geometryData.triangles;
					VkAccelerationStructureGeometryTrianglesDataKHR dstt = .();

					switch (srct.indexFormat) // NOLINT(clang-diagnostic-switch-enum)
					{
					case Format.R8_UINT:
						dstt.setIndexType(VkIndexType.eUint8Ext);
						break;

					case Format.R16_UINT:
						dstt.setIndexType(VkIndexType.eUint16);
						break;

					case Format.R32_UINT:
						dstt.setIndexType(VkIndexType.eUint32);
						break;

					case Format.UNKNOWN:
						dstt.setIndexType(VkIndexType.eNoneKHR);
						break;

					default:
						context.error("Unsupported ray tracing geometry index type");
						dstt.setIndexType(VkIndexType.eNoneKHR);
						break;
					}

					dstt.setVertexFormat(convertFormat(srct.vertexFormat));
					dstt.setVertexData(getBufferAddress(srct.vertexBuffer, srct.vertexOffset));
					dstt.setVertexStride(srct.vertexStride);
					dstt.setMaxVertex(Math.Max(srct.vertexCount, 1) - 1);
					dstt.setIndexData(getBufferAddress(srct.indexBuffer, srct.indexOffset));

					if (src.useTransform)
					{
						var src;
						dstt.setTransformData(VkDeviceOrHostAddressConstKHR().setHostAddress(&src.transform));
					}

					maxPrimitiveCount = (srct.indexFormat == Format.UNKNOWN)
						? (srct.vertexCount / 3)
						: (srct.indexCount / 3);

					dst.setGeometryType(VkGeometryTypeKHR.eTrianglesKHR);
					dst.geometry.setTriangles(dstt);

					break;
				}
			case nvrhi.rt.GeometryType.AABBs:
				{
					readonly ref nvrhi.rt.GeometryAABBs srca = ref src.geometryData.aabbs;
					VkAccelerationStructureGeometryAabbsDataKHR dsta = .();

					dsta.setData(getBufferAddress(srca.buffer, srca.offset));
					dsta.setStride(srca.stride);

					maxPrimitiveCount = srca.count;

					dst.setGeometryType(VkGeometryTypeKHR.eAabbsKHR);
					dst.geometry.setAabbs(dsta);

					break;
				}
			}

			if (pRange != null)
			{
				pRange.setPrimitiveCount(maxPrimitiveCount);
			}

			VkGeometryFlagsKHR geometryFlags = (VkGeometryFlagsKHR)0;
			if ((src.flags & nvrhi.rt.GeometryFlags.Opaque) != 0)
				geometryFlags |= VkGeometryFlagsKHR.eOpaqueBitKHR;
			if ((src.flags & nvrhi.rt.GeometryFlags.NoDuplicateAnyHitInvocation) != 0)
				geometryFlags |= VkGeometryFlagsKHR.eNoDuplicateAnyHitInvocationBitKHR;
			dst.setFlags(geometryFlags);
		}

		public static void computeMipLevelInformation(TextureDesc desc, uint32 mipLevel, uint32* widthOut, uint32* heightOut, uint32* depthOut)
		{
			uint32 width = Math.Max(desc.width >> mipLevel, uint32(1));
			uint32 height = Math.Max(desc.height >> mipLevel, uint32(1));
			uint32 depth = Math.Max(desc.depth >> mipLevel, uint32(1));

			if (widthOut != null)
				*widthOut = width;
			if (heightOut != null)
				*heightOut = height;
			if (depthOut != null)
				*depthOut = depth;
		}

		public static VkBorderColor pickSamplerBorderColor(SamplerDesc d)
		{
			if (d.borderColor.r == 0.f && d.borderColor.g == 0.f && d.borderColor.b == 0.f)
			{
				if (d.borderColor.a == 0.f)
				{
					return VkBorderColor.eFloatTransparentBlack;
				}

				if (d.borderColor.a == 1.f)
				{
					return VkBorderColor.eFloatOpaqueBlack;
				}
			}

			if (d.borderColor.r == 1.f && d.borderColor.g == 1.f && d.borderColor.b == 1.f)
			{
				if (d.borderColor.a == 1.f)
				{
					return VkBorderColor.eFloatOpaqueWhite;
				}
			}

			utils.NotSupported();
			return VkBorderColor.eFloatOpaqueBlack;
		}

		public static TextureVK.TextureSubresourceViewType getTextureViewType(Format bindingFormat, Format textureFormat)
		{
			Format format = (bindingFormat == Format.UNKNOWN) ? textureFormat : bindingFormat;

			readonly ref FormatInfo formatInfo = ref getFormatInfo(format);

			if (formatInfo.hasDepth)
				return TextureVK.TextureSubresourceViewType.DepthOnly;
			else if (formatInfo.hasStencil)
				return TextureVK.TextureSubresourceViewType.StencilOnly;
			else
				return TextureVK.TextureSubresourceViewType.AllAspects;
		}

		public static void registerShaderModule(
			IShader _shader,
			Dictionary<ShaderVK, uint32> shaderStageIndices,
			ref int numShaders,
			ref int numShadersWithSpecializations,
			ref int numSpecializationConstants)
		{
			if (_shader == null)
				return;

			ShaderVK shader = checked_cast<ShaderVK, IShader>(_shader);
			if (!shaderStageIndices.ContainsKey(shader))
			{
				countSpecializationConstants(shader, ref numShaders, ref numShadersWithSpecializations, ref numSpecializationConstants);
				shaderStageIndices[shader] = uint32(shaderStageIndices.Count);
			}
		}

		public static TextureDimension getDimensionForFramebuffer(TextureDimension dimension, bool isArray)
		{
			var dimension;
			// Can't render into cubes and 3D textures directly, convert them to 2D arrays
			if (dimension == TextureDimension.TextureCube || dimension == TextureDimension.TextureCubeArray || dimension == TextureDimension.Texture3D)
				dimension = TextureDimension.Texture2DArray;

			if (!isArray)
			{
				// Demote arrays to single textures if we just need one layer
				switch (dimension) // NOLINT(clang-diagnostic-switch-enum)
				{
				case TextureDimension.Texture1DArray:
					dimension = TextureDimension.Texture1D;
					break;
				case TextureDimension.Texture2DArray:
					dimension = TextureDimension.Texture2D;
					break;
				case TextureDimension.Texture2DMSArray:
					dimension = TextureDimension.Texture2DMS;
					break;
				default:
					break;
				}
			}

			return dimension;
		}

		public static VkViewport VKViewportWithDXCoords(Viewport v)
		{
			// requires VK_KHR_maintenance1 which allows negative-height to indicate an inverted coord space to match DX
			return VkViewport()
				{
					x = v.minX,
					y = v.maxY,
					width = v.maxX - v.minX,
					height = -(v.maxY - v.minY),
					minDepth = v.minZ,
					maxDepth = v.maxZ
				};
		}

		public static uint64 getQueueLastFinishedID(DeviceVK device, CommandQueue queueIndex)
		{
			QueueVK queue = device.getQueue(queueIndex);
			if (queue != null)
				return queue.getLastFinishedID();
			return 0;
		}
	}
}