using Win32.Graphics.Direct3D12;
namespace nvrhi.d3d12
{
	class BindlessLayout : RefCounter<IBindingLayout>
	{
		public BindlessLayoutDesc desc;
		public StaticVector<D3D12_DESCRIPTOR_RANGE1, 32> descriptorRanges;
		public D3D12_ROOT_PARAMETER1 rootParameter = .();

		public this(BindlessLayoutDesc _desc)
		{
			desc = desc;

			descriptorRanges.Resize(0);

			for (readonly ref BindingLayoutItem item in ref desc.registerSpaces)
			{
				D3D12_DESCRIPTOR_RANGE_TYPE rangeType;

				switch (item.type)
				{
				case ResourceType.Texture_SRV: fallthrough;
				case ResourceType.TypedBuffer_SRV: fallthrough;
				case ResourceType.StructuredBuffer_SRV: fallthrough;
				case ResourceType.RawBuffer_SRV: fallthrough;
				case ResourceType.RayTracingAccelStruct:
					rangeType = D3D12_DESCRIPTOR_RANGE_TYPE.SRV;
					break;

				case ResourceType.ConstantBuffer:
					rangeType = D3D12_DESCRIPTOR_RANGE_TYPE.CBV;
					break;

				case ResourceType.Texture_UAV: fallthrough;
				case ResourceType.TypedBuffer_UAV: fallthrough;
				case ResourceType.StructuredBuffer_UAV: fallthrough;
				case ResourceType.RawBuffer_UAV:
					rangeType = D3D12_DESCRIPTOR_RANGE_TYPE.UAV;
					break;

				case ResourceType.Sampler:
					rangeType = D3D12_DESCRIPTOR_RANGE_TYPE.SAMPLER;
					break;

				case ResourceType.None: fallthrough;
				case ResourceType.VolatileConstantBuffer: fallthrough;
				case ResourceType.PushConstants: fallthrough;
				case ResourceType.Count: fallthrough;
				default:
					nvrhi.utils.InvalidEnum();
					continue;
				}

				ref D3D12_DESCRIPTOR_RANGE1 descriptorRange = ref descriptorRanges.AddAndGetRef();

				descriptorRange.RangeType = rangeType;
				descriptorRange.NumDescriptors = ~0u; // unbounded
				descriptorRange.BaseShaderRegister = desc.firstSlot;
				descriptorRange.RegisterSpace = item.slot;
				descriptorRange.Flags = D3D12_DESCRIPTOR_RANGE_FLAGS.DESCRIPTORS_VOLATILE;
				descriptorRange.OffsetInDescriptorsFromTableStart = 0;
			}

			rootParameter.ParameterType = D3D12_ROOT_PARAMETER_TYPE.DESCRIPTOR_TABLE;
			rootParameter.ShaderVisibility = convertShaderStage(desc.visibility);
			rootParameter.DescriptorTable.NumDescriptorRanges = uint32(descriptorRanges.Count);
			rootParameter.DescriptorTable.pDescriptorRanges = &descriptorRanges[0];
		}

		public override BindingLayoutDesc* getDesc()  { return null; }
		public override BindlessLayoutDesc* getBindlessDesc() { return &desc; }
	}
}