#!/bin/bash

# Script for using IP Webcam as a microphone/webcam in Ubuntu 13.04 and Arch
# Copyright (C) 2011-2013 Antonio García Domínguez
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
#
# However, some of these flip methods do not seem to work. In
# particular, those which change the picture size, such as clockwise
# or counterclockwise. *-flip and rotate-180 do work, though.
#
# IMPORTANT: make sure that audio is enabled on IP Webcam, or the script
# will not work! If it works, it should stay open after clicking OK on
# the last message dialog: that's our GStreamer graph processing the
# audio and video from IP Webcam.
#
# TROUBLESHOOTING
#
# 1. Does v4l2loopback work properly?
#
# Try running these commands. You'll first need to install mplayer and
# ensure that your user can write to /dev/video*), and then run these
# commands on one tab:
#
#  sudo modprobe -r v4l2loopback
#  ls /dev/video*
#  (Note down the devices available.)
#  sudo modprobe v4l2loopback
#  ls /dev/video*
#  (Note down the new devices: let X be the number of the first new device.)
#  gst-launch videotestsrc ! v4l2sink device=/dev/videoX
#
# Now go to another tab and use mplayer to play it back:
#
#  mplayer -tv device=/dev/videoX tv://
#
# You should be able to see the GStreamer test video source, which is
# like a TV test card. Otherwise, there's an issue in your v4l2loopback
# installation that you should address before using this script.
#
# 2. Does the video connection work properly?
#
# To make sure the video from IP Webcam works for you (except for
# v4l2loopback and your video conference software), try this command
# with a simplified pipeline:
#
#   gst-launch souphttpsrc location="http://$IP:$PORT/videofeed" \
#               do-timestamp=true is-live=true \
#    ! multipartdemux ! jpegdec ! ffmpegcolorspace ! ximagesink
#
# You should be able to see the picture from your webcam on a new window.
# If that doesn't work, there's something wrong with your connection to
# the phone.
#
# 3. Are you plugging several devices into your PC?
#
# By default, the script assumes you're only plugging one device into
# your computer. If you're plugging in several Android devices to your
# computer, you will first need to tell this script which one should
# be used. Run 'adb devices' with only the desired device plugged in,
# and note down the identifer.
#
# Then, uncomment the line that adds the -s flag to ADB_FLAGS below,
# replacing 'deviceid' with the ID you just found, and run the script
# normally.
#
# --
#
# Last tested with:
# - souphttpsrc version 1.0.6
# - v4l2sink version 1.0.6
# - v4l2loopback version 0.7.0

# Exit on first error
set -e

if [ -n "$1" ]; then
    FLIP_METHOD=$1
else
    FLIP_METHOD=none
fi

GST_FLIP="! videoflip method=\"$FLIP_METHOD\" "
if [ $FLIP_METHOD = 'none' ]; then
    GST_FLIP=""
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

# Flags for ADB.
ADB_FLAGS=
#ADB_FLAGS="$ADB_FLAGS -s deviceid" # use when you need to pick from several devices (check deviceid in 'adb devices')

# IP used by the phone in your wireless network
WIFI_IP=192.168.2.140

# Port on which IP Webcam is listening
PORT=8080


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
    can_run "$ADB" && "$ADB" $ADB_FLAGS start-server
}

phone_plugged() {
    start_adb && test "$("$ADB" $ADB_FLAGS get-state)" = "device"
}

url_reachable() {
    if ! can_run curl && can_run apt-get; then
        # Some versions of Ubuntu do not have curl by default (Arch
        # has it in its core, so we don't need to check that case)
        sudo apt-get install -y curl
    fi
    curl -sI "$1" >/dev/null
}

send_intent() {
    start_adb && "$ADB" $ADB_FLAGS shell am start -a android.intent.action.MAIN -n $@
}

iw_server_is_started() {
    url_reachable "$VIDEO_URL"
}

start_iw_server() {
    send_intent com.pas.webcam/.Rolling
    sleep 2s
}

if can_run lsb_release; then
    DIST=`lsb_release -i | awk -F: '{print $2}'`
    RELEASE=`lsb_release -r | awk -F: '{print $2}'`
elif [ -f /etc/debian_version ] ; then
    DIST="Debian"
    RELEASE=`perl -ne 'chomp; if(m:(jessie|testing|sid):){print "8.0"}elsif(m:[\d\.]+:){print}else{print "0.0"}' < /etc/debian_version`
fi

GST_VER="0.10"
GST_CONVERTER="ffmpegcolorspace"
GST_MIMETYPE="video/x-raw-yuv"
GST_FORMAT="format=(fourcc)YV12"

GST_0_10_MIMETYPE=$GST_MIMETYPE
GST_0_10_FORMAT=$GST_FORMAT

if [ $DIST = "Debian" -a `echo "$RELEASE >= 8.0"   | bc` -eq 1 ] ||\
   [ $DIST = "Ubuntu" -a `echo "$RELEASE >= 14.04" | bc` -eq 1 ]
then
    GST_VER="1.0"
    GST_CONVERTER="videoconvert"
    GST_MIMETYPE="video/x-raw"
    GST_FORMAT="format=YV12"
fi

# GStreamer debug string (see gst-launch manpage)
GST_DEBUG=souphttpsrc:0,videoflip:0,$GST_CONVERTER:0,v4l2sink:0,pulse:0

### MAIN BODY

# Check if the user has v4l2loopback
if ! has_kernel_module v4l2loopback; then
    info "The v4l2loopback kernel module is not installed or could not be loaded. Attempting to install the kernel module using your distro's package manager."
    if [ $DIST = "Debian" ] || [ $DIST = "Ubuntu" ]; then
        V4L2LOOPBACK_PKGS="v4l2loopback-dkms"
        if [ $DIST = "Ubuntu" ]; then
           V4L2LOOPBACK_PKGS="${V4L2LOOPBACK_PKGS} python-apport"
        fi
        sudo apt-get -y install $V4L2LOOPBACK_PKGS
        if [ $? != 0 ]; then
            info "Installation failed.  Please install v4l2loopback manually from github.com/umlaeute/v4l2loopback."
        fi
    elif can_run yaourt; then
        yaourt -S v4l2loopback-git
    fi

    if has_kernel_module v4l2loopback; then
        info "The v4l2loopback kernel module was installed successfully."
    else
        error "Could not install the v4l2loopback kernel module through apt-get or yaourt."
    fi
fi

# check if the user has the pulse gst plugin installed
if [ ! -f /usr/lib/*/gstreamer-$GST_VER/libgstpulse.so ]; then
    if [ $DIST = "Debian" ] || [ $DIST = "Ubuntu" ]; then
        sudo apt-get install -y gstreamer${GST_VER}-pulseaudio
    elif can_run yaourt; then
        echo "we should figure out what package supplies this"
    fi
fi

# Use the first "v4l2 loopback" device as the webcam: this should help
# when loading v4l2loopback on a system that already has a regular
# webcam.
if ! can_run v4l2-ctl; then
    if can_run apt-get; then
        sudo apt-get install -y v4l-utils
    elif can_run pacman; then
        sudo pacman -S v4l-utils
    fi
fi
if can_run v4l2-ctl; then
    for d in /dev/video*; do
        if v4l2-ctl -d "$d" -D | grep -q "v4l2 loopback"; then
            DEVICE=$d
            break
        fi
    done
fi
if [ -z "$DEVICE" ]; then
    DEVICE=/dev/video0
    warning "Could not find the v4l2loopback device: falling back to $DEVICE"
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
        "$ADB" $ADB_FLAGS forward tcp:$PORT tcp:$PORT
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

SINK_NAME="ipwebcam"
# Load null-sink if needed
if !(pactl list sinks | grep -q $SINK_NAME); then
    pactl load-module module-null-sink sink_name="$SINK_NAME" sink_properties="device.description='IP\ Webcam'"
fi
SINK_ID=$(pactl list sinks | sed -n -e "/Owner Module:/h; /$SINK_NAME.monitor/{x; s/\s*Owner Module:\s*//g; p; q}")

#DUPLEX_SINK_NAME="ipwebcam_mic"
#if !(pactl list sinks | grep -q $DUPLEX_SINK_NAME); then
#    pactl load-module module-null-sink sink_name="$DUPLEX_SINK_NAME" sink_properties="device.description='IP\ Webcam\ and\ Mic\ MUX',filter.want=echo-cancel"
#fi
#DUPLEX_SINK_ID=$(pactl list sinks | sed -n -e "/Owner Module:/h; /$DUPLEX_SINK_NAME.monitor/{x; s/\s*Owner Module:\s*//g; p; q}")


#if !(pactl list modules | grep -q "source=${SINK_NAME}.monitor sink=${DUPLEX_SINK_NAME}"); then
#    pactl load-module module-loopback source="${SINK_NAME}.monitor" sink="$DUPLEX_SINK_NAME"
#fi
#SINKMON_LOOP_ID=$(pactl list modules | sed -n -e "/Module #/h; /source=${SINK_NAME}.monitor sink=${DUPLEX_SINK_NAME}/{x; s/\s*Module #\s*//g; p; q}")

DEFAULT_SINK=$(pacmd dump | mawk '/set-default-sink/ {print $2}')
DEFAULT_SOURCE=$(pacmd dump | mawk '/set-default-source/ {print $2}')

#if !(pactl list modules | grep -q "source=${DEFAULT_SINK} sink=${DUPLEX_SINK_NAME}"); then
#if !(pactl list modules | grep -q "source=${DUPLEX_SINK_NAME}.monitor sink=${DEFAULT_SINK}"); then
if !(pactl list modules | grep -q "source=${SINK_NAME}.monitor sink=${DEFAULT_SINK}"); then
#    pactl load-module module-loopback source=${DEFAULT_SINK} sink="$DUPLEX_SINK_NAME"
#    pactl load-module module-loopback source=${DUPLEX_SINK_NAME}.monitor sink="$DEFAULT_SINK"
    pactl load-module module-loopback source=${SINK_NAME}.monitor sink="$DEFAULT_SINK"
fi
#DEFAULT_LOOP_ID=$(pactl list modules | sed -n -e "/Module #/h; /source=${DEFAULT_SOURCE} sink=${DUPLEX_SINK_NAME}/{x; s/\s*Module #\s*//g; p; q}")
#DEFAULT_LOOP_ID=$(pactl list modules | sed -n -e "/Module #/h; /source=${DUPLEX_SINK_NAME}.monitor sink=${DEFAULT_SINK}/{x; s/\s*Module #\s*//g; p; q}")
DEFAULT_LOOP_ID=$(pactl list modules | sed -n -e "/Module #/h; /source=${SINK_NAME}.monitor sink=${DEFAULT_SINK}/{x; s/\s*Module #\s*//g; p; q}")

pactl load-module module-echo-cancel \
      source_name="ipwebcam_efilter" source_master="${SINK_NAME}.monitor" source_properties="device.description='IP\ Webcam\ and\ Mic\ echo\ filter\ source'" \
      sink_name="default_efilter" sink_master="${DEFAULT_SINK}" sink_properties="device.description='IP\ Webcam\ and\ Mic\ echo\ filter\ sink'" \
      aec_method="webrtc" save_aec=1 use_volume_sharing=1

# Install and open pavucontrol as needed
if ! can_run pavucontrol; then
    info "You don't have pavucontrol. I'll try to install its Debian/Ubuntu package."
    sudo apt-get install -y pavucontrol
fi
if ! pgrep pavucontrol; then
    info "We will open now pavucontrol. You should leave it open to change the recording device of your video chat program to 'Monitor IP Webcam'. NOTE: make sure that in 'Output Devices' *all* devices are listed, and in the Playback tab the $GSTLAUNCH program sends its audio to the 'IP Webcam'."
    pavucontrol &
fi

# Check for gst-launch
GSTLAUNCH=gst-launch-${GST_VER}
if [ $DIST = "Debian" ]; then
    # Debian
    if ! can_run "$GSTLAUNCH"; then
        info "You don't have gst-launch. I'll try to install its Debian/Ubuntu package."
        sudo apt-get install -y gstreamer${GST_VER}-tools
    fi
elif can_run pacman; then
    # Arch
    if ! can_run "$GSTLAUNCH"; then
        info "You don't have gst-launch. I'll try to install its Arch package."
        sudo pacman -S gstreamer${GST_VER} gstreamer${GST_VER}-good-plugins
    fi
fi
if ! can_run "$GSTLAUNCH"; then
    error "Could not find gst-launch. Exiting."
    exit 1
fi

# Start the GStreamer graph needed to grab the video and audio
set +e
info "Using IP Webcam as webcam/microphone through v4l2loopback device $DEVICE.  Microphone is directed to $SINK_NAME and multiplexed with ${DEFAULT_SOURCE}. You can now open your videochat app."

WIDTH=640
HEIGHT=480
GST_FPS=5
DIMENSIONS="width=$WIDTH,height=$HEIGHT"

GST_0_10_CAPS="$GST_0_10_MIMETYPE,$GST_0_10_FORMAT,$DIMENSIONS"
CAPS="$GST_MIMETYPE,$GST_FORMAT,$DIMENSIONS,framerate=$GST_FPS/1" \
#sudo v4l2loopback-ctl set-caps $GST_0_10_CAPS $DEVICE

"$GSTLAUNCH" -vt --gst-plugin-spew --gst-debug="$GST_DEBUG" \
  souphttpsrc location="$VIDEO_URL" do-timestamp=true is-live=true \
    ! multipartdemux \
    ! jpegdec \
    $GST_FLIP \
    ! $GST_CONVERTER \
    ! videoscale \
    ! videorate \
    ! $CAPS \
    ! v4l2sink device="$DEVICE" sync=true \
  souphttpsrc location="$AUDIO_URL" do-timestamp=true is-live=true \
    ! wavparse \
    ! audioconvert \
    ! volume volume=3 \
    ! rglimiter \
    ! pulsesink device="$SINK_NAME" sync=true \
    2>&1 | tee feed.log

info "Disconnected from IP Webcam. Have a nice day!"

pactl unload-module ${SINK_ID}
