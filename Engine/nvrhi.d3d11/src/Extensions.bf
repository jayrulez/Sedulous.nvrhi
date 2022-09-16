namespace Win32.Graphics.Direct3D11
{
	extension D3D11_RENDER_TARGET_BLEND_DESC
	{
		public static bool operator !=(Self lhsrt, Self rhsrt)
		{
			if (lhsrt.BlendEnable != rhsrt.BlendEnable ||
				lhsrt.SrcBlend != rhsrt.SrcBlend ||
				lhsrt.DestBlend != rhsrt.DestBlend ||
				lhsrt.BlendOp != rhsrt.BlendOp ||
				lhsrt.SrcBlendAlpha != rhsrt.SrcBlendAlpha ||
				lhsrt.DestBlendAlpha != rhsrt.DestBlendAlpha ||
				lhsrt.BlendOpAlpha != rhsrt.BlendOpAlpha ||
				lhsrt.RenderTargetWriteMask != rhsrt.RenderTargetWriteMask)
				return true;
			return false;
		}
	}

	extension D3D11_BLEND_DESC
	{
		public static bool operator !=(Self lhs, Self rhs)
		{
			if (lhs.AlphaToCoverageEnable != rhs.AlphaToCoverageEnable ||
				lhs.IndependentBlendEnable != rhs.IndependentBlendEnable)
				return true;
			for (int i = 0; i < lhs.RenderTarget.Count; i++)
			{
				if (lhs.RenderTarget[i] != rhs.RenderTarget[i])
					return true;
			}
			return false;
		}
	}

	extension D3D11_RASTERIZER_DESC
	{
		public static bool operator !=(Self lhs, Self rhs)
		{
			if (lhs.FillMode != rhs.FillMode ||
				lhs.CullMode != rhs.CullMode ||
				lhs.FrontCounterClockwise != rhs.FrontCounterClockwise ||
				lhs.DepthBias != rhs.DepthBias ||
				lhs.DepthBiasClamp != rhs.DepthBiasClamp ||
				lhs.SlopeScaledDepthBias != rhs.SlopeScaledDepthBias ||
				lhs.DepthClipEnable != rhs.DepthClipEnable ||
				lhs.ScissorEnable != rhs.ScissorEnable ||
				lhs.MultisampleEnable != rhs.MultisampleEnable ||
				lhs.AntialiasedLineEnable != rhs.AntialiasedLineEnable)
				return true;

			return false;
		}
	}

	extension D3D11_DEPTH_STENCILOP_DESC
	{
		public static bool operator !=(Self lhs, Self rhs)
		{
			if (lhs.StencilFailOp != rhs.StencilFailOp ||
				lhs.StencilDepthFailOp != rhs.StencilDepthFailOp ||
				lhs.StencilPassOp != rhs.StencilPassOp ||
				lhs.StencilFunc != rhs.StencilFunc)
				return true;
			return false;
		}
	}

	extension D3D11_DEPTH_STENCIL_DESC
	{
		public static bool operator !=(Self lhs, Self rhs)
		{
			if (lhs.DepthEnable != rhs.DepthEnable ||
				lhs.DepthWriteMask != rhs.DepthWriteMask ||
				lhs.DepthFunc != rhs.DepthFunc ||
				lhs.StencilEnable != rhs.StencilEnable ||
				lhs.StencilReadMask != rhs.StencilReadMask ||
				lhs.StencilWriteMask != rhs.StencilWriteMask ||
				lhs.FrontFace != rhs.FrontFace ||
				lhs.FrontFace != rhs.BackFace)
				return true;

			return false;
		}
	}
}