namespace nvrhi.d3d11;

class BindingLayoutD3D11 : RefCounter<IBindingLayout>
{
    public BindingLayoutDesc desc;

    public override BindingLayoutDesc* getDesc() { return &desc; }
    public override BindlessLayoutDesc* getBindlessDesc() { return null; }
}