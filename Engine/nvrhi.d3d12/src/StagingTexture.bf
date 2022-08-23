using Win32.Graphics.Direct3D12;
using System.Collections;
using System;
namespace nvrhi.d3d12
{
	class StagingTexture : RefCounter<IStagingTexture>
	{
		public TextureDesc desc = .();
		public D3D12_RESOURCE_DESC resourceDesc = .();
		public RefCountPtr<Buffer> buffer;
		public CpuAccessMode cpuAccess = CpuAccessMode.None;
		public List<UINT64> subresourceOffsets;

		public D3D12RefCountPtr<ID3D12Fence> lastUseFence;
		public  uint64 lastUseFenceValue = 0;

		public struct SliceRegion
		{
			// offset and size in bytes of this region inside the buffer
			public int64 offset = 0;
			public int size = 0;

			public D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint = .();
		}

		public SliceRegion mappedRegion = .();
		public CpuAccessMode mappedAccess = CpuAccessMode.None;

		// returns a SliceRegion struct corresponding to the subresource that slice points at
		// note that this always returns the entire subresource
		public SliceRegion getSliceRegion(ID3D12Device* device, TextureSlice slice)
		{
			SliceRegion ret = .();
			readonly UINT subresource = calcSubresource(slice.mipLevel, slice.arraySlice, 0,
				desc.mipLevels, desc.arraySize);

			Runtime.Assert(subresource < subresourceOffsets.Count);

			UINT64 size = 0;
			device.GetCopyableFootprints(resourceDesc, subresource, 1, subresourceOffsets[subresource], &ret.footprint, null, null, &size);
			ret.offset = int64(ret.footprint.Offset);
			ret.size = (.)size;
			return ret;
		}

		// returns the total size in bytes required for this staging texture
		public int getSizeInBytes(ID3D12Device* device)
		{
			// figure out the index of the last subresource
			readonly UINT lastSubresource = calcSubresource(desc.mipLevels - 1, desc.arraySize - 1, 0,
				desc.mipLevels, desc.arraySize);
			Runtime.Assert(lastSubresource < subresourceOffsets.Count);

			// compute size of last subresource
			UINT64 lastSubresourceSize = 0;
			device.GetCopyableFootprints(resourceDesc, lastSubresource, 1, 0,
				null, null, null, &lastSubresourceSize);

			return (.)(subresourceOffsets[lastSubresource] + lastSubresourceSize);
		}

		public void computeSubresourceOffsets(ID3D12Device* device)
		{
			readonly UINT lastSubresource = calcSubresource(desc.mipLevels - 1, desc.arraySize - 1, 0,
				desc.mipLevels, desc.arraySize);

			readonly UINT numSubresources = lastSubresource + 1;
			subresourceOffsets.Resize(numSubresources);

			UINT64 baseOffset = 0;
			for (UINT i = 0; i < lastSubresource + 1; i++)
			{
				UINT64 subresourceSize = 0;
				device.GetCopyableFootprints(resourceDesc, i, 1, 0,
					null, null, null, &subresourceSize);

				subresourceOffsets[i] = baseOffset;
				baseOffset += subresourceSize;
				baseOffset = D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT * ((baseOffset + D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT - 1) / D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
			}
		}

		public override readonly ref TextureDesc getDesc() { return ref desc; }
		public override NativeObject getNativeObject(ObjectType objectType)
		{
			switch (objectType)
			{
			case ObjectType.D3D12_Resource:
				return NativeObject(buffer.resource);
			default:
				return null;
			}
		}
	}
}