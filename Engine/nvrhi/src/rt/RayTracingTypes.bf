using System;
using System.Collections;
namespace nvrhi
{
	namespace rt
	{
		typealias AffineTransform = float[12] ;

		public static{
		public const AffineTransform c_IdentityTransform = .(
		//  +----+----+---------  rotation and scaling
		//  v    v    v
		    1.f, 0.f, 0.f, 0.f,
		    0.f, 1.f, 0.f, 0.f,
		    0.f, 0.f, 1.f, 0.f
		//                 ^
		//                 +----  translation
		);
		}

		enum GeometryFlags : uint8
		{
		    None = 0,
		    Opaque = 1,
		    NoDuplicateAnyHitInvocation = 2
		}

		enum GeometryType : uint8
		{
		    Triangles = 0,
		    AABBs = 1
		}

		struct GeometryAABB
		{
		    float minX;
		    float minY;
		    float minZ;
		    float maxX;
		    float maxY;
		    float maxZ;
		}

		struct GeometryTriangles
		{
		    IBuffer indexBuffer = null;   // make sure the first fields in both Triangles 
		    IBuffer vertexBuffer = null;  // and AABBs are IBuffer for easier debugging
		    Format indexFormat = Format.UNKNOWN;
		    Format vertexFormat = Format.UNKNOWN;
		    uint64 indexOffset = 0;
		    uint64 vertexOffset = 0;
		    uint32 indexCount = 0;
		    uint32 vertexCount = 0;
		    uint32 vertexStride = 0;

		    public ref GeometryTriangles setIndexBuffer(IBuffer value) mut { indexBuffer = value; return ref this; }
		    public ref GeometryTriangles setVertexBuffer(IBuffer value) mut { vertexBuffer = value; return ref this; }
		    public ref GeometryTriangles setIndexFormat(Format value) mut { indexFormat = value; return ref this; }
		    public ref GeometryTriangles setVertexFormat(Format value) mut { vertexFormat = value; return ref this; }
		    public ref GeometryTriangles setIndexOffset(uint64 value) mut { indexOffset = value; return ref this; }
		    public ref GeometryTriangles setVertexOffset(uint64 value) mut { vertexOffset = value; return ref this; }
		    public ref GeometryTriangles setIndexCount(uint32 value) mut { indexCount = value; return ref this; }
		    public ref GeometryTriangles setVertexCount(uint32 value) mut { vertexCount = value; return ref this; }
		    public ref GeometryTriangles setVertexStride(uint32 value) mut { vertexStride = value; return ref this; }
		}

		struct GeometryAABBs
		{
		    IBuffer buffer = null;
		    IBuffer unused = null;
		    uint64 offset = 0;
		    uint32 count = 0;
		    uint32 stride = 0;

		    public ref GeometryAABBs setBuffer(IBuffer value) mut { buffer = value; return ref this; }
		    public ref GeometryAABBs setOffset(uint64 value) mut { offset = value; return ref this; }
		    public ref GeometryAABBs setCount(uint32 value) mut { count = value; return ref this; }
		    public ref GeometryAABBs setStride(uint32 value) mut { stride = value; return ref this; }
		}

		struct GeometryDesc
		{
		    [Union]public struct GeomTypeUnion
		    {
		        public GeometryTriangles triangles;
		        public GeometryAABBs aabbs;
		    }
		    public using private GeomTypeUnion geometryData;

		    bool useTransform = false;
		    AffineTransform transform = .();
		    GeometryFlags flags = GeometryFlags.None;
		    GeometryType geometryType = GeometryType.Triangles;

		    public this() {
				geometryData = .();
			}

		    public ref GeometryDesc setTransform(AffineTransform value) mut { var value; Internal.MemCpy(&transform, &value, sizeof(AffineTransform)); useTransform = true; return ref this; }
		    public ref GeometryDesc setFlags(GeometryFlags value) mut { flags = value; return ref this; }
		    public ref GeometryDesc setTriangles(GeometryTriangles value) mut { geometryData.triangles = value; geometryType = GeometryType.Triangles; return ref this; }
		    public ref GeometryDesc setAABBs(GeometryAABBs value) mut { geometryData.aabbs = value; geometryType = GeometryType.AABBs; return ref this; }
		}

		enum InstanceFlags : uint32
		{
		    None = 0,
		    TriangleCullDisable = 1,
		    TriangleFrontCounterclockwise = 2,
		    ForceOpaque = 4,
		    ForceNonOpaque = 8
		}

		//NVRHI_ENUM_CLASS_FLAG_OPERATORS(InstanceFlags)

		struct InstanceDesc
		{
		    public AffineTransform transform = .();
		    /*public uint32 instanceID : 24;
		    public uint32 instanceMask : 8;
		    public uint32 instanceContributionToHitGroupIndex : 24;
		    public InstanceFlags flags : 8;*/
			[Bitfield<uint32>(.Public, .Bits(24), "instanceID")]
			[Bitfield<uint32>(.Public, .Bits(8), "instanceMask")]
			[Bitfield<uint32>(.Public, .Bits(24), "instanceContributionToHitGroupIndex")]
			[Bitfield<InstanceFlags>(.Public, .Bits(8), "flags")]
			private uint64 _bits = 0;
		    [Union, CRepr] struct AS
			{
		        public IAccelStruct bottomLevelAS; // for buildTopLevelAccelStruct
		        public uint64 blasDeviceAddress;  // for buildTopLevelAccelStructFromBuffer - use IAccelStruct::getDeviceAddress()
		    }
			public using private AS _as;

		    public this() 
		    {
				
				/*instanceID=0;
				instanceMask=0;
				instanceContributionToHitGroupIndex=0;
				flags=InstanceFlags.None;*/
				bottomLevelAS=null;

		        setTransform(c_IdentityTransform);
		    }

		    public ref InstanceDesc setInstanceID(uint32 value) mut { instanceID = value; return ref this; }
		    public ref InstanceDesc setInstanceContributionToHitGroupIndex(uint32 value) mut { instanceContributionToHitGroupIndex = value; return ref this; }
		    public ref InstanceDesc setInstanceMask(uint32 value) mut { instanceMask = value; return ref this; }
		    public ref InstanceDesc setTransform(AffineTransform value) mut { var value; Internal.MemCpy(&transform, &value, sizeof(AffineTransform)); return ref this; }
		    public ref InstanceDesc setFlags(InstanceFlags value) mut { flags = value; return ref this; }
		    public ref InstanceDesc setBLAS(IAccelStruct value) mut { bottomLevelAS = value; return ref this; }
		}

		public static{
			public static void Assert(){
			Compiler.Assert(sizeof(InstanceDesc) == 64, "sizeof(InstanceDesc) is supposed to be 64 bytes");
			}
		}

		enum AccelStructBuildFlags : uint8
		{
		    None = 0,
		    AllowUpdate = 1,
		    AllowCompaction = 2,
		    PreferFastTrace = 4,
		    PreferFastBuild = 8,
		    MinimizeMemory = 0x10,
		    PerformUpdate = 0x20
		}

		//NVRHI_ENUM_CLASS_FLAG_OPERATORS(AccelStructBuildFlags)

		struct AccelStructDesc
		{
		    public int topLevelMaxInstances = 0; // only applies when isTopLevel = true
		    public List<GeometryDesc> bottomLevelGeometries; // only applies when isTopLevel = false
		    public AccelStructBuildFlags buildFlags = AccelStructBuildFlags.None;
		    public String debugName;
		    public bool trackLiveness = true;
		    public bool isTopLevel = false;
		    public bool isVirtual = false;

		    public ref AccelStructDesc setTopLevelMaxInstances(int value) mut { topLevelMaxInstances = value; isTopLevel = true; return ref this; }
		    public ref AccelStructDesc addBottomLevelGeometry(GeometryDesc value) mut { bottomLevelGeometries.Add(value); isTopLevel = false; return ref this; }
		    public ref AccelStructDesc setBuildFlags(AccelStructBuildFlags value) mut { buildFlags = value; return ref this; }
		    public ref AccelStructDesc setDebugName(String value) mut { debugName = value; return ref this; }
		    public ref AccelStructDesc setTrackLiveness(bool value) mut { trackLiveness = value; return ref this; }
		    public ref AccelStructDesc setIsTopLevel(bool value) mut { isTopLevel = value; return ref this; }
		    public ref AccelStructDesc setIsVirtual(bool value) mut { isVirtual = value; return ref this; }
		}


		struct PipelineShaderDesc
		{
		    public String exportName;
		    public ShaderHandle shader;
		    public BindingLayoutHandle bindingLayout;

		    public ref PipelineShaderDesc setExportName(String value) mut { exportName = value; return ref this; }
		    public ref PipelineShaderDesc setShader(IShader value) mut { shader = value; return ref this; }
		    public ref PipelineShaderDesc setBindingLayout(IBindingLayout value) mut { bindingLayout = value; return ref this; }
		}

		struct PipelineHitGroupDesc
		{
		    public String exportName;
		    public ShaderHandle closestHitShader;
		    public ShaderHandle anyHitShader;
		    public ShaderHandle intersectionShader;
		    public BindingLayoutHandle bindingLayout;
		    public bool isProceduralPrimitive = false;

		    public ref PipelineHitGroupDesc setExportName(String value) mut { exportName = value; return ref this; }
		    public ref PipelineHitGroupDesc setClosestHitShader(IShader value) mut { closestHitShader = value; return ref this; }
		    public ref PipelineHitGroupDesc setAnyHitShader(IShader value) mut { anyHitShader = value; return ref this; }
		    public ref PipelineHitGroupDesc setIntersectionShader(IShader value) mut { intersectionShader = value; return ref this; }
		    public ref PipelineHitGroupDesc setBindingLayout(IBindingLayout value) mut { bindingLayout = value; return ref this; }
		    public ref PipelineHitGroupDesc setIsProceduralPrimitive(bool value) mut { isProceduralPrimitive = value; return ref this; }
		}

		struct PipelineDesc
		{
		    public List<PipelineShaderDesc> shaders;
		    public List<PipelineHitGroupDesc> hitGroups;
		    public BindingLayoutVector globalBindingLayouts;
		    public uint32 maxPayloadSize = 0;
		    public uint32 maxAttributeSize = sizeof(float) * 2; // typical case: float2 uv;
		    public uint32 maxRecursionDepth = 1;

		    public ref PipelineDesc addShader(PipelineShaderDesc value) mut { shaders.Add(value); return ref this; }
		    public ref PipelineDesc addHitGroup(PipelineHitGroupDesc value) mut { hitGroups.Add(value); return ref this; }
		    public ref PipelineDesc addBindingLayout(IBindingLayout value) mut { globalBindingLayouts.PushBack(value); return ref this; }
		    public ref PipelineDesc setMaxPayloadSize(uint32 value) mut { maxPayloadSize = value; return ref this; }
		    public ref PipelineDesc setMaxAttributeSize(uint32 value) mut { maxAttributeSize = value; return ref this; }
		    public ref PipelineDesc setMaxRecursionDepth(uint32 value) mut { maxRecursionDepth = value; return ref this; }
		}

		struct State
		{
		    public IShaderTable shaderTable = null;

		    public BindingSetVector bindings;

		    public ref State setShaderTable(IShaderTable value) mut { shaderTable = value; return ref this; }
		    public ref State addBindingSet(IBindingSet value) mut { bindings.PushBack(value); return ref this; }
		}

		struct DispatchRaysArguments
		{
		    public uint32 width = 1;
		    public uint32 height = 1;
		    public uint32 depth = 1;

		    public ref DispatchRaysArguments setWidth(uint32 value) mut { width = value; return ref this; }
		    public ref DispatchRaysArguments setHeight(uint32 value) mut { height = value; return ref this; }
		    public ref DispatchRaysArguments setDepth(uint32 value) mut { depth = value; return ref this; }
		    public ref DispatchRaysArguments setDimensions(uint32 w, uint32 h = 1, uint32 d = 1) mut { width = w; height = h; depth = d; return ref this; }
		}
	}
}