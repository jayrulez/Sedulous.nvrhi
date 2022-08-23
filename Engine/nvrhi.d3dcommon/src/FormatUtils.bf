using Win32.Graphics.Dxgi;
using System;
namespace nvrhi.d3dcommon
{
	public static
	{
		struct DxgiFormatMapping : this(Format abstractFormat, DXGI_FORMAT resourceFormat, DXGI_FORMAT srvFormat, DXGI_FORMAT rtvFormat)
		{
		}

		// Format mapping table. The rows must be in the exactly same order as Format enum members are defined.
		public static DxgiFormatMapping[?] c_FormatMappings = .(
		    .( Format.UNKNOWN,              DXGI_FORMAT.UNKNOWN,                DXGI_FORMAT.UNKNOWN,                  DXGI_FORMAT.UNKNOWN                ),

		    .( Format.R8_UINT,              DXGI_FORMAT.R8_TYPELESS,            DXGI_FORMAT.R8_UINT,                  DXGI_FORMAT.R8_UINT                ),
		    .( Format.R8_SINT,              DXGI_FORMAT.R8_TYPELESS,            DXGI_FORMAT.R8_SINT,                  DXGI_FORMAT.R8_SINT                ),
		    .( Format.R8_UNORM,             DXGI_FORMAT.R8_TYPELESS,            DXGI_FORMAT.R8_UNORM,                 DXGI_FORMAT.R8_UNORM               ),
		    .( Format.R8_SNORM,             DXGI_FORMAT.R8_TYPELESS,            DXGI_FORMAT.R8_SNORM,                 DXGI_FORMAT.R8_SNORM               ),
		    .( Format.RG8_UINT,             DXGI_FORMAT.R8G8_TYPELESS,          DXGI_FORMAT.R8G8_UINT,                DXGI_FORMAT.R8G8_UINT              ),
		    .( Format.RG8_SINT,             DXGI_FORMAT.R8G8_TYPELESS,          DXGI_FORMAT.R8G8_SINT,                DXGI_FORMAT.R8G8_SINT              ),
		    .( Format.RG8_UNORM,            DXGI_FORMAT.R8G8_TYPELESS,          DXGI_FORMAT.R8G8_UNORM,               DXGI_FORMAT.R8G8_UNORM             ),
		    .( Format.RG8_SNORM,            DXGI_FORMAT.R8G8_TYPELESS,          DXGI_FORMAT.R8G8_SNORM,               DXGI_FORMAT.R8G8_SNORM             ),
		    .( Format.R16_UINT,             DXGI_FORMAT.R16_TYPELESS,           DXGI_FORMAT.R16_UINT,                 DXGI_FORMAT.R16_UINT               ),
		    .( Format.R16_SINT,             DXGI_FORMAT.R16_TYPELESS,           DXGI_FORMAT.R16_SINT,                 DXGI_FORMAT.R16_SINT               ),
		    .( Format.R16_UNORM,            DXGI_FORMAT.R16_TYPELESS,           DXGI_FORMAT.R16_UNORM,                DXGI_FORMAT.R16_UNORM              ),
		    .( Format.R16_SNORM,            DXGI_FORMAT.R16_TYPELESS,           DXGI_FORMAT.R16_SNORM,                DXGI_FORMAT.R16_SNORM              ),
		    .( Format.R16_FLOAT,            DXGI_FORMAT.R16_TYPELESS,           DXGI_FORMAT.R16_FLOAT,                DXGI_FORMAT.R16_FLOAT              ),
		    .( Format.BGRA4_UNORM,          DXGI_FORMAT.B4G4R4A4_UNORM,         DXGI_FORMAT.B4G4R4A4_UNORM,           DXGI_FORMAT.B4G4R4A4_UNORM         ),
		    .( Format.B5G6R5_UNORM,         DXGI_FORMAT.B5G6R5_UNORM,           DXGI_FORMAT.B5G6R5_UNORM,             DXGI_FORMAT.B5G6R5_UNORM           ),
		    .( Format.B5G5R5A1_UNORM,       DXGI_FORMAT.B5G5R5A1_UNORM,         DXGI_FORMAT.B5G5R5A1_UNORM,           DXGI_FORMAT.B5G5R5A1_UNORM         ),
		    .( Format.RGBA8_UINT,           DXGI_FORMAT.R8G8B8A8_TYPELESS,      DXGI_FORMAT.R8G8B8A8_UINT,            DXGI_FORMAT.R8G8B8A8_UINT          ),
		    .( Format.RGBA8_SINT,           DXGI_FORMAT.R8G8B8A8_TYPELESS,      DXGI_FORMAT.R8G8B8A8_SINT,            DXGI_FORMAT.R8G8B8A8_SINT          ),
		    .( Format.RGBA8_UNORM,          DXGI_FORMAT.R8G8B8A8_TYPELESS,      DXGI_FORMAT.R8G8B8A8_UNORM,           DXGI_FORMAT.R8G8B8A8_UNORM         ),
		    .( Format.RGBA8_SNORM,          DXGI_FORMAT.R8G8B8A8_TYPELESS,      DXGI_FORMAT.R8G8B8A8_SNORM,           DXGI_FORMAT.R8G8B8A8_SNORM         ),
		    .( Format.BGRA8_UNORM,          DXGI_FORMAT.B8G8R8A8_TYPELESS,      DXGI_FORMAT.B8G8R8A8_UNORM,           DXGI_FORMAT.B8G8R8A8_UNORM         ),
		    .( Format.SRGBA8_UNORM,         DXGI_FORMAT.R8G8B8A8_TYPELESS,      DXGI_FORMAT.R8G8B8A8_UNORM_SRGB,      DXGI_FORMAT.R8G8B8A8_UNORM_SRGB    ),
		    .( Format.SBGRA8_UNORM,         DXGI_FORMAT.B8G8R8A8_TYPELESS,      DXGI_FORMAT.B8G8R8A8_UNORM_SRGB,      DXGI_FORMAT.B8G8R8A8_UNORM_SRGB    ),
		    .( Format.R10G10B10A2_UNORM,    DXGI_FORMAT.R10G10B10A2_TYPELESS,   DXGI_FORMAT.R10G10B10A2_UNORM,        DXGI_FORMAT.R10G10B10A2_UNORM      ),
		    .( Format.R11G11B10_FLOAT,      DXGI_FORMAT.R11G11B10_FLOAT,        DXGI_FORMAT.R11G11B10_FLOAT,          DXGI_FORMAT.R11G11B10_FLOAT        ),
		    .( Format.RG16_UINT,            DXGI_FORMAT.R16G16_TYPELESS,        DXGI_FORMAT.R16G16_UINT,              DXGI_FORMAT.R16G16_UINT            ),
		    .( Format.RG16_SINT,            DXGI_FORMAT.R16G16_TYPELESS,        DXGI_FORMAT.R16G16_SINT,              DXGI_FORMAT.R16G16_SINT            ),
		    .( Format.RG16_UNORM,           DXGI_FORMAT.R16G16_TYPELESS,        DXGI_FORMAT.R16G16_UNORM,             DXGI_FORMAT.R16G16_UNORM           ),
		    .( Format.RG16_SNORM,           DXGI_FORMAT.R16G16_TYPELESS,        DXGI_FORMAT.R16G16_SNORM,             DXGI_FORMAT.R16G16_SNORM           ),
		    .( Format.RG16_FLOAT,           DXGI_FORMAT.R16G16_TYPELESS,        DXGI_FORMAT.R16G16_FLOAT,             DXGI_FORMAT.R16G16_FLOAT           ),
		    .( Format.R32_UINT,             DXGI_FORMAT.R32_TYPELESS,           DXGI_FORMAT.R32_UINT,                 DXGI_FORMAT.R32_UINT               ),
		    .( Format.R32_SINT,             DXGI_FORMAT.R32_TYPELESS,           DXGI_FORMAT.R32_SINT,                 DXGI_FORMAT.R32_SINT               ),
		    .( Format.R32_FLOAT,            DXGI_FORMAT.R32_TYPELESS,           DXGI_FORMAT.R32_FLOAT,                DXGI_FORMAT.R32_FLOAT              ),
		    .( Format.RGBA16_UINT,          DXGI_FORMAT.R16G16B16A16_TYPELESS,  DXGI_FORMAT.R16G16B16A16_UINT,        DXGI_FORMAT.R16G16B16A16_UINT      ),
		    .( Format.RGBA16_SINT,          DXGI_FORMAT.R16G16B16A16_TYPELESS,  DXGI_FORMAT.R16G16B16A16_SINT,        DXGI_FORMAT.R16G16B16A16_SINT      ),
		    .( Format.RGBA16_FLOAT,         DXGI_FORMAT.R16G16B16A16_TYPELESS,  DXGI_FORMAT.R16G16B16A16_FLOAT,       DXGI_FORMAT.R16G16B16A16_FLOAT     ),
		    .( Format.RGBA16_UNORM,         DXGI_FORMAT.R16G16B16A16_TYPELESS,  DXGI_FORMAT.R16G16B16A16_UNORM,       DXGI_FORMAT.R16G16B16A16_UNORM     ),
		    .( Format.RGBA16_SNORM,         DXGI_FORMAT.R16G16B16A16_TYPELESS,  DXGI_FORMAT.R16G16B16A16_SNORM,       DXGI_FORMAT.R16G16B16A16_SNORM     ),
		    .( Format.RG32_UINT,            DXGI_FORMAT.R32G32_TYPELESS,        DXGI_FORMAT.R32G32_UINT,              DXGI_FORMAT.R32G32_UINT            ),
		    .( Format.RG32_SINT,            DXGI_FORMAT.R32G32_TYPELESS,        DXGI_FORMAT.R32G32_SINT,              DXGI_FORMAT.R32G32_SINT            ),
		    .( Format.RG32_FLOAT,           DXGI_FORMAT.R32G32_TYPELESS,        DXGI_FORMAT.R32G32_FLOAT,             DXGI_FORMAT.R32G32_FLOAT           ),
		    .( Format.RGB32_UINT,           DXGI_FORMAT.R32G32B32_TYPELESS,     DXGI_FORMAT.R32G32B32_UINT,           DXGI_FORMAT.R32G32B32_UINT         ),
		    .( Format.RGB32_SINT,           DXGI_FORMAT.R32G32B32_TYPELESS,     DXGI_FORMAT.R32G32B32_SINT,           DXGI_FORMAT.R32G32B32_SINT         ),
		    .( Format.RGB32_FLOAT,          DXGI_FORMAT.R32G32B32_TYPELESS,     DXGI_FORMAT.R32G32B32_FLOAT,          DXGI_FORMAT.R32G32B32_FLOAT        ),
		    .( Format.RGBA32_UINT,          DXGI_FORMAT.R32G32B32A32_TYPELESS,  DXGI_FORMAT.R32G32B32A32_UINT,        DXGI_FORMAT.R32G32B32A32_UINT      ),
		    .( Format.RGBA32_SINT,          DXGI_FORMAT.R32G32B32A32_TYPELESS,  DXGI_FORMAT.R32G32B32A32_SINT,        DXGI_FORMAT.R32G32B32A32_SINT      ),
		    .( Format.RGBA32_FLOAT,         DXGI_FORMAT.R32G32B32A32_TYPELESS,  DXGI_FORMAT.R32G32B32A32_FLOAT,       DXGI_FORMAT.R32G32B32A32_FLOAT     ),

		    .( Format.D16,                  DXGI_FORMAT.R16_TYPELESS,           DXGI_FORMAT.R16_UNORM,                DXGI_FORMAT.D16_UNORM              ),
		    .( Format.D24S8,                DXGI_FORMAT.R24G8_TYPELESS,         DXGI_FORMAT.R24_UNORM_X8_TYPELESS,    DXGI_FORMAT.D24_UNORM_S8_UINT      ),
		    .( Format.X24G8_UINT,           DXGI_FORMAT.R24G8_TYPELESS,         DXGI_FORMAT.X24_TYPELESS_G8_UINT,     DXGI_FORMAT.D24_UNORM_S8_UINT      ),
		    .( Format.D32,                  DXGI_FORMAT.R32_TYPELESS,           DXGI_FORMAT.R32_FLOAT,                DXGI_FORMAT.D32_FLOAT              ),
		    .( Format.D32S8,                DXGI_FORMAT.R32G8X24_TYPELESS,      DXGI_FORMAT.R32_FLOAT_X8X24_TYPELESS, DXGI_FORMAT.D32_FLOAT_S8X24_UINT   ),
		    .( Format.X32G8_UINT,           DXGI_FORMAT.R32G8X24_TYPELESS,      DXGI_FORMAT.X32_TYPELESS_G8X24_UINT,  DXGI_FORMAT.D32_FLOAT_S8X24_UINT   ),
		    
		    .( Format.BC1_UNORM,            DXGI_FORMAT.BC1_TYPELESS,           DXGI_FORMAT.BC1_UNORM,                DXGI_FORMAT.BC1_UNORM              ),
		    .( Format.BC1_UNORM_SRGB,       DXGI_FORMAT.BC1_TYPELESS,           DXGI_FORMAT.BC1_UNORM_SRGB,           DXGI_FORMAT.BC1_UNORM_SRGB         ),
		    .( Format.BC2_UNORM,            DXGI_FORMAT.BC2_TYPELESS,           DXGI_FORMAT.BC2_UNORM,                DXGI_FORMAT.BC2_UNORM              ),
		    .( Format.BC2_UNORM_SRGB,       DXGI_FORMAT.BC2_TYPELESS,           DXGI_FORMAT.BC2_UNORM_SRGB,           DXGI_FORMAT.BC2_UNORM_SRGB         ),
		    .( Format.BC3_UNORM,            DXGI_FORMAT.BC3_TYPELESS,           DXGI_FORMAT.BC3_UNORM,                DXGI_FORMAT.BC3_UNORM              ),
		    .( Format.BC3_UNORM_SRGB,       DXGI_FORMAT.BC3_TYPELESS,           DXGI_FORMAT.BC3_UNORM_SRGB,           DXGI_FORMAT.BC3_UNORM_SRGB         ),
		    .( Format.BC4_UNORM,            DXGI_FORMAT.BC4_TYPELESS,           DXGI_FORMAT.BC4_UNORM,                DXGI_FORMAT.BC4_UNORM              ),
		    .( Format.BC4_SNORM,            DXGI_FORMAT.BC4_TYPELESS,           DXGI_FORMAT.BC4_SNORM,                DXGI_FORMAT.BC4_SNORM              ),
		    .( Format.BC5_UNORM,            DXGI_FORMAT.BC5_TYPELESS,           DXGI_FORMAT.BC5_UNORM,                DXGI_FORMAT.BC5_UNORM              ),
		    .( Format.BC5_SNORM,            DXGI_FORMAT.BC5_TYPELESS,           DXGI_FORMAT.BC5_SNORM,                DXGI_FORMAT.BC5_SNORM              ),
		    .( Format.BC6H_UFLOAT,          DXGI_FORMAT.BC6H_TYPELESS,          DXGI_FORMAT.BC6H_UF16,                DXGI_FORMAT.BC6H_UF16              ),
		    .( Format.BC6H_SFLOAT,          DXGI_FORMAT.BC6H_TYPELESS,          DXGI_FORMAT.BC6H_SF16,                DXGI_FORMAT.BC6H_SF16              ),
		    .( Format.BC7_UNORM,            DXGI_FORMAT.BC7_TYPELESS,           DXGI_FORMAT.BC7_UNORM,                DXGI_FORMAT.BC7_UNORM              ),
		    .( Format.BC7_UNORM_SRGB,       DXGI_FORMAT.BC7_TYPELESS,           DXGI_FORMAT.BC7_UNORM_SRGB,           DXGI_FORMAT.BC7_UNORM_SRGB         ),
		);

		public static readonly ref DxgiFormatMapping getDxgiFormatMapping(Format abstractFormat)
		{
			Compiler.Assert(c_FormatMappings.Count == int(Format.COUNT), 
			    "The format mapping table doesn't have the right number of elements");

			readonly ref DxgiFormatMapping mapping = ref c_FormatMappings[uint32(abstractFormat)];
			Runtime.Assert(mapping.abstractFormat == abstractFormat);
			return ref mapping;
		}
	}
}