namespace nvrhi
{
	//////////////////////////////////////////////////////////////////////////
	// Shader Library
	//////////////////////////////////////////////////////////////////////////

	abstract class IShaderLibrary :  IResource
	{
		public abstract void getBytecode(void** ppBytecode, int* pSize);
		public abstract ShaderHandle getShader(char8* entryName, ShaderType shaderType);
	}

	typealias ShaderLibraryHandle = RefCountPtr<IShaderLibrary>;
}