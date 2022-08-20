using System;
namespace nvrhi
{
	abstract class IShader :  IResource
	{
		[NoDiscard] public abstract readonly ref ShaderDesc getDesc();
		public abstract void getBytecode(void** ppBytecode, int* pSize);
	}

	typealias ShaderHandle = RefCountPtr<IShader>;
}