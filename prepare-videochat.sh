#!/bin/bash

# Script for using IP Webcam as a microphone/webcam in Ubuntu 11.04
# Copyright (C) 2011 Antonio García Domínguez
# Licensed under GPLv3

# Exit on first error
set -e

### CONFIGURATION

# If your "adb" is not in your $PATH, set the full path to it here.
# If "adb" is in your $PATH, you don't have to change this option.
ADB_PATH=~/bin/android-sdk-linux_x86/platform-tools/adb
if which adb; then
    ADB=$(which adb)
else
    ADB=$ADB_PATH
fi

# IP used by the phone in your wireless network
WIFI_IP=192.168.2.122

# Port on which IP Webcam is listening
PORT=8080

# URL on which the latest v4l2loopback DKMS .deb can be found
V4L2LOOPBACK_DEB_URL=http://ftp.us.debian.org/debian/pool/main/v/v4l2loopback/v4l2loopback-dkms_0.4.0-1_all.deb

# Path to which the v4l2loopback DKMS .deb should be saved
V4L2LOOPBACK_DEB_PATH=/tmp/v4l2loopback-dkms.deb

### FUNCTIONS

has_kernel_module() {
    sudo modprobe -q "$1"
}

error() {
    zenity --error --text "$@"
    exit 1
}

warning() {
    zenity --warning --text "$@"
}

info() {
    zenity --info --text "$@"
}

confirm() {
    zenity --question --text "$@"
}

can_run() {
    # It's either the path to a file, or the name of an executable in $PATH
    (test -x "$1" || which "$1") >/dev/null
}

start_adb() {
    can_run "$ADB" && "$ADB" start-server
}

phone_plugged() {
    start_adb && test "$("$ADB" get-state)" == "device"
}

url_reachable() {
    curl -sI "$1" >/dev/null
}

send_intent() {
    start_adb && "$ADB" shell am start -a android.intent.action.MAIN -n $@
}

iw_server_is_started() {
    url_reachable "$VIDEO_URL"
}

start_iw_server() {
    send_intent com.pas.webcam/.Rolling
    sleep 2s
}

### MAIN BODY

# Check if the user has v4l2loopback
if ! has_kernel_module v4l2loopback; then
    info "The v4l2loopback kernel module is not installed or could not be loaded. I will try to install the kernel module using DKMS. If that doesn't work, please install v4l2loopback manually from github.com/umlaeute/v4l2loopback."
    sudo apt-get install dkms
    wget "$V4L2LOOPBACK_DEB_URL" -O "$V4L2LOOPBACK_DEB_PATH"
    sudo dpkg -i "$V4L2LOOPBACK_DEB_PATH"
    if has_kernel_module v4l2loopback; then
	info "The v4l2loopback kernel module was installed successfully."
    fi
fi

# Decide whether to connect through USB or through wi-fi
IP=$WIFI_IP
if ! can_run "$ADB"; then
    warning "adb is not available: you'll have to use Wi-Fi, which will be slower. Next time, please install the Android SDK from developer.android.com/sdk."
else
    while ! phone_plugged && ! confirm "adb is available, but the phone is not plugged in. Are you sure you want to use Wi-Fi (slower)? If you don't, please connect your phone to USB."; do
	true
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
if phone_plugged && ! iw_server_is_started; then
    # If the phone is plugged to USB and we have ADB, we can start the server by sending an intent
    start_iw_server
fi
while ! iw_server_is_started; do
    info "The IP Webcam video feed is not reachable at $VIDEO_URL. Please open IP Webcam in your phone and start the server."
done

# Load null-sink if needed
if !(pactl list | grep -q module-null-sink); then
    pactl load-module module-null-sink
fi

# Install and open pavucontrol as needed
if ! can_run pavucontrol; then
    info "You don't have pavucontrol. I'll try to install its Debian/Ubuntu package."
    sudo apt-get install pavucontrol
fi
if ! pgrep pavucontrol; then
    info "We will open now pavucontrol. You should leave it open to change the recording device of your video chat program to 'Monitor Null Output'. NOTE: make sure that in 'Output Devices' *all* devices are listed."
    pavucontrol &
fi

# Check for gst-launch
if ! can_run gst-launch; then
    info "You don't have gst-launch. I'll try to install its Debian/Ubuntu package."
    sudo apt-get install gstreamer-tools
fi

# Start the GStreamer graph needed to grab the video and audio
set +e
info "Using IP Webcam as webcam/microphone. You can now open your videochat app."
gst-launch -v \
    souphttpsrc location="http://$IP:$PORT/videofeed" do-timestamp=true is_live=true \
    ! multipartdemux ! jpegdec ! ffmpegcolorspace ! v4l2sink device=/dev/video0 \
    souphttpsrc location="http://$IP:$PORT/audio.wav" do-timestamp=true is_live=true \
    ! wavparse ! audioconvert ! volume volume=3 ! rglimiter ! pulsesink device=null sync=false \
    2>&1 | tee feed.log
info "Disconnected from IP Webcam. Have a nice day!"
