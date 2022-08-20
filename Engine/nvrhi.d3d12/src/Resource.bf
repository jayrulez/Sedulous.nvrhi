namespace nvrhi
{
	extension ObjectType
	{
		case D3D12_Device                           = 0x00020001;
		case D3D12_CommandQueue                     = 0x00020002;
		case D3D12_GraphicsCommandList              = 0x00020003;
		case D3D12_Resource                         = 0x00020004;
		case D3D12_RenderTargetViewDescriptor       = 0x00020005;
		case D3D12_DepthStencilViewDescriptor       = 0x00020006;
		case D3D12_ShaderResourceViewGpuDescripror  = 0x00020007;
		case D3D12_UnorderedAccessViewGpuDescripror = 0x00020008;
		case D3D12_RootSignature                    = 0x00020009;
		case D3D12_PipelineState                    = 0x0002000a;
		case D3D12_CommandAllocator                 = 0x0002000b;
	}
}