ipwebcam-gst
============

This is a shell script which allows Android users to use their phones as a webcam/microphone in Linux. The setup is as follows:

* [IP Webcam](https://market.android.com/details?id=com.pas.webcam) (on the phone) serves up a MJPEG live video stream and a WAV live audio stream through HTTP (port 8080 by default).
* If the phone is plugged to USB and ADB is available, the HTTP port in the phone is bridged to the same port in the computer, using ADB port forwarding. This is much faster than using Wi-Fi, and the shell will be able to start the IP Webcam application on the phone directly. The script supports Wi-Fi as well, but it can be rather choppy with bad reception, so I wouldn't recommend it.
* From the local port in the computer, a GStreamer graph takes the MJPEG live video stream and dumps it to a loopback V4L2 device, using [v4l2loopback](https://github.com/umlaeute/v4l2loopback). The audio stream is dumped to a PulseAudio null sink.
* Most videochat software in Linux is compatible with `v4l2loopback`: Skype 2.1 (*not* the latest 2.2, it seems), Cheese, Empathy, Google Talk video chats and Google+ hangouts should work.
* The sound recording device for your videochat application should be changed to the 'Monitor of Null Sink' using `pavucontrol`.

This project includes `prepare-videochat.sh`, which does all these things, except for switching the recording device for your videochat application. It does open `pavucontrol` if it's not running, though. The script installs `v4l2loopback`, the GStreamer tools and the "good" plugins and `pavucontrol` if required, but you will have to install the [Android SDK](http://developer.android.com/sdk) by yourself.

To use this script, simply run it with `./prepare-videochat.sh` and follow instructions. You may have to customize a few variables in the CONFIGURATION section before using it, though. You can also use something like `./prepare-videochat.sh horizontal-flip` to flip the video horizontally, in case you might need it.

Please make sure that audio is enabled on IP Webcam, or the script won't work!

Here's an idea for future work: switch to Python and use the official GStreamer binding. I'd love to see that, but I don't have enough free time :-(.

Disclaimer: the script has only been tested in my local installation of Ubuntu 13.04 and on Arch Linux. I think it should work on most recent Debian-based distributions as well (and Debian, of course). If you need any help, please create an issue on this project.

Note: the v4l2loopback-dkms package seems to be broken in Saucy (13.10), as it refers to an old v4l2loopback release (0.7.0) and not to the latest version as of date (0.8.0). Please install v4l2loopback from its official Github repo.

Note: You can install this script from AUR in Arch Linux. It will resolve all dependencies automatically.
