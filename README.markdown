ipwebcam-gst
============

This is a shell script which allows Android users to use their phones as a webcam/microphone in Linux. The setup is as follows:

* [IP Webcam](https://market.android.com/details?id=com.pas.webcam) (on the phone) serves up a MJPEG live video stream and a WAV live audio stream through HTTP (port 8080 by default).
* If the phone is plugged to USB and ADB is available, the HTTP port in the phone is bridged to the same port in the computer, using ADB port forwarding. This is much faster than using Wi-Fi, and the shell will be able to start the IP Webcam application on the phone directly. The script supports Wi-Fi as well, but it can be rather choppy with bad reception, so I wouldn't recommend it.
* From the local port in the computer, a GStreamer graph takes the MJPEG live video stream and dumps it to a loopback V4L2 device, using [v4l2loopback](https://github.com/umlaeute/v4l2loopback). The audio stream is dumped to a PulseAudio null sink.
* Most videochat software in Linux is compatible with `v4l2loopback`: Skype 2.1 (*not* the latest 2.2, it seems), Cheese, Empathy and the Google Talk video chat plugin should work.
* The sound recording device for your videochat application should be changed to the 'Monitor of Null Sink' using `pavucontrol`.

This project includes `prepare-videochat.sh`, which does all these things, except for switching the recording device for your videochat application. It does open `pavucontrol` if needed, though. The script installs `v4l2loopback`, the GStreamer tools and `pavucontrol` if required, but you will have to install the [Android SDK](http://developer.android.com/sdk) by yourself.

To use this script, simply run it with `./prepare-videochat.sh` and follow instructions. You may have to customize a few variables in the CUSTOMIZATION section before using it, though.

Disclaimer: the script has only been tested in my local installation of Ubuntu 11.04. I think it should work on most recent Debian-based distributions as well (and Debian, of course). If you need any help, drop me a direct message on Twitter at @antoniogado.
