using System;
using System.Collections;
using System.Threading;
using nvrhi.rt;
namespace nvrhi.utils
{
	public static
	{
		public static BlendState.RenderTarget CreateAddBlendState(
			BlendFactor srcBlend,
			BlendFactor dstBlend)
		{
			BlendState.RenderTarget target = .();
			target.blendEnable = true;
			target.blendOp = BlendOp.Add;
			target.srcBlend = srcBlend;
			target.destBlend = dstBlend;
			target.srcBlendAlpha = BlendFactor.Zero;
			target.destBlendAlpha = BlendFactor.One;
			return target;
		}

		public static BufferDesc CreateStaticConstantBufferDesc(
			uint32 byteSize,
			char8* debugName)
		{
			BufferDesc constantBufferDesc = .();
			constantBufferDesc.byteSize = byteSize;
			constantBufferDesc.debugName = new String(debugName); // todo: sed
			constantBufferDesc.isConstantBuffer = true;
			constantBufferDesc.isVolatile = false;
			return constantBufferDesc;
		}

		public static BufferDesc CreateVolatileConstantBufferDesc(
			uint32 byteSize,
			char8* debugName,
			uint32 maxVersions)
		{
			BufferDesc constantBufferDesc = .();
			constantBufferDesc.byteSize = byteSize;
			constantBufferDesc.debugName = new String(debugName); // todo: sed
			constantBufferDesc.isConstantBuffer = true;
			constantBufferDesc.isVolatile = true;
			constantBufferDesc.maxVersions = maxVersions;
			return constantBufferDesc;
		}

		public static bool CreateBindingSetAndLayout(
			nvrhi.IDevice device,
			nvrhi.ShaderType visibility,
			uint32 registerSpace,
			nvrhi.BindingSetDesc bindingSetDesc,
			ref nvrhi.BindingLayoutHandle bindingLayout,
			ref nvrhi.BindingSetHandle bindingSet)
		{
			delegate void(BindingSetItemArray setDesc, ref BindingLayoutItemArray layoutDesc) convertSetToLayout = scope  (setDesc, layoutDesc) =>
				{
					for (ref BindingSetItem item in ref setDesc)
					{
						BindingLayoutItem layoutItem = .();
						layoutItem.slot = item.slot;
						layoutItem.type = item.type;
						if (item.type == ResourceType.PushConstants)
							layoutItem.size = (.)uint32(item.range.byteSize);
						layoutDesc.PushBack(layoutItem);
					}
				};

			if (bindingLayout == null)
			{
				nvrhi.BindingLayoutDesc bindingLayoutDesc = .();
				bindingLayoutDesc.visibility = visibility;
				bindingLayoutDesc.registerSpace = registerSpace;
				convertSetToLayout(bindingSetDesc.bindings, ref bindingLayoutDesc.bindings);

				bindingLayout = device.createBindingLayout(bindingLayoutDesc);

				if (bindingLayout == null)
					return false;
			}

			if (bindingSet == null)
			{
				bindingSet = device.createBindingSet(bindingSetDesc, bindingLayout);

				if (bindingSet == null)
					return false;
			}

			return true;
		}

		public static void ClearColorAttachment(ICommandList commandList, IFramebuffer framebuffer, uint32 attachmentIndex, Color color)
		{
			readonly /*ref*/ FramebufferAttachment att = /*ref*/ framebuffer.getDesc().colorAttachments[attachmentIndex];
			if (att.texture != null)
			{
				commandList.clearTextureFloat(att.texture, att.subresources, color);
			}
		}

		public static void ClearDepthStencilAttachment(ICommandList commandList, IFramebuffer framebuffer, float depth, uint32 stencil)
		{
			readonly ref FramebufferAttachment att = ref framebuffer.getDesc().depthAttachment;
			if (att.texture != null)
			{
				commandList.clearTextureFloat(att.texture, att.subresources, Color(depth, float(stencil), 0.f, 0.f));
			}
		}

		public static void BuildBottomLevelAccelStruct(ICommandList commandList, nvrhi.rt.IAccelStruct @as, nvrhi.rt.AccelStructDesc desc)
		{
			commandList.buildBottomLevelAccelStruct(@as,
				desc.bottomLevelGeometries.Ptr,
				desc.bottomLevelGeometries.Count,
				desc.buildFlags);
		}

		public static void TextureUavBarrier(ICommandList commandList, ITexture texture)
		{
			commandList.setTextureState(texture, AllSubresources, ResourceStates.UnorderedAccess);
		}

		public static void BufferUavBarrier(ICommandList commandList, IBuffer buffer)
		{
			commandList.setBufferState(buffer, ResourceStates.UnorderedAccess);
		}

		public static Format ChooseFormat(IDevice device, nvrhi.FormatSupport requiredFeatures, nvrhi.Format* requestedFormats, int requestedFormatCount)
		{
			Runtime.Assert(device != null);
			Runtime.Assert(requestedFormats != null || requestedFormatCount == 0);

			for (int i = 0; i < requestedFormatCount; i++)
			{
				if ((device.queryFormatSupport(requestedFormats[i]) & requiredFeatures) == requiredFeatures)
					return requestedFormats[i];
			}

			return Format.UNKNOWN;
		}

		public static char8* GraphicsAPIToString(GraphicsAPI api)
		{
			switch (api)
			{
			case GraphicsAPI.D3D11:  return "D3D11";
			case GraphicsAPI.D3D12:  return "D3D12";
			case GraphicsAPI.VULKAN: return "Vulkan";
			default:                         return "<UNKNOWN>";
			}
		}

		public static char8* TextureDimensionToString(TextureDimension dimension)
		{
			switch (dimension)
			{
			case TextureDimension.Texture1D:           return "Texture1D";
			case TextureDimension.Texture1DArray:      return "Texture1DArray";
			case TextureDimension.Texture2D:           return "Texture2D";
			case TextureDimension.Texture2DArray:      return "Texture2DArray";
			case TextureDimension.TextureCube:         return "TextureCube";
			case TextureDimension.TextureCubeArray:    return "TextureCubeArray";
			case TextureDimension.Texture2DMS:         return "Texture2DMS";
			case TextureDimension.Texture2DMSArray:    return "Texture2DMSArray";
			case TextureDimension.Texture3D:           return "Texture3D";
			case TextureDimension.Unknown:             return "Unknown";
			default:                                    return "<INVALID>";
			}
		}

		public static char8* DebugNameToString(String debugName)
		{
			return String.IsNullOrEmpty(debugName) ? "<UNNAMED>" : debugName.CStr();
		}


		public static char8* ShaderStageToString(ShaderType stage)
		{
			switch (stage)
			{
			case ShaderType.None:          return "None";
			case ShaderType.Compute:       return "Compute";
			case ShaderType.Vertex:        return "Vertex";
			case ShaderType.Hull:          return "Hull";
			case ShaderType.Domain:        return "Domain";
			case ShaderType.Geometry:      return "Geometry";
			case ShaderType.Pixel:         return "Pixel";
			case ShaderType.Amplification: return "Amplification";
			case ShaderType.Mesh:          return "Mesh";
			case ShaderType.AllGraphics:   return "AllGraphics";
			case ShaderType.RayGeneration: return "RayGeneration";
			case ShaderType.AnyHit:        return "AnyHit";
			case ShaderType.ClosestHit:    return "ClosestHit";
			case ShaderType.Miss:          return "Miss";
			case ShaderType.Intersection:  return "Intersection";
			case ShaderType.Callable:      return "Callable";
			case ShaderType.AllRayTracing: return "AllRayTracing";
			case ShaderType.All:           return "All";
			default:                        return "<INVALID>";
			}
		}

		public static char8* ResourceTypeToString(ResourceType type)
		{
			switch (type)
			{
			case ResourceType.None:                    return "None";
			case ResourceType.Texture_SRV:             return "Texture_SRV";
			case ResourceType.Texture_UAV:             return "Texture_UAV";
			case ResourceType.TypedBuffer_SRV:         return "Buffer_SRV";
			case ResourceType.TypedBuffer_UAV:         return "Buffer_UAV";
			case ResourceType.StructuredBuffer_SRV:    return "StructuredBuffer_SRV";
			case ResourceType.StructuredBuffer_UAV:    return "StructuredBuffer_UAV";
			case ResourceType.RawBuffer_SRV:           return "RawBuffer_SRV";
			case ResourceType.RawBuffer_UAV:           return "RawBuffer_UAV";
			case ResourceType.ConstantBuffer:          return "ConstantBuffer";
			case ResourceType.VolatileConstantBuffer:  return "VolatileConstantBuffer";
			case ResourceType.Sampler:                 return "Sampler";
			case ResourceType.RayTracingAccelStruct:   return "RayTracingAccelStruct";
			case ResourceType.PushConstants:           return "PushConstants";
			case ResourceType.Count: fallthrough;
			default:                                    return "<INVALID>";
			}
		}

		public static char8* FormatToString(Format format)
		{
			return getFormatInfo(format).name;
		}

		public static char8* CommandQueueToString(CommandQueue queue)
		{
			switch (queue)
			{
			case CommandQueue.Graphics: return "Graphics";
			case CommandQueue.Compute:  return "Compute";
			case CommandQueue.Copy:     return "Copy";
			case CommandQueue.Count: fallthrough;
			default:
				return "<INVALID>";
			}
		}

		public static void GenerateHeapDebugName(HeapDesc desc, String message)
		{
			message.Append("Unnamed ");

			switch (desc.type)
			{
			case HeapType.DeviceLocal:
				message.Append("DeviceLocal");
				break;
			case HeapType.Upload:
				message.Append("Upload");
				break;
			case HeapType.Readback:
				message.Append("Readback");
				break;
			default:
				message.Append("Invalid-Type");
				break;
			}

			message.AppendF(" Heap ({0}) bytes", desc.capacity);
		}

		public static void GenerateTextureDebugName(TextureDesc desc, String message)
		{
			message.AppendF("Unnamed ", TextureDimensionToString(desc.dimension));
			message.AppendF(" (", getFormatInfo(desc.format).name);
			message.AppendF(", Width = {}", desc.width);

			if (desc.dimension >= TextureDimension.Texture2D)
				message.AppendF(", Height = {}", desc.height);

			if (desc.dimension == TextureDimension.Texture3D)
				message.AppendF(", Depth = {}", desc.depth);

			if (desc.dimension == TextureDimension.Texture1DArray ||
				desc.dimension == TextureDimension.Texture2DArray ||
				desc.dimension == TextureDimension.TextureCubeArray ||
				desc.dimension == TextureDimension.Texture2DMSArray)
				message.AppendF(", ArraySize = {}", desc.arraySize);

			if (desc.dimension == TextureDimension.Texture1D ||
				desc.dimension == TextureDimension.Texture1DArray ||
				desc.dimension == TextureDimension.Texture2D ||
				desc.dimension == TextureDimension.Texture2DArray ||
				desc.dimension == TextureDimension.TextureCube ||
				desc.dimension == TextureDimension.TextureCubeArray)
				message.AppendF(", MipLevels = {}", desc.mipLevels);

			if (desc.dimension == TextureDimension.Texture2DMS ||
				desc.dimension == TextureDimension.Texture2DMSArray)
				message.AppendF(", SampleCount = {}, SampleQuality = {}", desc.sampleCount,  desc.sampleQuality);

			if (desc.isRenderTarget) message.Append(", IsRenderTarget");
			if (desc.isUAV)          message.Append(", IsUAV");
			if (desc.isTypeless)     message.Append(", IsTypeless");

			message.Append(")");
		}

		public static void GenerateBufferDebugName(BufferDesc desc, String message)
		{
			message.AppendF("Unnamed Buffer (ByteSize = {}", desc.byteSize);

			if (desc.format != Format.UNKNOWN)
				message.AppendF(", Format = {}", getFormatInfo(desc.format).name);

			if (desc.structStride > 0)
				message.AppendF(", StructStride = {}", desc.structStride);

			if (desc.isVolatile)
				message.AppendF(", IsVolatile, MaxVersions = {}", desc.maxVersions);

			if (desc.canHaveUAVs) message.Append(", CanHaveUAVs");
			if (desc.canHaveTypedViews) message.Append(", CanHaveTypedViews");
			if (desc.canHaveRawViews) message.Append(", CanHaveRawViews");
			if (desc.isVertexBuffer) message.Append(", IsVertexBuffer");
			if (desc.isIndexBuffer) message.Append(", IsIndexBuffer");
			if (desc.isConstantBuffer) message.Append(", IsConstantBuffer");
			if (desc.isDrawIndirectArgs) message.Append(", IsDrawIndirectArgs");
			if (desc.isAccelStructBuildInput) message.Append(", IsAccelStructBuildInput");
			if (desc.isAccelStructStorage) message.Append(", IsAccelStructStorage");

			message.Append(")");
		}

		public static void NotImplemented()
		{
			Runtime.Assert(false, "Not Implemented"); // NOLINT(clang-diagnostic-string-conversion)
		}

		public static void NotSupported()
		{
			Runtime.Assert(false, "Not Supported"); // NOLINT(clang-diagnostic-string-conversion)
		}

		public static void InvalidEnum()
		{
			Runtime.Assert(false, "Invalid Enumeration Value"); // NOLINT(clang-diagnostic-string-conversion)
		}

	}

	class BitSetAllocator
	{
		public this(int capacity, bool multithreaded)
		{
			m_MultiThreaded = multithreaded;
			m_Allocated.Resize(capacity);
		}

		public int32 allocate()
		{
			if (m_MultiThreaded)
				m_Mutex.Enter();

			int32 result = -1;

			int32 capacity = (int32)m_Allocated.Count;
			for (int32 i = 0; i < capacity; i++)
			{
				int32 ii = (m_NextAvailable + i) % capacity;

				if (!m_Allocated[ii])
				{
					result = ii;
					m_NextAvailable = (ii + 1) % capacity;
					m_Allocated[ii] = true;
					break;
				}
			}

			if (m_MultiThreaded)
				m_Mutex.Exit();

			return result;
		}

		public void release(int32 index)
		{
			if (index >= 0 && index < (int32)m_Allocated.Count)
			{
				if (m_MultiThreaded)
					m_Mutex.Enter();

				m_Allocated[index] = false;
				m_NextAvailable = Math.Min(m_NextAvailable, index);

				if (m_MultiThreaded)
					m_Mutex.Exit();
			}
		}

		[NoDiscard] public  int getCapacity() { return m_Allocated.Count; }

		private int32 m_NextAvailable = 0;
		private List<bool> m_Allocated = new .() ~ delete _;
		private bool m_MultiThreaded;
		private Monitor m_Mutex = new .();
	}
}