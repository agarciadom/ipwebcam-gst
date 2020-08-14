# ipwebcam-gst

This is a shell script which allows Android users to use their phones as a webcam/microphone in Linux. The setup is as follows:

* [IP Webcam](https://market.android.com/details?id=com.pas.webcam) (on the phone) serves up a MJPEG live video stream and a WAV/Opus live audio stream through HTTP (port 8080 by default).
* If the phone is plugged to USB and ADB is available, the HTTP port in the phone is bridged to the same port in the computer, using ADB port forwarding. This is much faster than using Wi-Fi, and the shell will be able to start the IP Webcam application on the phone directly. The script supports Wi-Fi as well, but it can be rather choppy with bad reception, so I wouldn't recommend it.
* From the local port in the computer, a GStreamer graph takes the MJPEG live video stream and dumps it to a loopback V4L2 device, using [v4l2loopback](https://github.com/umlaeute/v4l2loopback). The audio stream is dumped to a PulseAudio null sink.
* Most videochat software in Linux is compatible with `v4l2loopback`: Skype 2.1 (*not* the latest 2.2, it seems), Cheese, Empathy, Google Talk video chats and Google+ hangouts should work.
* The sound recording device for your videochat application should be changed to the 'Monitor of Null Sink' using `pavucontrol`.

## How to use

First, install all necessary dependencies with:

```sh
sudo ./install-videochat.sh
```

From then onwards, you should be able to bring up the webcam from your regular user account:

```sh
./run-videochat.sh
```

`run-videochat.sh` accepts a number of command-line flags: you can check these with `./run-videochat.sh --help`.

Make sure you switch the recording device for your videochat application. The `install-videochat.sh` script installs `v4l2loopback`, the GStreamer tools and the "good" plugins and `pavucontrol` if required, but you will have to install the [Android SDK](http://developer.android.com/sdk) by yourself.

If you want to avoid using the command-line flags, you can instead customize the variables in the CONFIGURATION section of `run-videochat.sh` before using it.

By default, the script captures both video and audio. If you only want video or audio, you can use the `-v/--video` or `-a/--audio` flags respectively. You can also simply change the value of `CAPTURE_STREAM` inside `run-videochat.sh`. Make sure that IP Webcam is streaming the corresponding streams: otherwise, the script won't work!

## Future work

Ideas for future work:
* switch to Python and use the official GStreamer binding. I'd love to see that, but I don't have enough free time :-(.
* make a separated config file (system-wide and user-defined)

If you need help with the script, feel free to add an issue. Pull requests are welcome!
