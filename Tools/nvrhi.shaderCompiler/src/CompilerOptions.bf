using System;
using System.Collections;
namespace nvrhi.shaderCompiler
{
	struct CompilerOptions
	{
		public String shaderName;
		public String entryPoint;
		public String target;
		public String outputPath;
		public List<String> definitions;

		public String errorMessage;

		/*public bool parse(String line){

		}*/
	}
}