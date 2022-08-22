using System;
using System.Collections;
using System.Threading;
namespace nvrhi.shaderCompiler.App
{
	struct CompileTask
	{
		public String sourceFile;
		public String shaderName;
		public String entryPoint;
		public String combinedDefines;
		public String commandLine;
	}

	struct BlobEntry
	{
		public String compiledPermutationFile;
		public String permutation;
	}

	class Program
	{
		private static CommandLineOptions g_Options;
		private static String g_PlatformName;

		private static List<CompileTask> g_CompileTasks;
		private static int32 g_OriginalTaskCount;
		//private static atomic<int32> g_ProcessedTaskCount;
		private static int32 g_ProcessedTaskCount;
		private static Monitor g_TaskMutex;
		private static Monitor g_ReportMutex;
		private static bool g_Terminate = false;
		private static bool g_CompileSuccess = true;
		private static DateTime g_ConfigWriteTime;
		private static  Dictionary<String, List<BlobEntry>> g_ShaderBlobs;

		private static Dictionary<String, DateTime> g_HierarchicalUpdateTimes;
		private static List<String> g_IgnoreIncludes;

		private static char8* g_SharedCompilerOptions = "-nologo ";

		public static void Main(String[] args){

		}
	}
}