using Win32.Graphics.Direct3D11;
using System.Collections;
namespace nvrhi.d3d11;

class BindingSetD3D11 : RefCounter<IBindingSet>
{
	public BindingSetDesc desc;
	public BindingLayoutHandle layout;
	public ShaderType visibility = ShaderType.None;

	public ID3D11ShaderResourceView*[D3D11_COMMONSHADER_INPUT_RESOURCE_SLOT_COUNT] SRVs = .();
	public uint32 minSRVSlot = D3D11_COMMONSHADER_INPUT_RESOURCE_SLOT_COUNT;
	public uint32 maxSRVSlot = 0;

	public ID3D11SamplerState*[D3D11_COMMONSHADER_SAMPLER_SLOT_COUNT] samplers = .();
	public uint32 minSamplerSlot = D3D11_COMMONSHADER_SAMPLER_SLOT_COUNT;
	public uint32 maxSamplerSlot = 0;

	public ID3D11Buffer*[D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT] constantBuffers = .();
	public uint32 minConstantBufferSlot = D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT;
	public uint32 maxConstantBufferSlot = 0;

	public ID3D11UnorderedAccessView*[D3D11_1_UAV_SLOT_COUNT] UAVs = .();
	public uint32 minUAVSlot = D3D11_1_UAV_SLOT_COUNT;
	public uint32 maxUAVSlot = 0;

	public List<RefCountPtr<IResource>> resources;

	public override BindingSetDesc* getDesc()  { return &desc; }
	public override IBindingLayout getLayout() { return layout; }

	public bool isSupersetOf(BindingSetD3D11 other)
	{
		return minSRVSlot <= other.minSRVSlot && maxSRVSlot >= other.maxSRVSlot
			&& minUAVSlot <= other.minUAVSlot && maxUAVSlot >= other.maxUAVSlot
			&& minSamplerSlot <= other.minSamplerSlot && maxSamplerSlot >= other.maxSamplerSlot
			&& minConstantBufferSlot <= other.minConstantBufferSlot && maxConstantBufferSlot >= other.maxConstantBufferSlot;
	}
}