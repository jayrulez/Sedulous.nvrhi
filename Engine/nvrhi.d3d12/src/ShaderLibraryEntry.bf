namespace nvrhi.d3d12
{
	class ShaderLibraryEntry : RefCounter<IShader>
	{
		public ShaderDesc desc;
		public RefCountPtr<IShaderLibrary> library;

		public this(IShaderLibrary pLibrary, char8* entryName, ShaderType shaderType)
		{
			desc = .(shaderType);
			library = pLibrary;
			desc.entryName = new .(entryName);
		}

		public override readonly ref ShaderDesc getDesc() { return ref desc; }
		public override void getBytecode(void** ppBytecode, int* pSize)
		{
			library.getBytecode(ppBytecode, pSize);
		}
	}
}