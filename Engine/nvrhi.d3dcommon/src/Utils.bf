using Win32.Foundation;
namespace nvrhi.d3dcommon;

public static
{
	public static bool FAILED(HRESULT res)
	{
		return res != S_OK;
	}

	public static bool SUCCEEDED(HRESULT res)
	{
		return res == S_OK;
	}
}