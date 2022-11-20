using System;



namespace nvrhi
{
	public static
	{
		// Version of the public API provided by NVRHI.
		// Increment this when any changes to the API are made.
		public const uint32 c_HeaderVersion = 4;

		// Verifies that the version of the implementation matches the version of the header.
		// Returns true if they match. Use this when initializing apps using NVRHI as a shared library.
		public static bool verifyHeaderVersion(uint32 version = c_HeaderVersion)
		{
			return version == c_HeaderVersion;
		}

		public const uint32 c_MaxRenderTargets = 8;
		public const uint32 c_MaxViewports = 16;
		public const uint32 c_MaxVertexAttributes = 16;
		public const uint32 c_MaxBindingLayouts = 5;
		public const uint32 c_MaxBindingsPerLayout = 128;
		public const uint32 c_MaxVolatileConstantBuffersPerLayout = 6;
		public const uint32 c_MaxVolatileConstantBuffers = 32;
		public const uint32 c_MaxPushConstantSize = 128; // D3D12: root signature is 256 bytes max., Vulkan: 128 bytes of push constants guaranteed

	}

	//////////////////////////////////////////////////////////////////////////
	// Basic Types
	//////////////////////////////////////////////////////////////////////////

	[CRepr]
	struct Color
	{
		public float r;
		public float g;
		public float b;
		public float a;

		public this()
		{
			r = 0.f;
			g = 0.f;
			b = 0.f;
			a = 0.f;
		}
		public this(float c)
		{
			r = c;
			g = c;
			b = c;
			a = c;
		}
		public this(float _r, float _g, float _b, float _a)
		{
			r = _r;
			g = _g;
			b = _b;
			a = _a;
		}

		public static bool operator ==(Color a, Color _b) { return a.r == _b.r && a.g == _b.g && a.b == _b.b && a.a == _b.a; }
		public static bool operator !=(Color a, Color _b) { return !(a == _b); }
	}

	[CRepr]
	struct Viewport
	{
		public float minX, maxX;
		public float minY, maxY;
		public float minZ, maxZ;

		public this()
		{
			minX = (0.f);
			maxX = (0.f);
			minY = (0.f);
			maxY = (0.f);
			minZ = (0.f);
			maxZ = (1.f);
		}

		public this(float width, float height)
		{
			minX = (0.f);
			maxX = (width);
			minY = (0.f);
			maxY = (height);
			minZ = (0.f);
			maxZ = (1.f);
		}

		public this(float _minX, float _maxX, float _minY, float _maxY, float _minZ, float _maxZ)
		{
			minX = (_minX);
			maxX = (_maxX);
			minY = (_minY);
			maxY = (_maxY);
			minZ = (_minZ);
			maxZ = (_maxZ);
		}

		public static bool operator ==(Viewport a, Viewport b)
		{
			return a.minX == b.minX
				&& a.minY == b.minY
				&& a.minZ == b.minZ
				&& a.maxX == b.maxX
				&& a.maxY == b.maxY
				&& a.maxZ == b.maxZ;
		}
		public static bool operator !=(Viewport a, Viewport b) { return !(a == b); }

		[NoDiscard] public float width() { return maxX - minX; }
		[NoDiscard] public float height() { return maxY - minY; }
	}

	[CRepr]
	struct Rect
	{
		public int32 minX, maxX;
		public int32 minY, maxY;

		public this()
		{
			minX = (0); maxX = (0); minY = (0); maxY = (0);
		}
		public this(int32 width, int32 height)
		{
			minX = (0);
			maxX = (width);
			minY = (0);
			maxY = (height);
		}
		public this(int32 _minX, int32 _maxX, int32 _minY, int32 _maxY)
		{
			minX = (_minX);
			maxX = (_maxX);
			minY = (_minY);
			maxY = (_maxY);
		}
		public this(Viewport viewport)
		{
			minX = (int32(Math.Floor(viewport.minX)));
			maxX = (int32(Math.Ceiling(viewport.maxX)));
			minY = (int32(Math.Floor(viewport.minY)));
			maxY = (int32(Math.Ceiling(viewport.maxY)));
		}

		public static bool operator ==(Rect a, Rect b)
		{
			return a.minX == b.minX && a.minY == b.minY && a.maxX == b.maxX && a.maxY == b.maxY;
		}
		public static bool operator !=(Rect a, Rect b) { return !(a == b); }

		[NoDiscard] public int32 width() { return maxX - minX; }
		[NoDiscard] public int32 height() { return maxY - minY; }
	}

	enum GraphicsAPI : uint8
	{
		D3D11,
		D3D12,
		VULKAN
	}

	enum Format : uint8
	{
		UNKNOWN,

		R8_UINT,
		R8_SINT,
		R8_UNORM,
		R8_SNORM,
		RG8_UINT,
		RG8_SINT,
		RG8_UNORM,
		RG8_SNORM,
		R16_UINT,
		R16_SINT,
		R16_UNORM,
		R16_SNORM,
		R16_FLOAT,
		BGRA4_UNORM,
		B5G6R5_UNORM,
		B5G5R5A1_UNORM,
		RGBA8_UINT,
		RGBA8_SINT,
		RGBA8_UNORM,
		RGBA8_SNORM,
		BGRA8_UNORM,
		SRGBA8_UNORM,
		SBGRA8_UNORM,
		R10G10B10A2_UNORM,
		R11G11B10_FLOAT,
		RG16_UINT,
		RG16_SINT,
		RG16_UNORM,
		RG16_SNORM,
		RG16_FLOAT,
		R32_UINT,
		R32_SINT,
		R32_FLOAT,
		RGBA16_UINT,
		RGBA16_SINT,
		RGBA16_FLOAT,
		RGBA16_UNORM,
		RGBA16_SNORM,
		RG32_UINT,
		RG32_SINT,
		RG32_FLOAT,
		RGB32_UINT,
		RGB32_SINT,
		RGB32_FLOAT,
		RGBA32_UINT,
		RGBA32_SINT,
		RGBA32_FLOAT,

		D16,
		D24S8,
		X24G8_UINT,
		D32,
		D32S8,
		X32G8_UINT,

		BC1_UNORM,
		BC1_UNORM_SRGB,
		BC2_UNORM,
		BC2_UNORM_SRGB,
		BC3_UNORM,
		BC3_UNORM_SRGB,
		BC4_UNORM,
		BC4_SNORM,
		BC5_UNORM,
		BC5_SNORM,
		BC6H_UFLOAT,
		BC6H_SFLOAT,
		BC7_UNORM,
		BC7_UNORM_SRGB,

		COUNT,
	}

	enum FormatKind : uint8
	{
		Integer,
		Normalized,
		Float,
		DepthStencil
	}

	struct FormatInfo
	{
		public Format format;
		public char8* name;
		public uint8 bytesPerBlock;
		public uint8 blockSize;
		public FormatKind kind;
		public bool hasRed; // : 1;
		public bool hasGreen; // : 1;
		public bool hasBlue; // : 1;
		public bool hasAlpha; // : 1;
		public bool hasDepth; // : 1;
		public  bool hasStencil; // : 1;
		public bool isSigned; // : 1;
		public bool isSRGB; // : 1;

		public this(
			Format _format,
			char8* _name,
			uint8 _bytesPerBlock,
			uint8 _blockSize,
			FormatKind _kind,
			bool _hasRed,
			bool _hasGreen,
			bool _hasBlue,
			bool _hasAlpha,
			bool _hasDepth,
			bool _hasStencil,
			bool _isSigned,
			bool _isSRGB
			)
		{
			format = _format;
			name = _name;
			bytesPerBlock = _bytesPerBlock;
			blockSize = _blockSize;
			kind = _kind;
			hasRed = _hasRed;
			hasGreen = _hasGreen;
			hasBlue = _hasBlue;
			hasAlpha = _hasAlpha;
			hasDepth = _hasDepth;
			hasStencil = _hasStencil;
			isSigned = _isSigned;
			isSRGB = _isSRGB;
		}
	}

	public static
	{
		// Format mapping table. The rows must be in the exactly same order as Format enum members are defined.
		private static FormatInfo[?] c_FormatInfo =
			.( //format                   name             bytes blk         kind               red   green   blue  alpha  depth  stencl signed  srgb
			.(Format.UNKNOWN,           "UNKNOWN",           0,   0, FormatKind.Integer,      false, false, false, false, false, false, false, false),
			.(Format.R8_UINT,           "R8_UINT",           1,   1, FormatKind.Integer,      true,  false, false, false, false, false, false, false),
			.(Format.R8_SINT,           "R8_SINT",           1,   1, FormatKind.Integer,      true,  false, false, false, false, false, true,  false),
			.(Format.R8_UNORM,          "R8_UNORM",          1,   1, FormatKind.Normalized,   true,  false, false, false, false, false, false, false),
			.(Format.R8_SNORM,          "R8_SNORM",          1,   1, FormatKind.Normalized,   true,  false, false, false, false, false, false, false),
			.(Format.RG8_UINT,          "RG8_UINT",          2,   1, FormatKind.Integer,      true,  true,  false, false, false, false, false, false),
			.(Format.RG8_SINT,          "RG8_SINT",          2,   1, FormatKind.Integer,      true,  true,  false, false, false, false, true,  false),
			.(Format.RG8_UNORM,         "RG8_UNORM",         2,   1, FormatKind.Normalized,   true,  true,  false, false, false, false, false, false),
			.(Format.RG8_SNORM,         "RG8_SNORM",         2,   1, FormatKind.Normalized,   true,  true,  false, false, false, false, false, false),
			.(Format.R16_UINT,          "R16_UINT",          2,   1, FormatKind.Integer,      true,  false, false, false, false, false, false, false),
			.(Format.R16_SINT,          "R16_SINT",          2,   1, FormatKind.Integer,      true,  false, false, false, false, false, true,  false),
			.(Format.R16_UNORM,         "R16_UNORM",         2,   1, FormatKind.Normalized,   true,  false, false, false, false, false, false, false),
			.(Format.R16_SNORM,         "R16_SNORM",         2,   1, FormatKind.Normalized,   true,  false, false, false, false, false, false, false),
			.(Format.R16_FLOAT,         "R16_FLOAT",         2,   1, FormatKind.Float,        true,  false, false, false, false, false, true,  false),
			.(Format.BGRA4_UNORM,       "BGRA4_UNORM",       2,   1, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, false),
			.(Format.B5G6R5_UNORM,      "B5G6R5_UNORM",      2,   1, FormatKind.Normalized,   true,  true,  true,  false, false, false, false, false),
			.(Format.B5G5R5A1_UNORM,    "B5G5R5A1_UNORM",    2,   1, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, false),
			.(Format.RGBA8_UINT,        "RGBA8_UINT",        4,   1, FormatKind.Integer,      true,  true,  true,  true,  false, false, false, false),
			.(Format.RGBA8_SINT,        "RGBA8_SINT",        4,   1, FormatKind.Integer,      true,  true,  true,  true,  false, false, true,  false),
			.(Format.RGBA8_UNORM,       "RGBA8_UNORM",       4,   1, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, false),
			.(Format.RGBA8_SNORM,       "RGBA8_SNORM",       4,   1, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, false),
			.(Format.BGRA8_UNORM,       "BGRA8_UNORM",       4,   1, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, false),
			.(Format.SRGBA8_UNORM,      "SRGBA8_UNORM",      4,   1, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, true  ),
			.(Format.SBGRA8_UNORM,      "SBGRA8_UNORM",      4,   1, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, false),
			.(Format.R10G10B10A2_UNORM, "R10G10B10A2_UNORM", 4,   1, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, false),
			.(Format.R11G11B10_FLOAT,   "R11G11B10_FLOAT",   4,   1, FormatKind.Float,        true,  true,  true,  false, false, false, false, false),
			.(Format.RG16_UINT,         "RG16_UINT",         4,   1, FormatKind.Integer,      true,  true,  false, false, false, false, false, false),
			.(Format.RG16_SINT,         "RG16_SINT",         4,   1, FormatKind.Integer,      true,  true,  false, false, false, false, true,  false),
			.(Format.RG16_UNORM,        "RG16_UNORM",        4,   1, FormatKind.Normalized,   true,  true,  false, false, false, false, false, false),
			.(Format.RG16_SNORM,        "RG16_SNORM",        4,   1, FormatKind.Normalized,   true,  true,  false, false, false, false, false, false),
			.(Format.RG16_FLOAT,        "RG16_FLOAT",        4,   1, FormatKind.Float,        true,  true,  false, false, false, false, true,  false),
			.(Format.R32_UINT,          "R32_UINT",          4,   1, FormatKind.Integer,      true,  false, false, false, false, false, false, false),
			.(Format.R32_SINT,          "R32_SINT",          4,   1, FormatKind.Integer,      true,  false, false, false, false, false, true,  false),
			.(Format.R32_FLOAT,         "R32_FLOAT",         4,   1, FormatKind.Float,        true,  false, false, false, false, false, true,  false),
			.(Format.RGBA16_UINT,       "RGBA16_UINT",       8,   1, FormatKind.Integer,      true,  true,  true,  true,  false, false, false, false),
			.(Format.RGBA16_SINT,       "RGBA16_SINT",       8,   1, FormatKind.Integer,      true,  true,  true,  true,  false, false, true,  false),
			.(Format.RGBA16_FLOAT,      "RGBA16_FLOAT",      8,   1, FormatKind.Float,        true,  true,  true,  true,  false, false, true,  false),
			.(Format.RGBA16_UNORM,      "RGBA16_UNORM",      8,   1, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, false),
			.(Format.RGBA16_SNORM,      "RGBA16_SNORM",      8,   1, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, false),
			.(Format.RG32_UINT,         "RG32_UINT",         8,   1, FormatKind.Integer,      true,  true,  false, false, false, false, false, false),
			.(Format.RG32_SINT,         "RG32_SINT",         8,   1, FormatKind.Integer,      true,  true,  false, false, false, false, true,  false),
			.(Format.RG32_FLOAT,        "RG32_FLOAT",        8,   1, FormatKind.Float,        true,  true,  false, false, false, false, true,  false),
			.(Format.RGB32_UINT,        "RGB32_UINT",        12,  1, FormatKind.Integer,      true,  true,  true,  false, false, false, false, false),
			.(Format.RGB32_SINT,        "RGB32_SINT",        12,  1, FormatKind.Integer,      true,  true,  true,  false, false, false, true,  false),
			.(Format.RGB32_FLOAT,       "RGB32_FLOAT",       12,  1, FormatKind.Float,        true,  true,  true,  false, false, false, true,  false),
			.(Format.RGBA32_UINT,       "RGBA32_UINT",       16,  1, FormatKind.Integer,      true,  true,  true,  true,  false, false, false, false),
			.(Format.RGBA32_SINT,       "RGBA32_SINT",       16,  1, FormatKind.Integer,      true,  true,  true,  true,  false, false, true,  false),
			.(Format.RGBA32_FLOAT,      "RGBA32_FLOAT",      16,  1, FormatKind.Float,        true,  true,  true,  true,  false, false, true,  false),
			.(Format.D16,               "D16",               2,   1, FormatKind.DepthStencil, false, false, false, false, true,  false, false, false),
			.(Format.D24S8,             "D24S8",             4,   1, FormatKind.DepthStencil, false, false, false, false, true,  true,  false, false),
			.(Format.X24G8_UINT,        "X24G8_UINT",        4,   1, FormatKind.Integer,      false, false, false, false, false, true,  false, false),
			.(Format.D32,               "D32",               4,   1, FormatKind.DepthStencil, false, false, false, false, true,  false, false, false),
			.(Format.D32S8,             "D32S8",             8,   1, FormatKind.DepthStencil, false, false, false, false, true,  true,  false, false),
			.(Format.X32G8_UINT,        "X32G8_UINT",        8,   1, FormatKind.Integer,      false, false, false, false, false, true,  false, false),
			.(Format.BC1_UNORM,         "BC1_UNORM",         8,   4, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, false),
			.(Format.BC1_UNORM_SRGB,    "BC1_UNORM_SRGB",    8,   4, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, true  ),
			.(Format.BC2_UNORM,         "BC2_UNORM",         16,  4, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, false),
			.(Format.BC2_UNORM_SRGB,    "BC2_UNORM_SRGB",    16,  4, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, true  ),
			.(Format.BC3_UNORM,         "BC3_UNORM",         16,  4, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, false),
			.(Format.BC3_UNORM_SRGB,    "BC3_UNORM_SRGB",    16,  4, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, true  ),
			.(Format.BC4_UNORM,         "BC4_UNORM",         8,   4, FormatKind.Normalized,   true,  false, false, false, false, false, false, false),
			.(Format.BC4_SNORM,         "BC4_SNORM",         8,   4, FormatKind.Normalized,   true,  false, false, false, false, false, false, false),
			.(Format.BC5_UNORM,         "BC5_UNORM",         16,  4, FormatKind.Normalized,   true,  true,  false, false, false, false, false, false),
			.(Format.BC5_SNORM,         "BC5_SNORM",         16,  4, FormatKind.Normalized,   true,  true,  false, false, false, false, false, false),
			.(Format.BC6H_UFLOAT,       "BC6H_UFLOAT",       16,  4, FormatKind.Float,        true,  true,  true,  false, false, false, false, false),
			.(Format.BC6H_SFLOAT,       "BC6H_SFLOAT",       16,  4, FormatKind.Float,        true,  true,  true,  false, false, false, true,  false),
			.(Format.BC7_UNORM,         "BC7_UNORM",         16,  4, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, false),
			.(Format.BC7_UNORM_SRGB,    "BC7_UNORM_SRGB",    16,  4, FormatKind.Normalized,   true,  true,  true,  true,  false, false, false, true  )
			);

		public static readonly ref FormatInfo getFormatInfo(Format format)
		{
			Compiler.Assert(c_FormatInfo.Count == int(Format.COUNT),
				"The format info table doesn't have the right number of elements");

			if (uint32(format) >= uint32(Format.COUNT))
				return ref c_FormatInfo[0]; // UNKNOWN

			readonly ref FormatInfo info = ref c_FormatInfo[uint32(format)];
			Runtime.Assert(info.format == format);
			return ref info;
		}
	}

	enum FormatSupport : uint32
	{
		None            = 0,

		Buffer          = 0x00000001,
		IndexBuffer     = 0x00000002,
		VertexBuffer    = 0x00000004,

		Texture         = 0x00000008,
		DepthStencil    = 0x00000010,
		RenderTarget    = 0x00000020,
		Blendable       = 0x00000040,

		ShaderLoad      = 0x00000080,
		ShaderSample    = 0x00000100,
		ShaderUavLoad   = 0x00000200,
		ShaderUavStore  = 0x00000400,
		ShaderAtomic    = 0x00000800,
	}

	//////////////////////////////////////////////////////////////////////////
	// Heap
	//////////////////////////////////////////////////////////////////////////

	enum HeapType : uint8
	{
		DeviceLocal,
		Upload,
		Readback
	}

	struct HeapDesc
	{
		public uint64 capacity = 0;
		public HeapType type;
		public String debugName;

		public ref HeapDesc setCapacity(uint64 value) mut { capacity = value; return ref this; }
		public ref HeapDesc setType(HeapType value) mut { type = value; return ref this; }
		public ref HeapDesc setDebugName(String value) mut { debugName = value; return ref this; }
	}

	struct MemoryRequirements
	{
		public uint64 size = 0;
		public uint64 alignment = 0;
	}

	//////////////////////////////////////////////////////////////////////////
	// Texture
	//////////////////////////////////////////////////////////////////////////

	enum TextureDimension : uint8
	{
		Unknown,
		Texture1D,
		Texture1DArray,
		Texture2D,
		Texture2DArray,
		TextureCube,
		TextureCubeArray,
		Texture2DMS,
		Texture2DMSArray,
		Texture3D
	}

	enum CpuAccessMode : uint8
	{
		None,
		Read,
		Write
	}

	enum ResourceStates : uint32
	{
		Unknown               = 0,
		Common                = 0x00000001,
		ConstantBuffer        = 0x00000002,
		VertexBuffer          = 0x00000004,
		IndexBuffer           = 0x00000008,
		IndirectArgument      = 0x00000010,
		ShaderResource        = 0x00000020,
		UnorderedAccess       = 0x00000040,
		RenderTarget          = 0x00000080,
		DepthWrite            = 0x00000100,
		DepthRead             = 0x00000200,
		StreamOut             = 0x00000400,
		CopyDest              = 0x00000800,
		CopySource            = 0x00001000,
		ResolveDest           = 0x00002000,
		ResolveSource         = 0x00004000,
		Present               = 0x00008000,
		AccelStructRead       = 0x00010000,
		AccelStructWrite      = 0x00020000,
		AccelStructBuildInput = 0x00040000,
		AccelStructBuildBlas  = 0x00080000,
		ShadingRateSurface    = 0x00100000,
	}

	typealias MipLevel = uint32;
	typealias ArraySlice = uint32;

	// Flags for resources that need to be shared with other graphics APIs or other GPU devices.
	enum SharedResourceFlags : uint32
	{
		None                = 0,

		// D3D11: adds D3D11_RESOURCE_MISC_SHARED
		// D3D12: adds D3D12_HEAP_FLAG_SHARED
		// Vulkan: ignored
		Shared              = 0x01,

		// D3D11: adds (D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX | D3D11_RESOURCE_MISC_SHARED_NTHANDLE)
		// D3D12, Vulkan: ignored
		Shared_NTHandle     = 0x02,

		// D3D12: adds D3D12_RESOURCE_FLAG_ALLOW_CROSS_ADAPTER and D3D12_HEAP_FLAG_SHARED_CROSS_ADAPTER
		// D3D11, Vulkan: ignored
		Shared_CrossAdapter = 0x04,
	}

	//NVRHI_ENUM_CLASS_FLAG_OPERATORS(SharedResourceFlags)

	struct TextureDesc
	{
		public uint32 width = 1;
		public uint32 height = 1;
		public uint32 depth = 1;
		public uint32 arraySize = 1;
		public uint32 mipLevels = 1;
		public uint32 sampleCount = 1;
		public uint32 sampleQuality = 0;
		public Format format = Format.UNKNOWN;
		public TextureDimension dimension = TextureDimension.Texture2D;
		public String debugName;

		public bool isRenderTarget = false;
		public bool isUAV = false;
		public bool isTypeless = false;
		public bool isShadingRateSurface = false;

		public SharedResourceFlags sharedResourceFlags = SharedResourceFlags.None;

		// Indicates that the texture is created with no backing memory,
		// and memory is bound to the texture later using bindTextureMemory.
		// On DX12, the texture resource is created at the time of memory binding.
		public bool isVirtual = false;

		public Color clearValue;
		public bool useClearValue = false;

		public ResourceStates initialState = ResourceStates.Unknown;

		// If keepInitialState is true, command lists that use the texture will automatically
		// begin tracking the texture from the initial state and transition it to the initial state 
		// on command list close.
		public bool keepInitialState = false;

		public ref TextureDesc setWidth(uint32 value) mut { width = value; return ref this; }
		public ref TextureDesc setHeight(uint32 value) mut { height = value; return ref this; }
		public ref TextureDesc setDepth(uint32 value) mut { depth = value; return ref this; }
		public ref TextureDesc setArraySize(uint32 value) mut { arraySize = value; return ref this; }
		public ref TextureDesc setMipLevels(uint32 value) mut { mipLevels = value; return ref this; }
		public ref TextureDesc setSampleCount(uint32 value) mut { sampleCount = value; return ref this; }
		public ref TextureDesc setSampleQuality(uint32 value) mut { sampleQuality = value; return ref this; }
		public ref TextureDesc setFormat(Format value) mut { format = value; return ref this; }
		public ref TextureDesc setDimension(TextureDimension value) mut { dimension = value; return ref this; }
		public ref TextureDesc setDebugName(String value) mut { debugName = value; return ref this; }
		public ref TextureDesc setIsRenderTarget(bool value) mut { isRenderTarget = value; return ref this; }
		public ref TextureDesc setIsUAV(bool value) mut { isUAV = value; return ref this; }
		public ref TextureDesc setIsTypeless(bool value) mut { isTypeless = value; return ref this; }
		public ref TextureDesc setIsVirtual(bool value) mut { isVirtual = value; return ref this; }
		public ref TextureDesc setClearValue(Color value) mut { clearValue = value; useClearValue = true; return ref this; }
		public ref TextureDesc setUseClearValue(bool value) mut { useClearValue = value; return ref this; }
		public ref TextureDesc setInitialState(ResourceStates value) mut { initialState = value; return ref this; }
		public ref TextureDesc setKeepInitialState(bool value) mut { keepInitialState = value; return ref this; }
	}

	// describes a 2D section of a single mip level + single slice of a texture
	struct TextureSlice
	{
		public uint32 x = 0;
		public uint32 y = 0;
		public uint32 z = 0;
		// -1 means the entire dimension is part of the region
		// resolve() below will translate these values into actual dimensions
		public uint32 width = uint32(-1);
		public uint32 height = uint32(-1);
		public uint32 depth = uint32(-1);

		public MipLevel mipLevel = 0;
		public ArraySlice arraySlice = 0;

		[NoDiscard] public TextureSlice resolve(TextureDesc desc)
		{
			TextureSlice ret = this;

			Runtime.Assert(mipLevel < desc.mipLevels);

			if (width == uint32(-1))
				ret.width = (desc.width >> mipLevel);

			if (height == uint32(-1))
				ret.height = (desc.height >> mipLevel);

			if (depth == uint32(-1))
			{
				if (desc.dimension == TextureDimension.Texture3D)
					ret.depth = (desc.depth >> mipLevel);
				else
					ret.depth = 1;
			}

			return ret;
		}

		public ref TextureSlice setOrigin(uint32 vx = 0, uint32 vy = 0, uint32 vz = 0) mut { x = vx; y = vy; z = vz; return ref this; }
		public ref TextureSlice setWidth(uint32 value) mut { width = value; return ref this; }
		public ref TextureSlice setHeight(uint32 value) mut { height = value; return ref this; }
		public ref TextureSlice setDepth(uint32 value) mut { depth = value; return ref this; }
		public ref TextureSlice setSize(uint32 vx = uint32(-1), uint32 vy = uint32(-1), uint32 vz = uint32(-1)) mut { width = vx; height = vy; depth = vz; return ref this; }
		public ref TextureSlice setMipLevel(MipLevel level) mut { mipLevel = level; return ref this; }
		public ref TextureSlice setArraySlice(ArraySlice slice) mut { arraySlice = slice; return ref this; }
	}

	struct TextureSubresourceSet : IHashable
	{
		public const MipLevel AllMipLevels = MipLevel(-1);
		public const ArraySlice AllArraySlices = ArraySlice(-1);

		public MipLevel baseMipLevel = 0;
		public MipLevel numMipLevels = 1;
		public ArraySlice baseArraySlice = 0;
		public ArraySlice numArraySlices = 1;

		public this() { }

		public this(TextureSubresourceSet other)
		{
			baseMipLevel = other.baseMipLevel;
			numMipLevels = other.numMipLevels;
			baseArraySlice = other.baseArraySlice;
			numArraySlices = other.numArraySlices;
		}

		public this(MipLevel _baseMipLevel, MipLevel _numMipLevels, ArraySlice _baseArraySlice, ArraySlice _numArraySlices)
		{
			baseMipLevel = (_baseMipLevel);
			numMipLevels = (_numMipLevels);
			baseArraySlice = (_baseArraySlice);
			numArraySlices = (_numArraySlices);
		}

		[NoDiscard] public TextureSubresourceSet resolve(TextureDesc desc, bool singleMipLevel)
		{
			TextureSubresourceSet ret = .();
			ret.baseMipLevel = baseMipLevel;

			if (singleMipLevel)
			{
				ret.numMipLevels = 1;
			}
			else
			{
				uint32 lastMipLevelPlusOne = Math.Min(baseMipLevel + numMipLevels, desc.mipLevels);
				ret.numMipLevels = MipLevel(Math.Max(0, lastMipLevelPlusOne - baseMipLevel));
			}

			switch (desc.dimension)
			{
			case TextureDimension.Texture1DArray: fallthrough;
			case TextureDimension.Texture2DArray: fallthrough;
			case TextureDimension.TextureCube: fallthrough;
			case TextureDimension.TextureCubeArray: fallthrough;
			case TextureDimension.Texture2DMSArray:
				{
					ret.baseArraySlice = baseArraySlice;
					uint32 lastArraySlicePlusOne = Math.Min(baseArraySlice + numArraySlices, desc.arraySize);
					ret.numArraySlices = ArraySlice(Math.Max(0, lastArraySlicePlusOne - baseArraySlice));
					break;
				}
			default:
				ret.baseArraySlice = 0;
				ret.numArraySlices = 1;
				break;
			}

			return ret;
		}

		[NoDiscard] public bool isEntireTexture(TextureDesc desc)
		{
			if (baseMipLevel > 0 || baseMipLevel + numMipLevels < desc.mipLevels)
				return false;

			switch (desc.dimension)
			{
			case TextureDimension.Texture1DArray: fallthrough;
			case TextureDimension.Texture2DArray: fallthrough;
			case TextureDimension.TextureCube: fallthrough;
			case TextureDimension.TextureCubeArray: fallthrough;
			case TextureDimension.Texture2DMSArray:
				if (baseArraySlice > 0u || baseArraySlice + numArraySlices < desc.arraySize)
					return false;
				fallthrough;
			default:
				return true;
			}
		}

		public static bool operator ==(TextureSubresourceSet a, TextureSubresourceSet other)
		{
			return a.baseMipLevel == other.baseMipLevel &&
				a.numMipLevels == other.numMipLevels &&
				a.baseArraySlice == other.baseArraySlice &&
				a.numArraySlices == other.numArraySlices;
		}

		public static bool operator !=(TextureSubresourceSet a, TextureSubresourceSet other) { return !(a == other); }

		public ref TextureSubresourceSet setBaseMipLevel(MipLevel value) mut { baseMipLevel = value; return ref this; }
		public ref TextureSubresourceSet setNumMipLevels(MipLevel value) mut { numMipLevels = value; return ref this; }
		public ref TextureSubresourceSet setMipLevels(MipLevel @base, MipLevel num) mut { baseMipLevel = @base; numMipLevels = num; return ref this; }
		public ref TextureSubresourceSet setBaseArraySlice(ArraySlice value) mut { baseArraySlice = value; return ref this; }
		public ref TextureSubresourceSet setNumArraySlices(ArraySlice value) mut { numArraySlices = value; return ref this; }
		public ref TextureSubresourceSet setArraySlices(ArraySlice @base, ArraySlice num) mut { baseArraySlice = @base; numArraySlices = num; return ref this; }

		// see the bottom of this file for a specialization of std::hash<TextureSubresourceSet>
		public int GetHashCode()
		{
			int hash = 0;
			nvrhi.hash_combine(ref hash, baseMipLevel);
			nvrhi.hash_combine(ref hash, numMipLevels);
			nvrhi.hash_combine(ref hash, baseArraySlice);
			nvrhi.hash_combine(ref hash, numArraySlices);
			return hash;
		}
	}

	public static
	{
		public const TextureSubresourceSet AllSubresources = TextureSubresourceSet(0, TextureSubresourceSet.AllMipLevels, 0, TextureSubresourceSet.AllArraySlices);
	}

	//////////////////////////////////////////////////////////////////////////
	// Input Layout
	//////////////////////////////////////////////////////////////////////////

	struct VertexAttributeDesc
	{
		public String name;
		public Format format = Format.UNKNOWN;
		public uint32 arraySize = 1;
		public uint32 bufferIndex = 0;
		public uint32 offset = 0;
		// note: for most APIs, all strides for a given bufferIndex must be identical
		public uint32 elementStride = 0;
		public bool isInstanced = false;

		public ref VertexAttributeDesc setName(String value) mut { name = value; return ref this; }
		public ref VertexAttributeDesc setFormat(Format value) mut { format = value; return ref this; }
		public ref VertexAttributeDesc setArraySize(uint32 value) mut { arraySize = value; return ref this; }
		public ref VertexAttributeDesc setBufferIndex(uint32 value) mut { bufferIndex = value; return ref this; }
		public ref VertexAttributeDesc setOffset(uint32 value) mut { offset = value; return ref this; }
		public ref VertexAttributeDesc setElementStride(uint32 value) mut { elementStride = value; return ref this; }
		public ref VertexAttributeDesc setIsInstanced(bool value) mut { isInstanced = value; return ref this; }
	}

	//////////////////////////////////////////////////////////////////////////
	// Buffer
	//////////////////////////////////////////////////////////////////////////

	struct BufferDesc
	{
		public uint64 byteSize = 0;
		public uint32 structStride = 0; // if non-zero it's structured
		public uint32 maxVersions = 0; // only valid and required to be nonzero for volatile buffers on Vulkan
		public String debugName;
		public Format format = Format.UNKNOWN; // for typed buffer views
		public bool canHaveUAVs = false;
		public bool canHaveTypedViews = false;
		public bool canHaveRawViews = false;
		public bool isVertexBuffer = false;
		public bool isIndexBuffer = false;
		public bool isConstantBuffer = false;
		public bool isDrawIndirectArgs = false;
		public bool isAccelStructBuildInput = false;
		public bool isAccelStructStorage = false;

		// A dynamic/upload buffer whose contents only live in the current command list
		public bool isVolatile = false;

		// Indicates that the buffer is created with no backing memory,
		// and memory is bound to the texture later using bindBufferMemory.
		// On DX12, the buffer resource is created at the time of memory binding.
		public bool isVirtual = false;

		public ResourceStates initialState = ResourceStates.Common;

		// see TextureDesc::keepInitialState
		public bool keepInitialState = false;

		public CpuAccessMode cpuAccess = CpuAccessMode.None;

		public SharedResourceFlags sharedResourceFlags = SharedResourceFlags.None;

		public ref BufferDesc setByteSize(uint64 value) mut { byteSize = value; return ref this; }
		public ref BufferDesc setStructStride(uint32 value) mut { structStride = value; return ref this; }
		public ref BufferDesc setMaxVersions(uint32 value) mut { maxVersions = value; return ref this; }
		public ref BufferDesc setDebugName(String value) mut { debugName = value; return ref this; }
		public ref BufferDesc setFormat(Format value) mut { format = value; return ref this; }
		public ref BufferDesc setCanHaveUAVs(bool value) mut { canHaveUAVs = value; return ref this; }
		public ref BufferDesc setCanHaveTypedViews(bool value) mut { canHaveTypedViews = value; return ref this; }
		public ref BufferDesc setCanHaveRawViews(bool value) mut { canHaveRawViews = value; return ref this; }
		public ref BufferDesc setIsVertexBuffer(bool value) mut { isVertexBuffer = value; return ref this; }
		public ref BufferDesc setIsIndexBuffer(bool value) mut { isIndexBuffer = value; return ref this; }
		public ref BufferDesc setIsConstantBuffer(bool value) mut { isConstantBuffer = value; return ref this; }
		public ref BufferDesc setIsDrawIndirectArgs(bool value) mut { isDrawIndirectArgs = value; return ref this; }
		public ref BufferDesc setIsAccelStructBuildInput(bool value) mut { isAccelStructBuildInput = value; return ref this; }
		public ref BufferDesc setIsAccelStructStorage(bool value) mut { isAccelStructStorage = value; return ref this; }
		public ref BufferDesc setIsVolatile(bool value) mut { isVolatile = value; return ref this; }
		public ref BufferDesc setIsVirtual(bool value) mut { isVirtual = value; return ref this; }
		public ref BufferDesc setInitialState(ResourceStates value) mut { initialState = value; return ref this; }
		public ref BufferDesc setKeepInitialState(bool value) mut { keepInitialState = value; return ref this; }
		public ref BufferDesc setCpuAccess(CpuAccessMode value) mut { cpuAccess = value; return ref this; }
	}

	struct BufferRange : IHashable
	{
		public uint64 byteOffset = 0;
		public uint64 byteSize = 0;

		public this() { }

		public this(BufferRange other)
		{
			byteOffset = other.byteOffset;
			byteSize = other.byteSize;
		}

		public this(uint64 _byteOffset, uint64 _byteSize)
		{
			byteOffset = (_byteOffset);
			byteSize = (_byteSize);
		}

		[NoDiscard] public BufferRange resolve(BufferDesc desc)
		{
			BufferRange result = .();
			result.byteOffset = Math.Min(byteOffset, desc.byteSize);
			if (byteSize == 0)
				result.byteSize = desc.byteSize - result.byteOffset;
			else
				result.byteSize = Math.Min(byteSize, desc.byteSize - result.byteOffset);
			return result;
		}

		[NoDiscard] public bool isEntireBuffer(BufferDesc desc) { return (byteOffset == 0) && (byteSize == ~0uL || byteSize == desc.byteSize); }
		public static bool operator ==(BufferRange a, BufferRange other) { return a.byteOffset == other.byteOffset && a.byteSize == other.byteSize; }

		public ref BufferRange setByteOffset(uint64 value) mut { byteOffset = value; return ref this; }
		public ref BufferRange setByteSize(uint64 value) mut { byteSize = value; return ref this; }
		public int GetHashCode()
		{
			int hash = 0;
			nvrhi.hash_combine(ref hash, byteOffset);
			nvrhi.hash_combine(ref hash, byteSize);
			return hash;
		}
	}

	public static
	{
		public const BufferRange EntireBuffer = BufferRange(0, ~0uL);
	}

	//////////////////////////////////////////////////////////////////////////
	// Shader
	//////////////////////////////////////////////////////////////////////////

	// Shader type mask. The values match ones used in Vulkan.
	enum ShaderType : uint16
	{
		None            = 0x0000,

		Compute         = 0x0020,

		Vertex          = 0x0001,
		Hull            = 0x0002,
		Domain          = 0x0004,
		Geometry        = 0x0008,
		Pixel           = 0x0010,
		Amplification   = 0x0040,
		Mesh            = 0x0080,
		AllGraphics     = 0x00FE,

		RayGeneration   = 0x0100,
		AnyHit          = 0x0200,
		ClosestHit      = 0x0400,
		Miss            = 0x0800,
		Intersection    = 0x1000,
		Callable        = 0x2000,
		AllRayTracing   = 0x3F00,

		All             = 0x3FFF,
	}


	enum FastGeometryShaderFlags : uint8
	{
		ForceFastGS                      = 0x01,
		UseViewportMask                  = 0x02,
		OffsetTargetIndexByViewportIndex = 0x04,
		StrictApiOrder                   = 0x08
	}


	struct CustomSemantic
	{
		public enum CustomSemanticType
		{
			Undefined = 0,
			XRight = 1,
			ViewportMask = 2
		};

		public CustomSemanticType type = .Undefined;
		public String name;
	}

	struct ShaderDesc
	{
		public ShaderType shaderType = ShaderType.None;
		public String debugName = null;
		public String entryName = "main";

		public int32 hlslExtensionsUAV = -1;

		public bool useSpecificShaderExt = false;
		public uint32 numCustomSemantics = 0;
		public CustomSemantic* pCustomSemantics = null;

		public FastGeometryShaderFlags fastGSFlags = (FastGeometryShaderFlags)0;
		public uint32* pCoordinateSwizzling = null;

		public this() { }

		public this(ShaderType type)
		{
			shaderType = type;
		}
	}

	public struct ShaderSpecialization
	{
		public uint32 constantID = 0;
		[Union] public struct ShaderSpecializationValue
		{
			public uint32 u = 0;
			public int32 i;
			public float f;
		}

		public using public ShaderSpecializationValue value;

		public static ShaderSpecialization UInt32(uint32 constantID, uint32 u)
		{
			ShaderSpecialization s;
			s.constantID = constantID;
			s.value.u = u;
			return s;
		}

		public static ShaderSpecialization Int32(uint32 constantID, int32 i)
		{
			ShaderSpecialization s;
			s.constantID = constantID;
			s.value.i = i;
			return s;
		}

		public static ShaderSpecialization Float(uint32 constantID, float f)
		{
			ShaderSpecialization s;
			s.constantID = constantID;
			s.value.f = f;
			return s;
		}
	}

	//////////////////////////////////////////////////////////////////////////
	// Blend State
	//////////////////////////////////////////////////////////////////////////

	[AllowDuplicates]
	enum BlendFactor : uint8
	{
		Zero = 1,
		One = 2,
		SrcColor = 3,
		InvSrcColor = 4,
		SrcAlpha = 5,
		InvSrcAlpha = 6,
		DstAlpha  = 7,
		InvDstAlpha = 8,
		DstColor = 9,
		InvDstColor = 10,
		SrcAlphaSaturate = 11,
		ConstantColor = 14,
		InvConstantColor = 15,
		Src1Color = 16,
		InvSrc1Color = 17,
		Src1Alpha = 18,
		InvSrc1Alpha = 19,

		// Vulkan names
		OneMinusSrcColor = InvSrcColor,
		OneMinusSrcAlpha = InvSrcAlpha,
		OneMinusDstAlpha = InvDstAlpha,
		OneMinusDstColor = InvDstColor,
		OneMinusConstantColor = InvConstantColor,
		OneMinusSrc1Color = InvSrc1Color,
		OneMinusSrc1Alpha = InvSrc1Alpha,
	}

	enum BlendOp : uint8
	{
		Add = 1,
		Subrtact = 2,
		ReverseSubtract = 3,
		Min = 4,
		Max = 5
	}

	enum ColorMask : uint8
	{
		// These values are equal to their counterparts in DX11, DX12, and Vulkan.
		Red = 1,
		Green = 2,
		Blue = 4,
		Alpha = 8,
		All = 0xF
	}

	struct BlendState : IHashable
	{
		public struct RenderTarget : IHashable
		{
			public bool        blendEnable = false;
			public BlendFactor srcBlend = BlendFactor.One;
			public BlendFactor destBlend = BlendFactor.Zero;
			public BlendOp     blendOp = BlendOp.Add;
			public BlendFactor srcBlendAlpha = BlendFactor.One;
			public BlendFactor destBlendAlpha = BlendFactor.Zero;
			public BlendOp     blendOpAlpha = BlendOp.Add;
			public ColorMask   colorWriteMask = ColorMask.All;

			public ref RenderTarget setBlendEnable(bool enable) mut { blendEnable = enable; return ref this; }
			public ref RenderTarget enableBlend() mut { blendEnable = true; return ref this; }
			public ref RenderTarget disableBlend() mut { blendEnable = false; return ref this; }
			public ref RenderTarget setSrcBlend(BlendFactor value) mut { srcBlend = value; return ref this; }
			public ref RenderTarget setDestBlend(BlendFactor value) mut { destBlend = value; return ref this; }
			public ref RenderTarget setBlendOp(BlendOp value) mut { blendOp = value; return ref this; }
			public ref RenderTarget setSrcBlendAlpha(BlendFactor value) mut { srcBlendAlpha = value; return ref this; }
			public ref RenderTarget setDestBlendAlpha(BlendFactor value) mut { destBlendAlpha = value; return ref this; }
			public ref RenderTarget setBlendOpAlpha(BlendOp value) mut { blendOpAlpha = value; return ref this; }
			public ref RenderTarget setColorWriteMask(ColorMask value) mut { colorWriteMask = value; return ref this; }

			[NoDiscard] public bool usesConstantColor()
			{
				return srcBlend == BlendFactor.ConstantColor || srcBlend == BlendFactor.OneMinusConstantColor ||
					destBlend == BlendFactor.ConstantColor || destBlend == BlendFactor.OneMinusConstantColor ||
					srcBlendAlpha == BlendFactor.ConstantColor || srcBlendAlpha == BlendFactor.OneMinusConstantColor ||
					destBlendAlpha == BlendFactor.ConstantColor || destBlendAlpha == BlendFactor.OneMinusConstantColor;
			}

			public static bool operator ==(RenderTarget a, RenderTarget other)
			{
				return a.blendEnable == other.blendEnable
					&& a.srcBlend == other.srcBlend
					&& a.destBlend == other.destBlend
					&& a.blendOp == other.blendOp
					&& a.srcBlendAlpha == other.srcBlendAlpha
					&& a.destBlendAlpha == other.destBlendAlpha
					&& a.blendOpAlpha == other.blendOpAlpha
					&& a.colorWriteMask == other.colorWriteMask;
			}

			public static bool operator !=(RenderTarget a, RenderTarget other)
			{
				return !(a == other);
			}
			public int GetHashCode()
			{
				int hash = 0;
				nvrhi.hash_combine(ref hash, blendEnable);
				nvrhi.hash_combine(ref hash, srcBlend);
				nvrhi.hash_combine(ref hash, destBlend);
				nvrhi.hash_combine(ref hash, blendOp);
				nvrhi.hash_combine(ref hash, srcBlendAlpha);
				nvrhi.hash_combine(ref hash, destBlendAlpha);
				nvrhi.hash_combine(ref hash, blendOpAlpha);
				nvrhi.hash_combine(ref hash, colorWriteMask);
				return hash;
			}
		};

		public RenderTarget[c_MaxRenderTargets] targets = .InitAll;
		public bool alphaToCoverageEnable = false;

		public ref BlendState setRenderTarget(uint32 index, RenderTarget target) mut { targets[index] = target; return ref this; }
		public ref BlendState setAlphaToCoverageEnable(bool enable) mut { alphaToCoverageEnable = enable; return ref this; }
		public ref BlendState enableAlphaToCoverage() mut { alphaToCoverageEnable = true; return ref this; }
		public ref BlendState disableAlphaToCoverage() mut { alphaToCoverageEnable = false; return ref this; }

		[NoDiscard] public bool usesConstantColor(uint32 numTargets)
		{
			for (uint32 rt = 0; rt < numTargets; rt++)
			{
				if (targets[rt].usesConstantColor())
					return true;
			}

			return false;
		}

		public static bool operator ==(BlendState a, BlendState other)
		{
			if (a.alphaToCoverageEnable != other.alphaToCoverageEnable)
				return false;

			for (uint32 i = 0; i < c_MaxRenderTargets; ++i)
			{
				if (a.targets[i] != other.targets[i])
					return false;
			}

			return true;
		}

		public static bool operator !=(BlendState a, BlendState other)
		{
			return !(a == other);
		}
		public int GetHashCode()
		{
			int hash = 0;
			nvrhi.hash_combine(ref hash, alphaToCoverageEnable);
			for (readonly ref RenderTarget target in ref targets)
				nvrhi.hash_combine(ref hash, target);
			return hash;
		}
	}

	//////////////////////////////////////////////////////////////////////////
	// Raster State
	//////////////////////////////////////////////////////////////////////////

	[AllowDuplicates]
	enum RasterFillMode : uint8
	{
		Solid,
		Wireframe,

		// Vulkan names
		Fill = Solid,
		Line = Wireframe
	}

	enum RasterCullMode : uint8
	{
		Back,
		Front,
		None
	}

	struct RasterState
	{
		public RasterFillMode fillMode = RasterFillMode.Solid;
		public RasterCullMode cullMode = RasterCullMode.Back;
		public bool frontCounterClockwise = false;
		public bool depthClipEnable = false;
		public bool scissorEnable = false;
		public bool multisampleEnable = false;
		public bool antialiasedLineEnable = false;
		public int32 depthBias = 0;
		public float depthBiasClamp = 0.f;
		public float slopeScaledDepthBias = 0.f;

		// Extended rasterizer state supported by Maxwell
		// In D3D11, use NvAPI_D3D11_CreateRasterizerState to create such rasterizer state.
		public uint8 forcedSampleCount = 0;
		public bool programmableSamplePositionsEnable = false;
		public bool conservativeRasterEnable = false;
		public bool quadFillEnable = false;
		public char8[16] samplePositionsX = .();
		public char8[16] samplePositionsY = .();

		public ref RasterState setFillMode(RasterFillMode value) mut { fillMode = value; return ref this; }
		public ref RasterState setFillSolid()  mut { fillMode = RasterFillMode.Solid; return ref this; }
		public ref RasterState setFillWireframe() mut  { fillMode = RasterFillMode.Wireframe; return ref this; }
		public ref RasterState setCullMode(RasterCullMode value) mut { cullMode = value; return ref this; }
		public ref RasterState setCullBack()  mut { cullMode = RasterCullMode.Back; return ref this; }
		public ref RasterState setCullFront() mut  { cullMode = RasterCullMode.Front; return ref this; }
		public ref RasterState setCullNone()  mut { cullMode = RasterCullMode.None; return ref this; }
		public ref RasterState setFrontCounterClockwise(bool value) mut { frontCounterClockwise = value; return ref this; }
		public ref RasterState setDepthClipEnable(bool value) mut { depthClipEnable = value; return ref this; }
		public ref RasterState enableDepthClip()  mut { depthClipEnable = true; return ref this; }
		public ref RasterState disableDepthClip() mut  { depthClipEnable = false; return ref this; }
		public ref RasterState setScissorEnable(bool value) mut { scissorEnable = value; return ref this; }
		public ref RasterState enableScissor()  mut { scissorEnable = true; return ref this; }
		public ref RasterState disableScissor() mut  { scissorEnable = false; return ref this; }
		public ref RasterState setMultisampleEnable(bool value) mut { multisampleEnable = value; return ref this; }
		public ref RasterState enableMultisample() mut  { multisampleEnable = true; return ref this; }
		public ref RasterState disableMultisample() mut  { multisampleEnable = false; return ref this; }
		public ref RasterState setAntialiasedLineEnable(bool value) mut { antialiasedLineEnable = value; return ref this; }
		public ref RasterState enableAntialiasedLine() mut  { antialiasedLineEnable = true; return ref this; }
		public ref RasterState disableAntialiasedLine() mut  { antialiasedLineEnable = false; return ref this; }
		public ref RasterState setDepthBias(int32 value) mut { depthBias = value; return ref this; }
		public ref RasterState setDepthBiasClamp(float value) mut { depthBiasClamp = value; return ref this; }
		public ref RasterState setSlopeScaleDepthBias(float value) mut { slopeScaledDepthBias = value; return ref this; }
		public ref RasterState setForcedSampleCount(uint8 value) mut { forcedSampleCount = value; return ref this; }
		public ref RasterState setProgrammableSamplePositionsEnable(bool value) mut { programmableSamplePositionsEnable = value; return ref this; }
		public ref RasterState enableProgrammableSamplePositions()  mut { programmableSamplePositionsEnable = true; return ref this; }
		public ref RasterState disableProgrammableSamplePositions() mut  { programmableSamplePositionsEnable = false; return ref this; }
		public ref RasterState setConservativeRasterEnable(bool value) mut { conservativeRasterEnable = value; return ref this; }
		public ref RasterState enableConservativeRaster()  mut { conservativeRasterEnable = true; return ref this; }
		public ref RasterState disableConservativeRaster()  mut { conservativeRasterEnable = false; return ref this; }
		public ref RasterState setQuadFillEnable(bool value) mut { quadFillEnable = value; return ref this; }
		public ref RasterState enableQuadFill()  mut { quadFillEnable = true; return ref this; }
		public ref RasterState disableQuadFill() mut  { quadFillEnable = false; return ref this; }
		public ref RasterState setSamplePositions(char8* x, char8* y, int32 count) mut  { for (int32 i = 0; i < count; i++) { samplePositionsX[i] = x[i]; samplePositionsY[i] = y[i]; } return ref this; }
	}

	//////////////////////////////////////////////////////////////////////////
	// Depth Stencil State
	//////////////////////////////////////////////////////////////////////////

	enum StencilOp : uint8
	{
		Keep = 1,
		Zero = 2,
		Replace = 3,
		IncrementAndClamp = 4,
		DecrementAndClamp = 5,
		Invert = 6,
		IncrementAndWrap = 7,
		DecrementAndWrap = 8
	}

	enum ComparisonFunc : uint8
	{
		Never = 1,
		Less = 2,
		Equal = 3,
		LessOrEqual = 4,
		Greater = 5,
		NotEqual = 6,
		GreaterOrEqual = 7,
		Always = 8
	}

	struct DepthStencilState
	{
		public struct StencilOpDesc
		{
			public StencilOp failOp = StencilOp.Keep;
			public StencilOp depthFailOp = StencilOp.Keep;
			public StencilOp passOp = StencilOp.Keep;
			public ComparisonFunc stencilFunc = ComparisonFunc.Always;

			public ref StencilOpDesc setFailOp(StencilOp value) mut { failOp = value; return ref this; }
			public ref StencilOpDesc setDepthFailOp(StencilOp value) mut { depthFailOp = value; return ref this; }
			public ref StencilOpDesc setPassOp(StencilOp value) mut { passOp = value; return ref this; }
			public ref StencilOpDesc setStencilFunc(ComparisonFunc value) mut { stencilFunc = value; return ref this; }
		}

		public bool            depthTestEnable = true;
		public bool            depthWriteEnable = true;
		public ComparisonFunc  depthFunc = ComparisonFunc.Less;
		public bool            stencilEnable = false;
		public uint8         stencilReadMask = 0xff;
		public uint8         stencilWriteMask = 0xff;
		public uint8         stencilRefValue = 0;
		public StencilOpDesc   frontFaceStencil = .();
		public StencilOpDesc   backFaceStencil = .();

		public ref DepthStencilState setDepthTestEnable(bool value) mut { depthTestEnable = value; return ref this; }
		public ref DepthStencilState enableDepthTest() mut { depthTestEnable = true; return ref this; }
		public ref DepthStencilState disableDepthTest()  mut { depthTestEnable = false; return ref this; }
		public ref DepthStencilState setDepthWriteEnable(bool value) mut { depthWriteEnable = value; return ref this; }
		public ref DepthStencilState enableDepthWrite() mut  { depthWriteEnable = true; return ref this; }
		public ref DepthStencilState disableDepthWrite() mut  { depthWriteEnable = false; return ref this; }
		public ref DepthStencilState setDepthFunc(ComparisonFunc value) mut { depthFunc = value; return ref this; }
		public ref DepthStencilState setStencilEnable(bool value) mut { stencilEnable = value; return ref this; }
		public ref DepthStencilState enableStencil() mut  { stencilEnable = true; return ref this; }
		public ref DepthStencilState disableStencil()  mut { stencilEnable = false; return ref this; }
		public ref DepthStencilState setStencilReadMask(uint8 value) mut { stencilReadMask = value; return ref this; }
		public ref DepthStencilState setStencilWriteMask(uint8 value) mut { stencilWriteMask = value; return ref this; }
		public ref DepthStencilState setStencilRefValue(uint8 value) mut { stencilRefValue = value; return ref this; }
		public ref DepthStencilState setFrontFaceStencil(StencilOpDesc value) mut { frontFaceStencil = value; return ref this; }
		public ref DepthStencilState setBackFaceStencil(StencilOpDesc value) mut { backFaceStencil = value; return ref this; }
	}

	//////////////////////////////////////////////////////////////////////////
	// Viewport State
	//////////////////////////////////////////////////////////////////////////

	struct ViewportState
	{
		//These are in pixels
		// note: you can only set each of these either in the PSO or per draw call in DrawArguments
		// it is not legal to have the same state set in both the PSO and DrawArguments
		// leaving these vectors empty means no state is set
		public StaticVector<Viewport, const c_MaxViewports> viewports = .();
		public StaticVector<Rect, const c_MaxViewports> scissorRects = .();

		public ref ViewportState addViewport(Viewport v) mut { viewports.PushBack(v); return ref this; }
		public ref ViewportState addScissorRect(Rect r) mut { scissorRects.PushBack(r); return ref this; }
		public ref ViewportState addViewportAndScissorRect(Viewport v) mut { return ref addViewport(v).addScissorRect(Rect(v)); }
	}

	//////////////////////////////////////////////////////////////////////////
	// Sampler
	//////////////////////////////////////////////////////////////////////////

	[AllowDuplicates]
	enum SamplerAddressMode : uint8
	{
		// D3D names
		Clamp,
		Wrap,
		Border,
		Mirror,
		MirrorOnce,

		// Vulkan names
		ClampToEdge = Clamp,
		Repeat = Wrap,
		ClampToBorder = Border,
		MirroredRepeat = Mirror,
		MirrorClampToEdge = MirrorOnce
	}

	enum SamplerReductionType : uint8
	{
		Standard,
		Comparison,
		Minimum,
		Maximum
	}

	struct SamplerDesc
	{
		public Color borderColor = .(1.f);
		public float maxAnisotropy = 1.f;
		public float mipBias = 0.f;

		public bool minFilter = true;
		public bool magFilter = true;
		public bool mipFilter = true;
		public SamplerAddressMode addressU = SamplerAddressMode.Clamp;
		public SamplerAddressMode addressV = SamplerAddressMode.Clamp;
		public SamplerAddressMode addressW = SamplerAddressMode.Clamp;
		public SamplerReductionType reductionType = SamplerReductionType.Standard;

		public ref SamplerDesc setBorderColor(Color color) mut { borderColor = color; return ref this; }
		public ref SamplerDesc setMaxAnisotropy(float value) mut { maxAnisotropy = value; return ref this; }
		public ref SamplerDesc setMipBias(float value) mut { mipBias = value; return ref this; }
		public ref SamplerDesc setMinFilter(bool enable) mut { minFilter = enable; return ref this; }
		public ref SamplerDesc setMagFilter(bool enable) mut { magFilter = enable; return ref this; }
		public ref SamplerDesc setMipFilter(bool enable) mut { mipFilter = enable; return ref this; }
		public ref SamplerDesc setAllFilters(bool enable) mut { minFilter = magFilter = mipFilter = enable; return ref this; }
		public ref SamplerDesc setAddressU(SamplerAddressMode mode) mut { addressU = mode; return ref this; }
		public ref SamplerDesc setAddressV(SamplerAddressMode mode) mut { addressV = mode; return ref this; }
		public ref SamplerDesc setAddressW(SamplerAddressMode mode) mut { addressW = mode; return ref this; }
		public ref SamplerDesc setAllAddressModes(SamplerAddressMode mode) mut { addressU = addressV = addressW = mode; return ref this; }
		public ref SamplerDesc setReductionType(SamplerReductionType type) mut { reductionType = type; return ref this; }
	}

	//////////////////////////////////////////////////////////////////////////
	// Framebuffer
	//////////////////////////////////////////////////////////////////////////

	struct FramebufferAttachment
	{
		public ITexture texture = null;
		public TextureSubresourceSet subresources = TextureSubresourceSet(0, 1, 0, 1);
		public Format format = Format.UNKNOWN;
		public bool isReadOnly = false;

		public ref FramebufferAttachment setTexture(ITexture t) mut { texture = t; return ref this; }
		public ref FramebufferAttachment setSubresources(TextureSubresourceSet value) mut { subresources = value; return ref this; }
		public ref FramebufferAttachment setArraySlice(ArraySlice index) mut { subresources.baseArraySlice = index; subresources.numArraySlices = 1; return ref this; }
		public ref FramebufferAttachment setArraySliceRange(ArraySlice index, ArraySlice count) mut { subresources.baseArraySlice = index; subresources.numArraySlices = count; return ref this; }
		public ref FramebufferAttachment setMipLevel(MipLevel level) mut { subresources.baseMipLevel = level; subresources.numMipLevels = 1; return ref this; }
		public ref FramebufferAttachment setFormat(Format f) mut { format = f; return ref this; }
		public ref FramebufferAttachment setReadOnly(bool ro) mut { isReadOnly = ro; return ref this; }

		[NoDiscard] public bool valid()  { return texture != null; }
	}

	struct FramebufferDesc
	{
		public StaticVector<FramebufferAttachment, const c_MaxRenderTargets> colorAttachments = .();
		public FramebufferAttachment depthAttachment = .();
		public FramebufferAttachment shadingRateAttachment = .();

		public ref FramebufferDesc addColorAttachment(FramebufferAttachment a) mut { colorAttachments.PushBack(a); return ref this; }
		public ref FramebufferDesc addColorAttachment(ITexture texture) mut { colorAttachments.PushBack(FramebufferAttachment().setTexture(texture)); return ref this; }
		public ref FramebufferDesc addColorAttachment(ITexture texture, TextureSubresourceSet subresources) mut { colorAttachments.PushBack(FramebufferAttachment().setTexture(texture).setSubresources(subresources)); return ref this; }
		public ref FramebufferDesc setDepthAttachment(FramebufferAttachment d) mut { depthAttachment = d; return ref this; }
		public ref FramebufferDesc setDepthAttachment(ITexture texture) mut { depthAttachment = FramebufferAttachment().setTexture(texture); return ref this; }
		public ref FramebufferDesc setDepthAttachment(ITexture texture, TextureSubresourceSet subresources) mut { depthAttachment = FramebufferAttachment().setTexture(texture).setSubresources(subresources); return ref this; }
		public ref FramebufferDesc setShadingRateAttachment(FramebufferAttachment d) mut { shadingRateAttachment = d; return ref this; }
		public ref FramebufferDesc setShadingRateAttachment(ITexture texture) mut { shadingRateAttachment = FramebufferAttachment().setTexture(texture); return ref this; }
		public ref FramebufferDesc setShadingRateAttachment(ITexture texture, TextureSubresourceSet subresources) mut { shadingRateAttachment = FramebufferAttachment().setTexture(texture).setSubresources(subresources); return ref this; }
	}

	struct FramebufferInfo : IHashable
	{
		public StaticVector<Format, const c_MaxRenderTargets> colorFormats = .();
		public Format depthFormat = Format.UNKNOWN;
		public uint32 width = 0;
		public uint32 height = 0;
		public uint32 sampleCount = 1;
		public uint32 sampleQuality = 0;

		public this() { }
		public this(FramebufferDesc desc)
		{
			for (int i = 0; i < desc.colorAttachments.Count; i++)
			{
				readonly /*ref*/ FramebufferAttachment attachment = /*ref*/ desc.colorAttachments[i];
				colorFormats.PushBack(attachment.format == Format.UNKNOWN && attachment.texture != null ? attachment.texture.getDesc().format : attachment.format);
			}

			if (desc.depthAttachment.valid())
			{
				readonly TextureDesc textureDesc = desc.depthAttachment.texture.getDesc();
				depthFormat = textureDesc.format;
				width = textureDesc.width >> desc.depthAttachment.subresources.baseMipLevel;
				height = textureDesc.height >> desc.depthAttachment.subresources.baseMipLevel;
				sampleCount = textureDesc.sampleCount;
				sampleQuality = textureDesc.sampleQuality;
			}
			else if (!desc.colorAttachments.IsEmpty && desc.colorAttachments[0].valid())
			{
				readonly TextureDesc textureDesc = desc.colorAttachments[0].texture.getDesc();
				width = textureDesc.width >> desc.colorAttachments[0].subresources.baseMipLevel;
				height = textureDesc.height >> desc.colorAttachments[0].subresources.baseMipLevel;
				sampleCount = textureDesc.sampleCount;
				sampleQuality = textureDesc.sampleQuality;
			}
		}

		public static bool operator ==(FramebufferInfo a, FramebufferInfo other)
		{
			return formatsEqual(a.colorFormats, other.colorFormats)
				&& a.depthFormat == other.depthFormat
				&& a.width == other.width
				&& a.height == other.height
				&& a.sampleCount == other.sampleCount
				&& a.sampleQuality == other.sampleQuality;
		}
		public static bool operator !=(FramebufferInfo a, FramebufferInfo other) { return !(a == other); }

		[NoDiscard] public Viewport getViewport(float minZ = 0.f, float maxZ = 1.f)
		{
			return Viewport(0.f, float(width), 0.f, float(height), minZ, maxZ);
		}

		private static bool formatsEqual(StaticVector<Format, const c_MaxRenderTargets> a, StaticVector<Format, const c_MaxRenderTargets> b)
		{
			if (a.Count != b.Count) return false;
			for (int i = 0; i < a.Count; i++) if (a[i] != b[i]) return false;
			return true;
		}
		public int GetHashCode()
		{
			int hash = 0;
			for (var format in colorFormats)
				nvrhi.hash_combine(ref hash, format);
			nvrhi.hash_combine(ref hash, depthFormat);
			nvrhi.hash_combine(ref hash, width);
			nvrhi.hash_combine(ref hash, height);
			nvrhi.hash_combine(ref hash, sampleCount);
			nvrhi.hash_combine(ref hash, sampleQuality);
			return hash;
		}
	}


	//////////////////////////////////////////////////////////////////////////
	// Binding Layouts
	//////////////////////////////////////////////////////////////////////////

	// identifies the underlying resource type in a binding
	enum ResourceType : uint8
	{
		None,
		Texture_SRV,
		Texture_UAV,
		TypedBuffer_SRV,
		TypedBuffer_UAV,
		StructuredBuffer_SRV,
		StructuredBuffer_UAV,
		RawBuffer_SRV,
		RawBuffer_UAV,
		ConstantBuffer,
		VolatileConstantBuffer,
		Sampler,
		RayTracingAccelStruct,
		PushConstants,

		Count
	}

	struct BindingLayoutItem
	{
		public uint32 slot;

		public ResourceType type = .None; // : 8;
		public uint8 unused; // : 8;
		public uint16 size; // : 16;

		public static bool operator ==(BindingLayoutItem a, BindingLayoutItem b)
		{
			return a.slot == b.slot
				&& a.type == b.type
				&& a.size == b.size;
		}

		public static bool operator !=(BindingLayoutItem a, BindingLayoutItem b)  { return !(a == b); }

		// Helper functions for strongly typed initialization
		[OnCompile(.TypeInit), Comptime]
		public static void CodeGen()
		{
			String[?] typeNames = .(
				"Texture_SRV",
				"Texture_UAV",
				"TypedBuffer_SRV",
				"TypedBuffer_UAV",
				"StructuredBuffer_SRV",
				"StructuredBuffer_UAV",
				"RawBuffer_SRV",
				"RawBuffer_UAV",
				"ConstantBuffer",
				"VolatileConstantBuffer",
				"Sampler",
				"RayTracingAccelStruct");

			for (var typeName in typeNames)
			{
				Compiler.EmitTypeBody(typeof(Self), scope $"""
				public static BindingLayoutItem {typeName}(uint32 slot)
				{{
					BindingLayoutItem result = .();
					result.slot = slot;
					result.type = ResourceType.{typeName};
					return result;
				}}

				""");
			}
		}

		public static BindingLayoutItem PushConstants(uint32 slot, int size)
		{
			BindingLayoutItem result = .();
			result.slot = slot;
			result.type = ResourceType.PushConstants;
			result.size = uint16(size);
			return result;
		}
	}

	public static
	{
		public static void Assert()
		{
	// verify the packing of BindingLayoutItem for good alignment
			Compiler.Assert(sizeof(BindingLayoutItem) == 8, "sizeof(BindingLayoutItem) is supposed to be 8 bytes");
		}
	}

	typealias BindingLayoutItemArray = StaticVector<BindingLayoutItem, const c_MaxBindingsPerLayout>;

	// Describes compile-time settings for HLSL -> SPIR-V register allocation.
	// The default values match the offsets used by the NVRHI shaderCompiler tool.
	struct VulkanBindingOffsets
	{
		public uint32 shaderResource = 0;
		public uint32 sampler = 128;
		public uint32 constantBuffer = 256;
		public uint32 unorderedAccess = 384;

		public ref VulkanBindingOffsets setShaderResourceOffset(uint32 value) mut { shaderResource = value; return ref this; }
		public ref VulkanBindingOffsets setSamplerOffset(uint32 value) mut { sampler = value; return ref this; }
		public ref VulkanBindingOffsets setConstantBufferOffset(uint32 value) mut { constantBuffer = value; return ref this; }
		public ref VulkanBindingOffsets setUnorderedAccessViewOffset(uint32 value) mut { unorderedAccess = value; return ref this; }
	}

	struct BindingLayoutDesc
	{
		public ShaderType visibility = ShaderType.None;
		public uint32 registerSpace = 0;
		public BindingLayoutItemArray bindings;
		public VulkanBindingOffsets bindingOffsets;

		public ref BindingLayoutDesc setVisibility(ShaderType value) mut { visibility = value; return ref this; }
		public ref BindingLayoutDesc setRegisterSpace(uint32 value) mut { registerSpace = value; return ref this; }
		public ref BindingLayoutDesc addItem(BindingLayoutItem value) mut { bindings.PushBack(value); return ref this; }
		public ref BindingLayoutDesc setBindingOffsets(VulkanBindingOffsets value) mut { bindingOffsets = value; return ref this; }
	}

	// Bindless layouts allow applications to attach a descriptor table to an unbounded
	// resource array in the shader. The size of the array is not known ahead of time.
	// The same table can be bound to multiple register spaces on DX12, in order to 
	// access different types of resources stored in the table through different arrays.
	// The `registerSpaces` vector specifies which spaces will the table be bound to,
	// with the table type (SRV or UAV) derived from the resource type assigned to each space.
	struct BindlessLayoutDesc
	{
		public ShaderType visibility = ShaderType.None;
		public uint32 firstSlot = 0;
		public uint32 maxCapacity = 0;
		public StaticVector<BindingLayoutItem, 16> registerSpaces;

		public ref BindlessLayoutDesc setVisibility(ShaderType value) mut { visibility = value; return ref this; }
		public ref BindlessLayoutDesc setFirstSlot(uint32 value) mut { firstSlot = value; return ref this; }
		public ref BindlessLayoutDesc setMaxCapacity(uint32 value) mut { maxCapacity = value; return ref this; }
		public ref BindlessLayoutDesc addRegisterSpace(BindingLayoutItem value) mut { registerSpaces.PushBack(value); return ref this; }
	}

	//////////////////////////////////////////////////////////////////////////
	// Binding Sets
	//////////////////////////////////////////////////////////////////////////
	struct BindingSetItem : IHashable
	{
		public IResource resourceHandle = null;

		public uint32 slot = 0;

		public ResourceType type           = .None; //: 8;
		public TextureDimension dimension  = .Unknown; //: 8; // valid for Texture_SRV, Texture_UAV
		public Format format               = .UNKNOWN; //: 8; // valid for Texture_SRV, Texture_UAV, Buffer_SRV, Buffer_UAV
		public uint8 unused                = 0; //: 8;

		[Union] struct Data
		{
			public TextureSubresourceSet subresources = .(); // valid for Texture_SRV, Texture_UAV
			public BufferRange range = .(); // valid for Buffer_SRV, Buffer_UAV, ConstantBuffer
			public uint64[2] rawData;
		}
		public using private Data _data = .();

		private static void Asserts()
		{
		// verify that the `subresources` and `range` have the same size and are covered by `rawData`
			Compiler.Assert(sizeof(TextureSubresourceSet) == 16, "sizeof(TextureSubresourceSet) is supposed to be 16 bytes");
			Compiler.Assert(sizeof(BufferRange) == 16, "sizeof(BufferRange) is supposed to be 16 bytes");
		}

		public static bool operator ==(BindingSetItem a, BindingSetItem b)
		{
			return a.resourceHandle == b.resourceHandle
				&& a.slot == b.slot
				&& a.type == b.type
				&& a.dimension == b.dimension
				&& a.format == b.format
				&& a.rawData[0] == b.rawData[0]
				&& a.rawData[1] == b.rawData[1];
		}

		public  static bool operator !=(BindingSetItem a, BindingSetItem b)
		{
			return !(a == b);
		}

		// Default constructor that doesn't initialize anything for performance:
		// BindingSetItem's are stored in large statically sized arrays.
		public this() { }

		// Helper functions for strongly typed initialization

		public static BindingSetItem None(uint32 slot = 0)
		{
			BindingSetItem result = .();
			result.slot = slot;
			result.type = ResourceType.None;
			result.resourceHandle = null;
			result.format = Format.UNKNOWN;
			result.dimension = TextureDimension.Unknown;
			result.rawData[0] = 0;
			result.rawData[1] = 0;
			result.unused = 0;
			return result;
		}

		public static BindingSetItem Texture_SRV(uint32 slot, ITexture texture, Format format = Format.UNKNOWN,
			TextureSubresourceSet subresources = AllSubresources, TextureDimension dimension = TextureDimension.Unknown)
		{
			BindingSetItem result = .();
			result.slot = slot;
			result.type = ResourceType.Texture_SRV;
			result.resourceHandle = texture;
			result.format = format;
			result.dimension = dimension;
			result.subresources = subresources;
			result.unused = 0;
			return result;
		}

		public static BindingSetItem Texture_UAV(uint32 slot, ITexture texture, Format format = Format.UNKNOWN,
			TextureSubresourceSet subresources = TextureSubresourceSet(0, 1, 0, TextureSubresourceSet.AllArraySlices),
			TextureDimension dimension = TextureDimension.Unknown)
		{
			BindingSetItem result = .();
			result.slot = slot;
			result.type = ResourceType.Texture_UAV;
			result.resourceHandle = texture;
			result.format = format;
			result.dimension = dimension;
			result.subresources = subresources;
			result.unused = 0;
			return result;
		}

		public static BindingSetItem TypedBuffer_SRV(uint32 slot, IBuffer buffer, Format format = Format.UNKNOWN, BufferRange range = EntireBuffer)
		{
			BindingSetItem result = .();
			result.slot = slot;
			result.type = ResourceType.TypedBuffer_SRV;
			result.resourceHandle = buffer;
			result.format = format;
			result.dimension = TextureDimension.Unknown;
			result.range = range;
			result.unused = 0;
			return result;
		}

		public static BindingSetItem TypedBuffer_UAV(uint32 slot, IBuffer buffer, Format format = Format.UNKNOWN, BufferRange range = EntireBuffer)
		{
			BindingSetItem result = .();
			result.slot = slot;
			result.type = ResourceType.TypedBuffer_UAV;
			result.resourceHandle = buffer;
			result.format = format;
			result.dimension = TextureDimension.Unknown;
			result.range = range;
			result.unused = 0;
			return result;
		}

		public static BindingSetItem ConstantBuffer(uint32 slot, IBuffer buffer)
		{
			bool isVolatile = buffer != null && buffer.getDesc().isVolatile;

			BindingSetItem result = .();
			result.slot = slot;
			result.type = isVolatile ? ResourceType.VolatileConstantBuffer : ResourceType.ConstantBuffer;
			result.resourceHandle = buffer;
			result.format = Format.UNKNOWN;
			result.dimension = TextureDimension.Unknown;
			result.range = EntireBuffer;
			result.unused = 0;
			return result;
		}

		public static BindingSetItem Sampler(uint32 slot, ISampler sampler)
		{
			BindingSetItem result = .();
			result.slot = slot;
			result.type = ResourceType.Sampler;
			result.resourceHandle = sampler;
			result.format = Format.UNKNOWN;
			result.dimension = TextureDimension.Unknown;
			result.rawData[0] = 0;
			result.rawData[1] = 0;
			result.unused = 0;
			return result;
		}

		public static BindingSetItem RayTracingAccelStruct(uint32 slot, nvrhi.rt.IAccelStruct @as)
		{
			BindingSetItem result = .();
			result.slot = slot;
			result.type = ResourceType.RayTracingAccelStruct;
			result.resourceHandle = @as;
			result.format = Format.UNKNOWN;
			result.dimension = TextureDimension.Unknown;
			result.rawData[0] = 0;
			result.rawData[1] = 0;
			result.unused = 0;
			return result;
		}

		public static BindingSetItem StructuredBuffer_SRV(uint32 slot, IBuffer buffer, Format format = Format.UNKNOWN, BufferRange range = EntireBuffer)
		{
			BindingSetItem result = .();
			result.slot = slot;
			result.type = ResourceType.StructuredBuffer_SRV;
			result.resourceHandle = buffer;
			result.format = format;
			result.dimension = TextureDimension.Unknown;
			result.range = range;
			result.unused = 0;
			return result;
		}

		public static BindingSetItem StructuredBuffer_UAV(uint32 slot, IBuffer buffer, Format format = Format.UNKNOWN, BufferRange range = EntireBuffer)
		{
			BindingSetItem result = .();
			result.slot = slot;
			result.type = ResourceType.StructuredBuffer_UAV;
			result.resourceHandle = buffer;
			result.format = format;
			result.dimension = TextureDimension.Unknown;
			result.range = range;
			result.unused = 0;
			return result;
		}

		public static BindingSetItem RawBuffer_SRV(uint32 slot, IBuffer buffer, BufferRange range = EntireBuffer)
		{
			BindingSetItem result = .();
			result.slot = slot;
			result.type = ResourceType.RawBuffer_SRV;
			result.resourceHandle = buffer;
			result.format = Format.UNKNOWN;
			result.dimension = TextureDimension.Unknown;
			result.range = range;
			result.unused = 0;
			return result;
		}

		public static BindingSetItem RawBuffer_UAV(uint32 slot, IBuffer buffer, BufferRange range = EntireBuffer)
		{
			BindingSetItem result = .();
			result.slot = slot;
			result.type = ResourceType.RawBuffer_UAV;
			result.resourceHandle = buffer;
			result.format = Format.UNKNOWN;
			result.dimension = TextureDimension.Unknown;
			result.range = range;
			result.unused = 0;
			return result;
		}

		public static BindingSetItem PushConstants(uint32 slot, uint32 byteSize)
		{
			BindingSetItem result = .();
			result.slot = slot;
			result.type = ResourceType.PushConstants;
			result.resourceHandle = null;
			result.format = Format.UNKNOWN;
			result.dimension = TextureDimension.Unknown;
			result.range.byteOffset = 0;
			result.range.byteSize = byteSize;
			result.unused = 0;
			return result;
		}

		public ref BindingSetItem setFormat(Format value) mut { format = value; return ref this; }
		public ref BindingSetItem setDimension(TextureDimension value) mut { dimension = value; return ref this; }
		public ref BindingSetItem setSubresources(TextureSubresourceSet value) mut { subresources = value; return ref this; }
		public ref BindingSetItem setRange(BufferRange value) mut { range = value; return ref this; }
		public int GetHashCode()
		{
			int value = 0;
			nvrhi.hash_combine(ref value, resourceHandle);
			nvrhi.hash_combine(ref value, slot);
			nvrhi.hash_combine(ref value, type);
			nvrhi.hash_combine(ref value, dimension);
			nvrhi.hash_combine(ref value, format);
			nvrhi.hash_combine(ref value, rawData[0]);
			nvrhi.hash_combine(ref value, rawData[1]);
			return value;
		}
	}

	public static
	{
		private static void Asserts()
		{
		// verify the packing of BindingSetItem for good alignment
			Compiler.Assert(sizeof(BindingSetItem) == 32, "sizeof(BindingSetItem) is supposed to be 32 bytes");
		}
	}

		// describes the resource bindings for a single pipeline stage
	typealias BindingSetItemArray = StaticVector<BindingSetItem, const c_MaxBindingsPerLayout>;

		// describes a set of bindings across all stages of the pipeline
		// (not all bindings need to be present in the set, but the set must be defined by a single BindingSetItem object)
	struct BindingSetDesc : IHashable
	{
		public BindingSetItemArray bindings = .();

		// Enables automatic liveness tracking of this binding set by nvrhi command lists.
		// By setting trackLiveness to false, you take the responsibility of not releasing it 
		// until all rendering commands using the binding set are finished.
		public bool trackLiveness = true;

		public static bool operator ==(BindingSetDesc a, BindingSetDesc b)
		{
			if (a.bindings.Count != b.bindings.Count)
				return false;

			for (int i = 0; i < a.bindings.Count; ++i)
			{
				if (a.bindings[i] != b.bindings[i])
					return false;
			}

			return true;
		}

		public static bool operator !=(BindingSetDesc a, BindingSetDesc b)
		{
			return !(a == b);
		}

		public ref BindingSetDesc addItem(BindingSetItem value) mut { bindings.PushBack(value); return ref this; }
		public ref BindingSetDesc setTrackLiveness(bool value) mut { trackLiveness = value; return ref this; }
		public int GetHashCode()
		{
			int value = 0;
			for (readonly ref BindingSetItem item in ref bindings)
				hash_combine(ref value, item);
			return value;
		}
	}

	//////////////////////////////////////////////////////////////////////////
	// Draw State
	//////////////////////////////////////////////////////////////////////////

	enum PrimitiveType : uint8
	{
		PointList,
		LineList,
		TriangleList,
		TriangleStrip,
		TriangleFan,
		TriangleListWithAdjacency,
		TriangleStripWithAdjacency,
		PatchList
	}

	struct SinglePassStereoState
	{
		public bool enabled = false;
		public bool independentViewportMask = false;
		public uint16 renderTargetIndexOffset = 0;

		public static bool operator ==(SinglePassStereoState a, SinglePassStereoState b)
		{
			return a.enabled == b.enabled
				&& a.independentViewportMask == b.independentViewportMask
				&& a.renderTargetIndexOffset == b.renderTargetIndexOffset;
		}

		public static bool operator !=(SinglePassStereoState a, SinglePassStereoState b) { return !(a == b); }

		public ref SinglePassStereoState setEnabled(bool value) mut { enabled = value; return ref this; }
		public ref SinglePassStereoState setIndependentViewportMask(bool value) mut { independentViewportMask = value; return ref this; }
		public ref SinglePassStereoState setRenderTargetIndexOffset(uint16 value) mut { renderTargetIndexOffset = value; return ref this; }
	}

	struct RenderState
	{
		public BlendState blendState = .();
		public DepthStencilState depthStencilState = .();
		public RasterState rasterState = .();
		public SinglePassStereoState singlePassStereo;

		public ref RenderState setBlendState(BlendState value) mut { blendState = value; return ref this; }
		public ref RenderState setDepthStencilState(DepthStencilState value) mut { depthStencilState = value; return ref this; }
		public ref RenderState setRasterState(RasterState value) mut { rasterState = value; return ref this; }
		public ref RenderState setSinglePassStereoState(SinglePassStereoState value) mut { singlePassStereo = value; return ref this; }
	}

	enum VariableShadingRate : uint8
	{
		e1x1,
		e1x2,
		e2x1,
		e2x2,
		e2x4,
		e4x2,
		e4x4
	}

	enum ShadingRateCombiner : uint8
	{
		Passthrough,
		Override,
		Min,
		Max,
		ApplyRelative
	}

	struct VariableRateShadingState
	{
		public bool enabled = false;
		public VariableShadingRate shadingRate = VariableShadingRate.e1x1;
		public ShadingRateCombiner pipelinePrimitiveCombiner = ShadingRateCombiner.Passthrough;
		public ShadingRateCombiner imageCombiner = ShadingRateCombiner.Passthrough;

		public static bool operator ==(VariableRateShadingState a, VariableRateShadingState b)
		{
			return a.enabled == b.enabled
				&& a.shadingRate == b.shadingRate
				&& a.pipelinePrimitiveCombiner == b.pipelinePrimitiveCombiner
				&& a.imageCombiner == b.imageCombiner;
		}

		public static bool operator !=(VariableRateShadingState a, VariableRateShadingState b) { return !(a == b); }

		public ref VariableRateShadingState setEnabled(bool value) mut { enabled = value; return ref this; }
		public ref VariableRateShadingState setShadingRate(VariableShadingRate value) mut { shadingRate = value; return ref this; }
		public ref VariableRateShadingState setPipelinePrimitiveCombiner(ShadingRateCombiner value) mut { pipelinePrimitiveCombiner = value; return ref this; }
		public ref VariableRateShadingState setImageCombiner(ShadingRateCombiner value) mut { imageCombiner = value; return ref this; }
	}

	typealias BindingLayoutVector = StaticVector<BindingLayoutHandle, const c_MaxBindingLayouts>;

	struct GraphicsPipelineDesc
	{
		public PrimitiveType primType = PrimitiveType.TriangleList;
		public uint32 patchControlPoints = 0;
		public InputLayoutHandle inputLayout;

		public ShaderHandle VS;
		public ShaderHandle HS;
		public ShaderHandle DS;
		public ShaderHandle GS;
		public ShaderHandle PS;

		public RenderState renderState = .();
		public VariableRateShadingState shadingRateState = .();

		public BindingLayoutVector bindingLayouts = .();

		public ref GraphicsPipelineDesc setPrimType(PrimitiveType value) mut { primType = value; return ref this; }
		public ref GraphicsPipelineDesc setPatchControlPoints(uint32 value) mut { patchControlPoints = value; return ref this; }
		public ref GraphicsPipelineDesc setInputLayout(IInputLayout value) mut { inputLayout = value; return ref this; }
		public ref GraphicsPipelineDesc setVertexShader(IShader value) mut { VS = value; return ref this; }
		public ref GraphicsPipelineDesc setHullShader(IShader value) mut { HS = value; return ref this; }
		public ref GraphicsPipelineDesc setTessellationControlShader(IShader value) mut { HS = value; return ref this; }
		public ref GraphicsPipelineDesc setDomainShader(IShader value) mut { DS = value; return ref this; }
		public ref GraphicsPipelineDesc setTessellationEvaluationShader(IShader value) mut { DS = value; return ref this; }
		public ref GraphicsPipelineDesc setGeometryShader(IShader value) mut { GS = value; return ref this; }
		public ref GraphicsPipelineDesc setPixelShader(IShader value) mut { PS = value; return ref this; }
		public ref GraphicsPipelineDesc setFragmentShader(IShader value) mut { PS = value; return ref this; }
		public ref GraphicsPipelineDesc setRenderState(RenderState value) mut { renderState = value; return ref this; }
		public ref GraphicsPipelineDesc setVariableRateShadingState(VariableRateShadingState value) mut { shadingRateState = value; return ref this; }
		public ref GraphicsPipelineDesc addBindingLayout(IBindingLayout layout) mut { bindingLayouts.PushBack(layout); return ref this; }
	}

	struct ComputePipelineDesc
	{
		public ShaderHandle CS;

		public BindingLayoutVector bindingLayouts = .();

		public ref ComputePipelineDesc setComputeShader(IShader value) mut { CS = value; return ref this; }
		public ref ComputePipelineDesc addBindingLayout(IBindingLayout layout) mut { bindingLayouts.PushBack(layout); return ref this; }
	}

	struct MeshletPipelineDesc
	{
		public PrimitiveType primType = PrimitiveType.TriangleList;

		public ShaderHandle AS;
		public ShaderHandle MS;
		public ShaderHandle PS;

		public RenderState renderState = .();

		public BindingLayoutVector bindingLayouts = .();

		public ref MeshletPipelineDesc setPrimType(PrimitiveType value) mut { primType = value; return ref this; }
		public ref MeshletPipelineDesc setTaskShader(IShader value) mut { AS = value; return ref this; }
		public ref MeshletPipelineDesc setAmplificationShader(IShader value) mut { AS = value; return ref this; }
		public ref MeshletPipelineDesc setMeshShader(IShader value) mut { MS = value; return ref this; }
		public ref MeshletPipelineDesc setPixelShader(IShader value) mut { PS = value; return ref this; }
		public ref MeshletPipelineDesc setFragmentShader(IShader value) mut { PS = value; return ref this; }
		public ref MeshletPipelineDesc setRenderState(RenderState value) mut { renderState = value; return ref this; }
		public ref MeshletPipelineDesc addBindingLayout(IBindingLayout layout) mut { bindingLayouts.PushBack(layout); return ref this; }
	}

	//////////////////////////////////////////////////////////////////////////
	// Draw and Dispatch
	//////////////////////////////////////////////////////////////////////////

	struct VertexBufferBinding
	{
		public IBuffer buffer = null;
		public uint32 slot;
		public uint64 offset;

		public static bool operator ==(VertexBufferBinding a, VertexBufferBinding b)
		{
			return a.buffer == b.buffer
				&& a.slot == b.slot
				&& a.offset == b.offset;
		}
		public static bool operator !=(VertexBufferBinding a, VertexBufferBinding b) { return !(a == b); }

		public ref VertexBufferBinding setBuffer(IBuffer value) mut { buffer = value; return ref this; }
		public ref VertexBufferBinding setSlot(uint32 value) mut { slot = value; return ref this; }
		public ref VertexBufferBinding setOffset(uint64 value) mut { offset = value; return ref this; }
	}

	struct IndexBufferBinding
	{
		public IBuffer buffer = null;
		public Format format;
		public uint32 offset;

		public static bool operator ==(IndexBufferBinding a, IndexBufferBinding b)
		{
			return a.buffer == b.buffer
				&& a.format == b.format
				&& a.offset == b.offset;
		}
		public static bool operator !=(IndexBufferBinding a, IndexBufferBinding b) { return !(a == b); }

		public ref IndexBufferBinding setBuffer(IBuffer value) mut { buffer = value; return ref this; }
		public ref IndexBufferBinding setFormat(Format value) mut { format = value; return ref this; }
		public ref IndexBufferBinding setOffset(uint32 value) mut { offset = value; return ref this; }
	}

	typealias BindingSetVector = StaticVector<IBindingSet, const c_MaxBindingLayouts>;


	struct GraphicsState
	{
		public IGraphicsPipeline pipeline = null;
		public IFramebuffer framebuffer = null;
		public ViewportState viewport = .();
		public Color blendConstantColor = .();
		public VariableRateShadingState shadingRateState = .();

		public BindingSetVector bindings = .();

		public StaticVector<VertexBufferBinding, const c_MaxVertexAttributes> vertexBuffers = .();
		public IndexBufferBinding indexBuffer = .();

		public IBuffer indirectParams = null;

		public ref GraphicsState setPipeline(IGraphicsPipeline value) mut { pipeline = value; return ref this; }
		public ref GraphicsState setFramebuffer(IFramebuffer value) mut { framebuffer = value; return ref this; }
		public ref GraphicsState setViewport(ViewportState value) mut { viewport = value; return ref this; }
		public ref GraphicsState setBlendColor(Color value) mut { blendConstantColor = value; return ref this; }
		public ref GraphicsState addBindingSet(IBindingSet value) mut { bindings.PushBack(value); return ref this; }
		public ref GraphicsState addVertexBuffer(VertexBufferBinding value) mut { vertexBuffers.PushBack(value); return ref this; }
		public ref GraphicsState setIndexBuffer(IndexBufferBinding value) mut { indexBuffer = value; return ref this; }
		public ref GraphicsState setIndirectParams(IBuffer value) mut { indirectParams = value; return ref this; }
	}

	struct DrawArguments
	{
		public uint32 vertexCount = 0;
		public uint32 instanceCount = 1;
		public uint32 startIndexLocation = 0;
		public uint32 startVertexLocation = 0;
		public uint32 startInstanceLocation = 0;

		public ref DrawArguments setVertexCount(uint32 value) mut { vertexCount = value; return ref this; }
		public ref DrawArguments setInstanceCount(uint32 value) mut { instanceCount = value; return ref this; }
		public ref DrawArguments setStartIndexLocation(uint32 value) mut { startIndexLocation = value; return ref this; }
		public ref DrawArguments setStartVertexLocation(uint32 value) mut { startVertexLocation = value; return ref this; }
		public ref DrawArguments setStartInstanceLocation(uint32 value) mut { startInstanceLocation = value; return ref this; }
	}

	struct ComputeState
	{
		public IComputePipeline pipeline = null;

		public BindingSetVector bindings = .();

		public IBuffer indirectParams = null;

		public ref ComputeState setPipeline(IComputePipeline value) mut { pipeline = value; return ref this; }
		public ref ComputeState addBindingSet(IBindingSet value) mut { bindings.PushBack(value); return ref this; }
		public ref ComputeState setIndirectParams(IBuffer value) mut { indirectParams = value; return ref this; }
	}

	struct MeshletState
	{
		public IMeshletPipeline pipeline = null;
		public IFramebuffer framebuffer = null;
		public ViewportState viewport = .();
		public Color blendConstantColor = .();

		public BindingSetVector bindings = .();

		public IBuffer indirectParams = null;

		public ref MeshletState setPipeline(IMeshletPipeline value) mut { pipeline = value; return ref this; }
		public ref MeshletState setFramebuffer(IFramebuffer value) mut { framebuffer = value; return ref this; }
		public ref MeshletState setViewport(ViewportState value) mut { viewport = value; return ref this; }
		public ref MeshletState setBlendColor(Color value) mut { blendConstantColor = value; return ref this; }
		public ref MeshletState addBindingSet(IBindingSet value) mut { bindings.PushBack(value); return ref this; }
		public ref MeshletState setIndirectParams(IBuffer value) mut { indirectParams = value; return ref this; }
	}

	//////////////////////////////////////////////////////////////////////////
	// Misc
	//////////////////////////////////////////////////////////////////////////

	enum Feature : uint8
	{
		DeferredCommandLists,
		SinglePassStereo,
		RayTracingAccelStruct,
		RayTracingPipeline,
		RayQuery,
		FastGeometryShader,
		Meshlets,
		VariableRateShading,
		ShaderSpecializations,
		VirtualResources,
		ComputeQueue,
		CopyQueue
	}

	enum MessageSeverity : uint8
	{
		Info,
		Warning,
		Error,
		Fatal
	}

	enum CommandQueue : uint8
	{
		Graphics = 0,
		Compute,
		Copy,

		Count
	}

	struct VariableRateShadingFeatureInfo
	{
		public uint32 shadingRateImageTileSize;
	}

	struct CommandListParameters
	{
		// A command list with enableImmediateExecution = true maps to the immediate context on DX11.
		// Two immediate command lists cannot be open at the same time, which is checked by the validation layer.
		public bool enableImmediateExecution = true;

		// Minimum size of memory chunks created to upload data to the device on DX12.
		public int uploadChunkSize = 64 * 1024;

		// Minimum size of memory chunks created for AS build scratch buffers.
		public int scratchChunkSize = 64 * 1024;

		// Maximum total memory size used for all AS build scratch buffers owned by this command list.
		public int scratchMaxMemory = 1024 * 1024 * 1024;

		// Type of the queue that this command list is to be executed on.
		// COPY and COMPUTE queues have limited subsets of methods available.
		public CommandQueue queueType = CommandQueue.Graphics;

		public ref CommandListParameters setEnableImmediateExecution(bool value) mut { enableImmediateExecution = value; return ref this; }
		public ref CommandListParameters setUploadChunkSize(int value) mut { uploadChunkSize = value; return ref this; }
		public ref CommandListParameters setScratchChunkSize(int value) mut { scratchChunkSize = value; return ref this; }
		public ref CommandListParameters setScratchMaxMemory(int value) mut { scratchMaxMemory = value; return ref this; }
		public ref CommandListParameters setQueueType(CommandQueue value) mut { queueType = value; return ref this; }
	}

	public static
	{
		public static void hash_combine<T>(ref int seed, T v) where T : IHashable
		{
			/*std::hash<T> hasher;
			seed ^= hasher(v) + 0x9e3779b9 + (seed << 6) + (seed >> 2);*/
			seed ^= v.GetHashCode() + 0x9e3779b9 + (seed << 6) + (seed >> 2);
		}
	}
}