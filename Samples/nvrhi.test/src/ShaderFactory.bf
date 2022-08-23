using System;
using System.Collections;
using System.IO;
using System.Diagnostics;
namespace nvrhi.test
{
	struct ShaderMacro : this(String name, String definition)
	{
	}

	class ShaderFactory
	{
		private nvrhi.DeviceHandle m_Device;
		private Dictionary<String, List<uint8>> m_BytecodeCache = new .() ~ delete _;
		private String m_basePath;

		public this(nvrhi.DeviceHandle device, String basePath)
		{
			m_Device = device;
			m_basePath = basePath;
		}

		public void ClearCache()
		{
			m_BytecodeCache.Clear();
		}

		public nvrhi.ShaderHandle CreateShader(char8* fileName, char8* entryName, List<ShaderMacro> pDefines, nvrhi.ShaderType shaderType)
		{
			nvrhi.ShaderDesc desc = nvrhi.ShaderDesc(shaderType);
			desc.debugName = scope .(fileName);
			return CreateShader(fileName, entryName, pDefines, desc);
		}

		public nvrhi.ShaderHandle CreateShader(char8* fileName, char8* entryName, List<ShaderMacro> pDefines, nvrhi.ShaderDesc desc)
		{
			List<uint8> byteCode = GetBytecode(fileName, entryName, .. scope .());

			if (byteCode.Count == 0)
				return null;

			List<nvrhi.ShaderConstant> constants = scope .();
			if (pDefines != null)
			{
				for (readonly ref ShaderMacro define in ref pDefines)
					constants.Add(nvrhi.ShaderConstant() { name = define.name, value = define.definition });
			}

			nvrhi.ShaderDesc descCopy = desc;
			descCopy.entryName = scope .(entryName);

			return nvrhi.createShaderPermutation(m_Device, descCopy, byteCode.Ptr, byteCode.Count,
				constants.Ptr, uint32(constants.Count));
		}

		public nvrhi.ShaderLibraryHandle CreateShaderLibrary(char8* fileName, List<ShaderMacro> pDefines)
		{
			List<uint8> byteCode = GetBytecode(fileName, null, .. scope .());

			if (byteCode.Count == 0)
				return null;

			List<nvrhi.ShaderConstant> constants = scope .();
			if (pDefines != null)
			{
				for (readonly ref ShaderMacro define in ref pDefines)
					constants.Add(nvrhi.ShaderConstant() { name = define.name, value = define.definition });
			}

			return nvrhi.createShaderLibraryPermutation(m_Device, byteCode.Ptr, byteCode.Count,
				constants.Ptr, uint32(constants.Count));
		}

		public Result<void> GetBytecode(char8* fileName, char8* entryName, List<uint8> byteCode)
		{
			var entryName;
			if (entryName == null)
				entryName = "main";

			String adjustedName = scope .(fileName);
			{
				if (adjustedName.Contains(".hlsl"))
					adjustedName.Replace(".hlsl", "");

				if (entryName != null && !String.Equals(entryName, "main"))
					adjustedName.AppendF("_{}",  scope String(entryName));
			}

			String shaderFilePath = Path.InternalCombine(.. scope .(), m_basePath, scope $"{adjustedName}.bin");

			if (m_BytecodeCache.ContainsKey(shaderFilePath) && !m_BytecodeCache[shaderFilePath].IsEmpty)
			{
				byteCode.AddRange(m_BytecodeCache[shaderFilePath]);
				return .Ok;
			}

			FileStream fs = scope .();
			if (fs.Open(shaderFilePath) case .Ok)
			{
				List<uint8> data = scope .();
				data.Resize(fs.Length);

				if (fs.TryRead(data) case .Ok)
				{
					byteCode.AddRange(data);

					return .Ok;
				}
			}

			Debug.WriteLine("Couldn't read the binary file for shader {} from {}", fileName, shaderFilePath);
			return .Err;
		}
	}
}