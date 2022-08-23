using Win32.Graphics.Direct3D12;
using System.Collections;
using System;
using nvrhi.d3dcommon;
using Win32.Graphics.Dxgi;
namespace nvrhi.d3d12
{
	class Texture : RefCounter<ITexture>, TextureStateExtension
	{
		public readonly TextureDesc desc;
		public D3D12_RESOURCE_DESC resourceDesc;
		public D3D12RefCountPtr<ID3D12Resource> resource;
		public uint8 planeCount = 1;
		public HeapHandle heap;

		public this(Context* context, DeviceResources resources, TextureDesc desc, D3D12_RESOURCE_DESC resourceDesc)
		{
			this.desc = desc;
			resourceDesc = resourceDesc;
			m_Context = context;
			m_Resources = resources;
			stateInitialized = true;
		}

		public ~this()
		{
			for (var viewEntry in m_RenderTargetViews)
				m_Resources.renderTargetViewHeap.releaseDescriptor(viewEntry.value);

			for (var viewEntry in m_DepthStencilViews)
				m_Resources.depthStencilViewHeap.releaseDescriptor(viewEntry.value);

			for (var index in m_ClearMipLevelUAVs)
				m_Resources.shaderResourceViewHeap.releaseDescriptor(index);

			for (var viewEntry in m_CustomSRVs)
				m_Resources.shaderResourceViewHeap.releaseDescriptor(viewEntry.value);

			for (var viewEntry in m_CustomUAVs)
				m_Resources.shaderResourceViewHeap.releaseDescriptor(viewEntry.value);
		}

		public override readonly ref TextureDesc getDesc() { return ref desc; }

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

		public override NativeObject getNativeView(ObjectType objectType, Format format, TextureSubresourceSet subresources, TextureDimension dimension, bool isReadOnlyDSV = false)
		{
			Compiler.Assert(sizeof(void*) == sizeof(D3D12_CPU_DESCRIPTOR_HANDLE), "Cannot typecast a descriptor to void*");

			switch (objectType)
			{
			case nvrhi.ObjectType.D3D12_ShaderResourceViewGpuDescripror:
				{
					TextureBindingKey key = TextureBindingKey(subresources, format);
					DescriptorIndex descriptorIndex;
					if (!m_CustomSRVs.ContainsKey(key))
					{
						descriptorIndex = m_Resources.shaderResourceViewHeap.allocateDescriptor();
						m_CustomSRVs[key] = descriptorIndex;

						readonly D3D12_CPU_DESCRIPTOR_HANDLE cpuHandle = m_Resources.shaderResourceViewHeap.getCpuHandle(descriptorIndex);
						createSRV((.)cpuHandle.ptr, format, dimension, subresources);
						m_Resources.shaderResourceViewHeap.copyToShaderVisibleHeap(descriptorIndex);
					}
					else
					{
						descriptorIndex = m_CustomSRVs[key];
					}

					return NativeObject(m_Resources.shaderResourceViewHeap.getGpuHandle(descriptorIndex).ptr);
				}

			case nvrhi.ObjectType.D3D12_UnorderedAccessViewGpuDescripror:
				{
					TextureBindingKey key = TextureBindingKey(subresources, format);
					DescriptorIndex descriptorIndex;
					if (!m_CustomUAVs.ContainsKey(key))
					{
						descriptorIndex = m_Resources.shaderResourceViewHeap.allocateDescriptor();
						m_CustomUAVs[key] = descriptorIndex;

						readonly D3D12_CPU_DESCRIPTOR_HANDLE cpuHandle = m_Resources.shaderResourceViewHeap.getCpuHandle(descriptorIndex);
						createUAV((.)cpuHandle.ptr, format, dimension, subresources);
						m_Resources.shaderResourceViewHeap.copyToShaderVisibleHeap(descriptorIndex);
					}
					else
					{
						descriptorIndex = m_CustomUAVs[key];
					}

					return NativeObject(m_Resources.shaderResourceViewHeap.getGpuHandle(descriptorIndex).ptr);
				}
			case nvrhi.ObjectType.D3D12_RenderTargetViewDescriptor:
				{
					TextureBindingKey key = TextureBindingKey(subresources, format);
					DescriptorIndex descriptorIndex;

					if (!m_RenderTargetViews.ContainsKey(key))
					{
						descriptorIndex = m_Resources.renderTargetViewHeap.allocateDescriptor();
						m_RenderTargetViews[key] = descriptorIndex;

						readonly D3D12_CPU_DESCRIPTOR_HANDLE cpuHandle = m_Resources.renderTargetViewHeap.getCpuHandle(descriptorIndex);
						createRTV((.)cpuHandle.ptr, format, subresources);
					}
					else
					{
						descriptorIndex = m_RenderTargetViews[key];
					}

					return NativeObject(m_Resources.renderTargetViewHeap.getCpuHandle(descriptorIndex).ptr);
				}

			case nvrhi.ObjectType.D3D12_DepthStencilViewDescriptor:
				{
					TextureBindingKey key = TextureBindingKey(subresources, format, isReadOnlyDSV);
					DescriptorIndex descriptorIndex;

					if (!m_DepthStencilViews.ContainsKey(key))
					{
						descriptorIndex = m_Resources.depthStencilViewHeap.allocateDescriptor();
						m_DepthStencilViews[key] = descriptorIndex;

						readonly D3D12_CPU_DESCRIPTOR_HANDLE cpuHandle = m_Resources.depthStencilViewHeap.getCpuHandle(descriptorIndex);
						createDSV((.)cpuHandle.ptr, subresources, isReadOnlyDSV);
					}
					else
					{
						descriptorIndex = m_DepthStencilViews[key];
					}

					return NativeObject(m_Resources.depthStencilViewHeap.getCpuHandle(descriptorIndex).ptr);
				}

			default:
				return null;
			}
		}

		public void postCreate()
		{
			if (!String.IsNullOrEmpty(desc.debugName))
			{
				resource.SetName(desc.debugName.ToScopedNativeWChar!());
			}

			if (desc.isUAV)
			{
				m_ClearMipLevelUAVs.Resize(desc.mipLevels);
				m_ClearMipLevelUAVs.Fill(c_InvalidDescriptorIndex);
			}

			planeCount = m_Resources.getFormatPlaneCount(resourceDesc.Format);
		}

		public void createSRV(int descriptor, Format format, TextureDimension dimension, TextureSubresourceSet subresources)
		{
			var dimension;
			var subresources;
			subresources = subresources.resolve(desc, false);

			if (dimension == TextureDimension.Unknown)
				dimension = desc.dimension;

			D3D12_SHADER_RESOURCE_VIEW_DESC viewDesc = .();

			viewDesc.Format = getDxgiFormatMapping(format == Format.UNKNOWN ? desc.format : format).srvFormat;
			viewDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;

			uint32 planeSlice = (viewDesc.Format == DXGI_FORMAT.X24_TYPELESS_G8_UINT) ? 1 : 0;

			switch (dimension)
			{
			case TextureDimension.Texture1D:
				viewDesc.ViewDimension = D3D12_SRV_DIMENSION.TEXTURE1D;
				viewDesc.Texture1D.MostDetailedMip = subresources.baseMipLevel;
				viewDesc.Texture1D.MipLevels = subresources.numMipLevels;
				break;
			case TextureDimension.Texture1DArray:
				viewDesc.ViewDimension = D3D12_SRV_DIMENSION.TEXTURE1DARRAY;
				viewDesc.Texture1DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture1DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture1DArray.MostDetailedMip = subresources.baseMipLevel;
				viewDesc.Texture1DArray.MipLevels = subresources.numMipLevels;
				break;
			case TextureDimension.Texture2D:
				viewDesc.ViewDimension = D3D12_SRV_DIMENSION.TEXTURE2D;
				viewDesc.Texture2D.MostDetailedMip = subresources.baseMipLevel;
				viewDesc.Texture2D.MipLevels = subresources.numMipLevels;
				viewDesc.Texture2D.PlaneSlice = planeSlice;
				break;
			case TextureDimension.Texture2DArray:
				viewDesc.ViewDimension = D3D12_SRV_DIMENSION.TEXTURE2DARRAY;
				viewDesc.Texture2DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture2DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture2DArray.MostDetailedMip = subresources.baseMipLevel;
				viewDesc.Texture2DArray.MipLevels = subresources.numMipLevels;
				viewDesc.Texture2DArray.PlaneSlice = planeSlice;
				break;
			case TextureDimension.TextureCube:
				viewDesc.ViewDimension = D3D12_SRV_DIMENSION.TEXTURECUBE;
				viewDesc.TextureCube.MostDetailedMip = subresources.baseMipLevel;
				viewDesc.TextureCube.MipLevels = subresources.numMipLevels;
				break;
			case TextureDimension.TextureCubeArray:
				viewDesc.ViewDimension = D3D12_SRV_DIMENSION.TEXTURECUBEARRAY;
				viewDesc.TextureCubeArray.First2DArrayFace = subresources.baseArraySlice;
				viewDesc.TextureCubeArray.NumCubes = subresources.numArraySlices / 6;
				viewDesc.TextureCubeArray.MostDetailedMip = subresources.baseMipLevel;
				viewDesc.TextureCubeArray.MipLevels = subresources.numMipLevels;
				break;
			case TextureDimension.Texture2DMS:
				viewDesc.ViewDimension = D3D12_SRV_DIMENSION.TEXTURE2DMS;
				break;
			case TextureDimension.Texture2DMSArray:
				viewDesc.ViewDimension = D3D12_SRV_DIMENSION.TEXTURE2DMSARRAY;
				viewDesc.Texture2DMSArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture2DMSArray.ArraySize = subresources.numArraySlices;
				break;
			case TextureDimension.Texture3D:
				viewDesc.ViewDimension = D3D12_SRV_DIMENSION.TEXTURE3D;
				viewDesc.Texture3D.MostDetailedMip = subresources.baseMipLevel;
				viewDesc.Texture3D.MipLevels = subresources.numMipLevels;
				break;
			case TextureDimension.Unknown: fallthrough;
			default:
				nvrhi.utils.InvalidEnum();
				return;
			}

			m_Context.device.CreateShaderResourceView(resource, &viewDesc, .() { ptr = (.)descriptor });
		}

		public void createUAV(int descriptor, Format format, TextureDimension dimension, TextureSubresourceSet subresources)
		{
			var dimension;
			var subresources;
			subresources = subresources.resolve(desc, true);

			if (dimension == TextureDimension.Unknown)
				dimension = desc.dimension;

			D3D12_UNORDERED_ACCESS_VIEW_DESC viewDesc = .();

			viewDesc.Format = getDxgiFormatMapping(format == Format.UNKNOWN ? desc.format : format).srvFormat;

			switch (desc.dimension)
			{
			case TextureDimension.Texture1D:
				viewDesc.ViewDimension = D3D12_UAV_DIMENSION.TEXTURE1D;
				viewDesc.Texture1D.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture1DArray:
				viewDesc.ViewDimension = D3D12_UAV_DIMENSION.TEXTURE1DARRAY;
				viewDesc.Texture1DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture1DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture1DArray.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2D:
				viewDesc.ViewDimension = D3D12_UAV_DIMENSION.TEXTURE2D;
				viewDesc.Texture2D.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2DArray: fallthrough;
			case TextureDimension.TextureCube: fallthrough;
			case TextureDimension.TextureCubeArray:
				viewDesc.ViewDimension = D3D12_UAV_DIMENSION.TEXTURE2DARRAY;
				viewDesc.Texture2DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture2DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture2DArray.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture3D:
				viewDesc.ViewDimension = D3D12_UAV_DIMENSION.TEXTURE3D;
				viewDesc.Texture3D.FirstWSlice = 0;
				viewDesc.Texture3D.WSize = desc.depth;
				viewDesc.Texture3D.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2DMS: fallthrough;
			case TextureDimension.Texture2DMSArray:
				{
					String message = scope $"Texture {nvrhi.utils.DebugNameToString(desc.debugName)} has unsupported dimension for UAV: {nvrhi.utils.TextureDimensionToString(desc.dimension)}";
					m_Context.error(message);
					return;
				}
			case TextureDimension.Unknown: fallthrough;
			default:
				nvrhi.utils.InvalidEnum();
				return;
			}

			m_Context.device.CreateUnorderedAccessView(resource, null, &viewDesc, .() { ptr = (.)descriptor });
		}

		public void createRTV(int descriptor, Format format, TextureSubresourceSet subresources)
		{
			var subresources;
			subresources = subresources.resolve(desc, true);

			D3D12_RENDER_TARGET_VIEW_DESC viewDesc = .();

			viewDesc.Format = getDxgiFormatMapping(format == Format.UNKNOWN ? desc.format : format).rtvFormat;

			switch (desc.dimension)
			{
			case TextureDimension.Texture1D:
				viewDesc.ViewDimension = D3D12_RTV_DIMENSION.TEXTURE1D;
				viewDesc.Texture1D.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture1DArray:
				viewDesc.ViewDimension = D3D12_RTV_DIMENSION.TEXTURE1DARRAY;
				viewDesc.Texture1DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture1DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture1DArray.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2D:
				viewDesc.ViewDimension = D3D12_RTV_DIMENSION.TEXTURE2D;
				viewDesc.Texture2D.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2DArray: fallthrough;
			case TextureDimension.TextureCube: fallthrough;
			case TextureDimension.TextureCubeArray:
				viewDesc.ViewDimension = D3D12_RTV_DIMENSION.TEXTURE2DARRAY;
				viewDesc.Texture2DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture2DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture2DArray.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2DMS:
				viewDesc.ViewDimension = D3D12_RTV_DIMENSION.TEXTURE2DMS;
				break;
			case TextureDimension.Texture2DMSArray:
				viewDesc.ViewDimension = D3D12_RTV_DIMENSION.TEXTURE2DMSARRAY;
				viewDesc.Texture2DMSArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture2DMSArray.ArraySize = subresources.numArraySlices;
				break;
			case TextureDimension.Texture3D:
				viewDesc.ViewDimension = D3D12_RTV_DIMENSION.TEXTURE3D;
				viewDesc.Texture3D.FirstWSlice = subresources.baseArraySlice;
				viewDesc.Texture3D.WSize = subresources.numArraySlices;
				viewDesc.Texture3D.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Unknown: fallthrough;
			default:
				nvrhi.utils.InvalidEnum();
				return;
			}

			m_Context.device.CreateRenderTargetView(resource, &viewDesc, .() { ptr = (.)descriptor });
		}

		public void createDSV(int descriptor, TextureSubresourceSet subresources, bool isReadOnly = false)
		{
			var subresources;
			subresources = subresources.resolve(desc, true);

			D3D12_DEPTH_STENCIL_VIEW_DESC viewDesc = .();

			viewDesc.Format = getDxgiFormatMapping(desc.format).rtvFormat;

			if (isReadOnly)
			{
				viewDesc.Flags |= D3D12_DSV_FLAGS.READ_ONLY_DEPTH;
				if (viewDesc.Format == DXGI_FORMAT.D24_UNORM_S8_UINT || viewDesc.Format == DXGI_FORMAT.D32_FLOAT_S8X24_UINT)
					viewDesc.Flags |= D3D12_DSV_FLAGS.READ_ONLY_STENCIL;
			}

			switch (desc.dimension)
			{
			case TextureDimension.Texture1D:
				viewDesc.ViewDimension = D3D12_DSV_DIMENSION.TEXTURE1D;
				viewDesc.Texture1D.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture1DArray:
				viewDesc.ViewDimension = D3D12_DSV_DIMENSION.TEXTURE1DARRAY;
				viewDesc.Texture1DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture1DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture1DArray.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2D:
				viewDesc.ViewDimension = D3D12_DSV_DIMENSION.TEXTURE2D;
				viewDesc.Texture2D.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2DArray: fallthrough;
			case TextureDimension.TextureCube: fallthrough;
			case TextureDimension.TextureCubeArray:
				viewDesc.ViewDimension = D3D12_DSV_DIMENSION.TEXTURE2DARRAY;
				viewDesc.Texture2DArray.ArraySize = subresources.numArraySlices;
				viewDesc.Texture2DArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture2DArray.MipSlice = subresources.baseMipLevel;
				break;
			case TextureDimension.Texture2DMS:
				viewDesc.ViewDimension = D3D12_DSV_DIMENSION.TEXTURE2DMS;
				break;
			case TextureDimension.Texture2DMSArray:
				viewDesc.ViewDimension = D3D12_DSV_DIMENSION.TEXTURE2DMSARRAY;
				viewDesc.Texture2DMSArray.FirstArraySlice = subresources.baseArraySlice;
				viewDesc.Texture2DMSArray.ArraySize = subresources.numArraySlices;
				break;
			case TextureDimension.Texture3D:
				{
					String message = scope $"Texture {nvrhi.utils.DebugNameToString(desc.debugName)} has unsupported dimension for DSV: {nvrhi.utils.TextureDimensionToString(desc.dimension)}";
					m_Context.error(message);
					return;
				}
			case TextureDimension.Unknown:  fallthrough;
			default:
				nvrhi.utils.InvalidEnum();
				return;
			}

			m_Context.device.CreateDepthStencilView(resource, &viewDesc, .() { ptr = (.)descriptor });
		}

		public DescriptorIndex getClearMipLevelUAV(uint32 mipLevel)
		{
			Runtime.Assert(desc.isUAV);

			DescriptorIndex descriptorIndex = m_ClearMipLevelUAVs[mipLevel];

			if (descriptorIndex != c_InvalidDescriptorIndex)
				return descriptorIndex;

			descriptorIndex = m_Resources.shaderResourceViewHeap.allocateDescriptor();
			TextureSubresourceSet subresources = .(mipLevel, 1, 0, TextureSubresourceSet.AllArraySlices);
			createUAV((.)m_Resources.shaderResourceViewHeap.getCpuHandle(descriptorIndex).ptr, Format.UNKNOWN, TextureDimension.Unknown, subresources);
			m_Resources.shaderResourceViewHeap.copyToShaderVisibleHeap(descriptorIndex);
			m_ClearMipLevelUAVs[mipLevel] = descriptorIndex;

			return descriptorIndex;
		}

		private Context* m_Context;
		private DeviceResources m_Resources;

		private TextureBindingKey_HashMap<DescriptorIndex> m_RenderTargetViews = new .() ~ delete _;
		private TextureBindingKey_HashMap<DescriptorIndex> m_DepthStencilViews = new .() ~ delete _;
		private TextureBindingKey_HashMap<DescriptorIndex> m_CustomSRVs = new .() ~ delete _;
		private TextureBindingKey_HashMap<DescriptorIndex> m_CustomUAVs = new .() ~ delete _;
		private List<DescriptorIndex> m_ClearMipLevelUAVs = new .() ~ delete _;
		public ResourceStates permanentState { get; set; }

		public bool stateInitialized { get; set; }

	}
}