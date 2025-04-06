# Voice

Some judges may prefer voice input over entering text comments during the event.

Mozilla has a [Web Dictaphone](https://mdn.github.io/dom-examples/media/web-dictaphone/) demo that I can
incorporate into the program.

I'm expecting to use this to enable judges to record separate comments for each couple on the dance floor.
THose recordings will be stored, and can be played back in the studio in the presence of the student.
Options to download the audio can also be provided.

One thing to be aware of is that Apple has unique opinions on preferring proprietary audio formats with
strong commercial protection.  What that means is that audio recorded using Apple's Safari generally can't
directly be played back using other browsers.  Recording made using Firefox can be played back using
CHrome but not by Safari.  Generally it is best if you standardize on a single browser for your studio
if you chose to use this feature.  Picking one of Chrome, Edge, or Firefox provides you the best flexibility.

There are offline tools that I can look into that may help with conversion between these audio formats.
And there are audio formats like MP3 and M4A that look like they will work with any browser.

I'm not currently looking into integrating with any AI transcription services, but that could be a possibility
at some point.

One thing I'm concerned about is that if the audio can't be captured during the event for any reason you
may not be aware of this until after the event.  For this reason, it may be best to try it first with
a smaller event.