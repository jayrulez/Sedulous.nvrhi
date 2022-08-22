using System;
namespace nvrhi.deviceManager
{
	class DefaultMessageCallback : IMessageCallback
	{
		public override void message(MessageSeverity severity, char8* messageText)
		{
			Console.WriteLine(scope String(messageText));
		}
	}
}