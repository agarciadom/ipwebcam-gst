#!/bin/bash

# Script for using IP Webcam as a microphone/webcam in Ubuntu 11.04 and Arch
# Copyright (C) 2011 Antonio García Domínguez
# Licensed under GPLv3

# Usage: ./prepare-videochat.sh [flip method]
#
# [flip method] is "none" by default. Here are some values you can try
# out (from gst/videofilter/gstvideoflip.c):
#
# - clockwise: clockwise 90 degrees
# - rotate-180: 180 degrees
# - counterclockwise: counter-clockwise 90 degrees
# - horizontal-flip: flip horizontally
# - vertical-flip: flip vertically
# - upper-left-diagonal: flip across upper-left/lower-right diagonal
# - upper-right-diagonal: flip across upper-right/lower-left diagonal

# Exit on first error
set -e

if [ -n "$1" ]; then
    FLIP_METHOD=$1
else
    FLIP_METHOD=none
fi

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
V4L2LOOPBACK_DEB_URL=http://ftp.us.debian.org/debian/pool/main/v/v4l2loopback/v4l2loopback-dkms_0.5.0-1_all.deb

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
    (test -x "$1" || which "$1") &>/dev/null
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
    info "The v4l2loopback kernel module is not installed or could not be loaded. I will try to install the kernel module using your distro's package manager. If that doesn't work, please install v4l2loopback manually from github.com/umlaeute/v4l2loopback."
    if can_run apt-get; then
	sudo apt-get install dkms
	wget "$V4L2LOOPBACK_DEB_URL" -O "$V4L2LOOPBACK_DEB_PATH"
	sudo dpkg -i "$V4L2LOOPBACK_DEB_PATH"
    elif can_run yaourt; then
	yaourt -S gst-v4l2loopback
	yaourt -S v4l2loopback-git
    fi

    if has_kernel_module v4l2loopback; then
	info "The v4l2loopback kernel module was installed successfully."
    else
	error "Could not install the v4l2loopback kernel module through apt-get or yaourt."
    fi
fi

# Use the newest /dev/video* device as the webcam: this should help
# when loading v4l2loopback on a system that already has a regular
# webcam.
DEVICE=$(ls -1t /dev/video* | head -1)

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
GSTLAUNCH=gst-launch
if can_run apt-get; then
    # Debian
    GSTLAUNCH=gst-launch
    if ! can_run "$GSTLAUNCH"; then
	info "You don't have gst-launch. I'll try to install its Debian/Ubuntu package."
	sudo apt-get install gstreamer-tools	
    fi
elif can_run pacman; then
    # Arch
    GSTLAUNCH=gst-launch-0.10
    if ! can_run "$GSTLAUNCH"; then
	info "You don't have gst-launch. I'll try to install its Arch package."
	sudo pacman -S gstreamer0.10 gstreamer0.10-good-plugins
    fi
fi
if ! can_run "$GSTLAUNCH"; then
    error "Could not find gst-launch. Exiting."
    exit 1
fi

# Start the GStreamer graph needed to grab the video and audio
set +e
info "Using IP Webcam as webcam/microphone. You can now open your videochat app."
"$GSTLAUNCH" -evt --gst-plugin-spew \
    souphttpsrc location="http://$IP:$PORT/videofeed" do-timestamp=true is_live=true \
    ! multipartdemux ! jpegdec ! ffmpegcolorspace ! "video/x-raw-yuv, format=(fourcc){YV12}" ! videoflip method="$FLIP_METHOD" ! v4l2sink device="$DEVICE" \
    souphttpsrc location="http://$IP:$PORT/audio.wav" do-timestamp=true is_live=true \
    ! wavparse ! audioconvert ! volume volume=3 ! rglimiter ! pulsesink device=null sync=false \
    2>&1 | tee feed.log
info "Disconnected from IP Webcam. Have a nice day!"
