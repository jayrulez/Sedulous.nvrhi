using System.Collections;
using Win32.Graphics.Direct3D12;
using System;
using nvrhi.d3dcommon;
namespace nvrhi.d3d12
{
	class BindingLayout : RefCounter<IBindingLayout>
	{
	    public BindingLayoutDesc desc;
	    public uint32 pushConstantByteSize = 0;
	    public RootParameterIndex rootParameterPushConstants = ~0u;
	    public RootParameterIndex rootParameterSRVetc = ~0u;
	    public RootParameterIndex rootParameterSamplers = ~0u;
	    public int32 descriptorTableSizeSRVetc = 0;
	    public int32 descriptorTableSizeSamplers = 0;
	    public List<D3D12_DESCRIPTOR_RANGE1> descriptorRangesSRVetc;
	    public List<D3D12_DESCRIPTOR_RANGE1> descriptorRangesSamplers;
	    public List<BindingLayoutItem> bindingLayoutsSRVetc;
	    public StaticVector<(RootParameterIndex index, D3D12_ROOT_DESCRIPTOR1 descriptor), const c_MaxVolatileConstantBuffersPerLayout> rootParametersVolatileCB;
	    public StaticVector<D3D12_ROOT_PARAMETER1, 32> rootParameters;

	    public this(BindingLayoutDesc _desc){
			desc = _desc;

			// Start with some invalid values, to make sure that we start a new range on the first binding
			ResourceType currentType = (ResourceType)(-1);
			uint32 currentSlot = ~0u;

			D3D12_ROOT_CONSTANTS rootConstants = .();

			for (readonly ref BindingLayoutItem binding in ref desc.bindings)
			{
			    if (binding.type == ResourceType.VolatileConstantBuffer)
			    {
			        D3D12_ROOT_DESCRIPTOR1 rootDescriptor;
			        rootDescriptor.ShaderRegister = binding.slot;
			        rootDescriptor.RegisterSpace = desc.registerSpace;

			        // Volatile CBs are static descriptors, however strange that may seem.
			        // A volatile CB can only be bound to a command list after it's been written into, and 
			        // after that the data will not change until the command list has finished executing.
			        // Subsequent writes will be made into a newly allocated portion of an upload buffer.
			        rootDescriptor.Flags = D3D12_ROOT_DESCRIPTOR_FLAGS.D3D12_ROOT_DESCRIPTOR_FLAG_DATA_STATIC;

			        rootParametersVolatileCB.PushBack(((.)-1, rootDescriptor));
			    }
			    else if (binding.type == ResourceType.PushConstants)
			    {
			        pushConstantByteSize = binding.size;
			        rootConstants.ShaderRegister = binding.slot;
			        rootConstants.RegisterSpace = desc.registerSpace;
			        rootConstants.Num32BitValues = binding.size / 4;
			    }
			    else if (!AreResourceTypesCompatible(binding.type, currentType) || binding.slot != currentSlot + 1)
			    {
			        // Start a new range

			        if (binding.type == ResourceType.Sampler)
			        {
			            descriptorRangesSamplers.Resize(descriptorRangesSamplers.Count + 1);
			            ref D3D12_DESCRIPTOR_RANGE1 range = ref descriptorRangesSamplers[descriptorRangesSamplers.Count - 1];

			            range.RangeType = D3D12_DESCRIPTOR_RANGE_TYPE.D3D12_DESCRIPTOR_RANGE_TYPE_SAMPLER;
			            range.NumDescriptors = 1;
			            range.BaseShaderRegister = binding.slot;
			            range.RegisterSpace = desc.registerSpace;
			            range.OffsetInDescriptorsFromTableStart = (.)descriptorTableSizeSamplers;
			            range.Flags = D3D12_DESCRIPTOR_RANGE_FLAGS.D3D12_DESCRIPTOR_RANGE_FLAG_NONE;

			            descriptorTableSizeSamplers += 1;
			        }
			        else
			        {
			            descriptorRangesSRVetc.Resize(descriptorRangesSRVetc.Count + 1);
			            ref D3D12_DESCRIPTOR_RANGE1 range = ref descriptorRangesSRVetc[descriptorRangesSRVetc.Count - 1];

			            switch (binding.type)
			            {
			            case ResourceType.Texture_SRV: fallthrough;
			            case ResourceType.TypedBuffer_SRV: fallthrough;
			            case ResourceType.StructuredBuffer_SRV: fallthrough;
			            case ResourceType.RawBuffer_SRV: fallthrough;
			            case ResourceType.RayTracingAccelStruct:
			                range.RangeType = D3D12_DESCRIPTOR_RANGE_TYPE.D3D12_DESCRIPTOR_RANGE_TYPE_SRV;
			                break;

			            case ResourceType.Texture_UAV: fallthrough;
			            case ResourceType.TypedBuffer_UAV: fallthrough;
			            case ResourceType.StructuredBuffer_UAV: fallthrough;
			            case ResourceType.RawBuffer_UAV:
			                range.RangeType = D3D12_DESCRIPTOR_RANGE_TYPE.D3D12_DESCRIPTOR_RANGE_TYPE_UAV;
			                break;

			            case ResourceType.ConstantBuffer:
			                range.RangeType = D3D12_DESCRIPTOR_RANGE_TYPE.D3D12_DESCRIPTOR_RANGE_TYPE_CBV;
			                break;

			            case ResourceType.None: fallthrough;
			            case ResourceType.VolatileConstantBuffer: fallthrough;
			            case ResourceType.Sampler: fallthrough;
			            case ResourceType.PushConstants: fallthrough;
			            case ResourceType.Count: fallthrough;
			            default:
			                nvrhi.utils.InvalidEnum();
			                continue;
			            }
			            range.NumDescriptors = 1;
			            range.BaseShaderRegister = binding.slot;
			            range.RegisterSpace = desc.registerSpace;
			            range.OffsetInDescriptorsFromTableStart = (.)descriptorTableSizeSRVetc;

			            // We don't know how apps will use resources referenced in a binding set. They may bind 
			            // a buffer to the command list and then copy data into it.
			            range.Flags = D3D12_DESCRIPTOR_RANGE_FLAGS.D3D12_DESCRIPTOR_RANGE_FLAG_DATA_VOLATILE;

			            descriptorTableSizeSRVetc += 1;

			            bindingLayoutsSRVetc.Add(binding);
			        }

			        currentType = binding.type;
			        currentSlot = binding.slot;
			    }
			    else
			    {
			        // Extend the current range

			        if (binding.type == ResourceType.Sampler)
			        {
			            Runtime.Assert(!descriptorRangesSamplers.IsEmpty);
			            ref D3D12_DESCRIPTOR_RANGE1 range = ref descriptorRangesSamplers[descriptorRangesSamplers.Count - 1];

			            range.NumDescriptors += 1;
			            descriptorTableSizeSamplers += 1;
			        }
			        else
			        {
			            Runtime.Assert(!descriptorRangesSRVetc.IsEmpty);
			            ref D3D12_DESCRIPTOR_RANGE1 range = ref descriptorRangesSRVetc[descriptorRangesSRVetc.Count - 1];

			            range.NumDescriptors += 1;
			            descriptorTableSizeSRVetc += 1;

			            bindingLayoutsSRVetc.Add(binding);
			        }

			        currentSlot = binding.slot;
			    }
			}

			// A PipelineBindingLayout occupies a contiguous segment of a root signature.
			// The root parameter indices stored here are relative to the beginning of that segment, not to the RS item 0.

			rootParameters.Resize(0);

			if (rootConstants.Num32BitValues > 0)
			{
			    //D3D12_ROOT_PARAMETER1& param = rootParameters.emplace_back();
				D3D12_ROOT_PARAMETER1 param= .();

			    param.ParameterType = D3D12_ROOT_PARAMETER_TYPE.D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS;
			    param.Constants = rootConstants;

				rootParameters.PushBack(param);

			    rootParameterPushConstants = RootParameterIndex(rootParameters.Count - 1);
			}

			for (var rootParameterVolatileCB in ref rootParametersVolatileCB)
			{
			    rootParameters.Resize(rootParameters.Count + 1);
			    ref D3D12_ROOT_PARAMETER1 param = ref rootParameters[rootParameters.Count - 1];

			    param.ParameterType = D3D12_ROOT_PARAMETER_TYPE.D3D12_ROOT_PARAMETER_TYPE_CBV;
			    param.ShaderVisibility = convertShaderStage(desc.visibility);
			    param.Descriptor = rootParameterVolatileCB.descriptor;

			    rootParameterVolatileCB.index = RootParameterIndex(rootParameters.Count - 1);
			}

			if (descriptorTableSizeSamplers > 0)
			{
			    rootParameters.Resize(rootParameters.Count + 1);
			    ref D3D12_ROOT_PARAMETER1 param = ref rootParameters[rootParameters.Count - 1];

			    param.ParameterType = D3D12_ROOT_PARAMETER_TYPE.D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
			    param.ShaderVisibility = convertShaderStage(desc.visibility);
			    param.DescriptorTable.NumDescriptorRanges = UINT(descriptorRangesSamplers.Count);
			    param.DescriptorTable.pDescriptorRanges = &descriptorRangesSamplers[0];

			    rootParameterSamplers = RootParameterIndex(rootParameters.Count - 1);
			}

			if (descriptorTableSizeSRVetc > 0)
			{
			    rootParameters.Resize(rootParameters.Count + 1);
			    ref D3D12_ROOT_PARAMETER1 param = ref rootParameters[rootParameters.Count - 1];

			    param.ParameterType = D3D12_ROOT_PARAMETER_TYPE.D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
			    param.ShaderVisibility = convertShaderStage(desc.visibility);
			    param.DescriptorTable.NumDescriptorRanges = UINT(descriptorRangesSRVetc.Count);
			    param.DescriptorTable.pDescriptorRanges = &descriptorRangesSRVetc[0];

			    rootParameterSRVetc = RootParameterIndex(rootParameters.Count - 1);
			}
		}

	    public override BindingLayoutDesc* getDesc()  { return &desc; }
	    public override BindlessLayoutDesc* getBindlessDesc()  { return null; }
	}
}