# Logging

Every access to the application is logged.  Generally this occurs when you
click a button or follow a link.

Logs include failed access attempts, and include ip addresses.

An example of a log entry can be found at [Debugging Rails Applications](https://guides.rubyonrails.org/debugging_rails_applications.html#sending-messages).  Scroll until you find
"Here's an example of the log generated when this controller action is executed:"

I routinely scan the logs looking for suspicious activity and application failures.