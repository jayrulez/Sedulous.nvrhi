using System.Collections;
using System;
namespace nvrhi.vulkan
{
	class ShaderTable : /*RefCounter<nvrhi.rt.IShaderTable>*/ nvrhi.rt.IShaderTable
	{
		public RayTracingPipeline pipeline;

		public int32 rayGenerationShader = -1;
		public List<uint32> missShaders;
		public List<uint32> callableShaders;
		public List<uint32> hitGroups;

		public uint32 version = 0;

		public this(VulkanContext* context, RayTracingPipeline _pipeline)
		{
			pipeline = _pipeline;
			m_Context = context;
		}

		public override void setRayGenerationShader(char8* exportName, IBindingSet bindings = null)
		{
			if (bindings != null)
				utils.NotSupported();

			readonly int32 shaderGroupIndex = pipeline.findShaderGroup(scope .(exportName));

			if (verifyShaderGroupExists(exportName, shaderGroupIndex))
			{
				rayGenerationShader = shaderGroupIndex;
				++version;
			}
		}

		public override int32 addMissShader(char8* exportName, IBindingSet bindings = null)
		{
			if (bindings != null)
				utils.NotSupported();

			readonly int32 shaderGroupIndex = pipeline.findShaderGroup(scope .(exportName));

			if (verifyShaderGroupExists(exportName, shaderGroupIndex))
			{
				missShaders.Add(uint32(shaderGroupIndex));
				++version;

				return int32(missShaders.Count) - 1;
			}

			return -1;
		}

		public override int32 addHitGroup(char8* exportName, IBindingSet bindings = null)
		{
			if (bindings != null)
				utils.NotSupported();

			readonly int32 shaderGroupIndex = pipeline.findShaderGroup(scope .(exportName));

			if (verifyShaderGroupExists(exportName, shaderGroupIndex))
			{
				hitGroups.Add(uint32(shaderGroupIndex));
				++version;

				return int32(hitGroups.Count) - 1;
			}

			return -1;
		}

		public override int32 addCallableShader(char8* exportName, IBindingSet bindings = null)
		{
			if (bindings != null)
				utils.NotSupported();

			readonly int32 shaderGroupIndex = pipeline.findShaderGroup(scope .(exportName));

			if (verifyShaderGroupExists(exportName, shaderGroupIndex))
			{
				callableShaders.Add(uint32(shaderGroupIndex));
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

		public override nvrhi.rt.IPipeline getPipeline() { return pipeline; }

		public uint32 getNumEntries()
		{
			return 1 + // rayGeneration
				uint32(missShaders.Count) +
				uint32(hitGroups.Count) +
				uint32(callableShaders.Count);
		}

		private VulkanContext* m_Context;

		private bool verifyShaderGroupExists(char8* exportName, int32 shaderGroupIndex)
		{
			if (shaderGroupIndex >= 0)
				return true;

			String message = scope $"Cannot find a RT pipeline shader group for RayGen shader with name {exportName}";
			m_Context.error(message);
			return false;
		}
	}
}