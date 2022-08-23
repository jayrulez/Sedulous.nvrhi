using Win32.Graphics.Direct3D12;
using System;
using nvrhi.d3dcommon;
using Win32.Graphics.Dxgi;
namespace nvrhi.d3d12
{
	class Buffer : RefCounter<IBuffer>, BufferStateExtension
	{
		public readonly BufferDesc desc;
		public D3D12RefCountPtr<ID3D12Resource> resource;
		public D3D12_GPU_VIRTUAL_ADDRESS gpuVA = .();
		public D3D12_RESOURCE_DESC resourceDesc = .();

		public HeapHandle heap;

		public D3D12RefCountPtr<ID3D12Fence> lastUseFence;
		public uint64 lastUseFenceValue = 0;

		public this(Context* context, DeviceResources resources, BufferDesc desc)
		{
			this.desc = desc;
			m_Context = context;
			m_Resources = resources;
		}

		public ~this()
		{
			if (m_ClearUAV != c_InvalidDescriptorIndex)
			{
				m_Resources.shaderResourceViewHeap.releaseDescriptor(m_ClearUAV);
				m_ClearUAV = c_InvalidDescriptorIndex;
			}
		}

		public override readonly ref BufferDesc getDesc() { return ref desc; }

		public override NativeObject getNativeObject(ObjectType objectType)
		{
			switch (objectType)
			{
			case ObjectType.D3D12_Resource:
				return NativeObject(resource);
			default:
				return null;
			}
		}

		public void postCreate()
		{
			gpuVA = resource.GetGPUVirtualAddress();

			if (!String.IsNullOrEmpty(desc.debugName))
			{
				resource.SetName(desc.debugName.ToScopedNativeWChar!());
			}
		}

		public DescriptorIndex getClearUAV()
		{
			Runtime.Assert(desc.canHaveUAVs);

			if (m_ClearUAV != c_InvalidDescriptorIndex)
				return m_ClearUAV;

			m_ClearUAV = m_Resources.shaderResourceViewHeap.allocateDescriptor();
			createUAV((.)m_Resources.shaderResourceViewHeap.getCpuHandle(m_ClearUAV).ptr, Format.R32_UINT,
				EntireBuffer, ResourceType.TypedBuffer_UAV);
			m_Resources.shaderResourceViewHeap.copyToShaderVisibleHeap(m_ClearUAV);
			return m_ClearUAV;
		}

		public void createCBV(int descriptor)
		{
			Runtime.Assert(desc.isConstantBuffer);
			Runtime.Assert(desc.byteSize <= UINT.MaxValue);

			D3D12_CONSTANT_BUFFER_VIEW_DESC viewDesc;
			viewDesc.BufferLocation = resource.GetGPUVirtualAddress();
			viewDesc.SizeInBytes = (UINT)desc.byteSize;
			m_Context.device.CreateConstantBufferView(&viewDesc, .() { ptr = (.)descriptor });
		}

		public void createSRV(int descriptor, Format format, BufferRange range, ResourceType type)
		{
			var format;
			var range;
			D3D12_SHADER_RESOURCE_VIEW_DESC viewDesc = .();

			viewDesc.ViewDimension = D3D12_SRV_DIMENSION.BUFFER;
			viewDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;

			if (format == Format.UNKNOWN)
			{
				format = desc.format;
			}

			range = range.resolve(desc);

			switch (type) // NOLINT(clang-diagnostic-switch-enum)
			{
			case ResourceType.StructuredBuffer_SRV:
				Runtime.Assert(desc.structStride != 0);
				viewDesc.Format = DXGI_FORMAT.UNKNOWN;
				viewDesc.Buffer.FirstElement = range.byteOffset / desc.structStride;
				viewDesc.Buffer.NumElements = (UINT)(range.byteSize / desc.structStride);
				viewDesc.Buffer.StructureByteStride = desc.structStride;
				break;

			case ResourceType.RawBuffer_SRV:
				viewDesc.Format = DXGI_FORMAT.R32_TYPELESS;
				viewDesc.Buffer.FirstElement = range.byteOffset / 4;
				viewDesc.Buffer.NumElements = (UINT)(range.byteSize / 4);
				viewDesc.Buffer.Flags = D3D12_BUFFER_SRV_FLAGS.RAW;
				break;

			case ResourceType.TypedBuffer_SRV:
				{
					Runtime.Assert(format != Format.UNKNOWN);
					readonly ref DxgiFormatMapping mapping = ref getDxgiFormatMapping(format);
					readonly ref FormatInfo formatInfo = ref getFormatInfo(format);

					viewDesc.Format = mapping.srvFormat;
					viewDesc.Buffer.FirstElement = range.byteOffset / formatInfo.bytesPerBlock;
					viewDesc.Buffer.NumElements = (UINT)(range.byteSize / formatInfo.bytesPerBlock);
					break;
				}

			default:
				nvrhi.utils.InvalidEnum();
				return;
			}

			m_Context.device.CreateShaderResourceView(resource, &viewDesc, .() { ptr = (.)descriptor });
		}

		public void createUAV(int descriptor, Format format, BufferRange range, ResourceType type)
		{
			var format;
			var range;
			D3D12_UNORDERED_ACCESS_VIEW_DESC viewDesc = .();

			viewDesc.ViewDimension = D3D12_UAV_DIMENSION.BUFFER;

			if (format == Format.UNKNOWN)
			{
				format = desc.format;
			}

			range = range.resolve(desc);

			switch (type) // NOLINT(clang-diagnostic-switch-enum)
			{
			case ResourceType.StructuredBuffer_UAV:
				Runtime.Assert(desc.structStride != 0);
				viewDesc.Format = DXGI_FORMAT.UNKNOWN;
				viewDesc.Buffer.FirstElement = range.byteOffset / desc.structStride;
				viewDesc.Buffer.NumElements = (UINT)(range.byteSize / desc.structStride);
				viewDesc.Buffer.StructureByteStride = desc.structStride;
				break;

			case ResourceType.RawBuffer_UAV:
				viewDesc.Format = DXGI_FORMAT.R32_TYPELESS;
				viewDesc.Buffer.FirstElement = range.byteOffset / 4;
				viewDesc.Buffer.NumElements = (UINT)(range.byteSize / 4);
				viewDesc.Buffer.Flags = D3D12_BUFFER_UAV_FLAGS.RAW;
				break;

			case ResourceType.TypedBuffer_UAV:
				{
					Runtime.Assert(format != Format.UNKNOWN);
					readonly ref DxgiFormatMapping mapping = ref getDxgiFormatMapping(format);
					readonly ref FormatInfo formatInfo = ref getFormatInfo(format);

					viewDesc.Format = mapping.srvFormat;
					viewDesc.Buffer.FirstElement = range.byteOffset / formatInfo.bytesPerBlock;
					viewDesc.Buffer.NumElements = (UINT)(range.byteSize / formatInfo.bytesPerBlock);
					break;
				}

			default:
				nvrhi.utils.InvalidEnum();
				return;
			}

			m_Context.device.CreateUnorderedAccessView(resource, null, &viewDesc, .() { ptr = (.)descriptor });
		}

		public static void createNullSRV(int descriptor, Format format, Context* context)
		{
			readonly ref DxgiFormatMapping mapping = ref getDxgiFormatMapping(format == Format.UNKNOWN ? Format.R32_UINT : format);

			D3D12_SHADER_RESOURCE_VIEW_DESC viewDesc = .();
			viewDesc.Format = mapping.srvFormat;
			viewDesc.ViewDimension = D3D12_SRV_DIMENSION.BUFFER;
			viewDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
			context.device.CreateShaderResourceView(null, &viewDesc, .() { ptr = (.)descriptor });
		}

		public static void createNullUAV(int descriptor, Format format, Context* context)
		{
			readonly ref DxgiFormatMapping mapping = ref getDxgiFormatMapping(format == Format.UNKNOWN ? Format.R32_UINT : format);

			D3D12_UNORDERED_ACCESS_VIEW_DESC viewDesc = .();
			viewDesc.Format = mapping.srvFormat;
			viewDesc.ViewDimension = D3D12_UAV_DIMENSION.BUFFER;
			context.device.CreateUnorderedAccessView(null, null, &viewDesc, .() { ptr = (.)descriptor });
		}

		private Context* m_Context;
		private DeviceResources m_Resources;
		private DescriptorIndex m_ClearUAV = c_InvalidDescriptorIndex;

		public ResourceStates permanentState { get; set; }


	}
}