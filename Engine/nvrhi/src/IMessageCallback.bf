namespace nvrhi
{
	// IMessageCallback should be implemented by the application.
	abstract class IMessageCallback
	{
	    // NVRHI will call message(...) whenever it needs to signal something.
	    // The application is free to ignore the messages, show message boxes, or terminate.
	    public abstract void message(MessageSeverity severity, char8* messageText);
	}
}