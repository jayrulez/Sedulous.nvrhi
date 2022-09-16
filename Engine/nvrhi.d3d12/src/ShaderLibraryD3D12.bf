using System.Collections;
namespace nvrhi.d3d12
{
	class ShaderLibraryD3D12 : RefCounter<IShaderLibrary>
	{
		public List<char8> bytecode;

		public override void getBytecode(void** ppBytecode, int* pSize)
		{
			if (ppBytecode != null) *ppBytecode = bytecode.Ptr;
			if (pSize != null) *pSize = bytecode.Count;
		}
		public override ShaderHandle getShader(char8* entryName, ShaderType shaderType)
		{
			return ShaderHandle.Attach(new ShaderLibraryEntry(this, entryName, shaderType));
		}
	}
}