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

	struct BitSet<TCount> where TCount : const int
	{
		public int Count => TCount;

		private uint8[TCount] mValues = .();

		public bool this[int index]
		{
			get => mValues[index] == 1;
			set mut
			{
				mValues[index] = value ? 1 : 0;
			}
		};

		public bool Any()
		{
			for (int i = 0; i < this.Count; i++)
			{
				if (this[i])
					return true;
			}
			return false;
		}

		public static Self operator &(Self lhs, Self rhs)
		{
			Self value = lhs;

			for (int i = 0; i < value.Count; i++)
			{
				if (value[i] && rhs[i])
					value[i] = true;
				else
					value[i] = false;
			}

			return value;
		}

		public void operator &=(Self rhs) mut
		{
			this = this & rhs;
		}

		public static Self operator |(Self lhs, Self rhs)
		{
			Self value = lhs;

			for (int i = 0; i < value.Count; i++)
			{
				if (rhs[i])
					value[i] = true;
			}

			return value;
		}

		public void operator |=(Self rhs) mut
		{
			this = this | rhs;
		}

		public static Self operator ^(Self lhs, Self rhs)
		{
			Self value = lhs;

			for (int i = 0; i < value.Count; i++)
			{
				if (value[i] == rhs[i])
					value[i] = false;
				else
					value[i] = true;
			}

			return value;
		}

		public void operator ^=(Self rhs) mut
		{
			this = this ^ rhs;
		}

		public static Self operator ~(Self bitSet)
		{
			Self value = bitSet;
			for (int i = 0; i < bitSet.Count; i++)
			{
				value[i] = !bitSet[i];
			}

			return value;
		}

		public static bool operator ==(Self lhs, Self rhs)
		{
			return lhs.mValues == rhs.mValues;
		}

		public static bool operator !=(Self lhs, Self rhs)
		{
			return !(lhs == rhs);
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
			return SRV.Any() || Sampler.Any() || UAV.Any() || CB.Any();
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
			if (bits.Any())
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