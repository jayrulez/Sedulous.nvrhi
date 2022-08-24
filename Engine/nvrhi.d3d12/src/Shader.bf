using System.Collections;
namespace nvrhi.d3d12
{
	class Shader : RefCounter<IShader>
	{
		public ShaderDesc desc;
		public List<char8> bytecode;
	#if NVRHI_D3D12_WITH_NVAPI
		public List<NVAPI_D3D12_PSO_EXTENSION_DESC*> extensions;
		public List<NV_CUSTOM_SEMANTIC> customSemantics;
		public List<uint32> coordinateSwizzling;
	#endif

		public override readonly ref ShaderDesc getDesc() { return ref desc; }
		public override void getBytecode(void** ppBytecode, int* pSize)
		{
			if (ppBytecode != null) *ppBytecode = bytecode.Ptr;
			if (pSize != null) *pSize = bytecode.Count;
		}
	}
}