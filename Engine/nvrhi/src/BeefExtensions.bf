namespace System.Collections
{
	extension List<T> where T : struct
	{
		public void Assign(T* ptr, int count)
		{
			//Set(Span<T>(ptr, count));
			Resize(count);

			for (int i = 0; i < Count; i++)
			{
				this[i] = ptr[i];
			}
		}
	}
}

namespace System
{
	extension String
	{
		public static bool Compare(char8* lhs, char8* rhs, int length)
		{
			return EqualsHelper(lhs, rhs, length);
		}
	}
}