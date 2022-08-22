using System;
using System.Collections;
namespace nvrhi.shaderCompiler
{
	struct CommandLineOptions
	{
		public String inputFile;
		public String outputPath;
		public List<String> includePaths;
		public List<String> additionalDefines;
	    public List<String> ignoreFileNames;
	    public List<String> additionalCompilerOptions;
		public String compilerPath;
		public CompilerPlatform platform = CompilerPlatform.UNKNOWN;
		public bool parallel = false;
		public bool verbose = false;
		public bool force = false;
		public bool help = false;
		public bool keep = false;
		public int32 vulkanTextureShift = 0;
		public int32 vulkanSamplerShift = 128;
		public int32 vulkanConstantShift = 256;
		public int32 vulkanUavShift = 384;

		public String errorMessage;

		public bool parse(String[] args){
			//Options options = .(args[0]);

			return false;
		}
	}
}