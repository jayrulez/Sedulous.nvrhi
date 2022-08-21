using System;
using System.Threading;
namespace nvrhi
{
	// ObjectType enum contains identifiers for various object types. 
	// All constants have to be distinct. Implementations of NVRHI may extend the list.
	//
	// The encoding is chosen to minimize potential conflicts between implementations.
	// 0x00aabbcc, where:
	//   aa is GAPI, 1 for D3D11, 2 for D3D12, 3 for VK
	//   bb is layer, 0 for native GAPI objects, 1 for reference NVRHI backend, 2 for user-defined backends
	//   cc is a sequential number
	public enum ObjectType : uint32
	{
	}

	struct NativeObject
	{
		[Union]
		struct Pointer
		{
			public uint64 integer;
			public void* pointer;
		}

		public using private Pointer _;

		public this(uint64 i)
		{
			integer = i;
		}

		public this(void* p)
		{
			pointer = p;
		}

		public static implicit operator Self(void* pointer) => Self(pointer);
	}

	abstract class IResource
	{
		public virtual NativeObject getNativeObject(ObjectType objectType) { (void)objectType; return null; }
	}

	typealias ResourceHandle = RefCountPtr<IResource>;
}

namespace nvrhi
{
	typealias RefCountPtr<T> = T;

	extension IResource
	{
		private uint64 mRefCount = 1;
		private Monitor mRefCountMonitor = new .() ~ delete _;

		public uint64 AddRef()
		{
			using (mRefCountMonitor.Enter())
				return ++mRefCount;
		}

		public uint64 Release()
		{
			using (mRefCountMonitor.Enter())
			{
				uint64 result = --mRefCount;
				if (result == 0)
				{
					delete this;
				}
				return result;
			}
		}

		public Self Value => this;

		public T Get<T>() where T : IResource
		{
			return (T)this;
		}

		public static Self operator ->(Self self)
		{
			return self.Value;
		}

		public static RefCountPtr<T> Attach<T>(T value) where T : IResource
		{
			return value;
		}
	}
}


/*

namespace nvrhi
{

	typealias RefCountPtr<T> = RefCounted<T>;
}

namespace System
{
	extension RefCounted<T> where T : nvrhi.IResource
	{
		public static implicit operator nvrhi.RefCountPtr<T>(T resource)
		{
			return Self.Attach(resource);
		}

		public R Get<R>() where R : T
		{
			return Value;
		}
	}
}

*/