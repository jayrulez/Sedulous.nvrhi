using System;
using System.Collections;
using System.Threading;
namespace nvrhi.validation
{
	public static
	{
		public static void FillShaderBindingSetFromDesc<DescType>(IMessageCallback messageCallback, DescType desc, ref ShaderBindingSet bindingSet, ref ShaderBindingSet duplicates) where DescType : var
		{
			for ( /*readonly ref*/var item in ref desc)
			{
				switch (item.type)
				{
				case ResourceType.Texture_SRV: fallthrough;
				case ResourceType.TypedBuffer_SRV: fallthrough;
				case ResourceType.StructuredBuffer_SRV: fallthrough;
				case ResourceType.RawBuffer_SRV: fallthrough;
				case ResourceType.RayTracingAccelStruct:
					if (bindingSet.SRV[item.slot])
					{
						duplicates.SRV[item.slot] = true;
					}
					else
					{
						bindingSet.SRV[item.slot] = true;
						bindingSet.rangeSRV.add(item.slot);
					}
					break;

				case ResourceType.Texture_UAV: fallthrough;
				case ResourceType.TypedBuffer_UAV: fallthrough;
				case ResourceType.StructuredBuffer_UAV: fallthrough;
				case ResourceType.RawBuffer_UAV:
					if (bindingSet.UAV[item.slot])
					{
						duplicates.UAV[item.slot] = true;
					}
					else
					{
						bindingSet.UAV[item.slot] = true;
						bindingSet.rangeUAV.add(item.slot);
					}
					break;

				case ResourceType.ConstantBuffer: fallthrough;
				case ResourceType.VolatileConstantBuffer: fallthrough;
				case ResourceType.PushConstants:
					if (bindingSet.CB[item.slot])
					{
						duplicates.CB[item.slot] = true;
					}
					else
					{
						bindingSet.CB[item.slot] = true;

						if (item.type == ResourceType.VolatileConstantBuffer)
							++bindingSet.numVolatileCBs;

						bindingSet.rangeCB.add(item.slot);
					}
					break;

				case ResourceType.Sampler:
					if (bindingSet.Sampler[item.slot])
					{
						duplicates.Sampler[item.slot] = true;
					}
					else
					{
						bindingSet.Sampler[item.slot] = true;
						bindingSet.rangeSampler.add(item.slot);
					}
					break;

				case ResourceType.None: fallthrough;
				case ResourceType.Count: fallthrough;
				default:
					{
						String message = scope $"Invalid layout item type {(int32)item.type}";
						messageCallback.message(MessageSeverity.Error, message);
						break;
					}
				}
			}
		}

		public static ItemType* SelectShaderStage<ItemType, DescType>(DescType desc, nvrhi.ShaderType stage) where ItemType : var where DescType : var
		{
			switch (stage)
			{
			case nvrhi.ShaderType.Vertex: return &desc.VS;
			case nvrhi.ShaderType.Hull: return &desc.HS;
			case nvrhi.ShaderType.Domain: return &desc.DS;
			case nvrhi.ShaderType.Geometry: return &desc.GS;
			case nvrhi.ShaderType.Pixel: return &desc.PS;
			case nvrhi.ShaderType.Compute: return &desc.CS;
			default:
				utils.InvalidEnum();
				return null;
			}
		}

		public static ItemType* SelectGraphicsShaderStage<ItemType, DescType>(DescType desc, ShaderType stage) where ItemType : var where DescType : var
		{
			switch (stage) // NOLINT(clang-diagnostic-switch-enum)
			{
			case nvrhi.ShaderType.Vertex: return &desc.VS;
			case nvrhi.ShaderType.Hull: return &desc.HS;
			case nvrhi.ShaderType.Domain: return &desc.DS;
			case nvrhi.ShaderType.Geometry: return &desc.GS;
			case nvrhi.ShaderType.Pixel: return &desc.PS;
			default:
				utils.InvalidEnum();
				return null;
			}
		}

		public static ItemType* SelectMeshletShaderStage<ItemType, DescType>(DescType desc, nvrhi.ShaderType stage) where DescType : var
		{
			switch (stage) // NOLINT(clang-diagnostic-switch-enum)
			{
			case nvrhi.ShaderType.Amplification: return &desc.AS;
			case nvrhi.ShaderType.Mesh: return &desc.MS;
			case nvrhi.ShaderType.Pixel: return &desc.PS;
			default:
				utils.InvalidEnum();
				return null;
			}
		}

		public const ShaderType[?] g_GraphicsShaderStages = .(
			ShaderType.Vertex,
			ShaderType.Hull,
			ShaderType.Domain,
			ShaderType.Geometry,
			ShaderType.Pixel
			);

		public const ShaderType[?] g_MeshletShaderStages = .(
			ShaderType.Amplification,
			ShaderType.Mesh,
			ShaderType.Pixel
			);
	}

	class DeviceWrapper :  RefCounter<IDevice>
	{
		public this(IDevice device)
		{
			m_Device = device;
			m_MessageCallback = device.getMessageCallback();
		}

		protected DeviceHandle m_Device;
		protected IMessageCallback m_MessageCallback;
		private Monitor m_NumOpenImmediateCommandListsMonitor = new .() ~ delete _;
		private uint32 m_NumOpenImmediateCommandListsInternal = 0;
		protected /*std::atomic<uint32>*/ uint32 m_NumOpenImmediateCommandLists
		{
			get
			{
				using (m_NumOpenImmediateCommandListsMonitor.Enter())
				{
					return m_NumOpenImmediateCommandListsInternal;
				}
			} set
			{
				using (m_NumOpenImmediateCommandListsMonitor.Enter())
				{
					m_NumOpenImmediateCommandListsInternal = value;
				}
			}
		}

		protected void error(String messageText)
		{
			m_MessageCallback.message(MessageSeverity.Error, messageText);
		}

		protected void warning(String messageText)
		{
			m_MessageCallback.message(MessageSeverity.Warning, messageText);
		}

		protected bool validateBindingSetItem(BindingSetItem binding, bool isDescriptorTable, String errorStream)
		{
			switch (binding.type)
			{
			case ResourceType.None:
				if (!isDescriptorTable)
				{
					errorStream.Append("ResourceType.None bindings are not allowed in binding sets.\n");
					return false;
				}
				break;

			case ResourceType.Texture_SRV: fallthrough;
			case ResourceType.Texture_UAV:
				{
					ITexture texture = checked_cast<ITexture, IResource>(binding.resourceHandle);

					if (texture == null)
					{
						errorStream.Append("Null resource bindings are not allowed for textures.\n");
						return false;
					}

					readonly ref TextureDesc desc = ref texture.getDesc();

					TextureSubresourceSet subresources = binding.subresources.resolve(desc, false);
					if (subresources.numArraySlices == 0 || subresources.numMipLevels == 0)
					{
						errorStream.AppendF("The specified subresource set (BaseMipLevel = {}, NumMipLevels = {}, BaseArraySlice = {}, NumArraySlices = {}) does not intersect with the texture being bound ({}, MipLevels = {}, ArraySize = {})\n",
							binding.subresources.baseMipLevel,
							binding.subresources.numMipLevels,
							binding.subresources.baseArraySlice,
							binding.subresources.numArraySlices,
							utils.DebugNameToString(desc.debugName),
							desc.mipLevels,
							desc.arraySize
							);

						return false;
					}

					if ((binding.type == ResourceType.Texture_UAV) && !desc.isUAV)
					{
						errorStream.AppendF("Texture {} cannot be used as a UAV because it does not have the isUAV flag set.\n", utils.DebugNameToString(desc.debugName));
						return false;
					}

					if (binding.dimension != TextureDimension.Unknown)
					{
						if (!textureDimensionsCompatible(desc.dimension, binding.dimension))
						{
							errorStream.AppendF("Requested binding dimension ({}) is incompatible with the dimension ({}) of texture {}\n",
								utils.TextureDimensionToString(binding.dimension),
								utils.TextureDimensionToString(desc.dimension),
								utils.DebugNameToString(desc.debugName));
							return false;
						}
					}

					break;
				}

			case ResourceType.TypedBuffer_SRV: fallthrough;
			case ResourceType.TypedBuffer_UAV: fallthrough;
			case ResourceType.StructuredBuffer_SRV: fallthrough;
			case ResourceType.StructuredBuffer_UAV: fallthrough;
			case ResourceType.RawBuffer_SRV: fallthrough;
			case ResourceType.RawBuffer_UAV: fallthrough;
			case ResourceType.ConstantBuffer: fallthrough;
			case ResourceType.VolatileConstantBuffer:
				{
					IBuffer buffer = checked_cast<IBuffer, IResource>(binding.resourceHandle);

					if (buffer == null && binding.type != ResourceType.TypedBuffer_SRV && m_Device.getGraphicsAPI() != GraphicsAPI.VULKAN)
					{
						errorStream.Append("Null resource bindings are not allowed for buffers, unless it's a TypedBuffer_SRV type binding on DX11 or DX12.\n");
						return false;
					}

					if (buffer == null)
						return true;

					readonly ref BufferDesc desc = ref buffer.getDesc();

					bool isTypedView = (binding.type == ResourceType.TypedBuffer_SRV) || (binding.type == ResourceType.TypedBuffer_UAV);
					bool isStructuredView = (binding.type == ResourceType.StructuredBuffer_SRV) || (binding.type == ResourceType.StructuredBuffer_UAV);
					bool isRawView = (binding.type == ResourceType.RawBuffer_SRV) || (binding.type == ResourceType.RawBuffer_UAV);
					bool isUAV = (binding.type == ResourceType.TypedBuffer_UAV) || (binding.type == ResourceType.StructuredBuffer_UAV) || (binding.type == ResourceType.RawBuffer_UAV);
					bool isConstantView = (binding.type == ResourceType.ConstantBuffer) || (binding.type == ResourceType.VolatileConstantBuffer);

					if (isTypedView && !desc.canHaveTypedViews)
					{
						errorStream.AppendF("Cannot bind buffer {} as {} because it doesn't support typed views (BufferDesc::canHaveTypedViews).\n", utils.DebugNameToString(desc.debugName), utils.ResourceTypeToString(binding.type));
						return false;
					}

					if (isStructuredView && desc.structStride == 0)
					{
						errorStream.AppendF("Cannot bind buffer {0} as {} because it doesn't have structStride specified at creation.\n", utils.DebugNameToString(desc.debugName), utils.ResourceTypeToString(binding.type));
						return false;
					}

					if (isRawView && !desc.canHaveRawViews)
					{
						errorStream.AppendF("Cannot bind buffer {} as {} because it doesn't support raw views (BufferDesc::canHaveRawViews).\n", utils.DebugNameToString(desc.debugName), utils.ResourceTypeToString(binding.type));
						return false;
					}

					if (isUAV && !desc.canHaveUAVs)
					{
						errorStream.AppendF("Cannot bind buffer {} as  because it doesn't support unordeded access views (BufferDesc::canHaveUAVs).\n", utils.DebugNameToString(desc.debugName), utils.ResourceTypeToString(binding.type));
						return false;
					}

					if (isConstantView && !desc.isConstantBuffer)
					{
						errorStream.AppendF("Cannot bind buffer {} as {} because it doesn't support constant buffer views (BufferDesc::isConstantBuffer).\n", utils.DebugNameToString(desc.debugName), utils.ResourceTypeToString(binding.type));
						return false;
					}

					if (binding.type == ResourceType.ConstantBuffer && desc.isVolatile)
					{
						errorStream.AppendF("Cannot bind buffer {} as a regular ConstantBuffer because it's a VolatileConstantBuffer.\n", utils.DebugNameToString(desc.debugName));
						return false;
					}

					if (binding.type == ResourceType.VolatileConstantBuffer && !desc.isVolatile)
					{
						errorStream.AppendF("Cannot bind buffer {} as a VolatileConstantBuffer because it's a regular ConstantBuffer.\n", utils.DebugNameToString(desc.debugName));
						return false;
					}

					if (isTypedView && (binding.format == Format.UNKNOWN && desc.format == Format.UNKNOWN))
					{
						errorStream.AppendF("Both binding for typed buffer {} and its BufferDesc have format == UNKNOWN.\n", utils.DebugNameToString(desc.debugName));
						return false;
					}

					break;
				}

			case ResourceType.Sampler:
				if (binding.resourceHandle == null)
				{
					errorStream.Append("Null resource bindings are not allowed for samplers.\n");
					return false;
				}
				break;

			case ResourceType.RayTracingAccelStruct:
				if (binding.resourceHandle == null)
				{
					errorStream.Append("Null resource bindings are not allowed for ray tracing acceleration structures.\n");
					return false;
				}
				break;

			case ResourceType.PushConstants:
				if (isDescriptorTable)
				{
					errorStream.Append("Push constants cannot be used in a descriptor table.\n");
					return false;
				}
				if (binding.resourceHandle != null)
				{
					errorStream.Append("Push constants cannot have a resource specified.\n");
					return false;
				}
				if (binding.range.byteSize == 0)
				{
					errorStream.Append("Push constants must have nonzero size specified.\n");
					return false;
				}
				break;

			case ResourceType.Count:
			default:
				errorStream.AppendF("Unrecognized resourceType = {}\n", (uint32)binding.type);
				return false;
			}

			return true;
		}

		protected bool validatePipelineBindingLayouts(StaticVector<BindingLayoutHandle, const c_MaxBindingLayouts> bindingLayouts, List<IShader> shaders, GraphicsAPI api)
		{
			readonly int32 numBindingLayouts = int32(bindingLayouts.Count);
			bool anyErrors = false;
			bool anyDuplicateBindings = false;
			bool anyOverlappingBindings = false;
			String ssDuplicateBindings = scope .();
			String ssOverlappingBindings = scope .();

			for (IShader shader in shaders)
			{
				ShaderType stage = shader.getDesc().shaderType;

				StaticVector<ShaderBindingSet, const c_MaxBindingLayouts> bindingsPerLayout = .();
				StaticVector<ShaderBindingSet, const c_MaxBindingLayouts> duplicatesPerLayout = .();
				bindingsPerLayout.Resize(numBindingLayouts);
				duplicatesPerLayout.Resize(numBindingLayouts);

				// Accumulate binding information about the stage from all layouts

				for (int32 layoutIndex = 0; layoutIndex < numBindingLayouts; layoutIndex++)
				{
					if (bindingLayouts[layoutIndex] == null)
					{
						String message = scope $"Binding layout in slot {layoutIndex} is NULL";
						error(message);
						anyErrors = true;
					}
					else
					{
						readonly BindingLayoutDesc* layoutDesc = bindingLayouts[layoutIndex].getDesc();

						if (layoutDesc != null)
						{
							if (api != GraphicsAPI.VULKAN)
							{
								// Visibility does not apply to Vulkan
								if (!(layoutDesc.visibility & stage != 0))
									continue;
							}

							if (layoutDesc.registerSpace != 0)
							{
								continue; // TODO: add support for multiple register spaces. 
										  // Their indices can go up to 0xffffffef, according to the spec, so a vector won't work.
										  // https://microsoft.github.io/DirectX-Specs/d3d/ResourceBinding.html#note-about-register-space
							}

							FillShaderBindingSetFromDesc(m_MessageCallback, layoutDesc.bindings,
								/*ref bindingsPerLayout.GetValueAt(layoutIndex)*/ ref bindingsPerLayout[layoutIndex],
								/*ref duplicatesPerLayout.GetValueAt(layoutIndex)*/ ref duplicatesPerLayout[layoutIndex]);

							// Layouts with duplicates should not have passed validation in createBindingLayout
							Runtime.Assert(!duplicatesPerLayout[layoutIndex].any());
						}
					}
				}

				// Check for bindings to an unused shader stage

				if (shader == null)
				{
					for (int32 layoutIndex = 0; layoutIndex < numBindingLayouts; layoutIndex++)
					{
						if (bindingsPerLayout[layoutIndex].any())
						{
							String message = scope $"Binding layout in slot {layoutIndex} has bindings for a {utils.ShaderStageToString(stage)} shader, which is not used in the pipeline";
							error(message);
							anyErrors = true;
						}
					}
				}

				// Check for multiple layouts declaring the same bindings

				if (numBindingLayouts > 1)
				{
					ShaderBindingSet bindings = bindingsPerLayout[0];
					ShaderBindingSet duplicates = .();

					for (int32 layoutIndex = 1; layoutIndex < numBindingLayouts; layoutIndex++)
					{
						/*duplicates.SRV |= bindings.SRV & bindingsPerLayout[layoutIndex].SRV;
						duplicates.Sampler |= bindings.Sampler & bindingsPerLayout[layoutIndex].Sampler;
						duplicates.UAV |= bindings.UAV & bindingsPerLayout[layoutIndex].UAV;
						duplicates.CB |= bindings.CB & bindingsPerLayout[layoutIndex].CB;*/

						duplicates.SRV |= bindings.SRV & bindingsPerLayout[layoutIndex].SRV;
						duplicates.Sampler |= bindings.Sampler & bindingsPerLayout[layoutIndex].Sampler;
						duplicates.UAV |= bindings.UAV & bindingsPerLayout[layoutIndex].UAV;
						duplicates.CB |= bindings.CB & bindingsPerLayout[layoutIndex].CB;

						/*bindings.SRV |= bindingsPerLayout[layoutIndex].SRV;
						bindings.Sampler |= bindingsPerLayout[layoutIndex].Sampler;
						bindings.UAV |= bindingsPerLayout[layoutIndex].UAV;
						bindings.CB |= bindingsPerLayout[layoutIndex].CB;*/
						bindings.SRV |= bindingsPerLayout[layoutIndex].SRV;
						bindings.Sampler |= bindingsPerLayout[layoutIndex].Sampler;
						bindings.UAV |= bindingsPerLayout[layoutIndex].UAV;
						bindings.CB |= bindingsPerLayout[layoutIndex].CB;
					}

					if (duplicates.any())
					{
						if (!anyDuplicateBindings)
							ssDuplicateBindings.Append("Same bindings defined by more than one layout in this pipeline:");

						ssDuplicateBindings.AppendF("\n{} : {}", utils.ShaderStageToString(stage), duplicates);

						anyDuplicateBindings = true;
					}
					else
					{
						// Check for overlapping layouts.
						// Do this only when there are no duplicates, as with duplicates the layouts will always overlap.

						bool overlapSRV = false;
						bool overlapSampler = false;
						bool overlapUAV = false;
						bool overlapCB = false;

						for (int32 i = 0; i < numBindingLayouts - 1; i++)
						{
							readonly /*ref*/ ShaderBindingSet set1 = /*ref*/ bindingsPerLayout[i];

							for (int32 j = i + 1; j < numBindingLayouts; j++)
							{
								readonly /*ref*/ ShaderBindingSet set2 = /*ref*/ bindingsPerLayout[j];

								overlapSRV = overlapSRV || set1.rangeSRV.overlapsWith(set2.rangeSRV);
								overlapSampler = overlapSampler || set1.rangeSampler.overlapsWith(set2.rangeSampler);
								overlapUAV = overlapUAV || set1.rangeUAV.overlapsWith(set2.rangeUAV);
								overlapCB = overlapCB || set1.rangeCB.overlapsWith(set2.rangeCB);
							}
						}

						if (overlapSRV || overlapSampler || overlapUAV || overlapCB)
						{
							if (!anyOverlappingBindings)
								ssOverlappingBindings.Append("Binding layouts have overlapping register ranges:");

							ssOverlappingBindings.AppendF("\n{}: ", utils.ShaderStageToString(stage));

							bool first = true;
							delegate void(bool value, String text) @append = scope [&first, &ssOverlappingBindings] (value, text) =>
								{
									if (value)
									{
										if (!first) ssOverlappingBindings.Append(", ");
										ssOverlappingBindings.Append(text);
										first = false;
									}
								};

							@append(overlapSRV, "SRV");
							@append(overlapSampler, "Sampler");
							@append(overlapUAV, "UAV");
							@append(overlapCB, "CB");

							anyOverlappingBindings = true;
						}
					}
				}
			}

			if (anyDuplicateBindings)
			{
				error(ssDuplicateBindings);
				anyErrors = true;
			}

			if (anyOverlappingBindings)
			{
				error(ssOverlappingBindings);
				anyErrors = true;
			}

			int32 pushConstantCount = 0;
			uint32 pushConstantSize = 0;

			for (int32 layoutIndex = 0; layoutIndex < numBindingLayouts; layoutIndex++)
			{
				readonly BindingLayoutDesc* layoutDesc = bindingLayouts[layoutIndex].getDesc();
				if (layoutDesc != null)
				{
					for ( /*readonly ref*/var item in ref layoutDesc.bindings)
					{
						if (item.type == ResourceType.PushConstants)
						{
							pushConstantCount++;
							pushConstantSize = Math.Max(pushConstantSize, (uint32)item.size);
						}
					}
				}
			}

			if (pushConstantCount > 1)
			{
				String errorStream = scope $"Binding layout contains more than one ({pushConstantCount}) push constant blocks";
				error(errorStream);
				anyErrors = true;
			}

			if (pushConstantSize > c_MaxPushConstantSize)
			{
				String errorStream = scope $"Binding layout declares {pushConstantSize} bytes of push constant data, which exceeds the limit of {c_MaxPushConstantSize} bytes";
				error(errorStream);
				anyErrors = true;
			}

			return !anyErrors;
		}

		protected bool validateShaderType(ShaderType expected, ShaderDesc shaderDesc, char8* @function)
		{
			if (expected == shaderDesc.shaderType)
				return true;

			String message = scope $"Unexpected shader type used in {@function}: expected shaderType = {utils.ShaderStageToString(expected)}, actual shaderType = {utils.ShaderStageToString(shaderDesc.shaderType)} in {utils.DebugNameToString(shaderDesc.debugName)}:{shaderDesc.entryName}";
			error(message);
			return false;
		}

		protected bool validateRenderState(RenderState renderState, IFramebuffer fb)
		{
			if (fb == null)
			{
				error("framebuffer is NULL");
				return false;
			}

			readonly var fbDesc = fb.getDesc();

			if (renderState.depthStencilState.depthTestEnable ||
				renderState.depthStencilState.stencilEnable)
			{
				if (!fbDesc.depthAttachment.valid())
				{
					error("The depth-stencil state indicates that depth or stencil operations are used, but the framebuffer has no depth attachment.");
					return false;
				}
			}

			if ((renderState.depthStencilState.depthTestEnable && renderState.depthStencilState.depthWriteEnable) ||
				(renderState.depthStencilState.stencilEnable && renderState.depthStencilState.stencilWriteMask != 0))
			{
				if (fbDesc.depthAttachment.isReadOnly)
				{
					error("The depth-stencil state indicates that depth or stencil writes are used, but the framebuffer's depth attachment is read-only.");
					return false;
				}
			}
			else if (renderState.depthStencilState.depthTestEnable || renderState.depthStencilState.stencilEnable)
			{
				if (!fbDesc.depthAttachment.isReadOnly)
				{
					warning("The depth-stencil state indicates read-only depth and stencil, but the framebuffer has a read-write depth attachment, which is suboptimal.");
				}
			}

			return true;
		}

		// IResource implementation

		public override NativeObject getNativeObject(ObjectType objectType)
		{
			return m_Device.getNativeObject(objectType);
		}

		// IDevice implementation

		public override HeapHandle createHeap(HeapDesc d)
		{
			if (d.capacity == 0)
			{
				error("Cannot create a Heap with capacity = 0");
				return null;
			}

			HeapDesc patchedDesc = d;
			if (String.IsNullOrEmpty(patchedDesc.debugName))
				patchedDesc.debugName = utils.GenerateHeapDebugName(patchedDesc, .. new .());

			return m_Device.createHeap(patchedDesc);
		}



		public override TextureHandle createTexture(TextureDesc d)
		{
			bool anyErrors = false;

			switch (d.dimension)
			{
			case TextureDimension.Texture1D: fallthrough;
			case TextureDimension.Texture1DArray: fallthrough;
			case TextureDimension.Texture2D: fallthrough;
			case TextureDimension.Texture2DArray: fallthrough;
			case TextureDimension.TextureCube: fallthrough;
			case TextureDimension.TextureCubeArray: fallthrough;
			case TextureDimension.Texture2DMS: fallthrough;
			case TextureDimension.Texture2DMSArray: fallthrough;
			case TextureDimension.Texture3D:
				break;

			case TextureDimension.Unknown: fallthrough;
			default:
				error("Unknown texture dimension");
				return null;
			}

			char8* dimensionStr = utils.TextureDimensionToString(d.dimension);
			char8* debugName = utils.DebugNameToString(d.debugName);

			if (d.width == 0 || d.height == 0 || d.depth == 0 || d.arraySize == 0 || d.mipLevels == 0)
			{
				String message = scope $"{dimensionStr} {debugName}: width({d.width}), height({d.height}), depth({d.depth}), arraySize({d.arraySize}) and mipLevels({d.mipLevels}) must not be zero";
				error(message);
				return null;
			}

			switch (d.dimension) // NOLINT(clang-diagnostic-switch-enum)
			{
			case TextureDimension.Texture1D: fallthrough;
			case TextureDimension.Texture1DArray:
				if (d.height != 1)
				{
					String message = scope $"{dimensionStr} {debugName}: height({d.height}) must be equal to 1";
					error(message);
					anyErrors = true;
				}
				break;
			default: break;
			}

			switch (d.dimension) // NOLINT(clang-diagnostic-switch-enum)
			{
			case TextureDimension.Texture1D: fallthrough;
			case TextureDimension.Texture1DArray: fallthrough;
			case TextureDimension.Texture2D: fallthrough;
			case TextureDimension.Texture2DArray: fallthrough;
			case TextureDimension.TextureCube: fallthrough;
			case TextureDimension.TextureCubeArray: fallthrough;
			case TextureDimension.Texture2DMS: fallthrough;
			case TextureDimension.Texture2DMSArray:
				if (d.depth != 1)
				{
					String message = scope $"{dimensionStr} {debugName}: depth({d.depth}) must be equal to 1";
					error(message);
					anyErrors = true;
				}
				break;
			default: break;
			}

			switch (d.dimension) // NOLINT(clang-diagnostic-switch-enum)
			{
			case TextureDimension.Texture1D: fallthrough;
			case TextureDimension.Texture2D: fallthrough;
			case TextureDimension.Texture2DMS: fallthrough;
			case TextureDimension.Texture3D:
				if (d.arraySize != 1)
				{
					String message = scope $"{dimensionStr} {debugName}: arraySize({d.arraySize}) must be equal to 1";
					error(message);
					anyErrors = true;
				}
				break;
			case TextureDimension.TextureCube:
				if (d.arraySize != 6)
				{
					String message = scope $"{dimensionStr} {debugName}: arraySize({d.arraySize}) must be equal to 6";
					error(message);
					anyErrors = true;
				}
				break;
			case TextureDimension.TextureCubeArray:
				if ((d.arraySize % 6) != 0)
				{
					String message = scope $"{dimensionStr} {debugName}: arraySize({d.arraySize}) must be a multiple of 6";
					error(message);
					anyErrors = true;
				}
				break;
			default: break;
			}

			switch (d.dimension) // NOLINT(clang-diagnostic-switch-enum)
			{
			case TextureDimension.Texture1D: fallthrough;
			case TextureDimension.Texture1DArray: fallthrough;
			case TextureDimension.Texture2D: fallthrough;
			case TextureDimension.Texture2DArray: fallthrough;
			case TextureDimension.TextureCube: fallthrough;
			case TextureDimension.TextureCubeArray: fallthrough;
			case TextureDimension.Texture3D:
				if (d.sampleCount != 1)
				{
					String message = scope $"{dimensionStr} {debugName}: sampleCount({d.sampleCount}) must be equal to 1";
					error(message);
					anyErrors = true;
				}
				break;
			case TextureDimension.Texture2DMS: fallthrough;
			case TextureDimension.Texture2DMSArray:
				if (d.sampleCount != 2 && d.sampleCount != 4 && d.sampleCount != 8)
				{
					String message = scope $"{dimensionStr} {debugName}: sampleCount({d.sampleCount}) must be equal to 2, 4 or 8";
					error(message);
					anyErrors = true;
				}
				if (d.isUAV)
				{
					String message = scope $"{dimensionStr} {debugName}: multi-sampled textures cannot have UAVs (isUAV flag)";
					error(message);
					anyErrors = true;
				}
				break;
			default: break;
			}

			if (d.isVirtual && !m_Device.queryFeatureSupport(Feature.VirtualResources))
			{
				String message = scope $"{dimensionStr} {debugName}: The device does not support virtual resources";
				error(message);
				anyErrors = true;
			}

			if (anyErrors)
				return null;

			TextureDesc patchedDesc = d;
			if (String.IsNullOrEmpty(patchedDesc.debugName))
				patchedDesc.debugName = utils.GenerateTextureDebugName(patchedDesc, .. new .());

			return m_Device.createTexture(patchedDesc);
		}

		public override MemoryRequirements getTextureMemoryRequirements(ITexture texture)
		{
			if (texture == null)
			{
				error("getTextureMemoryRequirements: texture is NULL");
				return MemoryRequirements();
			}

			readonly MemoryRequirements memReq = m_Device.getTextureMemoryRequirements(texture);

			if (memReq.size == 0)
			{
				String message = scope $"Invalid texture {utils.DebugNameToString(texture.getDesc().debugName)}: getTextureMemoryRequirements returned zero size";

				error(message);
			}

			return memReq;
		}

		public override bool bindTextureMemory(ITexture texture, IHeap heap, uint64 offset)
		{
			if (texture == null)
			{
				error("bindTextureMemory: texture is NULL");
				return false;
			}

			if (heap == null)
			{
				error("bindTextureMemory: heap is NULL");
				return false;
			}

			readonly ref HeapDesc heapDesc = ref heap.getDesc();
			readonly ref TextureDesc textureDesc = ref texture.getDesc();

			if (!textureDesc.isVirtual)
			{
				String message = scope $"Cannot perform bindTextureMemory on texture {utils.DebugNameToString(textureDesc.debugName)} because it was created with isVirtual = false";

				error(message);
				return false;
			}

			MemoryRequirements memReq = m_Device.getTextureMemoryRequirements(texture);

			if (offset + memReq.size > heapDesc.capacity)
			{
				String message = scope $"Texture {utils.DebugNameToString(textureDesc.debugName)} does not fit into heap {utils.DebugNameToString(heapDesc.debugName)} at offset {offset} because it requires {memReq.size} bytes, and the heap capacity is {heapDesc.capacity} bytes";

				error(message);
				return false;
			}

			if (memReq.alignment != 0 && (offset % memReq.alignment) != 0)
			{
				String message = scope $"Texture {utils.DebugNameToString(textureDesc.debugName)} is placed in heap {utils.DebugNameToString(heapDesc.debugName)} at invalid alignment: required alignment to {memReq.alignment} bytes, actual offset is {offset} bytes";

				error(message);
				return false;
			}

			return m_Device.bindTextureMemory(texture, heap, offset);
		}


		public override TextureHandle createHandleForNativeTexture(ObjectType objectType, NativeObject texture, TextureDesc desc)
		{
			return m_Device.createHandleForNativeTexture(objectType, texture, desc);
		}


		public override StagingTextureHandle createStagingTexture(TextureDesc d, CpuAccessMode cpuAccess)
		{
			TextureDesc patchedDesc = d;
			if (String.IsNullOrEmpty(patchedDesc.debugName))
				patchedDesc.debugName = utils.GenerateTextureDebugName(patchedDesc, .. new .());

			return m_Device.createStagingTexture(patchedDesc, cpuAccess);
		}

		public override void* mapStagingTexture(IStagingTexture tex, TextureSlice slice, CpuAccessMode cpuAccess, int* outRowPitch)
		{
			return m_Device.mapStagingTexture(tex, slice, cpuAccess, outRowPitch);
		}

		public override void unmapStagingTexture(IStagingTexture tex)
		{
			m_Device.unmapStagingTexture(tex);
		}


		public override BufferHandle createBuffer(BufferDesc d)
		{
			BufferDesc patchedDesc = d;
			if (String.IsNullOrEmpty(patchedDesc.debugName))
				patchedDesc.debugName = utils.GenerateBufferDebugName(patchedDesc, .. new .());

			if (d.isVolatile && !d.isConstantBuffer)
			{
				String message = scope $"Buffer {patchedDesc.debugName} is volatile but is not a constant buffer. Only constant buffers can be made volatile.";
				error(message);
				return null;
			}

			if (d.isVolatile && d.maxVersions == 0)
			{
				String message = scope $"Volatile constant buffer {patchedDesc.debugName} has maxVersions = 0";
				error(message);
				return null;
			}

			if (d.isVolatile && (d.isVertexBuffer || d.isIndexBuffer || d.isDrawIndirectArgs || d.canHaveUAVs || d.isAccelStructBuildInput || d.isAccelStructStorage || d.isVirtual))
			{
				String message = scope $"Buffer {patchedDesc.debugName} is volatile but has unsupported usage flags:";
				if (d.isVertexBuffer) message.Append(" IsVertexBuffer");
				if (d.isIndexBuffer) message.Append(" IsIndexBuffer");
				if (d.isDrawIndirectArgs) message.Append(" IsDrawIndirectArgs");
				if (d.canHaveUAVs) message.Append(" CanHaveUAVs");
				if (d.isAccelStructBuildInput) message.Append(" IsAccelStructBuildInput");
				if (d.isAccelStructStorage) message.Append(" IsAccelStructStorage");
				if (d.isVirtual) message.Append(" IsVirtual");
				message.Append(".\nOnly constant buffers can be made volatile, and volatile buffers cannot be virtual.");
				error(message);
				return null;
			}

			if (d.isVolatile && d.cpuAccess != CpuAccessMode.None)
			{
				String message = scope $"Volatile constant buffer {patchedDesc.debugName} must have cpuAccess set to None. Write-discard access is implied.";
				error(message);
				return null;
			}

			if (d.isVirtual && !m_Device.queryFeatureSupport(Feature.VirtualResources))
			{
				error("The device does not support virtual resources");
				return null;
			}

			return m_Device.createBuffer(patchedDesc);
		}

		public override void* mapBuffer(IBuffer b, CpuAccessMode mapFlags)
		{
			return m_Device.mapBuffer(b, mapFlags);
		}

		public override void unmapBuffer(IBuffer b)
		{
			m_Device.unmapBuffer(b);
		}

		public override MemoryRequirements getBufferMemoryRequirements(IBuffer buffer)
		{
			if (buffer == null)
			{
				error("getBufferMemoryRequirements: buffer is NULL");
				return MemoryRequirements();
			}

			readonly MemoryRequirements memReq = m_Device.getBufferMemoryRequirements(buffer);

			if (memReq.size == 0)
			{
				String message = scope $"Invalid buffer {utils.DebugNameToString(buffer.getDesc().debugName)}: getBufferMemoryRequirements returned zero size";

				error(message);
			}

			return memReq;
		}

		public override bool bindBufferMemory(IBuffer buffer, IHeap heap, uint64 offset)
		{
			if (buffer == null)
			{
				error("bindBufferMemory: texture is NULL");
				return false;
			}

			if (heap == null)
			{
				error("bindBufferMemory: heap is NULL");
				return false;
			}

			readonly ref HeapDesc heapDesc = ref heap.getDesc();
			readonly ref BufferDesc bufferDesc = ref buffer.getDesc();

			if (!bufferDesc.isVirtual)
			{
				String message = scope $"Cannot perform bindBufferMemory on buffer {utils.DebugNameToString(bufferDesc.debugName)} because it was created with isVirtual = false";

				error(message);
				return false;
			}

			MemoryRequirements memReq = m_Device.getBufferMemoryRequirements(buffer);

			if (offset + memReq.size > heapDesc.capacity)
			{
				String message = scope $"Buffer {utils.DebugNameToString(bufferDesc.debugName)} does not fit into heap {utils.DebugNameToString(heapDesc.debugName)} at offset {offset} because it requires {memReq.size} bytes, and the heap capacity is {heapDesc.capacity} bytes";

				error(message);
				return false;
			}

			if (memReq.alignment != 0 && (offset % memReq.alignment) != 0)
			{
				String message = scope $"Buffer {utils.DebugNameToString(bufferDesc.debugName)} is placed in heap {utils.DebugNameToString(heapDesc.debugName)} at invalid alignment: required alignment to {memReq.alignment} bytes, actual offset is {offset} bytes";

				error(message);
				return false;
			}

			return m_Device.bindBufferMemory(buffer, heap, offset);
		}


		public override BufferHandle createHandleForNativeBuffer(ObjectType objectType, NativeObject buffer, BufferDesc desc)
		{
			return m_Device.createHandleForNativeBuffer(objectType, buffer, desc);
		}


		public override ShaderHandle createShader(ShaderDesc d, void* binary, int binarySize)
		{
			return m_Device.createShader(d, binary, binarySize);
		}

		public override ShaderHandle createShaderSpecialization(IShader baseShader, ShaderSpecialization* constants, uint32 numConstants)
		{
			if (!m_Device.queryFeatureSupport(Feature.ShaderSpecializations))
			{
				String message = scope $"The current graphics API ({utils.GraphicsAPIToString(m_Device.getGraphicsAPI())}) doesn't support shader specializations";
				error(message);
				return null;
			}

			if (constants == null || numConstants == 0)
			{
				error("Both 'constants' and 'numConstatns' must be non-zero in createShaderSpecialization");
				return null;
			}

			if (baseShader == null)
			{
				error("baseShader must be non-null in createShaderSpecialization");
				return null;
			}

			return m_Device.createShaderSpecialization(baseShader, constants, numConstants);
		}

		public override ShaderLibraryHandle createShaderLibrary(void* binary, int binarySize)
		{
			return m_Device.createShaderLibrary(binary, binarySize);
		}


		public override SamplerHandle createSampler(SamplerDesc d)
		{
			return m_Device.createSampler(d);
		}


		public override InputLayoutHandle createInputLayout(VertexAttributeDesc* d, uint32 attributeCount, IShader vertexShader)
		{
			return m_Device.createInputLayout(d, attributeCount, vertexShader);
		}

		// event queries
		public override EventQueryHandle createEventQuery()
		{
			return m_Device.createEventQuery();
		}

		public override void setEventQuery(IEventQuery query, CommandQueue queue)
		{
			m_Device.setEventQuery(query, queue);
		}
		public override bool pollEventQuery(IEventQuery query)
		{
			return m_Device.pollEventQuery(query);
		}

		public override void waitEventQuery(IEventQuery query)
		{
			m_Device.waitEventQuery(query);
		}

		public override void resetEventQuery(IEventQuery query)
		{
			m_Device.resetEventQuery(query);
		}


		// timer queries
		public override TimerQueryHandle createTimerQuery()
		{
			return m_Device.createTimerQuery();
		}

		public override bool pollTimerQuery(ITimerQuery query)
		{
			return m_Device.pollTimerQuery(query);
		}

		public override float getTimerQueryTime(ITimerQuery query)
		{
			return m_Device.getTimerQueryTime(query);
		}

		public override void resetTimerQuery(ITimerQuery query)
		{
			m_Device.resetTimerQuery(query);
		}


		public override GraphicsAPI getGraphicsAPI()
		{
			return m_Device.getGraphicsAPI();
		}


		public override FramebufferHandle createFramebuffer(FramebufferDesc desc)
		{
			return m_Device.createFramebuffer(desc);
		}



		public override GraphicsPipelineHandle createGraphicsPipeline(GraphicsPipelineDesc pipelineDesc, IFramebuffer fb)
		{
			List<IShader> shaders = scope .();

			for (ShaderType stage in g_GraphicsShaderStages)
			{
				IShader shader = *SelectGraphicsShaderStage<ShaderHandle, GraphicsPipelineDesc>(pipelineDesc, stage);
				if (shader != null)
				{
					shaders.Add(shader);

					if (!validateShaderType(stage, shader.getDesc(), "createGraphicsPipeline"))
						return null;
				}
			}

			if (!validatePipelineBindingLayouts(pipelineDesc.bindingLayouts, shaders, m_Device.getGraphicsAPI()))
				return null;

			if (!validateRenderState(pipelineDesc.renderState, fb))
				return null;

			return m_Device.createGraphicsPipeline(pipelineDesc, fb);
		}



		public override ComputePipelineHandle createComputePipeline(ComputePipelineDesc pipelineDesc)
		{
			if (pipelineDesc.CS == null)
			{
				error("createComputePipeline: CS = NULL");
				return null;
			}

			List<IShader> shaders = scope .() { pipelineDesc.CS };

			if (!validatePipelineBindingLayouts(pipelineDesc.bindingLayouts, shaders, m_Device.getGraphicsAPI()))
				return null;

			if (!validateShaderType(ShaderType.Compute, pipelineDesc.CS.getDesc(), "createComputePipeline"))
				return null;

			return m_Device.createComputePipeline(pipelineDesc);
		}



		public override MeshletPipelineHandle createMeshletPipeline(MeshletPipelineDesc pipelineDesc, IFramebuffer fb)
		{
			List<IShader> shaders  = scope .();

			for (ShaderType stage in g_MeshletShaderStages)
			{
				IShader shader = *SelectMeshletShaderStage<ShaderHandle, MeshletPipelineDesc>(pipelineDesc, stage);
				if (shader != null)
				{
					shaders.Add(shader);

					if (!validateShaderType(stage, shader.getDesc(), "createMeshletPipeline"))
						return null;
				}
			}

			if (!validatePipelineBindingLayouts(pipelineDesc.bindingLayouts, shaders, m_Device.getGraphicsAPI()))
				return null;

			if (!validateRenderState(pipelineDesc.renderState, fb))
				return null;

			return m_Device.createMeshletPipeline(pipelineDesc, fb);
		}



		public override nvrhi.rt.PipelineHandle createRayTracingPipeline(nvrhi.rt.PipelineDesc desc)
		{
			return m_Device.createRayTracingPipeline(desc);
		}



		public override BindingLayoutHandle createBindingLayout(BindingLayoutDesc desc)
		{
			String errorStream = scope .();
			bool anyErrors = false;

			ShaderBindingSet bindings = .();
			ShaderBindingSet duplicates = .();

			FillShaderBindingSetFromDesc(m_MessageCallback, desc.bindings, ref bindings, ref duplicates);

			if (desc.visibility == ShaderType.None)
			{
				errorStream.Append("Cannot create a binding layout with visibility = None\n");
				anyErrors = true;
			}

			if (duplicates.any())
			{
				errorStream.AppendF("Binding layout contains duplicate bindings: {}\n", duplicates);
				anyErrors = true;
			}

			if (bindings.numVolatileCBs > c_MaxVolatileConstantBuffersPerLayout)
			{
				errorStream.AppendF("Binding layout contains too many volatile CBs ({})\n", bindings.numVolatileCBs);
				anyErrors = true;
			}

			uint32 noneItemCount = 0;
			uint32 pushConstantCount = 0;
			for (readonly ref BindingLayoutItem item in ref desc.bindings)
			{
				if (item.type == ResourceType.None)
					noneItemCount++;

				if (item.type == ResourceType.PushConstants)
				{
					if (item.size == 0)
					{
						errorStream.Append("Push constant block size cannot be null\n");
						anyErrors = true;
					}

					if (item.size > c_MaxPushConstantSize)
					{
						errorStream.AppendF("Push constant block size ({}) cannot exceed {} bytes\n", item.size, c_MaxPushConstantSize);
						anyErrors = true;
					}

					if ((item.size % 4) != 0)
					{
						errorStream.AppendF("Push constant block size ({}) must be a multiple of 4\n", item.size);
						anyErrors = true;
					}

					pushConstantCount++;
				}
			}

			if (noneItemCount > 0)
			{
				errorStream.AppendF("Binding layout contains {} item(s) with type = None\n", noneItemCount);
				anyErrors = true;
			}

			if (pushConstantCount > 1)
			{
				errorStream.AppendF("Binding layout contains more than one ({}) push constant blocks\n", pushConstantCount);
				anyErrors = true;
			}

			if (m_Device.getGraphicsAPI() != GraphicsAPI.D3D12)
			{
				if (desc.registerSpace != 0)
				{
					errorStream.AppendF("Binding layout registerSpace = {0}, which is unsupported by the current backend\n", desc.registerSpace);
					anyErrors = true;
				}
			}

			if (anyErrors)
			{
				error(errorStream);
				return null;
			}

			return m_Device.createBindingLayout(desc);
		}

		public override BindingLayoutHandle createBindlessLayout(BindlessLayoutDesc desc)
		{
			String errorStream = scope .();
			bool anyErrors = false;

			if (desc.visibility == ShaderType.None)
			{
				errorStream.Append("Cannot create a bindless layout with visibility = None\n");
				anyErrors = true;
			}

			if (desc.registerSpaces.IsEmpty)
			{
				errorStream.Append("Bindless layout has no register spaces assigned\n");
				anyErrors = true;
			}

			if (desc.maxCapacity == 0)
			{
				errorStream.Append("Bindless layout has maxCapacity = 0\n");
				anyErrors = true;
			}

			for (readonly ref BindingLayoutItem item in ref desc.registerSpaces)
			{
				switch (item.type)
				{
				case ResourceType.Texture_SRV: fallthrough;
				case ResourceType.TypedBuffer_SRV: fallthrough;
				case ResourceType.StructuredBuffer_SRV: fallthrough;
				case ResourceType.RawBuffer_SRV: fallthrough;
				case ResourceType.RayTracingAccelStruct: fallthrough;
				case ResourceType.ConstantBuffer: fallthrough;
				case ResourceType.Texture_UAV: fallthrough;
				case ResourceType.TypedBuffer_UAV: fallthrough;
				case ResourceType.StructuredBuffer_UAV: fallthrough;
				case ResourceType.RawBuffer_UAV:
					continue;
				case ResourceType.VolatileConstantBuffer:
					errorStream.AppendF("Volatile CBs cannot be placed into a bindless layout (slot {})\n", item.slot);
					anyErrors = true;
					break;
				case ResourceType.Sampler:
					errorStream.AppendF("Bindless samplers are not implemented (slot {})\n", item.slot);
					anyErrors = true;
					break;
				case ResourceType.PushConstants:
					errorStream.AppendF("Push constants cannot be placed into a bindless layout (slot {})\n", item.slot);
					anyErrors = true;
					break;

				case ResourceType.None: fallthrough;
				case ResourceType.Count: fallthrough;
				default:
					errorStream.AppendF("Invalid resource type {} in slot {}\n", int32(item.type),  item.slot);
					anyErrors = true;
					break;
				}
			}

			if (anyErrors)
			{
				error(errorStream);
				return null;
			}

			return m_Device.createBindlessLayout(desc);
		}


		public override BindingSetHandle createBindingSet(BindingSetDesc desc, IBindingLayout layout)
		{
			if (layout == null)
			{
				error("Cannot create a binding set without a valid layout");
				return null;
			}

			readonly BindingLayoutDesc* layoutDesc = layout.getDesc();
			if (layoutDesc == null)
			{
				error("Cannot create a binding set from a bindless layout");
				return null;
			}

			String errorStream = scope .();
			bool anyErrors = false;

			ShaderBindingSet layoutBindings = .();
			ShaderBindingSet layoutDuplicates = .();

			FillShaderBindingSetFromDesc(m_MessageCallback, layoutDesc.bindings, ref layoutBindings, ref layoutDuplicates);

			ShaderBindingSet setBindings = .();
			ShaderBindingSet setDuplicates = .();

			FillShaderBindingSetFromDesc(m_MessageCallback, desc.bindings, ref setBindings, ref setDuplicates);

			ShaderBindingSet declaredNotBound = .();
			ShaderBindingSet boundNotDeclared = .();

			declaredNotBound.SRV = layoutBindings.SRV & ~setBindings.SRV;
			declaredNotBound.Sampler = layoutBindings.Sampler & ~setBindings.Sampler;
			declaredNotBound.UAV = layoutBindings.UAV & ~setBindings.UAV;
			declaredNotBound.CB = layoutBindings.CB & ~setBindings.CB;

			boundNotDeclared.SRV = ~layoutBindings.SRV & setBindings.SRV;
			boundNotDeclared.Sampler = ~layoutBindings.Sampler & setBindings.Sampler;
			boundNotDeclared.UAV = ~layoutBindings.UAV & setBindings.UAV;
			boundNotDeclared.CB = ~layoutBindings.CB & setBindings.CB;

			if (declaredNotBound.any())
			{
				errorStream.AppendF("Bindings declared in the layout are not present in the binding set: {}\n", declaredNotBound);
				anyErrors = true;
			}

			if (boundNotDeclared.any())
			{
				errorStream.AppendF("Bindings in the binding set are not declared in the layout: {}\n", boundNotDeclared);
				anyErrors = true;
			}

			if (setDuplicates.any())
			{
				errorStream.AppendF("Binding set contains duplicate bindings: {}\n", setDuplicates);
				anyErrors = true;
			}

			if (desc.bindings.Count != layoutDesc.bindings.Count)
			{
				errorStream.AppendF("The number of items in the binding set descriptor ({}) is different from the number of items in the layout ({})\n", desc.bindings.Count, layoutDesc.bindings.Count);
				anyErrors = true;
			}
			else
			{
				for (int index = 0; index < desc.bindings.Count; index++)
				{
					readonly /*ref*/ BindingSetItem setItem = /*ref*/ desc.bindings[index];
					readonly /*ref*/ BindingLayoutItem layoutItem = /*ref*/ layoutDesc.bindings[index];

					if ((setItem.slot != layoutItem.slot) || (setItem.type != layoutItem.type))
					{
						errorStream.AppendF("Binding set item {} doesn't match layout item {}: expected {}({}) received {}({})\n",
							index,
							index,
							utils.ResourceTypeToString(layoutItem.type),
							layoutItem.slot,
							utils.ResourceTypeToString(setItem.type), setItem.slot);

						anyErrors = true;
					}

					if (!validateBindingSetItem(setItem, false, errorStream))
						anyErrors = true;
				}
			}

			if (anyErrors)
			{
				error(errorStream);
				return null;
			}

			// Unwrap the resources
			BindingSetDesc patchedDesc = desc;
			for (var binding in ref patchedDesc.bindings)
			{
				binding.resourceHandle = unwrapResource(binding.resourceHandle);
			}

			return m_Device.createBindingSet(patchedDesc, layout);
		}

		public override DescriptorTableHandle createDescriptorTable(IBindingLayout layout)
		{
			if (layout.getBindlessDesc() == null)
			{
				error("Descriptor tables can only be created with bindless layouts");
				return null;
			}

			return m_Device.createDescriptorTable(layout);
		}


		public override void resizeDescriptorTable(IDescriptorTable descriptorTable, uint32 newSize, bool keepContents)
		{
			m_Device.resizeDescriptorTable(descriptorTable, newSize, keepContents);
		}

		public override bool writeDescriptorTable(IDescriptorTable descriptorTable, BindingSetItem item)
		{
			String errorStream = scope .();

			if (!validateBindingSetItem(item, true, errorStream))
			{
				error(errorStream);
				return false;
			}

			BindingSetItem patchedItem = item;
			patchedItem.resourceHandle = unwrapResource(patchedItem.resourceHandle);

			return m_Device.writeDescriptorTable(descriptorTable, patchedItem);
		}


		public override nvrhi.rt.AccelStructHandle createAccelStruct(nvrhi.rt.AccelStructDesc desc)
		{
			nvrhi.rt.AccelStructHandle @as = m_Device.createAccelStruct(desc);

			if (@as == null)
				return null;

			if ((desc.buildFlags & nvrhi.rt.AccelStructBuildFlags.AllowCompaction) != 0 &&
				desc.isTopLevel)
			{
				String message = scope $"Cannot create TLAS {utils.DebugNameToString(desc.debugName)} with the AllowCompaction flag set: compaction is not supported for TLAS'es";
				error(message);
				return null;
			}

			if ((desc.buildFlags & nvrhi.rt.AccelStructBuildFlags.AllowUpdate) != 0 &&
				(desc.buildFlags & nvrhi.rt.AccelStructBuildFlags.AllowCompaction) != 0)
			{
				String message = scope $"Cannot create AccelStruct {utils.DebugNameToString(desc.debugName)} with incompatible flags: AllowUpdate and AllowCompaction";
				error(message);
				return null;
			}

			AccelStructWrapper wrapper = new AccelStructWrapper(@as);
			wrapper.isTopLevel = desc.isTopLevel;
			wrapper.allowUpdate = !!(desc.buildFlags & nvrhi.rt.AccelStructBuildFlags.AllowUpdate != 0);
			wrapper.allowCompaction = !!(desc.buildFlags & nvrhi.rt.AccelStructBuildFlags.AllowCompaction != 0);
			wrapper.maxInstances = desc.topLevelMaxInstances;

			return nvrhi.rt.AccelStructHandle.Attach(wrapper);
		}

		public override MemoryRequirements getAccelStructMemoryRequirements(nvrhi.rt.IAccelStruct @as)
		{
			var @as = @as;
			if (@as == null)
			{
				error("getAccelStructMemoryRequirements: @as is NULL");
				return MemoryRequirements();
			}

			AccelStructWrapper wrapper = @as as AccelStructWrapper;
			if (wrapper != null)
				@as = wrapper.getUnderlyingObject();

			readonly MemoryRequirements memReq = m_Device.getAccelStructMemoryRequirements(@as);

			return memReq;
		}

		public override bool bindAccelStructMemory(nvrhi.rt.IAccelStruct @as, IHeap heap, uint64 offset)
		{
			var @as = @as;
			if (@as == null)
			{
				error("bindAccelStructMemory: texture is NULL");
				return false;
			}

			if (heap == null)
			{
				error("bindAccelStructMemory: heap is NULL");
				return false;
			}

			AccelStructWrapper wrapper = @as as AccelStructWrapper;
			if (wrapper != null)
				@as = wrapper.getUnderlyingObject();

			readonly ref HeapDesc heapDesc = ref heap.getDesc();
			readonly ref nvrhi.rt.AccelStructDesc asDesc = ref @as.getDesc();

			if (!asDesc.isVirtual)
			{
				String message = scope $"Cannot perform bindAccelStructMemory on AccelStruct {utils.DebugNameToString(asDesc.debugName)} because it was created with isVirtual = false";

				error(message);
				return false;
			}

			MemoryRequirements memReq = m_Device.getAccelStructMemoryRequirements(@as);

			if (offset + memReq.size > heapDesc.capacity)
			{
				String message = scope $"AccelStruct {utils.DebugNameToString(asDesc.debugName)} does not fit into heap {utils.DebugNameToString(heapDesc.debugName)} at offset {offset} because it requires {memReq.size} bytes, and the heap capacity is {heapDesc.capacity} bytes";

				error(message);
				return false;
			}

			if (memReq.alignment != 0 && (offset % memReq.alignment) != 0)
			{
				String message = scope $"AccelStruct {utils.DebugNameToString(asDesc.debugName)} is placed in heap {utils.DebugNameToString(heapDesc.debugName)} at invalid alignment: required alignment to {memReq.alignment} bytes, actual offset is {offset} bytes";

				error(message);
				return false;
			}

			return m_Device.bindAccelStructMemory(@as, heap, offset);
		}


		public override CommandListHandle createCommandList(CommandListParameters @params)
		{
			switch (@params.queueType)
			{
			case CommandQueue.Graphics:
				// Assume the graphics queue always exists
				break;

			case CommandQueue.Compute:
				if (!m_Device.queryFeatureSupport(Feature.ComputeQueue))
				{
					error("Compute queue is not supported or initialized in this device");
					return null;
				}
				break;

			case CommandQueue.Copy:
				if (!m_Device.queryFeatureSupport(Feature.CopyQueue))
				{
					error("Copy queue is not supported or initialized in this device");
					return null;
				}
				break;

			case CommandQueue.Count: fallthrough;
			default:
				utils.InvalidEnum();
				return null;
			}

			CommandListHandle commandList = m_Device.createCommandList(@params);

			if (commandList == null)
				return null;

			CommandListWrapper wrapper = new CommandListWrapper(this, commandList, @params.enableImmediateExecution, @params.queueType);
			return CommandListHandle.Attach(wrapper);
		}

		public override uint64 executeCommandLists(Span<ICommandList> pCommandLists, CommandQueue executionQueue)
		{
			int numCommandLists = pCommandLists.Length;
			if (numCommandLists == 0)
				return 0;

			if (pCommandLists.Ptr == null)
			{
				error("executeCommandLists: pCommandLists is NULL");
				return 0;
			}

			List<ICommandList> unwrappedCommandLists = scope .();
			unwrappedCommandLists.Resize(numCommandLists);

			for (int i = 0; i < numCommandLists; i++)
			{
				if (pCommandLists[i] == null)
				{
					String message = scope $"executeCommandLists: pCommandLists[{i}] is NULL";
					error(message);
					return 0;
				}

				readonly ref CommandListParameters desc = ref pCommandLists[i].getDesc();
				if (desc.queueType != executionQueue)
				{
					String message = scope $"executeCommandLists: The command list [{i}] type is {utils.CommandQueueToString(desc.queueType)}, it cannot be executed on a {utils.CommandQueueToString(executionQueue)} queue";
					error(message);
					return 0;
				}

				CommandListWrapper wrapper = pCommandLists[i] as CommandListWrapper;
				if (wrapper != null)
				{
					if (!wrapper.[Friend]requireExecuteState())
						return 0;

					unwrappedCommandLists[i] = wrapper.[Friend]getUnderlyingCommandList();
				}
				else
					unwrappedCommandLists[i] = pCommandLists[i];
			}

			return m_Device.executeCommandLists(unwrappedCommandLists, executionQueue);
		}

		public override void queueWaitForCommandList(CommandQueue waitQueue, CommandQueue executionQueue, uint64 instance)
		{
			m_Device.queueWaitForCommandList(waitQueue, executionQueue, instance);
		}

		public override void waitForIdle()
		{
			m_Device.waitForIdle();
		}

		public override void runGarbageCollection()
		{
			m_Device.runGarbageCollection();
		}

		public override bool queryFeatureSupport(Feature feature, void* pInfo, int infoSize)
		{
			return m_Device.queryFeatureSupport(feature, pInfo, infoSize);
		}

		public override FormatSupport queryFormatSupport(Format format)
		{
			return m_Device.queryFormatSupport(format);
		}

		public override NativeObject getNativeQueue(ObjectType objectType, CommandQueue queue)
		{
			return m_Device.getNativeQueue(objectType, queue);
		}

		public override IMessageCallback getMessageCallback()
		{
			return m_MessageCallback;
		}
	}
}