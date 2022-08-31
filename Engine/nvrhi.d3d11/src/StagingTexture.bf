using nvrhi.d3dcommon;
namespace nvrhi.d3d11;

class StagingTexture : RefCounter<IStagingTexture>
{
    public RefCountPtr<Texture> texture;
    public CpuAccessMode cpuAccess = CpuAccessMode.None;
    public UINT mappedSubresource = UINT(-1);
    
    public override readonly ref TextureDesc getDesc() { return ref texture.getDesc(); }
}