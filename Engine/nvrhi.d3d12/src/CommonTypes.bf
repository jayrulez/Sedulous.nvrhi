using Win32.Graphics.Direct3D12;
using System;
using Win32.Foundation;
using System.Collections;
using Win32.System.Com;

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

		case Nvrhi_D3D12_Device         = 0x00020101;
		case Nvrhi_D3D12_CommandList    = 0x00020102;
	}
}


namespace nvrhi.d3d12
{
	typealias D3D12_GPU_VIRTUAL_ADDRESS = uint64;
	typealias UINT = uint32;
	typealias UINT64 = uint64;
	typealias LONG = int64;
	typealias D3D12_RECT = RECT;

	typealias D3D12RefCountPtr<T> = T*;

	class IRootSignature : IResource
	{
	}
	typealias RootSignatureHandle = RefCountPtr<IRootSignature>;

	abstract class ICommandList : nvrhi.ICommandList
	{
		public abstract bool allocateUploadBuffer(int size, void** pCpuAddress, D3D12_GPU_VIRTUAL_ADDRESS* pGpuAddress);
		public abstract bool commitDescriptorHeaps();
		public abstract D3D12_GPU_VIRTUAL_ADDRESS getBufferGpuVA(IBuffer buffer);

		public abstract void updateGraphicsVolatileBuffers();
		public abstract void updateComputeVolatileBuffers();
	}

	typealias CommandListHandle = RefCountPtr<nvrhi.d3d12.ICommandList>;

	typealias DescriptorIndex = uint32;

	abstract class IDescriptorHeap
	{
		public abstract DescriptorIndex allocateDescriptors(uint32 count);
		public abstract DescriptorIndex allocateDescriptor();
		public abstract void releaseDescriptors(DescriptorIndex baseIndex, uint32 count);
		public abstract void releaseDescriptor(DescriptorIndex index);
		public abstract D3D12_CPU_DESCRIPTOR_HANDLE getCpuHandle(DescriptorIndex index);
		public abstract D3D12_CPU_DESCRIPTOR_HANDLE getCpuHandleShaderVisible(DescriptorIndex index);
		public abstract D3D12_GPU_DESCRIPTOR_HANDLE getGpuHandle(DescriptorIndex index);
		[NoDiscard] public abstract ID3D12DescriptorHeap* getHeap();
		[NoDiscard] public abstract ID3D12DescriptorHeap* getShaderVisibleHeap();
	}

	enum DescriptorHeapType
	{
		RenderTargetView,
		DepthStencilView,
		ShaderResrouceView,
		Sampler
	}

	abstract class IDevice : nvrhi.IDevice
	{
		// D3D12-specific methods
		public abstract RootSignatureHandle buildRootSignature(StaticVector<BindingLayoutHandle, const c_MaxBindingLayouts> pipelineLayouts, bool allowInputLayout, bool isLocal, D3D12_ROOT_PARAMETER1* pCustomParameters = null, uint32 numCustomParameters = 0);
		public abstract GraphicsPipelineHandle createHandleForNativeGraphicsPipeline(IRootSignature rootSignature, ID3D12PipelineState* pipelineState, GraphicsPipelineDesc desc, FramebufferInfo framebufferInfo);
		public abstract MeshletPipelineHandle createHandleForNativeMeshletPipeline(IRootSignature rootSignature, ID3D12PipelineState* pipelineState, MeshletPipelineDesc desc, FramebufferInfo framebufferInfo);
		[NoDiscard] public abstract IDescriptorHeap getDescriptorHeap(DescriptorHeapType heapType);
	}

	typealias DeviceHandle = RefCountPtr<nvrhi.d3d12.IDevice>;

	struct DeviceDesc
	{
		public IMessageCallback errorCB = null;
		public ID3D12Device* pDevice = null;
		public ID3D12CommandQueue* pGraphicsCommandQueue = null;
		public ID3D12CommandQueue* pComputeCommandQueue = null;
		public ID3D12CommandQueue* pCopyCommandQueue = null;

		public uint32 renderTargetViewHeapSize = 1024;
		public uint32 depthStencilViewHeapSize = 1024;
		public uint32 shaderResourceViewHeapSize = 16384;
		public uint32 samplerHeapSize = 1024;
		public uint32 maxTimerQueries = 256;
	}


	typealias RootParameterIndex = uint32;

	public static
	{
		public const DescriptorIndex c_InvalidDescriptorIndex = ~0u;
		public const D3D12_RESOURCE_STATES c_ResourceStateUnknown = (D3D12_RESOURCE_STATES)~0u;
	}

	struct DX12_ViewportState
	{
		public UINT numViewports = 0;
		public D3D12_VIEWPORT[16] viewports = .();
		public UINT numScissorRects = 0;
		public D3D12_RECT[16] scissorRects = .();
	}

	class TextureState
	{
		public List<D3D12_RESOURCE_STATES> subresourceStates = new .() ~ delete _;
		public bool enableUavBarriers = true;
		public bool firstUavBarrierPlaced = false;
		public bool permanentTransition = false;

		public this(uint32 numSubresources)
		{
			subresourceStates.Resize(numSubresources, c_ResourceStateUnknown);
		}
	}

	class BufferState
	{
		public D3D12_RESOURCE_STATES state = c_ResourceStateUnknown;
		public bool enableUavBarriers = true;
		public bool firstUavBarrierPlaced = false;
		public D3D12_GPU_VIRTUAL_ADDRESS volatileData = 0;
		public bool permanentTransition = false;
	}

	class ShaderTableState
	{
	    public uint32 committedVersion = 0;
	    public ID3D12DescriptorHeap* descriptorHeapSRV = null;
	    public ID3D12DescriptorHeap* descriptorHeapSamplers = null;
	    public D3D12_DISPATCH_RAYS_DESC dispatchRaysTemplate = .();
	}

	class BufferChunk
	{
		public const uint64 c_sizeAlignment = 4096; // GPU page size

		public D3D12RefCountPtr<ID3D12Resource> buffer;
		public uint64 version = 0;
		public uint64 bufferSize = 0;
		public uint64 writePointer = 0;
		public void* cpuVA = null;
		public D3D12_GPU_VIRTUAL_ADDRESS gpuVA = 0;
		public uint32 identifier = 0;

		public ~this()
		{
			if (buffer != null && cpuVA != null)
			{
				buffer.Unmap(0, null);
				cpuVA = null;
			}
		}
	}

	class InternalCommandList
	{
	    public D3D12RefCountPtr<ID3D12CommandAllocator> allocator;
	    public D3D12RefCountPtr<ID3D12GraphicsCommandList> commandList;
	    public D3D12RefCountPtr<ID3D12GraphicsCommandList4> commandList4;
	    public D3D12RefCountPtr<ID3D12GraphicsCommandList6> commandList6;
	    public uint64 lastSubmittedInstance = 0;
	}

	class CommandListInstance
	{
	    public uint64 submittedInstance = 0;
	    public CommandQueue commandQueue = CommandQueue.Graphics;
	    public D3D12RefCountPtr<ID3D12Fence> fence;
	    public D3D12RefCountPtr<ID3D12CommandAllocator> commandAllocator;
	    public D3D12RefCountPtr<ID3D12CommandList> commandList;
	    public List<RefCountPtr<IResource>> referencedResources = new .() ~ delete _;
	    public List<RefCountPtr<IUnknown>> referencedNativeResources = new .() ~ delete _;
	    public List<RefCountPtr<StagingTexture>> referencedStagingTextures = new .() ~ delete _;
	    public List<RefCountPtr<Buffer>> referencedStagingBuffers = new .() ~ delete _;
	    public List<RefCountPtr<TimerQuery>> referencedTimerQueries = new .() ~ delete _;
#if NVRHI_WITH_RTXMU
	    public List<uint64> rtxmuBuildIds = new .() ~ delete _;
	    public List<uint64> rtxmuCompactionIds = new .() ~ delete _;
#endif
	}
}