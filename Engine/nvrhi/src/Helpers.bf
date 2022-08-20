using System;
namespace nvrhi
{
	public static
	{
		public static T align<T>(T size, T alignment) where T : var
		{
			return (size + alignment - 1) & ~(alignment - 1);
		}

		[NoDiscard] public static bool arraysAreDifferent<T, U>(T a, U b)
			where T : var
			where U : var
		{
			if (a.Count != b.Count)
				return true;

			for (uint32 i = 0; i < uint32(a.Count); i++)
			{
				if (a[i] != b[i])
					return true;
			}

			return false;
		}

		[NoDiscard] public static uint32 arrayDifferenceMask<T, U>(T a, U b)
			where T : var
			where U : var
		{
			Runtime.Assert(a.Count <= 32);
			Runtime.Assert(b.Count <= 32);

			if (a.Count != b.Count)
				return ~0u;

			uint32 mask = 0;
			for (uint32 i = 0; i < uint32(a.Count); i++)
			{
				if (a[i] != b[i])
					mask |= (1 << i);
			}

			return mask;
		}

		[Inline] public static uint32 hash_to_u32(int hash)
		{
			return uint32(hash) ^ (uint32(hash >> 32));
		}

		// A type cast that is safer than static_cast in debug builds, and is a simple static_cast in release builds.
		// Used for downcasting various ISomething* pointers to their implementation classes in the backends.
		public static T checked_cast<T, U>(U u) where T : U where U : class
		{
			//Compiler.Assert(typeof(T) is typeof(U)/*, "Redundant checked_cast"*/);
#if DEBUG
			if (u == null) return null;
			T t = u as T;
			if (t == null) Runtime.Assert(false, "Invalid type cast");
			return t;
#else
			return (T)u;
#endif
		}
	}
}