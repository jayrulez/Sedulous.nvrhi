using System;
using System.Collections;
namespace nvrhi
{
	struct ShaderConstant
	{
		public char8* name;
		public char8* value;
	}

	struct ShaderBlobEntry
	{
		public uint32 permutationSize;
		public uint32 dataSize;
	}

	public static
	{
		public const char8* g_BlobSignature = "NVSP";
		public const int g_BlobSignatureSize = 4;

		public static bool findPermutationInBlob(
			void* blob,
			int blobSize,
			ShaderConstant* constants,
			uint32 numConstants,
			void** pBinary,
			int* pSize)
		{
			if (blob == null || blobSize < g_BlobSignatureSize)
				return false;

			if (pBinary == null || pSize == null)
				return false;

			if (Internal.MemCmp(blob, g_BlobSignature, g_BlobSignatureSize) != 0)
			{
				if (numConstants == 0)
				{
					*pBinary = blob;
					*pSize = blobSize;
					return true; // this blob is not a permutation blob, and no permutation is requested
				}
				else
				{
					return false; // this blob is not a permutation blob, but the caller requested a permutation
				}
			}

			var blob;
			var blobSize;
			blob = (char8*)blob + g_BlobSignatureSize;
			blobSize -= g_BlobSignatureSize;

			String permutation = scope $"";
			for (uint32 n = 0; n < numConstants; n++)
			{
				readonly ref ShaderConstant constant = ref constants[n];

				permutation.AppendF("{}={} ", constant.name, constant.value);
			}

			while (blobSize > sizeof(ShaderBlobEntry))
			{
				readonly ShaderBlobEntry* header = (ShaderBlobEntry*)blob;

				if (header.dataSize == 0)
					return false; // last header in the blob is empty

				if (blobSize < sizeof(ShaderBlobEntry) + header.dataSize + header.permutationSize)
					return false; // insufficient bytes in the blob, cannot continue

				char8* entryPermutation = (char8*)blob + sizeof(ShaderBlobEntry);

				if ((header.permutationSize == permutation.Length) && ((permutation.Length == 0) || String.Compare(entryPermutation, permutation.Ptr, permutation.Length)))
				{
					char8* binary = (char8*)blob + sizeof(ShaderBlobEntry) + header.permutationSize;

					*pBinary = binary;
					*pSize = header.dataSize;
					return true;
				}

				int offset = sizeof(ShaderBlobEntry) + header.dataSize + header.permutationSize;
				blob = (char8*)blob + offset;
				blobSize -= offset;
			}

			return false; // went through the blob, permutation not found
		}

		public static void enumeratePermutationsInBlob(
			void* blob,
			int blobSize,
			List<String> permutations)
		{
			if (blob == null || blobSize < g_BlobSignatureSize)
				return;

			if (Internal.MemCmp(blob, g_BlobSignature, g_BlobSignatureSize) != 0)
				return;

			var blob;
			var blobSize;
			blob = (char8*)blob + g_BlobSignatureSize;
			blobSize -= g_BlobSignatureSize;

			while (blobSize > sizeof(ShaderBlobEntry))
			{
				readonly ShaderBlobEntry* header = (ShaderBlobEntry*)blob;

				if (header.dataSize == 0)
					return;

				if (blobSize < sizeof(ShaderBlobEntry) + header.dataSize + header.permutationSize)
					return;

				if (header.permutationSize > 0)
				{
					String permutation = new .();
					char8* p = scope char8[header.permutationSize]*;
					Internal.MemCpy(p, (char8*)blob + sizeof(ShaderBlobEntry), header.permutationSize);
					permutation.Set(scope .(p));

					permutations.Add(permutation);
				}
				else
				{
					permutations.Add("<default>");
				}

				int offset = sizeof(ShaderBlobEntry) + header.dataSize + header.permutationSize;
				blob = (char8*)blob + offset;
				blobSize -= offset;
			}
		}

		public static void formatShaderNotFoundMessage(
			void* blob,
			int blobSize,
			ShaderConstant* constants,
			uint32 numConstants, String message)
		{
			message.Append("Couldn't find the required shader permutation in the blob, or the blob is corrupted.\nRequired permutation key: \n");

			if (numConstants > 0)
			{
				for (uint32 n = 0; n < numConstants; n++)
				{
					readonly ref ShaderConstant constant = ref constants[n];
					message.AppendF("{}={};", constant.name, constant.value);
				}
			}
			else
			{
				message.Append("<default>");
			}

			message.Append("\n");

			List<String> permutations = scope .();
			enumeratePermutationsInBlob(blob, blobSize, permutations);

			if (!permutations.IsEmpty)
			{
				message.Append("Permutations available in the blob:\n");
				for (String key in permutations)
					message.AppendF("{}\n", key);
			}
			else
			{
				message.Append("No permutations found in the blob.");
			}
		}

		public static ShaderHandle createShaderPermutation(
			IDevice device,
			ShaderDesc d,
			void* blob,
			int blobSize,
			ShaderConstant* constants,
			uint32 numConstants,
			bool errorIfNotFound = true)
		{
			void* binary = null;
			int binarySize = 0;

			if (findPermutationInBlob(blob, blobSize, constants, numConstants, &binary, &binarySize))
			{
				return device.createShader(d, binary, binarySize);
			}

			if (errorIfNotFound)
			{
				String message = formatShaderNotFoundMessage(blob, blobSize, constants, numConstants, .. scope .());
				device.getMessageCallback().message(MessageSeverity.Error, message);
			}

			return null;
		}

		public static ShaderLibraryHandle createShaderLibraryPermutation(
			IDevice device,
			void* blob,
			int blobSize,
			ShaderConstant* constants,
			uint32 numConstants,
			bool errorIfNotFound = true)
		{
			void* binary = null;
			int binarySize = 0;

			if (findPermutationInBlob(blob, blobSize, constants, numConstants, &binary, &binarySize))
			{
				return device.createShaderLibrary(binary, binarySize);
			}

			if (errorIfNotFound)
			{
				String message = formatShaderNotFoundMessage(blob, blobSize, constants, numConstants, .. scope .());
				device.getMessageCallback().message(MessageSeverity.Error, message);
			}

			return null;
		}
	}
}