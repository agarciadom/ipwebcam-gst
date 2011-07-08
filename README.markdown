ipwebcam-gst
============

This is a very simple shell script which allows Android users to use their phones as a webcam/microphone in Linux. The setup is slightly contrived, though:

* IP Webcam (on the phone) serves up a MJPEG live video stream and a WAV live audio stream through HTTP (port 8080 by default).
* Port 8080 in the phone is bridged to port 8080 in the computer that the phone is plugged to, using ADB port forwarding. You can use IP Webcam through Wi-Fi, but it's rather choppy, so I wouldn't recommend it.
* From local port 8080, a GStreamer graph takes the MJPEG live video stream and dumps it to a loopback V4L2 device, using [v4l2loopback](https://github.com/umlaeute/v4l2loopback). The audio stream is dumped to a PulseAudio null sink.
* Most videochat software in Linux is compatible with `v4l2loopback`: Skype 2.1 (*not* 2.2, it seems), Cheese, Empathy and the Google Talk video chat plugin should work.
* The monitor source for the null sink can be used as the sound recording device for your videochat application, using `pavucontrol`.

This project includes `prepare-videochat.sh`, which does all these things, except for switching the recording device for your videochat application. It does open `pavucontrol` as needed, though. The script installs the GStreamer tools and `pavucontrol` if needed, but you will have to compile and install the Android SDK and v4l2loopback by yourself.

To use this script, simply run it with `./prepare-videochat.sh` and follow instructions. You may have to customize a few variables in the CUSTOMIZATION section before using it, though.

Disclaimer: the script has only been tested in my local installation of Ubuntu 11.04. I can't really support other distributions, sorry!
