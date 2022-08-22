using System.Collections;
using System;
namespace nvrhi.vulkan
{
	class StagingTexture : RefCounter<IStagingTexture>
	{
		public TextureDesc desc;
		// backing store for staging texture is a buffer
		public RefCountPtr<Buffer> buffer;
		// per-mip, per-slice regions
		// offset = mipLevel * numDepthSlices + depthSlice
		public List<StagingTextureRegion> sliceRegions;

		// we follow DX conventions when mapping slices and mip levels:
		// for a 3D or array texture, array layers / 3d depth slices for a given mip slice
		// are consecutive in memory, with padding in between for alignment
		// https://msdn.microsoft.com/en-us/library/windows/desktop/dn705766(v=vs.85).aspx

		// compute the size of a mip level slice
		// this is the size of a single slice of a 3D texture / array for the given mip level
		public int computeSliceSize(uint32 mipLevel)
		{
			readonly ref FormatInfo formatInfo = ref getFormatInfo(desc.format);

			var wInBlocks = (desc.width >> mipLevel) / formatInfo.blockSize;
			var hInBlocks = (desc.height >> mipLevel) / formatInfo.blockSize;

			var blockPitchBytes = (wInBlocks >> mipLevel) * formatInfo.bytesPerBlock;
			return blockPitchBytes * hInBlocks;
		}

		public readonly ref StagingTextureRegion getSliceRegion(uint32 mipLevel, uint32 arraySlice, uint32 z)
		{
			var mipLevel;
			if (desc.depth != 1)
			{
				// Hard case, since each mip level has half the slices @as the previous one.
				Runtime.Assert(arraySlice == 0);
				Runtime.Assert(z < desc.depth);

				uint32 mipDepth = desc.depth;
				uint32 index = 0;
				while (mipLevel-- > 0)
				{
					index += mipDepth;
					mipDepth = Math.Max(mipDepth, uint32(1));
				}
				return ref sliceRegions[index + z];
			}
			else if (desc.arraySize != 1)
			{
				// Easy case, since each mip level has a consistent number of slices.
				Runtime.Assert(z == 0);
				Runtime.Assert(arraySlice < desc.arraySize);
				Runtime.Assert(sliceRegions.Count == desc.mipLevels * desc.arraySize);
				return ref sliceRegions[mipLevel * desc.arraySize + arraySlice];
			}
			else
			{
				Runtime.Assert(arraySlice == 0);
				Runtime.Assert(z == 0);
				Runtime.Assert(sliceRegions.Count == 1);
				return ref sliceRegions[0];
			}
		}
		public void populateSliceRegions()
		{
			int64 curOffset = 0;

			sliceRegions.Clear();

			for (uint32 mip = 0; mip < desc.mipLevels; mip++)
			{
				var sliceSize = computeSliceSize(mip);

				uint32 depth = Math.Max(desc.depth >> mip, uint32(1));
				uint32 numSlices = desc.arraySize * depth;

				for (uint32 slice = 0; slice < numSlices; slice++)
				{
					sliceRegions.Add(.(curOffset, sliceSize));

					// update offset for the next region
					curOffset = alignBufferOffset(int64(curOffset + sliceSize));
				}
			}
		}

		public int getBufferSize()
		{
			Runtime.Assert(sliceRegions.Count > 0);
			int size = sliceRegions.Back.offset + sliceRegions.Back.size;
			Runtime.Assert(size > 0);
			return size;
		}

		public override readonly ref TextureDesc getDesc()  { return ref desc; }
	}
}