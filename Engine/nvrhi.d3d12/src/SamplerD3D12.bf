using Win32.Graphics.Direct3D12;
using System;
using nvrhi.d3dcommon;
namespace nvrhi.d3d12
{
	class SamplerD3D12 : RefCounter<ISampler>
	{
		public this(D3D12Context* context, SamplerDesc desc)
		{
			m_Context = context;
			m_Desc = desc;
			m_d3d12desc = .();

			UINT reductionType = (.)convertSamplerReductionType(desc.reductionType);

			if (m_Desc.maxAnisotropy > 1.0f)
			{
				m_d3d12desc.Filter = D3D12_ENCODE_ANISOTROPIC_FILTER!(reductionType);
			}
			else
			{
				m_d3d12desc.Filter = D3D12_ENCODE_BASIC_FILTER!(
					m_Desc.minFilter ? D3D12_FILTER_TYPE.D3D12_FILTER_TYPE_LINEAR : D3D12_FILTER_TYPE.D3D12_FILTER_TYPE_POINT,
					m_Desc.magFilter ? D3D12_FILTER_TYPE.D3D12_FILTER_TYPE_LINEAR : D3D12_FILTER_TYPE.D3D12_FILTER_TYPE_POINT,
					m_Desc.mipFilter ? D3D12_FILTER_TYPE.D3D12_FILTER_TYPE_LINEAR : D3D12_FILTER_TYPE.D3D12_FILTER_TYPE_POINT,
					reductionType);
			}

			m_d3d12desc.AddressU = convertSamplerAddressMode(m_Desc.addressU);
			m_d3d12desc.AddressV = convertSamplerAddressMode(m_Desc.addressV);
			m_d3d12desc.AddressW = convertSamplerAddressMode(m_Desc.addressW);

			m_d3d12desc.MipLODBias = m_Desc.mipBias;
			m_d3d12desc.MaxAnisotropy = Math.Max((UINT)m_Desc.maxAnisotropy, 1U);
			m_d3d12desc.ComparisonFunc = D3D12_COMPARISON_FUNC.D3D12_COMPARISON_FUNC_LESS;
			m_d3d12desc.BorderColor[0] = m_Desc.borderColor.r;
			m_d3d12desc.BorderColor[1] = m_Desc.borderColor.g;
			m_d3d12desc.BorderColor[2] = m_Desc.borderColor.b;
			m_d3d12desc.BorderColor[3] = m_Desc.borderColor.a;
			m_d3d12desc.MinLOD = 0;
			m_d3d12desc.MaxLOD = D3D12_FLOAT32_MAX;
		}

		public void createDescriptor(int descriptor)
		{
			m_Context.device.CreateSampler(&m_d3d12desc, .() { ptr = (.)descriptor });
		}

		public override readonly ref SamplerDesc getDesc()  { return ref m_Desc; }

		private D3D12Context* m_Context;
		private SamplerDesc m_Desc = .();
		private D3D12_SAMPLER_DESC m_d3d12desc = .();
	}
}