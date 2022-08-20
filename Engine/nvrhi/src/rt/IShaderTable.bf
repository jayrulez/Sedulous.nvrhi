namespace nvrhi.rt
{
	abstract class IShaderTable :  IResource
	{
	    public abstract void setRayGenerationShader(char8* exportName, IBindingSet bindings = null);
	    public abstract int32 addMissShader(char8* exportName, IBindingSet bindings = null);
	    public abstract int32 addHitGroup(char8* exportName, IBindingSet bindings = null);
	    public abstract int32 addCallableShader(char8* exportName, IBindingSet bindings = null);
	    public abstract void clearMissShaders();
	    public abstract void clearHitShaders();
	    public abstract void clearCallableShaders();
	    public abstract IPipeline getPipeline();
	}

	typealias ShaderTableHandle = RefCountPtr<IShaderTable> ;
}