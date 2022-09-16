using Win32.Graphics.Direct3D11;
using System.Collections;
using System;
using nvrhi.d3dcommon;
using Win32.Foundation;
namespace nvrhi.d3d11;

class BufferD3D11 : RefCounter<IBuffer>
{
	public BufferDesc desc;
	public D3D11RefCountPtr<ID3D11Buffer> resource;

	public this(D3D11Context* context) { m_Context = context;  }
	public override readonly ref BufferDesc getDesc() { return ref desc; }
	public override NativeObject getNativeObject(ObjectType objectType)
	{
		switch (objectType)
		{
		case ObjectType.D3D11_Resource: fallthrough;
		case ObjectType.D3D11_Buffer:
			return NativeObject(resource);
		default:
			return null;
		}
	}

	public ID3D11ShaderResourceView* getSRV(Format format, BufferRange range, ResourceType type)
	{
		var format;
		var range;

		if (format == Format.UNKNOWN)
		{
			format = desc.format;
		}

		range = range.resolve(desc);

		ref D3D11RefCountPtr<ID3D11ShaderResourceView> srv = ref m_ShaderResourceViews[BufferBindingKey(range, format, type)];
		if (srv != null)
			return srv;


		D3D11_SHADER_RESOURCE_VIEW_DESC desc11;
		desc11.ViewDimension = .D3D11_SRV_DIMENSION_BUFFEREX;
		desc11.BufferEx.Flags = 0;

		switch (type) // NOLINT(clang-diagnostic-switch-enum)
		{
		case ResourceType.StructuredBuffer_SRV:
			Runtime.Assert(desc.structStride != 0);
			desc11.Format = .DXGI_FORMAT_UNKNOWN;
			desc11.BufferEx.FirstElement = (uint32)(range.byteOffset / desc.structStride);
			desc11.BufferEx.NumElements = (uint32)(range.byteSize / desc.structStride);
			break;

		case ResourceType.RawBuffer_SRV:
			desc11.Format = .DXGI_FORMAT_R32_TYPELESS;
			desc11.BufferEx.FirstElement = (uint32)(range.byteOffset / 4);
			desc11.BufferEx.NumElements = (uint32)(range.byteSize / 4);
			desc11.BufferEx.Flags = (.)D3D11_BUFFEREX_SRV_FLAG.D3D11_BUFFEREX_SRV_FLAG_RAW;
			break;

		case ResourceType.TypedBuffer_SRV:
			{
				Runtime.Assert(format != Format.UNKNOWN);
				readonly ref DxgiFormatMapping formatMapping = ref getDxgiFormatMapping(format);
				readonly ref FormatInfo formatInfo = ref getFormatInfo(format);

				desc11.Format = formatMapping.srvFormat;
				desc11.BufferEx.FirstElement = (UINT)(range.byteOffset / formatInfo.bytesPerBlock);
				desc11.BufferEx.NumElements = (UINT)(range.byteSize / formatInfo.bytesPerBlock);
				break;
			}

		default:
			nvrhi.utils.InvalidEnum();
			return null;
		}

		readonly HRESULT res = m_Context.device.CreateShaderResourceView(resource, &desc11, &srv);
		if (FAILED(res))
		{
			String message = scope $"CreateUnorderedAccessView call failed for buffer {nvrhi.utils.DebugNameToString(desc.debugName)}, HRESULT = 0x{res}";
			m_Context.error(message);
		}

		return srv;
	}

	public ID3D11UnorderedAccessView* getUAV(Format format, BufferRange range, ResourceType type)
	{
		var format;
		var range;

		if (format == Format.UNKNOWN)
		{
			format = desc.format;
		}

		range = range.resolve(desc);

		ref D3D11RefCountPtr<ID3D11UnorderedAccessView> uav = ref m_UnorderedAccessViews[BufferBindingKey(range, format, type)];
		if (uav != null)
			return uav;

		D3D11_UNORDERED_ACCESS_VIEW_DESC desc11;
		desc11.ViewDimension = .D3D11_UAV_DIMENSION_BUFFER;
		desc11.Buffer.Flags = 0;

		switch (type) // NOLINT(clang-diagnostic-switch-enum)
		{
		case ResourceType.StructuredBuffer_UAV:
			Runtime.Assert(desc.structStride != 0);
			desc11.Format = .DXGI_FORMAT_UNKNOWN;
			desc11.Buffer.FirstElement = (UINT)(range.byteOffset / desc.structStride);
			desc11.Buffer.NumElements = (UINT)(range.byteSize / desc.structStride);
			break;

		case ResourceType.RawBuffer_UAV:
			desc11.Format = .DXGI_FORMAT_R32_TYPELESS;
			desc11.Buffer.FirstElement = (UINT)(range.byteOffset / 4);
			desc11.Buffer.NumElements = (UINT)(range.byteSize / 4);
			desc11.Buffer.Flags = (.)D3D11_BUFFER_UAV_FLAG.D3D11_BUFFER_UAV_FLAG_RAW;
			break;

		case ResourceType.TypedBuffer_UAV:
			{
				Runtime.Assert(format != Format.UNKNOWN);
				readonly ref DxgiFormatMapping formatMapping = ref getDxgiFormatMapping(format);
				readonly ref FormatInfo formatInfo = ref getFormatInfo(format);

				desc11.Format = formatMapping.srvFormat;
				desc11.Buffer.FirstElement = (UINT)(range.byteOffset / formatInfo.bytesPerBlock);
				desc11.Buffer.NumElements = (UINT)(range.byteSize / formatInfo.bytesPerBlock);
				break;
			}

		default:
			nvrhi.utils.InvalidEnum();
			return null;
		}

		readonly HRESULT res = m_Context.device.CreateUnorderedAccessView(resource, &desc11, &uav);
		if (FAILED(res))
		{
			String message = scope $"CreateUnorderedAccessView call failed for buffer {nvrhi.utils.DebugNameToString(desc.debugName)}, HRESULT = 0x{res}";
			m_Context.error(message);
		}

		return uav;
	}

	private D3D11Context* m_Context;
	private Dictionary<BufferBindingKey, D3D11RefCountPtr<ID3D11ShaderResourceView>> m_ShaderResourceViews;
	private Dictionary<BufferBindingKey, D3D11RefCountPtr<ID3D11UnorderedAccessView>> m_UnorderedAccessViews;
}