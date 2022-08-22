using System;
namespace nvrhi.device_manager
{
	class DefaultMessageCallback : IMessageCallback
	{
		public override void message(MessageSeverity severity, char8* messageText)
		{
			Console.WriteLine(scope String(messageText));
		}
	}
}