using Bulkan;
using System.Collections;
using System;
namespace nvrhi.vulkan
{
	struct ResourceStateMapping : this(ResourceStates nvrhiState, VkPipelineStageFlags stageFlags, VkAccessFlags accessMask, VkImageLayout imageLayout)
	{
	}

	public static{
		public static VkSamplerAddressMode convertSamplerAddressMode(SamplerAddressMode mode)
		{
		    switch(mode)
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
		    if ((shaderType & ShaderType.Miss) != 0)           result |= uint32(VkShaderStageFlags.eMissBitKHR);   // same etc...
		    if ((shaderType & ShaderType.ClosestHit) != 0)     result |= uint32(VkShaderStageFlags.eClosestHitBitKHR);
		    if ((shaderType & ShaderType.AnyHit) != 0)         result |= uint32(VkShaderStageFlags.eAnyHitBitKHR);
		    if ((shaderType & ShaderType.Intersection) != 0)   result |= uint32(VkShaderStageFlags.eIntersectionBitKHR);

		    return (VkShaderStageFlags)result;
		}

			public const ResourceStateMapping[?] g_ResourceStateMap = 
				.(
				    .( ResourceStates.Common,
				        VkPipelineStageFlags.eTopOfPipeBit,
				        VkAccessFlags(),
				        VkImageLayout.eUndefined ),
				    .( ResourceStates.ConstantBuffer,
				        VkPipelineStageFlags.eAllCommandsBit,
				        VkAccessFlags.eUniformReadBit,
				        VkImageLayout.eUndefined ),
				    .( ResourceStates.VertexBuffer,
				        VkPipelineStageFlags.eVertexInputBit,
				        VkAccessFlags.eVertexAttributeReadBit,
				        VkImageLayout.eUndefined ),
				    .( ResourceStates.IndexBuffer,
				        VkPipelineStageFlags.eVertexInputBit,
				        VkAccessFlags.eIndexReadBit,
				        VkImageLayout.eUndefined ),
				    .( ResourceStates.IndirectArgument,
				        VkPipelineStageFlags.eDrawIndirectBit,
				        VkAccessFlags.eIndirectCommandReadBit,
				        VkImageLayout.eUndefined ),
				    .( ResourceStates.ShaderResource,
				        VkPipelineStageFlags.eAllCommandsBit,
				        VkAccessFlags.eShaderReadBit,
				        VkImageLayout.eShaderReadOnlyOptimal ),
				    .( ResourceStates.UnorderedAccess,
				        VkPipelineStageFlags.eAllCommandsBit,
				        VkAccessFlags.eShaderReadBit | VkAccessFlags.eShaderWriteBit,
				        VkImageLayout.eGeneral ),
				    .( ResourceStates.RenderTarget,
				        VkPipelineStageFlags.eColorAttachmentOutputBit,
				        VkAccessFlags.eColorAttachmentReadBit | VkAccessFlags.eColorAttachmentWriteBit,
				        VkImageLayout.eColorAttachmentOptimal ),
				    .( ResourceStates.DepthWrite,
				        VkPipelineStageFlags.eEarlyFragmentTestsBit | VkPipelineStageFlags.eLateFragmentTestsBit,
				        VkAccessFlags.eDepthStencilAttachmentReadBit | VkAccessFlags.eDepthStencilAttachmentWriteBit,
				        VkImageLayout.eDepthStencilAttachmentOptimal ),
				    .( ResourceStates.DepthRead,
				        VkPipelineStageFlags.eEarlyFragmentTestsBit | VkPipelineStageFlags.eLateFragmentTestsBit,
				        VkAccessFlags.eDepthStencilAttachmentReadBit,
				        VkImageLayout.eDepthStencilAttachmentOptimal ),
				    .( ResourceStates.StreamOut,
				        VkPipelineStageFlags.eTransformFeedbackBitEXT,
				        VkAccessFlags.eTransformFeedbackWriteBitEXT,
				        VkImageLayout.eUndefined ),
				    .( ResourceStates.CopyDest,
				        VkPipelineStageFlags.eTransferBit,
				        VkAccessFlags.eTransferWriteBit,
				        VkImageLayout.eTransferDstOptimal ),
				    .( ResourceStates.CopySource,
				        VkPipelineStageFlags.eTransferBit,
				        VkAccessFlags.eTransferReadBit,
				        VkImageLayout.eTransferSrcOptimal ),
				    .( ResourceStates.ResolveDest,
				        VkPipelineStageFlags.eTransferBit,
				        VkAccessFlags.eTransferWriteBit,
				        VkImageLayout.eTransferDstOptimal ),
				    .( ResourceStates.ResolveSource,
				        VkPipelineStageFlags.eTransferBit,
				        VkAccessFlags.eTransferReadBit,
				        VkImageLayout.eTransferSrcOptimal ),
				    .( ResourceStates.Present,
				        VkPipelineStageFlags.eAllCommandsBit,
				        VkAccessFlags.eMemoryReadBit,
				        VkImageLayout.ePresentSrcKHR ),
				    .( ResourceStates.AccelStructRead,
				        VkPipelineStageFlags.eRayTracingShaderBitKHR | VkPipelineStageFlags.eComputeShaderBit,
				        VkAccessFlags.eAccelerationStructureReadBitKHR,
				        VkImageLayout.eUndefined ),
				    .( ResourceStates.AccelStructWrite,
				        VkPipelineStageFlags.eAccelerationStructureBuildBitKHR,
				        VkAccessFlags.eAccelerationStructureWriteBitKHR,
				        VkImageLayout.eUndefined ),
				    .( ResourceStates.AccelStructBuildInput,
				        VkPipelineStageFlags.eAccelerationStructureBuildBitKHR,
				        VkAccessFlags.eAccelerationStructureReadBitKHR,
				        VkImageLayout.eUndefined ),
				    .( ResourceStates.AccelStructBuildBlas,
				        VkPipelineStageFlags.eAccelerationStructureBuildBitKHR,
				        VkAccessFlags.eAccelerationStructureReadBitKHR,
				        VkImageLayout.eUndefined ),
				    .( ResourceStates.ShadingRateSurface,
				        VkPipelineStageFlags.eFragmentShadingRateAttachmentBitKHR,
				        VkAccessFlags.eFragmentShadingRateAttachmentReadBitKHR,
				        VkImageLayout.eFragmentShadingRateAttachmentOptimalKHR ),
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
		    switch(topology)
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
		    switch(mode)
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
		    switch(mode)
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
		    switch(op)
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
		    switch(op)
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
		    switch(value)
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
		    switch(op)
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
		    static_assert(uint32(nvrhi.rt.InstanceFlags.TriangleCullDisable) == uint32(VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR));
		    static_assert(uint32(nvrhi.rt.InstanceFlags.TriangleFrontCounterclockwise) == uint32(VK_GEOMETRY_INSTANCE_TRIANGLE_FRONT_COUNTERCLOCKWISE_BIT_KHR));
		    static_assert(uint32(nvrhi.rt.InstanceFlags.ForceOpaque) == uint32(VK_GEOMETRY_INSTANCE_FORCE_OPAQUE_BIT_KHR));
		    static_assert(uint32(nvrhi.rt.InstanceFlags.ForceNonOpaque) == uint32(VK_GEOMETRY_INSTANCE_FORCE_NO_OPAQUE_BIT_KHR));

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
		    Shader shader,
		    ref int numShaders,
		    ref int numShadersWithSpecializations,
		    ref int numSpecializationConstants)
		{
		    if (!shader)
		        return;

		    numShaders += 1;

		    if (shader.specializationConstants.empty())
		        return;

		    numShadersWithSpecializations += 1;
		    numSpecializationConstants += shader.specializationConstants.size();
		}

		public static VkPipelineShaderStageCreateInfo makeShaderStageCreateInfo(
		    Shader shader,
		    List<VkSpecializationInfo> specInfos,
		    List<VkSpecializationMapEntry> specMapEntries,
		    List<uint32> specData)
		{
		    var shaderStageCreateInfo = VkPipelineShaderStageCreateInfo()
		        .setStage(shader.stageFlagBits)
		        .setModule(shader.shaderModule)
		        .setPName(shader.desc.entryName.c_str());

		    if (!shader.specializationConstants.empty())
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
		            .setMapEntryCount((uint32)(shader.specializationConstants.size()))
		            .setPData(specData.Ptr + specData.Count)
		            .setDataSize(shader.specializationConstants.size() * sizeof(uint32));

		        int dataOffset = 0;
		        for (readonly ref var constant in ref shader.specializationConstants)
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

	}
}