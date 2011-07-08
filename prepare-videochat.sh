#!/bin/sh

# Script for using IP Webcam as a microphone/webcam in Ubuntu 11.04
# Copyright (C) 2010 Antonio García Domínguez
# Licensed under GPLv3

set -e

### CONFIGURATION START

# Path to "adb" in the Android SDK
ADB=~/bin/android-sdk-linux_x86/platform-tools/adb

# IP used by the phone in your wireless network
WIFI_IP=192.168.2.122

# Port on which IP Webcam is listening
PORT=8080

### CONFIGURATION END

# Decide whether to connect through USB or through wi-fi
if zenity --question --text "Is the phone plugged to a USB port?"; then
    "$ADB" forward tcp:$PORT tcp:$PORT
    IP=127.0.0.1
else
    IP=$WIFI_IP
fi

# Remind the user to open up IP Webcam and start the server
zenity --info --text "Now open IP Webcam in your phone and start the server."

# Install and open pavucontrol as needed
if ! type pavucontrol; then
    zenity --info --text "You don't have pavucontrol. I'll try to install its Ubuntu package."
    sudo apt-get install pavucontrol
fi
if ! pgrep pavucontrol; then
    zenity --info --text "We will open now pavucontrol. You should leave it open to change the recording device of your video chat program to 'Monitor Null Output'. NOTE: make sure that in 'Output Devices' *all* devices are listed."
    pavucontrol &
fi

# Load null-sink if needed
if !(pactl list | grep -q module-null-sink); then
    pactl load-module module-null-sink
fi

# Start up the required GStreamer graph
if ! type gst-launch; then
    zenity --info --text "You don't have gst-launch. I'll try to install its Ubuntu package."
    sudo apt-get install gstreamer0.10-tools
fi
gst-launch -v \
    souphttpsrc location="http://$IP:$PORT/videofeed" do-timestamp=true is_live=true \
    ! jpegdec ! ffmpegcolorspace ! v4l2sink device=/dev/video0 \
    souphttpsrc location="http://$IP:$PORT/audio.wav" do-timestamp=true is_live=true \
    ! wavparse ! pulsesink device=null sync=false \
    2>&1 | tee feed.log
