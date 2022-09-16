using Win32.Graphics.Direct3D11;
using Win32.Foundation;
using System;
using System.Collections;
using nvrhi.d3dcommon;
namespace nvrhi.d3d11;

class DeviceD3D11 : RefCounter<nvrhi.IDevice>
{
	public this(D3D11DeviceDesc desc)
	{
		m_Context.messageCallback = desc.messageCallback;
		m_Context.immediateContext = desc.context;
		desc.context.GetDevice(&m_Context.device);

#if NVRHI_D3D11_WITH_NVAPI
		m_Context.nvapiAvailable = NvAPI_Initialize() == NVAPI_OK;

		if (m_Context.nvapiAvailable)
		{
			NV_QUERY_SINGLE_PASS_STEREO_SUPPORT_PARAMS stereoParams{};
			stereoParams.version = NV_QUERY_SINGLE_PASS_STEREO_SUPPORT_PARAMS_VER;

			if (NvAPI_D3D_QuerySinglePassStereoSupport(m_Context.device, &stereoParams) == NVAPI_OK && stereoParams.bSinglePassStereoSupported)
			{
				m_SinglePassStereoSupported = true;
			}

			// There is no query for FastGS, so query support for FP16 atomics as a proxy.
			// Both features were introduced in the same architecture (Maxwell).
			bool supported = false;
			if (NvAPI_D3D11_IsNvShaderExtnOpCodeSupported(m_Context.device, NV_EXTN_OP_FP16_ATOMIC, &supported) == NVAPI_OK && supported)
			{
				m_FastGeometryShaderSupported = true;
			}
		}
#endif

		D3D11_BUFFER_DESC bufferDesc = .();
		bufferDesc.ByteWidth = c_MaxPushConstantSize;
		bufferDesc.BindFlags = (.)D3D11_BIND_FLAG.D3D11_BIND_CONSTANT_BUFFER;
		bufferDesc.Usage = .D3D11_USAGE_DEFAULT;
		bufferDesc.CPUAccessFlags = 0;
		readonly HRESULT res = m_Context.device.CreateBuffer(&bufferDesc, null, &m_Context.pushConstantBuffer);

		if (FAILED(res))
		{
			String message = scope $"CreateBuffer call failed for the push constants buffer, HRESULT = 0x{res:X}";
			m_Context.error(message);
		}

		m_ImmediateCommandList = CommandListHandle.Attach(new CommandListD3D11(m_Context, this, .()));
	}

	// IResource implementation

	public override NativeObject getNativeObject(ObjectType objectType)
	{
		switch (objectType)
		{
		case ObjectType.D3D11_Device:
			return NativeObject(m_Context.device);
		case ObjectType.D3D11_DeviceContext:
			return NativeObject(m_Context.immediateContext);
		case ObjectType.Nvrhi_D3D11_Device:
			return Internal.UnsafeCastToPtr(this);
		default:
			return null;
		}
	}

	// IDevice implementation

	public override HeapHandle createHeap(HeapDesc d)
	{
		nvrhi.utils.NotSupported();
		return null;
	}

	public override TextureHandle createTexture(TextureDesc d)
	{
		return createTexture(d, CpuAccessMode.None);
	}

	public override MemoryRequirements getTextureMemoryRequirements(ITexture texture)
	{
		nvrhi.utils.NotSupported();
		return MemoryRequirements();
	}
	public override bool bindTextureMemory(ITexture texture, IHeap heap, uint64 offset)
	{
		nvrhi.utils.NotSupported();
		return false;
	}

	public override TextureHandle createHandleForNativeTexture(ObjectType objectType, NativeObject _texture, TextureDesc desc)
	{
		if (_texture.pointer == null)
			return null;

		if (objectType != ObjectType.D3D11_Resource)
			return null;

		TextureD3D11 texture = new TextureD3D11(m_Context);
		texture.desc = desc;
		texture.resource = (ID3D11Resource*)(_texture.pointer);

		return TextureHandle.Attach(texture);
	}

	public override StagingTextureHandle createStagingTexture(TextureDesc d, CpuAccessMode cpuAccess)
	{
		Runtime.Assert(cpuAccess != CpuAccessMode.None);
		StagingTextureD3D11 ret = new StagingTextureD3D11();
		TextureHandle t = createTexture(d, cpuAccess);
		ret.texture = checked_cast<TextureD3D11, ITexture>(t.Get<ITexture>());
		ret.cpuAccess = cpuAccess;
		return StagingTextureHandle.Attach(ret);
	}

	public override void* mapStagingTexture(IStagingTexture _stagingTexture, TextureSlice slice, CpuAccessMode cpuAccess, int* outRowPitch)
	{
		StagingTextureD3D11 stagingTexture = checked_cast<StagingTextureD3D11, IStagingTexture>(_stagingTexture);

		Runtime.Assert(slice.x == 0);
		Runtime.Assert(slice.y == 0);
		Runtime.Assert(cpuAccess != CpuAccessMode.None);

		TextureD3D11 t = stagingTexture.texture;
		var resolvedSlice = slice.resolve(t.desc);

		D3D11_MAP mapType;
		switch (cpuAccess) // NOLINT(clang-diagnostic-switch-enum)
		{
		case CpuAccessMode.Read:
			Runtime.Assert(stagingTexture.cpuAccess == CpuAccessMode.Read);
			mapType = .D3D11_MAP_READ;
			break;

		case CpuAccessMode.Write:
			Runtime.Assert(stagingTexture.cpuAccess == CpuAccessMode.Write);
			mapType = .D3D11_MAP_WRITE;
			break;

		default:
			m_Context.error("Unsupported CpuAccessMode in mapStagingTexture");
			return null;
		}
		UINT subresource = D3D11CalcSubresource(resolvedSlice.mipLevel, resolvedSlice.arraySlice, t.desc.mipLevels);

		D3D11_MAPPED_SUBRESOURCE res = .();
		if (SUCCEEDED(m_Context.immediateContext.Map(t.resource, subresource, mapType, 0, &res)))
		{
			stagingTexture.mappedSubresource = subresource;
			*outRowPitch = (int)res.RowPitch;
			return res.pData;
		} else
		{
			return null;
		}
	}

	public override void unmapStagingTexture(IStagingTexture _t)
	{
		StagingTextureD3D11 t = checked_cast<StagingTextureD3D11, IStagingTexture>(_t);

		Runtime.Assert(t.mappedSubresource != UINT(-1));
		m_Context.immediateContext.Unmap(t.texture.resource, t.mappedSubresource);
		t.mappedSubresource = UINT(-1);
	}

	public override BufferHandle createBuffer(BufferDesc d)
	{
		Runtime.Assert(d.byteSize <= uint64.MaxValue);

		D3D11_BUFFER_DESC desc11 = .();
		desc11.ByteWidth = (UINT)d.byteSize;

		// These don't map exactly, but it should be generally correct
		switch (d.cpuAccess)
		{
		case CpuAccessMode.None:
			desc11.Usage = .D3D11_USAGE_DEFAULT;
			desc11.CPUAccessFlags = 0;
			break;

		case CpuAccessMode.Read:
			desc11.Usage = .D3D11_USAGE_STAGING;
			desc11.CPUAccessFlags = (.)D3D11_CPU_ACCESS_FLAG.D3D11_CPU_ACCESS_READ;
			break;

		case CpuAccessMode.Write:
			desc11.Usage = .D3D11_USAGE_DYNAMIC;
			desc11.CPUAccessFlags = (.)D3D11_CPU_ACCESS_FLAG.D3D11_CPU_ACCESS_WRITE;
			break;
		}

		if (d.isConstantBuffer)
		{
			desc11.BindFlags = (.)D3D11_BIND_FLAG.D3D11_BIND_CONSTANT_BUFFER;
			desc11.ByteWidth = align(desc11.ByteWidth, 16u);
		}
		else
		{
			desc11.BindFlags = 0;

			if (desc11.Usage != .D3D11_USAGE_STAGING)
				desc11.BindFlags |= (.)D3D11_BIND_FLAG.D3D11_BIND_SHADER_RESOURCE;

			if (d.canHaveUAVs)
				desc11.BindFlags |= (.)D3D11_BIND_FLAG.D3D11_BIND_UNORDERED_ACCESS;

			if (d.isIndexBuffer)
				desc11.BindFlags |= (.)D3D11_BIND_FLAG.D3D11_BIND_INDEX_BUFFER;

			if (d.isVertexBuffer)
				desc11.BindFlags |= (.)D3D11_BIND_FLAG.D3D11_BIND_VERTEX_BUFFER;
		}

		desc11.MiscFlags = 0;
		if (d.isDrawIndirectArgs)
			desc11.MiscFlags |= (.)D3D11_RESOURCE_MISC_FLAG.D3D11_RESOURCE_MISC_DRAWINDIRECT_ARGS;

		if (d.structStride != 0)
			desc11.MiscFlags |= (.)D3D11_RESOURCE_MISC_FLAG.D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;

		if (d.canHaveRawViews)
			desc11.MiscFlags |= (.)D3D11_RESOURCE_MISC_FLAG.D3D11_RESOURCE_MISC_BUFFER_ALLOW_RAW_VIEWS;

		desc11.StructureByteStride = (UINT)d.structStride;

		if ((d.sharedResourceFlags & SharedResourceFlags.Shared_NTHandle) != 0)
			desc11.MiscFlags |= (.)D3D11_RESOURCE_MISC_FLAG.D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX | (.)D3D11_RESOURCE_MISC_FLAG.D3D11_RESOURCE_MISC_SHARED_NTHANDLE;
		else if ((d.sharedResourceFlags & SharedResourceFlags.Shared) != 0)
			desc11.MiscFlags |= (.)D3D11_RESOURCE_MISC_FLAG.D3D11_RESOURCE_MISC_SHARED;

		D3D11RefCountPtr<ID3D11Buffer> newBuffer = null;
		readonly HRESULT res = m_Context.device.CreateBuffer(&desc11, null, &newBuffer);
		if (FAILED(res))
		{
			String message = scope $"CreataeBuffer call failed for buffer {nvrhi.utils.DebugNameToString(d.debugName)}, HRESULT = 0x{res:X}";
			m_Context.error(message);
			return null;
		}

		if (!String.IsNullOrEmpty(d.debugName))
			SetDebugName(newBuffer, d.debugName);

		BufferD3D11 buffer = new BufferD3D11(m_Context);
		buffer.desc = d;
		buffer.resource = newBuffer;
		return BufferHandle.Attach(buffer);
	}
	public override void* mapBuffer(IBuffer _buffer, CpuAccessMode flags)
	{
		BufferD3D11 buffer = checked_cast<BufferD3D11, IBuffer>(_buffer);

		D3D11_MAP mapType;
		switch (flags) // NOLINT(clang-diagnostic-switch-enum)
		{
		case CpuAccessMode.Read:
			Runtime.Assert(buffer.desc.cpuAccess == CpuAccessMode.Read);
			mapType = .D3D11_MAP_READ;
			break;

		case CpuAccessMode.Write:
			Runtime.Assert(buffer.desc.cpuAccess == CpuAccessMode.Write);
			mapType = .D3D11_MAP_WRITE_DISCARD;
			break;

		default:
			m_Context.error("Unsupported CpuAccessMode in mapBuffer");
			return null;
		}

		D3D11_MAPPED_SUBRESOURCE res = .();
		if (SUCCEEDED(m_Context.immediateContext.Map(buffer.resource, 0, mapType, 0, &res)))
		{
			return res.pData;
		} else
		{
			return null;
		}
	}

	public override void unmapBuffer(IBuffer _buffer)
	{
		BufferD3D11 buffer = checked_cast<BufferD3D11, IBuffer>(_buffer);

		m_Context.immediateContext.Unmap(buffer.resource, 0);
	}
	public override MemoryRequirements getBufferMemoryRequirements(IBuffer buffer)
	{
		nvrhi.utils.NotSupported();
		return MemoryRequirements();
	}
	public override bool bindBufferMemory(IBuffer buffer, IHeap heap, uint64 offset)
	{
		nvrhi.utils.NotSupported();
		return false;
	}

	public override BufferHandle createHandleForNativeBuffer(ObjectType objectType, NativeObject _buffer, BufferDesc desc)
	{
		if (_buffer.pointer == null)
			return null;

		if (objectType != ObjectType.D3D11_Buffer)
			return null;

		ID3D11Buffer* pBuffer = (ID3D11Buffer*)(_buffer.pointer);

		BufferD3D11 buffer = new BufferD3D11(m_Context);
		buffer.desc = desc;
		buffer.resource = pBuffer;
		return BufferHandle.Attach(buffer);
	}


#if NVRHI_D3D11_WITH_NVAPI
	private static bool convertCustomSemantics(uint32 numSemantics, const CustomSemantic* semantics, List<NV_CUSTOM_SEMANTIC> output)
	{
		output.resize(numSemantics);
		for (uint32 i = 0; i < numSemantics; i++)
		{
			const CustomSemantic& src = semantics[i];
			NV_CUSTOM_SEMANTIC& dst = output[i];

			dst.version = NV_CUSTOM_SEMANTIC_VERSION;
			dst.RegisterMask = 0;
			dst.RegisterNum = 0;
			dst.RegisterSpecified = FALSE;
			dst.Reserved = 0;

			strncpy_s(dst.NVCustomSemanticNameString, src.name.c_str(), src.name.size());

			switch (src.type)
			{
			case CustomSemantic.XRight: 
				dst.NVCustomSemanticType = NV_X_RIGHT_SEMANTIC;
				break;

			case CustomSemantic.ViewportMask:
				dst.NVCustomSemanticType = NV_VIEWPORT_MASK_SEMANTIC;
				break;

			case CustomSemantic.Undefined:
				nvrhi.utils.InvalidEnum();
				break;

			default:
				nvrhi.utils.InvalidEnum();
				return false;
			}
		}

		return true;
	}
#endif

	private static void createShaderFailed(char8* @function, HRESULT res, ShaderDesc d, D3D11Context* context)
	{
		String message = scope $"{@function} call failed for shader nvrhi.utils.DebugNameToString(d.debugName), HRESULT = 0x{res:X}";
		context.error(message);
	}

	public override ShaderHandle createShader(ShaderDesc d, void* binary, int binarySize)
	{
		// Attach a RefCountPtr right away so that it's destroyed on an error exit
		RefCountPtr<ShaderD3D11> shader = RefCountPtr<ShaderD3D11>.Attach(new ShaderD3D11());

		switch (d.shaderType) // NOLINT(clang-diagnostic-switch-enum)
		{
		case ShaderType.Vertex:
			{
				// Save the bytecode for potential input layout creation later
				shader.bytecode.Resize(binarySize);
				Internal.MemCpy(shader.bytecode.Ptr, binary, binarySize);

				if (d.numCustomSemantics == 0)
				{
					readonly HRESULT res = m_Context.device.CreateVertexShader(binary, (.)binarySize, null, &shader.VS);
					if (FAILED(res))
					{
						createShaderFailed("CreateVertexShader", res, d, m_Context);
						return null;
					}
				}
				else
				{
#if NVRHI_D3D11_WITH_NVAPI
					List<NV_CUSTOM_SEMANTIC> nvapiSemantics;
					convertCustomSemantics(d.numCustomSemantics, d.pCustomSemantics, nvapiSemantics);

					NvAPI_D3D11_CREATE_VERTEX_SHADER_EX Args = {};
					Args.version = NVAPI_D3D11_CREATEVERTEXSHADEREX_VERSION;
					Args.NumCustomSemantics = d.numCustomSemantics;
					Args.pCustomSemantics = nvapiSemantics.data();
					Args.UseSpecificShaderExt = d.useSpecificShaderExt;

					if (NvAPI_D3D11_CreateVertexShaderEx(m_Context.device, binary, binarySize, null, &Args, &shader.VS) != NVAPI_OK)
						return null;
#else
					return null;
#endif
				}
			}
			break;
		case ShaderType.Hull:
			{
				if (d.numCustomSemantics == 0)
				{
					readonly HRESULT res = m_Context.device.CreateHullShader(binary, (.)binarySize, null, &shader.HS);
					if (FAILED(res))
					{
						createShaderFailed("CreateHullShader", res, d, m_Context);
						return null;
					}
				}
				else
				{
#if NVRHI_D3D11_WITH_NVAPI
					List<NV_CUSTOM_SEMANTIC> nvapiSemantics;
					convertCustomSemantics(d.numCustomSemantics, d.pCustomSemantics, nvapiSemantics);

					NvAPI_D3D11_CREATE_HULL_SHADER_EX Args = {};
					Args.version = NVAPI_D3D11_CREATEHULLSHADEREX_VERSION;
					Args.NumCustomSemantics = d.numCustomSemantics;
					Args.pCustomSemantics = nvapiSemantics.data();
					Args.UseSpecificShaderExt = d.useSpecificShaderExt;

					if (NvAPI_D3D11_CreateHullShaderEx(m_Context.device, binary, binarySize, null, &Args, &shader.HS) != NVAPI_OK)
						return null;
#else
					return null;
#endif
				}
			}
			break;
		case ShaderType.Domain:
			{
				if (d.numCustomSemantics == 0)
				{
					readonly HRESULT res = m_Context.device.CreateDomainShader(binary, (.)binarySize, null, &shader.DS);
					if (FAILED(res))
					{
						createShaderFailed("CreateDomainShader", res, d, m_Context);
						return null;
					}
				}
				else
				{
#if NVRHI_D3D11_WITH_NVAPI
					List<NV_CUSTOM_SEMANTIC> nvapiSemantics;
					convertCustomSemantics(d.numCustomSemantics, d.pCustomSemantics, nvapiSemantics);

					NvAPI_D3D11_CREATE_DOMAIN_SHADER_EX Args = {};
					Args.version = NVAPI_D3D11_CREATEDOMAINSHADEREX_VERSION;
					Args.NumCustomSemantics = d.numCustomSemantics;
					Args.pCustomSemantics = nvapiSemantics.data();
					Args.UseSpecificShaderExt = d.useSpecificShaderExt;

					if (NvAPI_D3D11_CreateDomainShaderEx(m_Context.device, binary, binarySize, null, &Args, &shader.DS) != NVAPI_OK)
						return null;
#else
					return null;
#endif
				}
			}
			break;
		case ShaderType.Geometry:
			{
				if (d.numCustomSemantics == 0 && uint32(d.fastGSFlags) == 0 && d.pCoordinateSwizzling == null)
				{
					readonly HRESULT res = m_Context.device.CreateGeometryShader(binary, (.)binarySize, null, &shader.GS);
					if (FAILED(res))
					{
						createShaderFailed("CreateGeometryShader", res, d, m_Context);
						return null;
					}
				}
				else
				{
#if NVRHI_D3D11_WITH_NVAPI           
					List<NV_CUSTOM_SEMANTIC> nvapiSemantics;
					convertCustomSemantics(d.numCustomSemantics, d.pCustomSemantics, nvapiSemantics);

					NvAPI_D3D11_CREATE_GEOMETRY_SHADER_EX Args = {};
					Args.version = NVAPI_D3D11_CREATEGEOMETRYSHADEREX_2_VERSION;
					Args.NumCustomSemantics = d.numCustomSemantics;
					Args.pCustomSemantics = nvapiSemantics.data();
					Args.UseCoordinateSwizzle = d.pCoordinateSwizzling != null;
					Args.pCoordinateSwizzling = d.pCoordinateSwizzling;
					Args.ForceFastGS = (d.fastGSFlags & FastGeometryShaderFlags.ForceFastGS) != 0;
					Args.UseViewportMask = (d.fastGSFlags & FastGeometryShaderFlags.UseViewportMask) != 0;
					Args.OffsetRtIndexByVpIndex = (d.fastGSFlags & FastGeometryShaderFlags.OffsetTargetIndexByViewportIndex) != 0;
					Args.DontUseViewportOrder = (d.fastGSFlags & FastGeometryShaderFlags.StrictApiOrder) != 0;
					Args.UseSpecificShaderExt = d.useSpecificShaderExt;

					if (NvAPI_D3D11_CreateGeometryShaderEx_2(m_Context.device, binary, binarySize, null, &Args, &shader.GS) != NVAPI_OK)
						return null;
#else
					return null;
#endif
				}
			}
			break;
		case ShaderType.Pixel:
			{
				if (d.hlslExtensionsUAV >= 0)
				{
#if NVRHI_D3D11_WITH_NVAPI
					if (NvAPI_D3D11_SetNvShaderExtnSlot(m_Context.device, d.hlslExtensionsUAV) != NVAPI_OK)
						return null;
#else
					return null;
#endif
				}

				readonly HRESULT res = m_Context.device.CreatePixelShader(binary, (.)binarySize, null, &shader.PS);
				if (FAILED(res))
				{
					createShaderFailed("CreatePixelShader", res, d, m_Context);
					return null;
				}

#if NVRHI_D3D11_WITH_NVAPI
				if (d.hlslExtensionsUAV >= 0)
				{
					NvAPI_D3D11_SetNvShaderExtnSlot(m_Context.device, ~0u);
				}
#endif
			}
			break;
		case ShaderType.Compute:
			{
				if (d.hlslExtensionsUAV >= 0)
				{
#if NVRHI_D3D11_WITH_NVAPI
					if (NvAPI_D3D11_SetNvShaderExtnSlot(m_Context.device, d.hlslExtensionsUAV) != NVAPI_OK)
						return null;
#else
					return null;
#endif
				}

				readonly HRESULT res = m_Context.device.CreateComputeShader(binary, (.)binarySize, null, &shader.CS);
				if (FAILED(res))
				{
					createShaderFailed("CreateComputeShader", res, d, m_Context);
					return null;
				}

#if NVRHI_D3D11_WITH_NVAPI
				if (d.hlslExtensionsUAV >= 0)
				{
					NvAPI_D3D11_SetNvShaderExtnSlot(m_Context.device, ~0u);
				}
#endif
			}
			break;

		default:
			m_Context.error("Unsupported shaderType provided to createShader");
			return null;
		}

		shader.desc = d;
		return shader; // NOLINT(clang-diagnostic-return-std-move-in-c++11)
	}
	public override ShaderHandle createShaderSpecialization(IShader baseShader, ShaderSpecialization* constants, uint32 numConstants)
	{
		nvrhi.utils.NotSupported();
		return null;
	}
	public override ShaderLibraryHandle createShaderLibrary(void* binary, int binarySize) { (void)binary; (void)binarySize; return null; }

	public override SamplerHandle createSampler(SamplerDesc d)
	{
		D3D11_SAMPLER_DESC desc11;

		UINT reductionType = convertSamplerReductionType(d.reductionType);

		if (d.maxAnisotropy > 1.0f)
		{
			desc11.Filter = D3D11_ENCODE_ANISOTROPIC_FILTER(reductionType);
		}
		else
		{
			desc11.Filter = D3D11_ENCODE_BASIC_FILTER(
				d.minFilter ? D3D11_FILTER_TYPE.D3D11_FILTER_TYPE_LINEAR : D3D11_FILTER_TYPE.D3D11_FILTER_TYPE_POINT,
				d.magFilter ? D3D11_FILTER_TYPE.D3D11_FILTER_TYPE_LINEAR : D3D11_FILTER_TYPE.D3D11_FILTER_TYPE_POINT,
				d.mipFilter ? D3D11_FILTER_TYPE.D3D11_FILTER_TYPE_LINEAR : D3D11_FILTER_TYPE.D3D11_FILTER_TYPE_POINT,
				reductionType);
		}

		desc11.AddressU = convertSamplerAddressMode(d.addressU);
		desc11.AddressV = convertSamplerAddressMode(d.addressV);
		desc11.AddressW = convertSamplerAddressMode(d.addressW);

		desc11.MipLODBias = d.mipBias;
		desc11.MaxAnisotropy = Math.Max((UINT)d.maxAnisotropy, 1);
		desc11.ComparisonFunc = .D3D11_COMPARISON_LESS;
		desc11.BorderColor[0] = d.borderColor.r;
		desc11.BorderColor[1] = d.borderColor.g;
		desc11.BorderColor[2] = d.borderColor.b;
		desc11.BorderColor[3] = d.borderColor.a;
		desc11.MinLOD = 0;
		desc11.MaxLOD = D3D11_FLOAT32_MAX;

		D3D11RefCountPtr<ID3D11SamplerState> sState = null;
		readonly HRESULT res = m_Context.device.CreateSamplerState(&desc11, &sState);
		if (FAILED(res))
		{
			String message = scope $"CreateSamplerState call failed, HRESULT = 0x{res:X}";
			m_Context.error(message);
			return null;
		}

		SamplerD3D11 sampler = new SamplerD3D11();
		sampler.sampler = sState;
		sampler.desc = d;
		return SamplerHandle.Attach(sampler);
	}

	public override InputLayoutHandle createInputLayout(VertexAttributeDesc* d, uint32 attributeCount, IShader _vertexShader)
	{
		ShaderD3D11 vertexShader = checked_cast<ShaderD3D11, IShader>(_vertexShader);

		if (vertexShader == null)
		{
			m_Context.error("No vertex shader provided to createInputLayout");
			return null;
		}

		if (vertexShader.desc.shaderType != ShaderType.Vertex)
		{
			m_Context.error("A non-vertex shader provided to createInputLayout");
			return null;
		}

		InputLayoutD3D11 inputLayout = new InputLayoutD3D11();

		inputLayout.attributes.Resize(attributeCount);

		StaticVector<D3D11_INPUT_ELEMENT_DESC, const c_MaxVertexAttributes> elementDesc = .();
		for (uint32 i = 0; i < attributeCount; i++)
		{
			inputLayout.attributes[i] = d[i];

			Runtime.Assert(d[i].arraySize > 0);

			readonly ref DxgiFormatMapping formatMapping = ref getDxgiFormatMapping(d[i].format);
			readonly ref FormatInfo formatInfo = ref getFormatInfo(d[i].format);

			for (uint32 semanticIndex = 0; semanticIndex < d[i].arraySize; semanticIndex++)
			{
				D3D11_INPUT_ELEMENT_DESC desc;

				desc.SemanticName = (.)d[i].name.CStr();
				desc.SemanticIndex = semanticIndex;
				desc.Format = formatMapping.srvFormat;
				desc.InputSlot = d[i].bufferIndex;
				desc.AlignedByteOffset = d[i].offset + semanticIndex * formatInfo.bytesPerBlock;
				desc.InputSlotClass = d[i].isInstanced ? .D3D11_INPUT_PER_INSTANCE_DATA : .D3D11_INPUT_PER_VERTEX_DATA;
				desc.InstanceDataStepRate = d[i].isInstanced ? 1 : 0;

				elementDesc.PushBack(desc);
			}
		}

		readonly HRESULT res = m_Context.device.CreateInputLayout(elementDesc.Ptr, uint32(elementDesc.Count), vertexShader.bytecode.Ptr, (.)vertexShader.bytecode.Count, &inputLayout.layout);
		if (FAILED(res))
		{
			String message = scope $"CreateInputLayout call failed for shader {nvrhi.utils.DebugNameToString(vertexShader.desc.debugName)}, HRESULT = 0x{res:X}";
			m_Context.error(message);
		}

		for (uint32 i = 0; i < attributeCount; i++)
		{
			readonly var index = d[i].bufferIndex;

			if (!inputLayout.elementStrides.ContainsKey(index))
			{
				inputLayout.elementStrides[index] = d[i].elementStride;
			} else
			{
				Runtime.Assert(inputLayout.elementStrides[index] == d[i].elementStride);
			}
		}

		return InputLayoutHandle.Attach(inputLayout);
	}

	// event queries
	private static bool checkedCreateQuery(D3D11_QUERY_DESC queryDesc, char8* name, D3D11Context* context, ID3D11Query** pQuery)
	{
		var queryDesc;
		readonly HRESULT res = context.device.CreateQuery(&queryDesc, pQuery);

		if (FAILED(res))
		{
			String message = scope $"CreateQuery call failed for {scope String(name)}, HRESULT = 0x{res:X}";
			context.error(message);

			return false;
		}

		return true;
	}

	public override EventQueryHandle createEventQuery()
	{
		EventQueryD3D11 ret = new EventQueryD3D11();

		D3D11_QUERY_DESC queryDesc;
		queryDesc.Query = .D3D11_QUERY_EVENT;
		queryDesc.MiscFlags = 0;

		if (!checkedCreateQuery(queryDesc, "EventQuery", m_Context, &ret.query))
		{
			delete ret;
			return null;
		}

		return EventQueryHandle.Attach(ret);
	}
	public override void setEventQuery(IEventQuery _query, CommandQueue queue)
	{
		(void)queue;

		EventQueryD3D11 query = checked_cast<EventQueryD3D11, IEventQuery>(_query);

		m_Context.immediateContext.End(query.query /*.Get<IEventQuery>()*/);
	}
	public override bool pollEventQuery(IEventQuery _query)
	{
		EventQueryD3D11 query = checked_cast<EventQueryD3D11, IEventQuery>(_query);

		if (query.resolved)
		{
			return true;
		}

		readonly HRESULT hr = m_Context.immediateContext.GetData(query.query /*.Get<IEventQuery>()*/, null, 0, (.)D3D11_ASYNC_GETDATA_FLAG.D3D11_ASYNC_GETDATA_DONOTFLUSH);

		if (SUCCEEDED(hr))
		{
			query.resolved = true;
			return true;
		} else
		{
			return false;
		}
	}

	public override void waitEventQuery(IEventQuery _query)
	{
		EventQueryD3D11 query = checked_cast<EventQueryD3D11, IEventQuery>(_query);

		if (query.resolved)
		{
			return;
		}

		HRESULT hr;

		repeat
		{
			hr = m_Context.immediateContext.GetData(query.query /*.Get()*/, null, 0, 0);
		} while (hr == S_FALSE);

		Runtime.Assert(SUCCEEDED(hr));
	}
	public override void resetEventQuery(IEventQuery _query)
	{
		EventQueryD3D11 query = checked_cast<EventQueryD3D11, IEventQuery>(_query);

		query.resolved = false;
	}

	// timer queries
	public override TimerQueryHandle createTimerQuery()
	{
		TimerQueryD3D11 ret = new TimerQueryD3D11();

		D3D11_QUERY_DESC queryDesc;

		queryDesc.Query = .D3D11_QUERY_TIMESTAMP_DISJOINT;
		queryDesc.MiscFlags = 0;

		if (!checkedCreateQuery(queryDesc, "TimerQuery Disjoint", m_Context, &ret.disjoint))
		{
			delete ret;
			return null;
		}

		queryDesc.Query = .D3D11_QUERY_TIMESTAMP;
		queryDesc.MiscFlags = 0;

		if (!checkedCreateQuery(queryDesc, "TimerQuery Start", m_Context, &ret.start))
		{
			delete ret;
			return null;
		}

		if (!checkedCreateQuery(queryDesc, "TimerQuery End", m_Context, &ret.end))
		{
			delete ret;
			return null;
		}

		return TimerQueryHandle.Attach(ret);
	}
	public override bool pollTimerQuery(ITimerQuery _query)
	{
		TimerQueryD3D11 query = checked_cast<TimerQueryD3D11, ITimerQuery>(_query);

		if (query.resolved)
		{
			return true;
		}

		readonly HRESULT hr = m_Context.immediateContext.GetData(query.disjoint /*.Get()*/, null, 0, (.)D3D11_ASYNC_GETDATA_FLAG.D3D11_ASYNC_GETDATA_DONOTFLUSH);

		if (SUCCEEDED(hr))
		{
			// note: we don't mark this as resolved since we need to read data back and compute timing info
			// this is done in getTimerQueryTimeMS
			return true;
		} else
		{
			return false;
		}
	}
	public override float getTimerQueryTime(ITimerQuery _query)
	{
		TimerQueryD3D11 query = checked_cast<TimerQueryD3D11, ITimerQuery>(_query);

		if (!query.resolved)
		{
			HRESULT hr;

			D3D11_QUERY_DATA_TIMESTAMP_DISJOINT disjointData = .();

			repeat
			{
				hr = m_Context.immediateContext.GetData(query.disjoint /*.Get()*/, &disjointData, sizeof(decltype(disjointData)), 0);
			} while (hr == S_FALSE);
			Runtime.Assert(SUCCEEDED(hr));

			query.resolved = true;

			if (disjointData.Disjoint == /*TRUE*/ 1)
			{
				// query resolved but captured invalid timing data
				query.time = 0.f;
			} else
			{
				UINT64 startTime = 0, endTime = 0;
				repeat
				{
					hr = m_Context.immediateContext.GetData(query.start /*.Get()*/, &startTime, sizeof(decltype(startTime)), 0);
				} while (hr == S_FALSE);
				Runtime.Assert(SUCCEEDED(hr));

				repeat
				{
					hr = m_Context.immediateContext.GetData(query.end /*.Get()*/, &endTime, sizeof(decltype(endTime)), 0);
				} while (hr == S_FALSE);
				Runtime.Assert(SUCCEEDED(hr));

				double delta = double(endTime - startTime);
				double frequency = double(disjointData.Frequency);
				query.time = float(delta / frequency);
			}
		}

		return query.time;
	}
	public override void resetTimerQuery(ITimerQuery _query)
	{
		TimerQueryD3D11 query = checked_cast<TimerQueryD3D11, ITimerQuery>(_query);

		query.resolved = false;
		query.time = 0.f;
	}

	public override GraphicsAPI getGraphicsAPI()
	{
		return GraphicsAPI.D3D11;
	}

	public override FramebufferHandle createFramebuffer(FramebufferDesc desc)
	{
		FramebufferD3D11 ret = new FramebufferD3D11();
		ret.desc = desc;
		ret.framebufferInfo = FramebufferInfo(desc);

		for (var colorAttachment in desc.colorAttachments)
		{
			Runtime.Assert(colorAttachment.valid());
			ret.RTVs.PushBack(getRTVForAttachment(colorAttachment));
		}

		if (desc.depthAttachment.valid())
		{
			ret.DSV = getDSVForAttachment(desc.depthAttachment);
		}

		return FramebufferHandle.Attach(ret);
	}

	public override GraphicsPipelineHandle createGraphicsPipeline(GraphicsPipelineDesc desc, IFramebuffer fb)
	{
		readonly ref RenderState renderState = ref desc.renderState;

		if (desc.renderState.singlePassStereo.enabled && !m_SinglePassStereoSupported)
		{
			m_Context.error("Single-pass stereo is not supported by this device");
			return null;
		}

		GraphicsPipelineD3D11 pso = new GraphicsPipelineD3D11();
		pso.desc = desc;
		pso.framebufferInfo = fb.getFramebufferInfo();

		pso.primitiveTopology = convertPrimType(desc.primType, desc.patchControlPoints);
		pso.inputLayout = checked_cast<InputLayoutD3D11, IInputLayout>(desc.inputLayout.Get<IInputLayout>());

		pso.pRS = getRasterizerState(renderState.rasterState);
		pso.pBlendState = getBlendState(renderState.blendState);
		pso.pDepthStencilState = getDepthStencilState(renderState.depthStencilState);
		pso.requiresBlendFactor = renderState.blendState.usesConstantColor(uint32(pso.framebufferInfo.colorFormats.Count));

		pso.stencilRef = renderState.depthStencilState.stencilRefValue;
		pso.shaderMask = ShaderType.None;

		if (desc.VS != null) { pso.pVS = checked_cast<ShaderD3D11, IShader>(desc.VS.Get<IShader>()).VS; pso.shaderMask = pso.shaderMask | ShaderType.Vertex; }
		if (desc.HS != null) { pso.pHS = checked_cast<ShaderD3D11, IShader>(desc.HS.Get<IShader>()).HS; pso.shaderMask = pso.shaderMask | ShaderType.Hull; }
		if (desc.DS != null) { pso.pDS = checked_cast<ShaderD3D11, IShader>(desc.DS.Get<IShader>()).DS; pso.shaderMask = pso.shaderMask | ShaderType.Domain; }
		if (desc.GS != null) { pso.pGS = checked_cast<ShaderD3D11, IShader>(desc.GS.Get<IShader>()).GS; pso.shaderMask = pso.shaderMask | ShaderType.Geometry; }
		if (desc.PS != null) { pso.pPS = checked_cast<ShaderD3D11, IShader>(desc.PS.Get<IShader>()).PS; pso.shaderMask = pso.shaderMask | ShaderType.Pixel; }

		// Set a flag if the PS has any UAV bindings in the layout
		for (var _layout in  ref desc.bindingLayouts)
		{
			BindingLayoutD3D11 layout = checked_cast<BindingLayoutD3D11, IBindingLayout>(_layout.Get<IBindingLayout>());

			if ((layout.desc.visibility & ShaderType.Pixel) == 0)
				continue;

			for (readonly var item in ref layout.desc.bindings)
			{
				if (item.type == ResourceType.TypedBuffer_UAV || item.type == ResourceType.Texture_UAV || item.type == ResourceType.StructuredBuffer_UAV)
				{
					pso.pixelShaderHasUAVs = true;
					break;
				}
			}

			if (pso.pixelShaderHasUAVs)
				break;
		}

		return GraphicsPipelineHandle.Attach(pso);
	}

	public override ComputePipelineHandle createComputePipeline(ComputePipelineDesc desc)
	{
		ComputePipelineD3D11 pso = new ComputePipelineD3D11();
		pso.desc = desc;

		if (desc.CS != null) pso.shader = checked_cast<ShaderD3D11, IShader>(desc.CS.Get<IShader>()).CS;

		return ComputePipelineHandle.Attach(pso);
	}

	public override MeshletPipelineHandle createMeshletPipeline(MeshletPipelineDesc desc, IFramebuffer fb)
	{
		return null;
	}

	public override nvrhi.rt.PipelineHandle createRayTracingPipeline(nvrhi.rt.PipelineDesc desc)
	{
		return null;
	}

	public override BindingLayoutHandle createBindingLayout(BindingLayoutDesc desc)
	{
		BindingLayoutD3D11 layout = new BindingLayoutD3D11();
		layout.desc = desc;
		return BindingLayoutHandle.Attach(layout);
	}
	public override BindingLayoutHandle createBindlessLayout(BindlessLayoutDesc desc)
	{
		return null;
	}

	public override BindingSetHandle createBindingSet(BindingSetDesc desc, IBindingLayout layout)
	{
		BindingSetD3D11 ret = new BindingSetD3D11();
		ret.desc = desc;
		ret.layout = layout;
		ret.visibility = layout.getDesc().visibility;

		for (readonly ref BindingSetItem binding in ref desc.bindings)
		{
			readonly ref uint32 slot = ref binding.slot;

			switch (binding.type) // NOLINT(clang-diagnostic-switch-enum)
			{
			case ResourceType.Texture_SRV:
				{
					readonly var texture = checked_cast<TextureD3D11, IResource>(binding.resourceHandle);

					Runtime.Assert(ret.SRVs[slot] == null);
					ret.SRVs[slot] = texture.getSRV(binding.format, binding.subresources, binding.dimension);

					ret.minSRVSlot = Math.Min(ret.minSRVSlot, slot);
					ret.maxSRVSlot = Math.Max(ret.maxSRVSlot, slot);
				}

				break;

			case ResourceType.Texture_UAV:
				{
					readonly var texture = checked_cast<TextureD3D11, IResource>(binding.resourceHandle);

					ret.UAVs[slot] = texture.getUAV(binding.format, binding.subresources, binding.dimension);

					ret.minUAVSlot = Math.Min(ret.minUAVSlot, slot);
					ret.maxUAVSlot = Math.Max(ret.maxUAVSlot, slot);
				}

				break;

			case ResourceType.TypedBuffer_SRV,
				ResourceType.StructuredBuffer_SRV,
				ResourceType.RawBuffer_SRV:
				{
					readonly var buffer = checked_cast<BufferD3D11, IResource>(binding.resourceHandle);

					Runtime.Assert(ret.SRVs[slot] == null);
					ret.SRVs[slot] = buffer.getSRV(binding.format, binding.range, binding.type);

					ret.minSRVSlot = Math.Min(ret.minSRVSlot, slot);
					ret.maxSRVSlot = Math.Max(ret.maxSRVSlot, slot);
				}

				break;

			case ResourceType.TypedBuffer_UAV,
				ResourceType.StructuredBuffer_UAV,
				ResourceType.RawBuffer_UAV:
				{
					readonly var buffer = checked_cast<BufferD3D11, IResource>(binding.resourceHandle);
					ret.UAVs[slot] = buffer.getUAV(binding.format, binding.range, binding.type);

					ret.minUAVSlot = Math.Min(ret.minUAVSlot, slot);
					ret.maxUAVSlot = Math.Max(ret.maxUAVSlot, slot);
				}

				break;

			// DX11 makes no distinction between regular and volatile CBs
			case ResourceType.ConstantBuffer,
				ResourceType.VolatileConstantBuffer:
				{
					Runtime.Assert(ret.constantBuffers[slot] == null);

					readonly var buffer = checked_cast<BufferD3D11, IResource>(binding.resourceHandle);
					ret.constantBuffers[slot] = buffer.resource /*.Get()*/;

					ret.minConstantBufferSlot = Math.Min(ret.minConstantBufferSlot, slot);
					ret.maxConstantBufferSlot = Math.Max(ret.maxConstantBufferSlot, slot);
				}

				break;

			case ResourceType.Sampler:
				{
					Runtime.Assert(ret.samplers[slot] == null);

					readonly var sampler = checked_cast<SamplerD3D11, IResource>(binding.resourceHandle);
					ret.samplers[slot] = sampler.sampler /*.Get()*/;

					ret.minSamplerSlot = Math.Min(ret.minSamplerSlot, slot);
					ret.maxSamplerSlot = Math.Max(ret.maxSamplerSlot, slot);
				}

				break;

			case ResourceType.PushConstants:
				{
					ret.constantBuffers[slot] = m_Context.pushConstantBuffer;

					ret.minConstantBufferSlot = Math.Min(ret.minConstantBufferSlot, slot);
					ret.maxConstantBufferSlot = Math.Max(ret.maxConstantBufferSlot, slot);
				}

				break;

			default:
				{
					readonly String message = scope $"Unsupported resource binding type: {nvrhi.utils.ResourceTypeToString(binding.type)}";
					m_Context.error(message);
					continue;
				}
			}

			if (binding.resourceHandle != null)
			{
				ret.resources.Add(binding.resourceHandle);
			}
		}

		return BindingSetHandle.Attach(ret);
	}
	public override DescriptorTableHandle createDescriptorTable(IBindingLayout layout)
	{
		return null;
	}

	public override void resizeDescriptorTable(IDescriptorTable descriptorTable, uint32 newSize, bool keepContents = true)
	{
		nvrhi.utils.NotSupported();
	}
	public override bool writeDescriptorTable(IDescriptorTable descriptorTable, BindingSetItem item)
	{
		nvrhi.utils.NotSupported();
		return false;
	}

	public override nvrhi.rt.AccelStructHandle createAccelStruct(nvrhi.rt.AccelStructDesc desc)
	{
		return null;
	}
	public override MemoryRequirements getAccelStructMemoryRequirements(nvrhi.rt.IAccelStruct @as)
	{
		nvrhi.utils.NotSupported();
		return MemoryRequirements();
	}
	public override bool bindAccelStructMemory(nvrhi.rt.IAccelStruct @as, IHeap heap, uint64 offset)
	{
		nvrhi.utils.NotSupported();
		return false;
	}

	public override CommandListHandle createCommandList(CommandListParameters @params = CommandListParameters())
	{
		if (!@params.enableImmediateExecution)
		{
			m_Context.error("Deferred command lists are not supported by the D3D11 backend.");
			return null;
		}

		if (@params.queueType != CommandQueue.Graphics)
		{
			m_Context.error("Non-graphics queues are not supported by the D3D11 backend.");
			return null;
		}

		return m_ImmediateCommandList;
	}
	public override uint64 executeCommandLists(Span<ICommandList> pCommandLists, CommandQueue executionQueue = CommandQueue.Graphics) { (void)pCommandLists; /*(void)numCommandLists;*/ (void)executionQueue; return 0; }
	public override void queueWaitForCommandList(CommandQueue waitQueue, CommandQueue executionQueue, uint64 instance) { (void)waitQueue; (void)executionQueue; (void)instance; }
	public override void waitForIdle()
	{
		if (m_WaitForIdleQuery != null)
		{
			m_WaitForIdleQuery = createEventQuery();
		}

		if (m_WaitForIdleQuery != null)
			return;

		setEventQuery(m_WaitForIdleQuery, CommandQueue.Graphics);
		waitEventQuery(m_WaitForIdleQuery);
		resetEventQuery(m_WaitForIdleQuery);
	}
	public override void runGarbageCollection() { }
	public override bool queryFeatureSupport(Feature feature, void* pInfo = null, int infoSize = 0)
	{
		(void)pInfo;
		(void)infoSize;

		switch (feature) // NOLINT(clang-diagnostic-switch-enum)
		{
		case Feature.DeferredCommandLists:
			return false;
		case Feature.SinglePassStereo:
			return m_SinglePassStereoSupported;
		case Feature.FastGeometryShader:
			return m_FastGeometryShaderSupported;
		default:
			return false;
		}
	}
	public override FormatSupport queryFormatSupport(Format format)
	{
		readonly ref DxgiFormatMapping formatMapping = ref getDxgiFormatMapping(format);

		FormatSupport result = FormatSupport.None;

		UINT flags = 0;
		m_Context.device.CheckFormatSupport(formatMapping.rtvFormat, &flags);

		if (flags & (.)D3D11_FORMAT_SUPPORT.D3D11_FORMAT_SUPPORT_BUFFER != 0)
			result = result | FormatSupport.Buffer;
		if (flags & (.)(D3D11_FORMAT_SUPPORT.D3D11_FORMAT_SUPPORT_TEXTURE1D | D3D11_FORMAT_SUPPORT.D3D11_FORMAT_SUPPORT_TEXTURE2D | D3D11_FORMAT_SUPPORT.D3D11_FORMAT_SUPPORT_TEXTURE3D | D3D11_FORMAT_SUPPORT.D3D11_FORMAT_SUPPORT_TEXTURECUBE) != 0)
			result = result | FormatSupport.Texture;
		if (flags & (.)D3D11_FORMAT_SUPPORT.D3D11_FORMAT_SUPPORT_DEPTH_STENCIL != 0)
			result = result | FormatSupport.DepthStencil;
		if (flags & (.)D3D11_FORMAT_SUPPORT.D3D11_FORMAT_SUPPORT_RENDER_TARGET != 0)
			result = result | FormatSupport.RenderTarget;
		if (flags & (.)D3D11_FORMAT_SUPPORT.D3D11_FORMAT_SUPPORT_BLENDABLE != 0)
			result = result | FormatSupport.Blendable;

		if (formatMapping.srvFormat != formatMapping.rtvFormat)
		{
			flags = 0;
			m_Context.device.CheckFormatSupport(formatMapping.srvFormat, &flags);
		}

		if (flags & (.)D3D11_FORMAT_SUPPORT.D3D11_FORMAT_SUPPORT_IA_INDEX_BUFFER != 0)
			result = result | FormatSupport.IndexBuffer;
		if (flags & (.)D3D11_FORMAT_SUPPORT.D3D11_FORMAT_SUPPORT_IA_VERTEX_BUFFER != 0)
			result = result | FormatSupport.VertexBuffer;
		if (flags & (.)D3D11_FORMAT_SUPPORT.D3D11_FORMAT_SUPPORT_SHADER_LOAD != 0)
			result = result | FormatSupport.ShaderLoad;
		if (flags & (.)D3D11_FORMAT_SUPPORT.D3D11_FORMAT_SUPPORT_SHADER_SAMPLE != 0)
			result = result | FormatSupport.ShaderSample;

		D3D11_FEATURE_DATA_FORMAT_SUPPORT2 featureData = .();
		featureData.InFormat = formatMapping.srvFormat;

		m_Context.device.CheckFeatureSupport(.D3D11_FEATURE_FORMAT_SUPPORT2, &featureData, sizeof(decltype(featureData)));

		if (featureData.OutFormatSupport2 & (.)D3D11_FORMAT_SUPPORT2.D3D11_FORMAT_SUPPORT2_UAV_ATOMIC_ADD != 0)
			result = result | FormatSupport.ShaderAtomic;
		if (featureData.OutFormatSupport2 & (.)D3D11_FORMAT_SUPPORT2.D3D11_FORMAT_SUPPORT2_UAV_TYPED_LOAD != 0)
			result = result | FormatSupport.ShaderUavLoad;
		if (featureData.OutFormatSupport2 & (.)D3D11_FORMAT_SUPPORT2.D3D11_FORMAT_SUPPORT2_UAV_TYPED_STORE != 0)
			result = result | FormatSupport.ShaderUavStore;

		return result;
	}
	public override NativeObject getNativeQueue(ObjectType objectType, CommandQueue queue) { (void)objectType; (void)queue;  return null; }
	public override IMessageCallback getMessageCallback() { return m_Context.messageCallback; }

	private D3D11Context* m_Context;
	private EventQueryHandle m_WaitForIdleQuery;
	private CommandListHandle m_ImmediateCommandList;

	private Dictionary<int, D3D11RefCountPtr<ID3D11BlendState>> m_BlendStates;
	private Dictionary<int, D3D11RefCountPtr<ID3D11DepthStencilState>> m_DepthStencilStates;
	private Dictionary<int, D3D11RefCountPtr<ID3D11RasterizerState>> m_RasterizerStates;

	private bool m_SinglePassStereoSupported = false;
	private bool m_FastGeometryShaderSupported = false;

	private TextureHandle createTexture(TextureDesc d, CpuAccessMode cpuAccess)
	{
		if (d.isVirtual)
		{
			nvrhi.utils.NotSupported();
			return null;
		}

		D3D11_USAGE usage = (cpuAccess == CpuAccessMode.None ? .D3D11_USAGE_DEFAULT : .D3D11_USAGE_STAGING);

		readonly ref DxgiFormatMapping formatMapping = ref getDxgiFormatMapping(d.format);
		readonly ref FormatInfo formatInfo = ref getFormatInfo(d.format);

		// convert flags
		UINT bindFlags;
		if (cpuAccess != CpuAccessMode.None)
		{
			bindFlags = 0;
		} else
		{
			bindFlags = (.)D3D11_BIND_FLAG.D3D11_BIND_SHADER_RESOURCE;
			if (d.isRenderTarget)
				bindFlags |= (formatInfo.hasDepth || formatInfo.hasStencil) ? (.)D3D11_BIND_FLAG.D3D11_BIND_DEPTH_STENCIL : (.)D3D11_BIND_FLAG.D3D11_BIND_RENDER_TARGET;
			if (d.isUAV)
				bindFlags |= (.)D3D11_BIND_FLAG.D3D11_BIND_UNORDERED_ACCESS;
		}

		UINT cpuAccessFlags = 0;
		if (cpuAccess == CpuAccessMode.Read)
			cpuAccessFlags = (.)D3D11_CPU_ACCESS_FLAG.D3D11_CPU_ACCESS_READ;
		if (cpuAccess == CpuAccessMode.Write)
			cpuAccessFlags = (.)D3D11_CPU_ACCESS_FLAG.D3D11_CPU_ACCESS_WRITE;

		UINT miscFlags = 0;
		if ((d.sharedResourceFlags & SharedResourceFlags.Shared_NTHandle) != 0)
			miscFlags |= (.)D3D11_RESOURCE_MISC_FLAG.D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX | (.)D3D11_RESOURCE_MISC_FLAG.D3D11_RESOURCE_MISC_SHARED_NTHANDLE;
		else if ((d.sharedResourceFlags & SharedResourceFlags.Shared) != 0)
			miscFlags |= (.)D3D11_RESOURCE_MISC_FLAG.D3D11_RESOURCE_MISC_SHARED;

		D3D11RefCountPtr<ID3D11Resource> pResource = null;

		switch (d.dimension)
		{
		case TextureDimension.Texture1D,
			TextureDimension.Texture1DArray:
			{
				D3D11_TEXTURE1D_DESC desc11;
				desc11.Width = d.width;
				desc11.MipLevels = d.mipLevels;
				desc11.ArraySize = d.arraySize;
				desc11.Format = d.isTypeless ? formatMapping.resourceFormat : formatMapping.rtvFormat;
				desc11.Usage = usage;
				desc11.BindFlags = bindFlags;
				desc11.CPUAccessFlags = cpuAccessFlags;
				desc11.MiscFlags = miscFlags;

				D3D11RefCountPtr<ID3D11Texture1D> newTexture = null;
				readonly HRESULT res = m_Context.device.CreateTexture1D(&desc11, null, &newTexture);
				if (FAILED(res))
				{
					String message = scope $"CreateTexture1D call failed for texture {nvrhi.utils.DebugNameToString(d.debugName)}, HRESULT = 0x{res:X}";
					m_Context.error(message);
					return null;
				}

				pResource = newTexture;
				break;
			}
		case TextureDimension.Texture2D,
			TextureDimension.Texture2DArray,
			TextureDimension.TextureCube,
			TextureDimension.TextureCubeArray,
			TextureDimension.Texture2DMS,
			TextureDimension.Texture2DMSArray:
			{
				D3D11_TEXTURE2D_DESC desc11;
				desc11.Width = d.width;
				desc11.Height = d.height;
				desc11.MipLevels = d.mipLevels;
				desc11.ArraySize = d.arraySize;
				desc11.Format = d.isTypeless ? formatMapping.resourceFormat : formatMapping.rtvFormat;
				desc11.SampleDesc.Count = d.sampleCount;
				desc11.SampleDesc.Quality = d.sampleQuality;
				desc11.Usage = usage;
				desc11.BindFlags = (.)bindFlags;
				desc11.CPUAccessFlags = (.)cpuAccessFlags;

				if (d.dimension == TextureDimension.TextureCube || d.dimension == TextureDimension.TextureCubeArray)
					desc11.MiscFlags = (.)miscFlags | (.)D3D11_RESOURCE_MISC_FLAG.D3D11_RESOURCE_MISC_TEXTURECUBE;
				else
					desc11.MiscFlags = (.)miscFlags;

				D3D11RefCountPtr<ID3D11Texture2D> newTexture = null;
				readonly HRESULT res = m_Context.device.CreateTexture2D(&desc11, null, &newTexture);
				if (FAILED(res))
				{
					String message = scope $"CreateTexture2D call failed for texture {nvrhi.utils.DebugNameToString(d.debugName)}, HRESULT = 0x{res:X}";
					m_Context.error(message);
					return null;
				}

				pResource = newTexture;
				break;
			}

		case TextureDimension.Texture3D:
			{
				D3D11_TEXTURE3D_DESC desc11;
				desc11.Width = d.width;
				desc11.Height = d.height;
				desc11.Depth = d.depth;
				desc11.MipLevels = d.mipLevels;
				desc11.Format = d.isTypeless ? formatMapping.resourceFormat : formatMapping.rtvFormat;
				desc11.Usage = usage;
				desc11.BindFlags = bindFlags;
				desc11.CPUAccessFlags = cpuAccessFlags;
				desc11.MiscFlags = miscFlags;

				D3D11RefCountPtr<ID3D11Texture3D> newTexture = null;
				HRESULT res = m_Context.device.CreateTexture3D(&desc11, null, &newTexture);
				if (FAILED(res))
				{
					String message = scope $"CreateTexture3D call failed for texture {nvrhi.utils.DebugNameToString(d.debugName)}, HRESULT = 0x{res:X}";
					m_Context.error(message);
					return null;
				}

				pResource = newTexture;
				break;
			}

		case TextureDimension.Unknown: fallthrough;
		default:
			nvrhi.utils.InvalidEnum();
			return null;
		}

		if (!String.IsNullOrEmpty(d.debugName))
			SetDebugName(pResource, d.debugName);

		TextureD3D11 texture = new TextureD3D11(m_Context);
		texture.desc = d;
		texture.resource = pResource;
		return TextureHandle.Attach(texture);
	}

	private ID3D11RenderTargetView* getRTVForAttachment(FramebufferAttachment attachment)
	{
		TextureD3D11 texture = checked_cast<TextureD3D11, ITexture>(attachment.texture);

		if (texture != null)
			return texture.getRTV(attachment.format, attachment.subresources);

		return null;
	}

	private ID3D11DepthStencilView* getDSVForAttachment(FramebufferAttachment attachment)
	{
		TextureD3D11 texture = checked_cast<TextureD3D11, ITexture>(attachment.texture);

		if (texture != null)
			return texture.getDSV(attachment.subresources, attachment.isReadOnly);

		return null;
	}

	private ID3D11BlendState* getBlendState(BlendState blendState)
	{
		int hash = 0;
		hash_combine(ref hash, blendState.alphaToCoverageEnable);

		for (readonly var target in ref blendState.targets)
		{
			hash_combine(ref hash, target.blendEnable);
			hash_combine(ref hash, target.srcBlend);
			hash_combine(ref hash, target.destBlend);
			hash_combine(ref hash, target.blendOp);
			hash_combine(ref hash, target.srcBlendAlpha);
			hash_combine(ref hash, target.destBlendAlpha);
			hash_combine(ref hash, target.blendOpAlpha);
			hash_combine(ref hash, target.colorWriteMask);
		}

		D3D11RefCountPtr<ID3D11BlendState> d3dBlendState = m_BlendStates[hash];

		if (d3dBlendState != null)
			return d3dBlendState;

		D3D11_BLEND_DESC desc11New = .();
		desc11New.AlphaToCoverageEnable = blendState.alphaToCoverageEnable ? /*TRUE*/ 1 : /*FALSE*/ 0;
		//we always use this and set the states for each target explicitly
		desc11New.IndependentBlendEnable = /*TRUE*/ 1;

		for (uint32 i = 0; i < c_MaxRenderTargets; i++)
		{
			readonly ref BlendState.RenderTarget src = ref blendState.targets[i];
			ref D3D11_RENDER_TARGET_BLEND_DESC dst = ref desc11New.RenderTarget[i];

			dst.BlendEnable = src.blendEnable ? /*TRUE*/ 1 : /*FALSE*/ 0;
			dst.SrcBlend = convertBlendValue(src.srcBlend);
			dst.DestBlend = convertBlendValue(src.destBlend);
			dst.BlendOp = convertBlendOp(src.blendOp);
			dst.SrcBlendAlpha = convertBlendValue(src.srcBlendAlpha);
			dst.DestBlendAlpha = convertBlendValue(src.destBlendAlpha);
			dst.BlendOpAlpha = convertBlendOp(src.blendOpAlpha);
			dst.RenderTargetWriteMask = (uint8)src.colorWriteMask;
		}

		readonly HRESULT res = m_Context.device.CreateBlendState(&desc11New, &d3dBlendState);
		if (FAILED(res))
		{
			String message = scope $"CreateBlendState call failed, HRESULT = 0x{res:X}";
			m_Context.error(message);
			return null;
		}

		m_BlendStates[hash] = d3dBlendState;
		return d3dBlendState;
	}

	private ID3D11DepthStencilState* getDepthStencilState(DepthStencilState depthState)
	{
		int hash = 0;
		hash_combine(ref hash, depthState.depthTestEnable);
		hash_combine(ref hash, depthState.depthWriteEnable);
		hash_combine(ref hash, depthState.depthFunc);
		hash_combine(ref hash, depthState.stencilEnable);
		hash_combine(ref hash, depthState.stencilReadMask);
		hash_combine(ref hash, depthState.stencilWriteMask);
		hash_combine(ref hash, depthState.stencilRefValue);
		hash_combine(ref hash, depthState.frontFaceStencil.failOp);
		hash_combine(ref hash, depthState.frontFaceStencil.depthFailOp);
		hash_combine(ref hash, depthState.frontFaceStencil.passOp);
		hash_combine(ref hash, depthState.frontFaceStencil.stencilFunc);
		hash_combine(ref hash, depthState.backFaceStencil.failOp);
		hash_combine(ref hash, depthState.backFaceStencil.depthFailOp);
		hash_combine(ref hash, depthState.backFaceStencil.passOp);
		hash_combine(ref hash, depthState.backFaceStencil.stencilFunc);

		D3D11RefCountPtr<ID3D11DepthStencilState> d3dDepthStencilState = m_DepthStencilStates[hash];

		if (d3dDepthStencilState != null)
			return d3dDepthStencilState;

		D3D11_DEPTH_STENCIL_DESC desc11New;
		desc11New.DepthEnable = depthState.depthTestEnable ? /*TRUE*/ 1 : /*FALSE*/ 0;
		desc11New.DepthWriteMask = depthState.depthWriteEnable ? .D3D11_DEPTH_WRITE_MASK_ALL : .D3D11_DEPTH_WRITE_MASK_ZERO;
		desc11New.DepthFunc = convertComparisonFunc(depthState.depthFunc);
		desc11New.StencilEnable = depthState.stencilEnable ? /*TRUE*/ 1 : /*FALSE*/ 0;
		desc11New.StencilReadMask = (uint8)depthState.stencilReadMask;
		desc11New.StencilWriteMask = (uint8)depthState.stencilWriteMask;
		desc11New.FrontFace.StencilFailOp = convertStencilOp(depthState.frontFaceStencil.failOp);
		desc11New.FrontFace.StencilDepthFailOp = convertStencilOp(depthState.frontFaceStencil.depthFailOp);
		desc11New.FrontFace.StencilPassOp = convertStencilOp(depthState.frontFaceStencil.passOp);
		desc11New.FrontFace.StencilFunc = convertComparisonFunc(depthState.frontFaceStencil.stencilFunc);
		desc11New.BackFace.StencilFailOp = convertStencilOp(depthState.backFaceStencil.failOp);
		desc11New.BackFace.StencilDepthFailOp = convertStencilOp(depthState.backFaceStencil.depthFailOp);
		desc11New.BackFace.StencilPassOp = convertStencilOp(depthState.backFaceStencil.passOp);
		desc11New.BackFace.StencilFunc = convertComparisonFunc(depthState.backFaceStencil.stencilFunc);

		readonly HRESULT res = m_Context.device.CreateDepthStencilState(&desc11New, &d3dDepthStencilState);
		if (FAILED(res))
		{
			String message = scope $"CreateDepthStencilState call failed, HRESULT = 0x{res:X}";
			m_Context.error(message);
			return null;
		}

		m_DepthStencilStates[hash] = d3dDepthStencilState;
		return d3dDepthStencilState;
	}

	private ID3D11RasterizerState* getRasterizerState(RasterState rasterState)
	{
		int hash = 0;
		hash_combine(ref hash, rasterState.fillMode);
		hash_combine(ref hash, rasterState.cullMode);
		hash_combine(ref hash, rasterState.frontCounterClockwise);
		hash_combine(ref hash, rasterState.depthClipEnable);
		hash_combine(ref hash, rasterState.scissorEnable);
		hash_combine(ref hash, rasterState.multisampleEnable);
		hash_combine(ref hash, rasterState.antialiasedLineEnable);
		hash_combine(ref hash, rasterState.depthBias);
		hash_combine(ref hash, rasterState.depthBiasClamp);
		hash_combine(ref hash, rasterState.slopeScaledDepthBias);
		hash_combine(ref hash, rasterState.forcedSampleCount);
		hash_combine(ref hash, rasterState.programmableSamplePositionsEnable);
		hash_combine(ref hash, rasterState.conservativeRasterEnable);
		hash_combine(ref hash, rasterState.quadFillEnable);

		if (rasterState.programmableSamplePositionsEnable)
		{
			for (int32 i = 0; i < 16; i++)
			{
				hash_combine(ref hash, rasterState.samplePositionsX[i]);
				hash_combine(ref hash, rasterState.samplePositionsY[i]);
			}
		}

		D3D11RefCountPtr<ID3D11RasterizerState> d3dRasterizerState = m_RasterizerStates[hash];

		if (d3dRasterizerState != null)
			return d3dRasterizerState;

		D3D11_RASTERIZER_DESC desc11New;
		switch (rasterState.fillMode)
		{
		case RasterFillMode.Solid:
			desc11New.FillMode = .D3D11_FILL_SOLID;
			break;
		case RasterFillMode.Wireframe:
			desc11New.FillMode = .D3D11_FILL_WIREFRAME;
			break;
		default:
			nvrhi.utils.InvalidEnum();
		}

		switch (rasterState.cullMode)
		{
		case RasterCullMode.Back:
			desc11New.CullMode = .D3D11_CULL_BACK;
			break;
		case RasterCullMode.Front:
			desc11New.CullMode = .D3D11_CULL_FRONT;
			break;
		case RasterCullMode.None:
			desc11New.CullMode = .D3D11_CULL_NONE;
			break;
		default:
			nvrhi.utils.InvalidEnum();
		}

		desc11New.FrontCounterClockwise = rasterState.frontCounterClockwise ? /*TRUE*/ 1 : /*FALSE*/ 0;
		desc11New.DepthBias = rasterState.depthBias;
		desc11New.DepthBiasClamp = rasterState.depthBiasClamp;
		desc11New.SlopeScaledDepthBias = rasterState.slopeScaledDepthBias;
		desc11New.DepthClipEnable = rasterState.depthClipEnable ? /*TRUE*/ 1 : /*FALSE*/ 0;
		desc11New.ScissorEnable = rasterState.scissorEnable ? /*TRUE*/ 1 : /*FALSE*/ 0;
		desc11New.MultisampleEnable = rasterState.multisampleEnable ? /*TRUE*/ 1 : /*FALSE*/ 0;
		desc11New.AntialiasedLineEnable = rasterState.antialiasedLineEnable ? /*TRUE*/ 1 : /*FALSE*/ 0;

		bool extendedState = rasterState.conservativeRasterEnable
			|| rasterState.forcedSampleCount != 0
			|| rasterState.programmableSamplePositionsEnable
			|| rasterState.quadFillEnable;

		if (extendedState)
		{
#if NVRHI_D3D11_WITH_NVAPI
			NvAPI_D3D11_RASTERIZER_DESC_EX descEx;
			memset(&descEx, 0, sizeof(descEx));
			memcpy(&descEx, &desc11New, sizeof(desc11New));

			descEx.ConservativeRasterEnable = rasterState.conservativeRasterEnable;
			descEx.ProgrammableSamplePositionsEnable = rasterState.programmableSamplePositionsEnable;
			descEx.SampleCount = rasterState.forcedSampleCount;
			descEx.ForcedSampleCount = rasterState.forcedSampleCount;
			descEx.QuadFillMode = rasterState.quadFillEnable ? NVAPI_QUAD_FILLMODE_BBOX : NVAPI_QUAD_FILLMODE_DISABLED;
			memcpy(descEx.SamplePositionsX, rasterState.samplePositionsX, sizeof(rasterState.samplePositionsX));
			memcpy(descEx.SamplePositionsY, rasterState.samplePositionsY, sizeof(rasterState.samplePositionsY));

			if (NVAPI_OK != NvAPI_D3D11_CreateRasterizerState(m_Context.device, &descEx, &d3dRasterizerState))
			{
				m_Context.error("NvAPI_D3D11_CreateRasterizerState call failed");
				return null;
			}
#else
			m_Context.error("Cannot create an extended rasterizer state without NVAPI support");
			return null;
#endif
		}
		else
		{
			readonly HRESULT res = m_Context.device.CreateRasterizerState(&desc11New, &d3dRasterizerState);

			if (FAILED(res))
			{
				String message = scope $"CreateRasterizerState call failed, HRESULT = 0x{res:X}";
				m_Context.error(message);
				return null;
			}
		}

		m_RasterizerStates[hash] = d3dRasterizerState;
		return d3dRasterizerState;
	}
}