using System;
using System.Collections;
using System.Threading;
using System.IO;
using System.Diagnostics;
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
		private static CommandLineOptions g_Options = .();
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

		public static void Main(String[] args)
		{
			if (!g_Options.parse(args))
			{
				Console.WriteLine(g_Options.errorMessage);
				//return;
			}

			switch (g_Options.platform)
			{
			case CompilerPlatform.DXBC: g_PlatformName = "DXBC"; break;
			case CompilerPlatform.DXIL: g_PlatformName = "DXIL"; break;
			case CompilerPlatform.SPIRV: g_PlatformName = "SPIR-V"; break;
			case CompilerPlatform.UNKNOWN: g_PlatformName = "UNKNOWN"; break; // never happens
			}

			if (g_Options.ignoreFileNames != null)
			{
				for ( /*readonly ref*/var fileName in /*ref*/ g_Options.ignoreFileNames)
				{
					g_IgnoreIncludes.Add(fileName);
				}
			}

			if (g_Options.inputFile != null)
				g_ConfigWriteTime = File.GetLastWriteTime(g_Options.inputFile);

			// Updated shaderCompiler executable also means everything must be recompiled
			g_ConfigWriteTime = Math.Max(g_ConfigWriteTime, File.GetLastWriteTime(Environment.GetExecutableFilePath(.. scope .())));

			FileStream configFile = new .();
			configFile.Open(g_Options.inputFile);

			var text = File.ReadAllText(g_Options.inputFile, .. scope .());

			var enumerator = text.Split("\n");

			while (enumerator.MoveNext())
			{

			}
		}
	}
}