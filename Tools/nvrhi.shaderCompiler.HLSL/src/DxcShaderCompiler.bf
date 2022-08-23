using Dxc_Beef;
using System;
using System.IO;
using System.Collections;
using System.Diagnostics;
using static System.Windows.COM_IUnknown;
namespace nvrhi.shaderCompiler.Dxc
{
	enum OutputType
	{
		DXIL,
		SPIRV
	}

	struct SPIRVBindingOffsets
	{
		public uint32 TextureOffset;
		public uint32 SamplerOffset;
		public uint32 ConstantBufferOffset;
		public uint32 StorageTextureAndBufferOffset;
	}

	struct ShaderCompilerOptions
	{
		public StringView ShaderPath;
		public ShaderType ShaderType;
		public StringView ShaderModel = "6_5";
		public StringView EntryPoint;
		public OutputType OutputType;
		public Dictionary<StringView, StringView> Defines;

		public SPIRVBindingOffsets SPIRVBindingOffsets = .()
			{
				TextureOffset = 0,
				SamplerOffset = 128,
				ConstantBufferOffset = 256,
				StorageTextureAndBufferOffset = 384
			};
	}

	public static
	{
		public static void GetShaderTarget(ShaderType stage, StringView model, String target)
		{
			switch (stage) {
			case .Compute:
				target.AppendF("cs_{}", model);
				break;

			case .Vertex:
				target.AppendF("vs_{}", model);
				break;

			case .Hull:
				target.AppendF("hs_{}", model);
				break;

			case .Domain:
				target.AppendF("ds_{}", model);
				break;

			case .Geometry:
				target.AppendF("gs_{}", model);
				break;

			case .Pixel:
				target.AppendF("ps_{}", model);
				break;

			case .Amplification:
				target.AppendF("as_{}", model);
				break;

			case .Mesh:
				target.AppendF("ms_{}", model);
				break;

			case .RayGeneration:
				target.AppendF("lib_{}", model);
				break;

			case .AnyHit:
				target.AppendF("lib_{}", model);
				break;

			case .ClosestHit:
				target.AppendF("lib_{}", model);
				break;

			case .Miss:
				target.AppendF("lib_{}", model);
				break;

			case .Intersection:
				target.AppendF("lib_{}", model);
				break;

			case .Callable:
				target.AppendF("lib_{}", model);
				break;

			default:
				Runtime.FatalError();
			}
		}
	}

	class DxcShaderCompiler
	{
		public static bool IsInitialized { get; private set; }
		private static IDxcLibrary* pLibrary = null;

		private static Result<void> Initialize()
		{
			if (IsInitialized)
				return .Ok;

			HResult result = Dxc.CreateInstance(out pLibrary);
			if (result != .OK)
				return .Err;

			IsInitialized = true;
			return .Ok;
		}

		private String mBasePath;

		public static this()
		{
			Initialize();
		}

		public this(StringView basePath)
		{
			mBasePath = new .(basePath);
		}

		public ~this()
		{
			delete mBasePath;
		}

		public Result<void> CompileShader(ShaderCompilerOptions options, List<uint8> compiledByteCode)
		{
			String shaderDir = Path.GetDirectoryPath(options.ShaderPath, .. scope .());


			IDxcCompiler3* pCompiler = null;

			var result = Dxc.CreateInstance(out pCompiler);
			if (result != .OK)
				return .Err;

			uint32 codePage = 0;
			IDxcBlobEncoding* pSource = null;
			result = pLibrary.CreateBlobFromFile(options.ShaderPath, &codePage, out pSource);
			if (result != .OK)
				return .Err;

			String target = GetShaderTarget(options.ShaderType, options.ShaderModel, .. scope .());

			List<StringView> arguments = scope .();

			arguments.Add("/Zi");
			arguments.Add("/Qembed_debug");


			arguments.Add("-E");
			arguments.Add(options.EntryPoint);

			arguments.Add("-T");
			arguments.Add(target);

			if (options.Defines != null)
			{
				for (var define in options.Defines)
				{
					arguments.Add(scope :: $"-D{define.key}={define.value}");
				}
			}

			if (options.OutputType == .DXIL)
			{
				arguments.Add(scope :: $"-DDXIL");
			}

			if (options.OutputType == .SPIRV)
			{
				arguments.Add(scope :: $"-DSPIRV");
				arguments.Add(scope :: $"-DVULKAN");

				int VK_S_SHIFT = options.SPIRVBindingOffsets.SamplerOffset;
				int VK_T_SHIFT = options.SPIRVBindingOffsets.TextureOffset;
				int VK_B_SHIFT = options.SPIRVBindingOffsets.ConstantBufferOffset;
				int VK_U_SHIFT = options.SPIRVBindingOffsets.StorageTextureAndBufferOffset;

				for (int space = 0; space < 10; space++)
				{
					String spaceString = scope $"{space}";
					arguments.Add("-fvk-s-shift");
					arguments.Add(scope :: $"{VK_S_SHIFT}");
					arguments.Add(spaceString);


					arguments.Add("-fvk-t-shift");
					arguments.Add(scope :: $"{VK_T_SHIFT}");
					arguments.Add(spaceString);

					arguments.Add("-fvk-b-shift");
					arguments.Add(scope :: $"{VK_B_SHIFT}");
					arguments.Add(spaceString);

					arguments.Add("-fvk-u-shift");
					arguments.Add(scope :: $"{VK_U_SHIFT}");
					arguments.Add(spaceString);
				}


				arguments.Add(scope :: $"-spirv");
				arguments.Add(scope :: $"-fspv-target-env=vulkan1.2");
				arguments.Add(scope :: $"-fspv-extension=SPV_EXT_descriptor_indexing");
				arguments.Add(scope :: $"-fspv-extension=KHR");
			}

			arguments.Add("-WX");
			arguments.Add("-O3");
			arguments.Add("-enable-16bit-types");

			DxcBuffer buffer = .()
				{
					Ptr = pSource.GetBufferPointer(),
					Size = pSource.GetBufferSize(),
					Encoding = 0
				};

			IncludeHandler includeHandler = .(pLibrary, mBasePath, shaderDir);

			result = pCompiler.Compile(&buffer, arguments, &includeHandler, ref IDxcResult.sIID, var ppResult);
			if (result != .OK)
				return .Err;

			IDxcResult* pResult = (.)ppResult;

			result = pResult.GetStatus(var status);

			if (status != .OK)
			{
				IDxcBlobEncoding* pErrors = null;
				result = pResult.GetErrorBuffer(out pErrors);
				if (pErrors != null && pErrors.GetBufferSize() > 0)
				{
					Debug.WriteLine(scope String((char8*)pErrors.GetBufferPointer()));
				}
				return .Err;
			}

			IDxcBlob* pBlob = null;

			result = pResult.GetResult(out pBlob);
			if (result != .OK)
				return .Err;

			compiledByteCode.AddRange(Span<uint8>((.)pBlob.GetBufferPointer(), pBlob.GetBufferSize()));

			return .Ok;
		}
	}

	struct IncludeHandler : IDxcIncludeHandler
	{
		public this(IDxcLibrary* pLibrary, String shaderCompilerBasePath, String shaderPath)
		{
			m_pLibrary = pLibrary;
			m_ShaderCompilerBasePath = shaderCompilerBasePath;
			m_ShaderPath = shaderPath;

			function [CallingConvention(.Stdcall)] HResult(IncludeHandler* this, ref Guid riid, void** result) queryInterface = => QueryInterface;
			function [CallingConvention(.Stdcall)] uint32(IncludeHandler* this) addRef = => AddRef;
			function [CallingConvention(.Stdcall)] uint32(IncludeHandler* this) release = => Release;
			function [CallingConvention(.Stdcall)] HResult(IncludeHandler* this, char16* pFilename, out IDxcBlob* ppIncludeSource) loadSource = => LoadSource;

			mDVT = .();
			mDVT.QueryInterface = (.)(void*)queryInterface;
			mDVT.AddRef = (.)(void*)addRef;
			mDVT.Release = (.)(void*)release;
			mDVT.LoadSource = (.)(void*)loadSource;

			mVT = &mDVT;
		}

		private HResult LoadSource(char16* pFilename, out IDxcBlob* ppIncludeSource)
		{
			ppIncludeSource = ?;
			IDxcBlobEncoding* pSource = null;

			// try to load the include next to the shader file first
			String shaderPath = Path.InternalCombine(.. scope .(), m_ShaderPath, scope String(pFilename));

			HResult result = m_pLibrary.CreateBlobFromFile(shaderPath, null, out pSource);

			if (result == .OK && pSource != null)
			{
				ppIncludeSource = pSource;

				return result;
			}

			// try to load the include from the base shader path
			String shaderBasePath = Path.InternalCombine(.. scope .(), m_ShaderCompilerBasePath, scope String(pFilename));

			result = m_pLibrary.CreateBlobFromFile(shaderBasePath, null, out pSource);

			if (result == .OK && pSource != null)
			{
				ppIncludeSource = pSource;
			}
			return result;
		}

		private HResult QueryInterface(ref Guid riid, void** result)
		{
			return (.)0x80004001;
		}

		private uint32 AddRef()
		{
			return (.)0x80004001;
		}

		private uint32 Release()
		{
			return (.)0x80004001;
		}


		public new VTable* VT
		{
			get
			{
				return (.)mVT;
			}
		}

		private IDxcIncludeHandler.VTable mDVT;
		private IDxcLibrary* m_pLibrary = null;
		private String m_ShaderCompilerBasePath = null;
		private String m_ShaderPath = null;
	}
}