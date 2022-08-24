using System.Collections;
using Win32.Graphics.Direct3D12;
using System;
namespace nvrhi.d3d12;

class RayTracingPipeline : RefCounter<nvrhi.rt.IPipeline>
{
	public nvrhi.rt.PipelineDesc desc;

	public Dictionary<IBindingLayout, RootSignatureHandle> localRootSignatures;
	public RefCountPtr<RootSignature> globalRootSignature;
	public D3D12RefCountPtr<ID3D12StateObject> pipelineState;
	public D3D12RefCountPtr<ID3D12StateObjectProperties> pipelineInfo;

	public struct ExportTableEntry
	{
		public IBindingLayout bindingLayout;
		public readonly void* pShaderIdentifier;
	}

	public Dictionary<String, ExportTableEntry> exports;
	public uint32 maxLocalRootParameters = 0;

	public this(Context* context)
		{ m_Context = context; }

	public ExportTableEntry* getExport(char8* name)
	{
		String nameString = scope String(name);
		if (exports.ContainsKey(nameString))
		{
			return &exports[nameString];
		}

		return null;
	}

	public uint32 getShaderTableEntrySize()
	{
		uint32 requiredSize = D3D12_SHADER_IDENTIFIER_SIZE_IN_BYTES + sizeof(UINT64) * maxLocalRootParameters;
		return align(requiredSize, uint32(D3D12_RAYTRACING_SHADER_TABLE_BYTE_ALIGNMENT));
	}

	public override readonly ref nvrhi.rt.PipelineDesc getDesc() { return ref desc; }
	public override nvrhi.rt.ShaderTableHandle createShaderTable()
	{
		return nvrhi.rt.ShaderTableHandle.Attach(new ShaderTable(m_Context, this));
	}

	private Context* m_Context;
}