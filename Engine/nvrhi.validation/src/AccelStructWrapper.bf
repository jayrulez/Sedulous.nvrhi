using System.Collections;
using nvrhi.rt;
namespace nvrhi.validation
{
	class AccelStructWrapper :  RefCounter<nvrhi.rt.IAccelStruct>
	{
		public bool isTopLevel = false;
		public bool allowCompaction = false;
		public bool allowUpdate = false;
		public bool wasBuilt = false;

		// BLAS only
		public List<nvrhi.rt.GeometryDesc> buildGeometries;

		// TLAS only
		public int maxInstances = 0;
		public int buildInstances = 0;

		public this(IAccelStruct @as)
		{
			m_AccelStruct = @as;
		}
		public IAccelStruct getUnderlyingObject() { return m_AccelStruct; }

		// IResource

		public override NativeObject getNativeObject(ObjectType objectType)
			{ return m_AccelStruct.getNativeObject(objectType); }

		// IAccelStruct

		public override readonly ref nvrhi.rt.AccelStructDesc getDesc() { return ref m_AccelStruct.getDesc(); }
		public override bool isCompacted()  { return m_AccelStruct.isCompacted(); }
		public override uint64 getDeviceAddress()  { return m_AccelStruct.getDeviceAddress(); };

		private nvrhi.rt.AccelStructHandle m_AccelStruct;
	}
}