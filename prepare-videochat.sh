#!/bin/bash

# Script for using IP Webcam as a microphone/webcam in Ubuntu 11.04
# Copyright (C) 2011 Antonio García Domínguez
# Licensed under GPLv3

set -e

### CONFIGURATION

# Path to "adb" in the Android SDK
ADB=~/bin/android-sdk-linux_x86/platform-tools/adb

# IP used by the phone in your wireless network
WIFI_IP=192.168.2.122

# Port on which IP Webcam is listening
PORT=8080

### FUNCTIONS

has_kernel_module() {
    modprobe -q "$1"
}

error() {
    zenity --error --text $@
    exit 1
}

warning() {
    zenity --warning --text "$1"
}

info() {
    zenity --info --text "$1"
}

confirm() {
    zenity --question --text "$1"
}

can_run()       {
    type -P "$1" >/dev/null
}

phone_plugged() {
    test "$("$ADB" get-state)" == "device"
}

url_reachable() {
    curl -sI "$1" >/dev/null
}

### MAIN BODY

# Check if the user has v4l2loopback
if ! has_kernel_module v4l2loopback; then
    error "The v4l2loopback kernel module is not installed or could not be loaded. Please install v4l2loopback from github.com/umlaeute/v4l2loopback."
fi

# Decide whether to connect through USB or through wi-fi
IP=$WIFI_IP
if ! can_run "$ADB"; then
    warning "adb is not available: you'll have to use Wi-Fi, which will be slower. Next time, please install the Android SDK from developer.android.com/sdk."
else
    while ! phone_plugged && ! confirm "adb is available, but the phone is not plugged in. Are you sure you want to use Wi-Fi (slower)? If you don't, please connect your phone to USB."; do
	true;
    done
    if phone_plugged; then
	"$ADB" forward tcp:$PORT tcp:$PORT
	IP=127.0.0.1
    fi
fi

# Remind the user to open up IP Webcam and start the server
BASE_URL=http://$IP:$PORT
VIDEO_URL=$BASE_URL/videofeed
AUDIO_URL=$BASE_URL/audio.wav
while ! url_reachable "$VIDEO_URL"; do
    info "The IP Webcam video feed is not reachable at $VIDEO_URL. Please open IP Webcam in your phone and start the server."
done

# Load null-sink if needed
if !(pactl list | grep -q module-null-sink); then
    pactl load-module module-null-sink
fi

# Install and open pavucontrol as needed
if ! can_run pavucontrol; then
    info "You don't have pavucontrol. I'll try to install its Ubuntu package."
    sudo apt-get install pavucontrol
fi
if ! pgrep pavucontrol; then
    info "We will open now pavucontrol. You should leave it open to change the recording device of your video chat program to 'Monitor Null Output'. NOTE: make sure that in 'Output Devices' *all* devices are listed."
    pavucontrol &
fi

# Start up the required GStreamer graph
if ! can_run gst-launch; then
    info "You don't have gst-launch. I'll try to install its Ubuntu package."
    sudo apt-get install gstreamer0.10-tools
fi

set +e
info "Using IP Webcam as webcam/microphone. You can now open your videochat app."
gst-launch -v \
    souphttpsrc location="http://$IP:$PORT/videofeed" do-timestamp=true is_live=true \
    ! multipartdemux ! jpegdec ! ffmpegcolorspace ! v4l2sink device=/dev/video0 \
    souphttpsrc location="http://$IP:$PORT/audio.wav" do-timestamp=true is_live=true \
    ! wavparse ! audioconvert ! volume volume=3 ! rglimiter ! pulsesink device=null sync=false \
    2>&1 | tee feed.log
info "Disconnected from IP Webcam. Have a nice day!"
