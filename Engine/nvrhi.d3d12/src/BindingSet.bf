using System.Collections;
using Win32.Graphics.Direct3D12;
using System;
namespace nvrhi.d3d12
{
	class BindingSet : RefCounter<IBindingSet>
	{
		public RefCountPtr<BindingLayout> layout;
		public BindingSetDesc desc;

		// ShaderType . DescriptorIndex
		public DescriptorIndex descriptorTableSRVetc = 0;
		public DescriptorIndex descriptorTableSamplers = 0;
		public RootParameterIndex rootParameterIndexSRVetc = 0;
		public RootParameterIndex rootParameterIndexSamplers = 0;
		public bool descriptorTableValidSRVetc = false;
		public bool descriptorTableValidSamplers = false;
		public bool hasUavBindings = false;

		public StaticVector<(RootParameterIndex index, IBuffer buffer), const c_MaxVolatileConstantBuffersPerLayout> rootParametersVolatileCB;

		public List<RefCountPtr<IResource>> resources = new .() ~ delete  _;

		public List<uint16> bindingsThatNeedTransitions = new .() ~ delete _;

		public this(Context* context, DeviceResources resources)
		{
			m_Context = context;
			m_Resources = resources;
		}

		public ~this()
		{
			m_Resources.shaderResourceViewHeap.releaseDescriptors(descriptorTableSRVetc, (.)layout.descriptorTableSizeSRVetc);

			m_Resources.samplerHeap.releaseDescriptors(descriptorTableSamplers, (.)layout.descriptorTableSizeSamplers);
		}

		public void createDescriptors()
		{
			// Process the volatile constant buffers: they occupy one root parameter each
			for (readonly var parameter in ref layout.rootParametersVolatileCB)
			{
				IBuffer foundBuffer = null;

				RootParameterIndex rootParameterIndex = parameter.index;
				readonly ref D3D12_ROOT_DESCRIPTOR1  rootDescriptor = ref parameter.descriptor;

				for (readonly var binding in ref desc.bindings)
				{
					if (binding.type == ResourceType.VolatileConstantBuffer && binding.slot == rootDescriptor.ShaderRegister)
					{
						Buffer buffer = checked_cast<Buffer, IResource>(binding.resourceHandle);
						resources.Add(buffer);

						foundBuffer = buffer;
						break;
					}
				}

				// Add an entry to the binding set's array, whether we found the buffer in the binding set or not.
				// Even if not found, the command list still has to bind something to the root parameter.
				rootParametersVolatileCB.PushBack((rootParameterIndex, foundBuffer));
			}

			if (layout.descriptorTableSizeSamplers > 0)
			{
				DescriptorIndex descriptorTableBaseIndex = m_Resources.samplerHeap.allocateDescriptors((.)layout.descriptorTableSizeSamplers);
				descriptorTableSamplers = descriptorTableBaseIndex;
				rootParameterIndexSamplers = layout.rootParameterSamplers;
				descriptorTableValidSamplers = true;

				for (readonly var range in ref layout.descriptorRangesSamplers)
				{
					for (uint32 itemInRange = 0; itemInRange < range.NumDescriptors; itemInRange++)
					{
						uint32 slot = range.BaseShaderRegister + itemInRange;
						bool found = false;
						D3D12_CPU_DESCRIPTOR_HANDLE descriptorHandle = m_Resources.samplerHeap.getCpuHandle(
							descriptorTableBaseIndex + range.OffsetInDescriptorsFromTableStart + itemInRange);

						for (readonly var binding in ref desc.bindings)
						{
							if (binding.type == ResourceType.Sampler && binding.slot == slot)
							{
								Sampler sampler = checked_cast<Sampler, IResource>(binding.resourceHandle);
								resources.Add(sampler);

								sampler.createDescriptor((.)descriptorHandle.ptr);
								found = true;
								break;
							}
						}

						if (!found)
						{
							// Create a default sampler
							D3D12_SAMPLER_DESC samplerDesc = .();
							m_Context.device.CreateSampler(&samplerDesc, descriptorHandle);
						}
					}
				}

				m_Resources.samplerHeap.copyToShaderVisibleHeap(descriptorTableBaseIndex, (.)layout.descriptorTableSizeSamplers);
			}

			if (layout.descriptorTableSizeSRVetc > 0)
			{
				DescriptorIndex descriptorTableBaseIndex = m_Resources.shaderResourceViewHeap.allocateDescriptors((.)layout.descriptorTableSizeSRVetc);
				descriptorTableSRVetc = descriptorTableBaseIndex;
				rootParameterIndexSRVetc = layout.rootParameterSRVetc;
				descriptorTableValidSRVetc = true;

				for (readonly var range in ref layout.descriptorRangesSRVetc)
				{
					for (uint32 itemInRange = 0; itemInRange < range.NumDescriptors; itemInRange++)
					{
						uint32 slot = range.BaseShaderRegister + itemInRange;
						bool found = false;
						D3D12_CPU_DESCRIPTOR_HANDLE descriptorHandle = m_Resources.shaderResourceViewHeap.getCpuHandle(
							descriptorTableBaseIndex + range.OffsetInDescriptorsFromTableStart + itemInRange);

						IResource pResource = null;

						for (int bindingIndex = 0; bindingIndex < desc.bindings.Count; bindingIndex++)
						{
							readonly ref BindingSetItem binding = ref desc.bindings[bindingIndex];

							if (binding.slot != slot)
								continue;

							readonly var bindingType = GetNormalizedResourceType(binding.type);

							if (range.RangeType == D3D12_DESCRIPTOR_RANGE_TYPE.D3D12_DESCRIPTOR_RANGE_TYPE_SRV && bindingType == ResourceType.TypedBuffer_SRV)
							{
								if (binding.resourceHandle != null)
								{
									Buffer buffer = checked_cast<Buffer, IResource>(binding.resourceHandle);
									pResource = buffer;

									buffer.createSRV((.)descriptorHandle.ptr, binding.format, binding.range, binding.type);

									if (buffer.permanentState == .Unknown)
										bindingsThatNeedTransitions.Add((uint16)(bindingIndex));
									else
										verifyPermanentResourceState(buffer.permanentState, ResourceStates.ShaderResource,
											false, buffer.desc.debugName, m_Context.messageCallback);
								}
								else
								{
									Buffer.createNullSRV((.)descriptorHandle.ptr, binding.format, m_Context);
								}

								found = true;
								break;
							}
							else if (range.RangeType == D3D12_DESCRIPTOR_RANGE_TYPE.D3D12_DESCRIPTOR_RANGE_TYPE_UAV && bindingType == ResourceType.TypedBuffer_UAV)
							{
								if (binding.resourceHandle != null)
								{
									Buffer buffer = checked_cast<Buffer, IResource>(binding.resourceHandle);
									pResource = buffer;

									buffer.createUAV((.)descriptorHandle.ptr, binding.format, binding.range, binding.type);

									if (buffer.permanentState == .Unknown)
										bindingsThatNeedTransitions.Add((uint16)(bindingIndex));
									else
										verifyPermanentResourceState(buffer.permanentState, ResourceStates.UnorderedAccess,
											false, buffer.desc.debugName, m_Context.messageCallback);
								}
								else
								{
									Buffer.createNullUAV((.)descriptorHandle.ptr, binding.format, m_Context);
								}

								hasUavBindings = true;
								found = true;
								break;
							}
							else if (range.RangeType == D3D12_DESCRIPTOR_RANGE_TYPE.D3D12_DESCRIPTOR_RANGE_TYPE_SRV && bindingType == ResourceType.Texture_SRV)
							{
								Texture texture = checked_cast<Texture, IResource>(binding.resourceHandle);

								TextureSubresourceSet subresources = binding.subresources;

								texture.createSRV((.)descriptorHandle.ptr, binding.format, binding.dimension, subresources);
								pResource = texture;

								if (texture.permanentState == .Unknown)
									bindingsThatNeedTransitions.Add((uint16)(bindingIndex));
								else
									verifyPermanentResourceState(texture.permanentState, ResourceStates.ShaderResource,
										true, texture.desc.debugName, m_Context.messageCallback);

								found = true;
								break;
							}
							else if (range.RangeType == D3D12_DESCRIPTOR_RANGE_TYPE.D3D12_DESCRIPTOR_RANGE_TYPE_UAV && bindingType == ResourceType.Texture_UAV)
							{
								Texture texture = checked_cast<Texture, IResource>(binding.resourceHandle);

								TextureSubresourceSet subresources = binding.subresources;

								texture.createUAV((.)descriptorHandle.ptr, binding.format, binding.dimension, subresources);
								pResource = texture;

								if (texture.permanentState == .Unknown)
									bindingsThatNeedTransitions.Add((uint16)(bindingIndex));
								else
									verifyPermanentResourceState(texture.permanentState, ResourceStates.UnorderedAccess,
										true, texture.desc.debugName, m_Context.messageCallback);

								hasUavBindings = true;
								found = true;
								break;
							}
							else if (range.RangeType == D3D12_DESCRIPTOR_RANGE_TYPE.D3D12_DESCRIPTOR_RANGE_TYPE_SRV && bindingType == ResourceType.RayTracingAccelStruct)
							{
								AccelStruct accelStruct = checked_cast<AccelStruct, IResource>(binding.resourceHandle);
								accelStruct.createSRV((.)descriptorHandle.ptr);
								pResource = accelStruct;

								bindingsThatNeedTransitions.Add((uint16)(bindingIndex));

								found = true;
								break;
							}
							else if (range.RangeType == D3D12_DESCRIPTOR_RANGE_TYPE.D3D12_DESCRIPTOR_RANGE_TYPE_CBV && bindingType == ResourceType.ConstantBuffer)
							{
								Buffer buffer = checked_cast<Buffer, IResource>(binding.resourceHandle);

								buffer.createCBV((.)descriptorHandle.ptr);
								pResource = buffer;

								if (buffer.desc.isVolatile)
								{
									String message = scope $"Attempted to bind a volatile constant buffer {nvrhi.utils.DebugNameToString(buffer.desc.debugName)} to a non-volatile CB layout at slot b{binding.slot}";
									m_Context.error(message);
									found = false;
									break;
								}
								else
								{
									if (buffer.permanentState == .Unknown)
										bindingsThatNeedTransitions.Add((uint16)(bindingIndex));
									else
										verifyPermanentResourceState(buffer.permanentState, ResourceStates.ConstantBuffer,
											false, buffer.desc.debugName, m_Context.messageCallback);
								}

								found = true;
								break;
							}
						}

						if (pResource != null)
						{
							resources.Add(pResource);
						}

						if (!found)
						{
							// Create a null SRV, UAV, or CBV

							switch (range.RangeType)
							{
							case D3D12_DESCRIPTOR_RANGE_TYPE.D3D12_DESCRIPTOR_RANGE_TYPE_SRV:
								Buffer.createNullSRV((.)descriptorHandle.ptr, Format.UNKNOWN, m_Context);
								break;

							case D3D12_DESCRIPTOR_RANGE_TYPE.D3D12_DESCRIPTOR_RANGE_TYPE_UAV:
								Buffer.createNullUAV((.)descriptorHandle.ptr, Format.UNKNOWN, m_Context);
								break;

							case D3D12_DESCRIPTOR_RANGE_TYPE.D3D12_DESCRIPTOR_RANGE_TYPE_CBV:
								m_Context.device.CreateConstantBufferView(null, descriptorHandle);
								break;

							case D3D12_DESCRIPTOR_RANGE_TYPE.D3D12_DESCRIPTOR_RANGE_TYPE_SAMPLER: fallthrough;
							default:
								nvrhi.utils.InvalidEnum();
								break;
							}
						}
					}
				}

				m_Resources.shaderResourceViewHeap.copyToShaderVisibleHeap(descriptorTableBaseIndex, (.)layout.descriptorTableSizeSRVetc);
			}
		}

		public override BindingSetDesc* getDesc()  { return &desc; }
		public override IBindingLayout getLayout()  { return layout; }

		private Context* m_Context;
		private DeviceResources m_Resources;
	}
}