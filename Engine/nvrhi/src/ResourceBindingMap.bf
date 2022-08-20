using System.Collections;
namespace nvrhi
{
	// describes a texture binding --- used to manage SRV / VkImageView per texture
	struct TextureBindingKey : TextureSubresourceSet
	{
		public Format format = default;
		public bool isReadOnlyDSV = default;

		public this()
		{
		}

		public this(TextureSubresourceSet b, Format _format, bool _isReadOnlyDSV = false) : base(b)
		{
			format = _format;
			isReadOnlyDSV = _isReadOnlyDSV;
		}

		public static bool operator ==(TextureBindingKey lhs, TextureBindingKey other)
		{
			return lhs.format == other.format &&
				(TextureSubresourceSet)lhs == (TextureSubresourceSet)other &&
				lhs.isReadOnlyDSV == other.isReadOnlyDSV;
		}

		public new int GetHashCode()
		{
			return (int)format
				^ base.GetHashCode()
				^ isReadOnlyDSV ? 1 : 0;
		}
	}

	typealias TextureBindingKey_HashMap<T> = Dictionary<TextureBindingKey, T>;

	struct BufferBindingKey : BufferRange
	{
		Format format = default;
		ResourceType type = default;

		public this()
			{ }

		public this(BufferRange range, Format _format, ResourceType _type) : base(range)
		{
			format = _format;
			type = _type;
		}

		public static bool operator ==(BufferBindingKey lhs, BufferBindingKey other)
		{
			return lhs.format == other.format &&
				lhs.type == other.type &&
				(BufferRange)lhs == (BufferRange)other;
		}

		public new int GetHashCode()
		{
			return (int)format
				^ base.GetHashCode();
		}
	}
}