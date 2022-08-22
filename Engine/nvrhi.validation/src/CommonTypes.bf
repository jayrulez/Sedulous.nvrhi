using System;
namespace nvrhi.validation
{
	struct Range
	{
		public uint32 min = ~0u;
		public uint32 max = 0;

		public void add(uint32 item) mut
		{
			min = Math.Min(min, item);
			max = Math.Max(max, item);
		}
		[NoDiscard] public bool empty()
		{
			return min > max;
		}
		[NoDiscard] public bool overlapsWith(nvrhi.validation.Range other)
		{
			return !empty() && !other.empty() && max >= other.min && min <= other.max;
		}
	}

	struct BitSet<TBits> where TBits : const int
	{
		public int Count => TBits;

		private uint8[TBits] mValues = .();

		public bool this[int index]
		{
			get => mValues[index] == 1;
			set mut
			{
				mValues[index] = value ? 1 : 0;
			}
		};

		public bool any()
		{
			for (int i = 0; i < TBits; i++)
			{
				if (this[i])
					return true;
			}
			return false;
		}

		public Self and(Self other)
		{
			Self value = this;

			for (int i = 0; i < value.Count; i++)
			{
				if (value[i] && other[i])
					value[i] = true;
				else
					value[i] = false;
			}

			return value;
		}

		public ref Self andEqual(Self other) mut
		{
			this = this.and(other);

			return ref this;
		}

		public Self or(Self other)
		{
			Self value = this;

			for (int i = 0; i < value.Count; i++)
			{
				if (other[i])
					value[i] = true;
			}

			return value;
		}

		public ref Self orEqual(Self other) mut
		{
			this = this.or(other);

			return ref this;
		}

		public Self xor(Self other)
		{
			Self value = this;

			for (int i = 0; i < value.Count; i++)
			{
				if (value[i] == other[i])
					value[i] = false;
				else
					value[i] = true;
			}

			return value;
		}

		public ref Self xorEqual(Self other) mut
		{
			this = this.xor(other);

			return ref this;
		}

		public Self complement()
		{
			Self value = this;

			for (int i = 0; i < value.Count; i++)
			{
				value[i] = !this[i];
			}

			return value;
		}
	}

	struct ShaderBindingSet
	{
		public BitSet<128> SRV;
		public BitSet<128> Sampler;
		public BitSet<16> UAV;
		public BitSet<16> CB;
		public uint32 numVolatileCBs = 0;
		public nvrhi.validation.Range rangeSRV;
		public nvrhi.validation.Range rangeSampler;
		public nvrhi.validation.Range rangeUAV;
		public nvrhi.validation.Range rangeCB;

		[NoDiscard] public bool any()
		{
			return SRV.any() || Sampler.any() || UAV.any() || CB.any();
		}

		[NoDiscard] public bool overlapsWith(ShaderBindingSet other)
		{
			return rangeSRV.overlapsWith(other.rangeSRV)
				|| rangeSampler.overlapsWith(other.rangeSampler)
				|| rangeUAV.overlapsWith(other.rangeUAV)
				|| rangeCB.overlapsWith(other.rangeCB);
		}

		public override void ToString(String outStr)
		{
			bool first = true;
			BitsetToStream(SRV, outStr, "t", ref first);
			BitsetToStream(Sampler, outStr, "s", ref first);
			BitsetToStream(UAV, outStr, "u", ref first);
			BitsetToStream(CB, outStr, "b", ref first);
		}
	}

	enum CommandListState
	{
		INITIAL,
		OPEN,
		CLOSED
	}

	public static
	{
		public static IResource unwrapResource(IResource resource)
		{
			if (resource != null)
				return null;

			AccelStructWrapper asWrapper = (AccelStructWrapper)resource;

			if (asWrapper != null)
				return asWrapper.getUnderlyingObject();

			// More resource types to be added here when their wrappers are implemented

			return resource;
		}

		public static void BitsetToStream<N>(BitSet<N> bits, String os, char8* prefix, ref bool first) where N : const int
		{
			if (bits.any())
			{
				for (uint32 slot = 0; slot < bits.Count; slot++)
				{
					if (bits[slot])
					{
						if (!first)
							os.Append(", ");
						os.AppendF("{}{}", prefix, slot);
						first = false;
					}
				}
			}
		}
	}
}