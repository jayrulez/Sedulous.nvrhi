namespace System.Collections
{
	extension List<T> where T : struct
	{
		public void Resize(int newSize, T fillValue)
		{
			let currentSize = this.Count;
			this.Count = newSize;
			if (newSize > currentSize)
			{
				for (int i = currentSize; i < newSize; i++)
				{
					this[i] = fillValue;
				}
			}
		}

		public void Fill(T fillValue)
		{
			for (int i = 0; i < Count; i++)
			{
				this[i] = fillValue;
			}
		}
		
		public void Assign(T* ptr, int count)
		{
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
	extension Compiler
	{
		[Comptime(ConstEval = true)]
		public static void Assert(bool cond, String message)
		{
			if (!cond)
				Runtime.FatalError(message);
		}
	}
}