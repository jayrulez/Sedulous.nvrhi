using System.Collections;
namespace nvrhi.d3d12;

class ShaderTable : RefCounter<nvrhi.rt.IShaderTable>
{
	public struct Entry
	{
		public void* pShaderIdentifier;
		public BindingSetHandle localBindings;
	}

	public RefCountPtr<RayTracingPipeline> pipeline;

	public Entry rayGenerationShader = .();
	public List<Entry> missShaders = new .() ~ delete _;
	public List<Entry> callableShaders = new .() ~ delete _;
	public List<Entry> hitGroups = new .() ~ delete _;

	public uint32 version = 0;

	public this(Context* context, RayTracingPipeline _pipeline)
	{
		pipeline = _pipeline;
		m_Context = context;
	}

	public uint32 getNumEntries()
	{
		return 1 + // rayGeneration
			uint32(missShaders.Count) +
			uint32(hitGroups.Count) +
			uint32(callableShaders.Count);
	}

	public override void setRayGenerationShader(char8* exportName, IBindingSet bindings = null)
	{
		readonly RayTracingPipeline.ExportTableEntry* pipelineExport = pipeline.getExport(exportName);

		if (verifyExport(pipelineExport, bindings))
		{
			rayGenerationShader.pShaderIdentifier = pipelineExport.pShaderIdentifier;
			rayGenerationShader.localBindings = bindings;

			++version;
		}
	}

	public override int32 addMissShader(char8* exportName, IBindingSet bindings = null)
	{
		readonly RayTracingPipeline.ExportTableEntry* pipelineExport = pipeline.getExport(exportName);

		if (verifyExport(pipelineExport, bindings))
		{
			Entry entry = .();
			entry.pShaderIdentifier = pipelineExport.pShaderIdentifier;
			entry.localBindings = bindings;
			missShaders.Add(entry);

			++version;

			return int32(missShaders.Count) - 1;
		}

		return -1;
	}

	public override int32 addHitGroup(char8* exportName, IBindingSet bindings = null)
	{
		readonly RayTracingPipeline.ExportTableEntry* pipelineExport = pipeline.getExport(exportName);

		if (verifyExport(pipelineExport, bindings))
		{
			Entry entry = .();
			entry.pShaderIdentifier = pipelineExport.pShaderIdentifier;
			entry.localBindings = bindings;
			hitGroups.Add(entry);

			++version;

			return int32(hitGroups.Count) - 1;
		}

		return -1;
	}

	public override int32 addCallableShader(char8* exportName, IBindingSet bindings = null)
	{
		readonly RayTracingPipeline.ExportTableEntry* pipelineExport = pipeline.getExport(exportName);

		if (verifyExport(pipelineExport, bindings))
		{
			Entry entry = .();
			entry.pShaderIdentifier = pipelineExport.pShaderIdentifier;
			entry.localBindings = bindings;
			callableShaders.Add(entry);

			++version;

			return int32(callableShaders.Count) - 1;
		}

		return -1;
	}

	public override void clearMissShaders()
	{
		missShaders.Clear();
		++version;
	}
	public override void clearHitShaders()
	{
		hitGroups.Clear();
		++version;
	}
	public override void clearCallableShaders()
	{
		callableShaders.Clear();
		++version;
	}

	public override nvrhi.rt.IPipeline getPipeline()
	{
		return pipeline;
	}

	private Context* m_Context;

	private bool verifyExport(RayTracingPipeline.ExportTableEntry* pExport, IBindingSet bindings)
	{
		if (pExport == null)
		{
			m_Context.error("Couldn't find a DXR PSO export with a given name");
			return false;
		}

		if (pExport.bindingLayout != null && bindings == null)
		{
			m_Context.error("A shader table entry does not provide required local bindings");
			return false;
		}

		if (pExport.bindingLayout == null && bindings != null)
		{
			m_Context.error("A shader table entry provides local bindings, but none are required");
			return false;
		}

		if (bindings != null && (checked_cast<nvrhi.d3d12.BindingSet, IBindingSet>(bindings).layout != pExport.bindingLayout))
		{
			m_Context.error("A shader table entry provides local bindings that do not match the expected layout");
			return false;
		}

		return true;
	}
}