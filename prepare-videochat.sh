#!/bin/bash

# Script for using IP Webcam as a microphone/webcam in Debian Jessie,
# Ubuntu 13.04, 14.04, 16.04 and Arch Linux

# Copyright (C) 2011-2013 Antonio García Domínguez
# Copyright (C) 2016 C.J. Adams-Collier
# Copyright (C) 2016 Laptander
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
# To be able to use audio from your phone as a virtual microphone, open pavucontrol,
# then open Playback tab and choose 'IP Webcam' for gst-launch-1.0 playback Stream.
# Then to use audio stream in Audacity, open it and press record button or click on
# the Recording Meter Toolbar to start monitoring, then go to pavucontrol's Recording tab
# and choose "Monitor of IP Webcam" for ALSA plug-in [audacity].
# If you want to be able to hear other applications sounds, for example from web-browser,
# then while it is playing some sound, go to pavucontrol's Playback tab and choose your
# default sound card for web-browser.

#
# INSTALLATION
#
# In Arch Linux
# install ipwebcam-gst-git package from AUR
#
# TROUBLESHOOTING
#
# 1. Does v4l2loopback work properly?
#
# Try running these commands. You'll first need to install mplayer and
# ensure that your user can write to /dev/video*).
#
#  sudo modprobe -r v4l2loopback
#  ls /dev/video*
#  (Note down the devices available.)
#  sudo modprobe v4l2loopback
#  ls /dev/video*
#  (Note down the new devices: let X be the number of the first new device.)
#  v4l2-ctl -D -d /dev/videoX
#  gst-launch videotestsrc ! v4l2sink device=/dev/videoX & mplayer -tv device=/dev/videoX tv://
#
#
# You should be able to see the GStreamer test video source, which is
# like a TV test card. Otherwise, there's an issue in your v4l2loopback
# installation that you should address before using this script.
#
# 2. Does the video connection work properly?
#
# To make sure the video from IP Webcam works for you (except for
# v4l2loopback and your video conference software), try this command
# with a simplified pipeline (do not forget to replace $IP and $PORT
# with your values):
#
# on Debian:
#   gst-launch souphttpsrc location="http://$IP:$PORT/videofeed" \
#               do-timestamp=true is-live=true \
#    ! multipartdemux ! jpegdec ! ffmpegcolorspace ! ximagesink
#
# on Arch Linux:
#   gst-launch-1.0 souphttpsrc location="http://$IP:$PORT/videofeed" \
#               do-timestamp=true is-live=true \
#    ! multipartdemux ! jpegdec ! videoconvert ! ximagesink
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
if which adb > /dev/null ; then
    ADB=$(which adb)
else
    ADB=$ADB_PATH
fi

# Flags for ADB.
ADB_FLAGS=
#ADB_FLAGS="$ADB_FLAGS -s deviceid" # use when you need to pick from several devices (check deviceid in 'adb devices')

# idea: make ability to choose IP version (usefull for IPv6-only environment)
# IP_VERSION=4

# IP used by the phone in your wireless network
WIFI_IP=192.168.2.140

# Port on which IP Webcam is listening
PORT=8080

# Dimensions of video
WIDTH=640
HEIGHT=480

# Frame rate of video
GST_FPS=5

# Choose audio codec from wav, aac or opus
# do not choose opus until editing pipeline. If choose opus, pipeline will not work
# and some errors will appear in feed.log.
# I do not know how to edit pipelines for now.
AUDIO_CODEC=wav

# Choose which stream to capture.
#  a - audio only, v - video only, av - audio and video.
# Make sure that IP webcam is streaming corresponding streams, otherwise error will occur.
CAPTURE_STREAM=av

### FUNCTIONS

has_kernel_module() {
    # Checks if module exists in system (but does not load it)
    MODULE="$1"
    if lsmod | grep "$MODULE" >/dev/null 2>/dev/null; then
        # echo "$MODULE is loaded! So it exists."
        return 0
    else
       # Determining kernel object existence
       # I do not know why, but using -q in egrep makes it always return 1, so do not use it
       if [ `find /lib/modules/$(uname -r)/ -name "$MODULE.ko" | egrep '.*'` ]; then
        return 0
       else
        return 1
       fi
    fi

}

error() {
    zenity --error --text "$@" > /dev/null 2>&1
    exit 1
}

warning() {
    zenity --warning --text "$@" > /dev/null 2>&1
}

info() {
    zenity --info --text "$@" > /dev/null 2>&1
}

confirm() {
    zenity --question --text "$@" > /dev/null 2>&1
}

can_run() {
    # It's either the path to a file, or the name of an executable in $PATH
    which "$1" >/dev/null 2>/dev/null
}

install_package() {
    if [ $DIST = "Debian" ] || [ $DIST = "Ubuntu" ] || [ $DIST = "LinuxMint" ]; then
        echo "Trying to install $1 package."
        sudo apt-get install -y "$1"
    elif [ $DIST = "Arch" ]; then
        error "Please install $1 package"
    fi
}

start_adb() {
    can_run "$ADB" && "$ADB" $ADB_FLAGS start-server
}

stop_adb() {
    can_run "$ADB" && "$ADB" $ADB_FLAGS kill-server
}

phone_plugged() {
    test "$("$ADB" $ADB_FLAGS get-state)" = "device"
}

url_reachable() {
    if ! can_run curl && can_run apt-get; then
        # Some versions of Ubuntu do not have curl by default (Arch
        # has it in its core, so we don't need to check that case)
        sudo apt-get install -y curl
    fi
    curl -m 5 -sI "$1" >/dev/null
}

send_intent() {
    "$ADB" $ADB_FLAGS shell am start -a android.intent.action.MAIN -n $@
}


iw_server_is_started() {
    # todo: should check not just reachable, but if is not 404 page
    # otherwise if ip webcam is streaming a, but script expects av,
    # it will display that all ok, but actually not working.
    if [ $CAPTURE_STREAM = av ]; then
      : # help me optimize this code
	temp=$(url_reachable "$AUDIO_URL"); au=$?; #echo au=$au
	temp=$(url_reachable "$VIDEO_URL"); vu=$?; #echo vu=$vu
	if [ $au = 0 -a $vu = 0 ]; then return 0; else return 1; fi
    elif [ $CAPTURE_STREAM = a ]; then
	if url_reachable "$AUDIO_URL"; then return 0; else return 1; fi
    elif [ $CAPTURE_STREAM = v ]; then
	if url_reachable "$VIDEO_URL"; then return 0; else return 1; fi
    else
	error "Incorrect CAPTURE_STREAM value ($CAPTURE_STREAM). Should be a, v or av."
    fi
    echo You are in error; return 1
}

start_iw_server() {
    send_intent com.pas.webcam/.Rolling
    sleep 2s
}

module_id_by_sinkname() {
    pacmd list-sinks | grep -e 'name:' -e 'module:' | grep -A1 "name: <$1>" | grep module: | cut -f2 -d: | tr -d ' '
}

# is this function needed somewhere?
module_id_by_sourcename() {
    pacmd list-sources | grep -e 'name:' -e 'module:' | grep -A1 "name: <$1>" | grep module: | cut -f2 -d: | tr -d ' '
}


if can_run lsb_release; then
    DIST=`lsb_release -i | cut -f2 -d ":"`
    RELEASE=`lsb_release -r | cut -f2 -d ":"`
elif [ -f /etc/debian_version ] ; then
    DIST="Debian"
    RELEASE=`perl -ne 'chomp; if(m:(jessie|testing|sid):){print "8.0"}elsif(m:[\d\.]+:){print}else{print "0.0"}' < /etc/debian_version`
fi

GST_VER="0.10"
GST_VIDEO_CONVERTER="ffmpegcolorspace"
GST_VIDEO_MIMETYPE="video/x-raw-yuv"
GST_VIDEO_FORMAT="format=(fourcc)YV12"

GST_AUDIO_MIMETYPE="audio/x-raw-int"
GST_AUDIO_FORMAT="width=16,depth=16,endianness=1234,signed=true"
GST_AUDIO_RATE="rate=44100"
GST_AUDIO_CHANNELS="channels=1"
GST_AUDIO_LAYOUT=""

GST_1_0_AUDIO_FORMAT="format=S16LE"
GST_0_10_VIDEO_MIMETYPE=$GST_VIDEO_MIMETYPE
GST_0_10_VIDEO_FORMAT=$GST_VIDEO_FORMAT

if [ $DIST = "Debian" -a `echo "$RELEASE >= 8.0"   | bc` -eq 1 ] ||\
   [ $DIST = "Ubuntu" -a `echo "$RELEASE >= 14.04" | bc` -eq 1 ] ||\
   [ $DIST = "Arch" ]
then
    GST_VER="1.0"
    GST_VIDEO_CONVERTER="videoconvert"
    GST_VIDEO_MIMETYPE="video/x-raw"
    GST_VIDEO_FORMAT="format=YV12"

    GST_AUDIO_MIMETYPE="audio/x-raw"
    GST_AUDIO_FORMAT=$GST_1_0_AUDIO_FORMAT
    GST_AUDIO_LAYOUT=",layout=interleaved"
fi

DIMENSIONS="width=$WIDTH,height=$HEIGHT"

GST_0_10_VIDEO_CAPS="$GST_0_10_VIDEO_MIMETYPE,$GST_0_10_VIDEO_FORMAT,$DIMENSIONS"
GST_VIDEO_CAPS="$GST_VIDEO_MIMETYPE,$GST_VIDEO_FORMAT,$DIMENSIONS,framerate=$GST_FPS/1"
GST_AUDIO_CAPS="$GST_AUDIO_MIMETYPE,$GST_AUDIO_FORMAT$GST_AUDIO_LAYOUT,$GST_AUDIO_RATE,$GST_AUDIO_CHANNELS"
PA_AUDIO_CAPS="$GST_AUDIO_FORMAT $GST_AUDIO_RATE $GST_AUDIO_CHANNELS"

# GStreamer debug string (see gst-launch manpage)
GST_DEBUG=souphttpsrc:0,videoflip:0,$GST_CONVERTER:0,v4l2sink:0,pulse:0
# Is $GST_CONVERTER defined anywhere? Maybe you mean videoconvert vs ffmpegcolorspace? It is in GST_VIDEO_CONVERTER

### MAIN BODY


if ! can_run zenity; then
    install_package zenity
fi

# Check if the user has v4l2loopback
if ! has_kernel_module v4l2loopback; then
    if [ $DIST = "Debian" ] || [ $DIST = "Ubuntu" ] || [ $DIST = "Arch" ]; then
        install_package "v4l2loopback-dkms"
        if [ $DIST = "Ubuntu" ]; then
           install_package "python-apport"
        fi

        if [ $? != 0 ]; then
            info "Installation failed.  Please install v4l2loopback manually from github.com/umlaeute/v4l2loopback."
        fi
    fi

    if has_kernel_module v4l2loopback; then
        info "The v4l2loopback kernel module was installed successfully."
    else
        error "Could not install the v4l2loopback kernel module through apt-get."
    fi
fi

# Probe module if not probed yet
if lsmod | grep v4l2loopback >/dev/null 2>/dev/null; then
    # module is already loaded, do nothing
    :
elif [ $CAPTURE_STREAM = v -o $CAPTURE_STREAM = av ]; then
    echo Loading module
    sudo modprobe v4l2loopback #-q > /dev/null 2>&1
fi

# check if the user has the pulse gst plugin installed
if find "/usr/lib/gstreamer-$GST_VER/libgstpulse.so" "/usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgstpulse.so" 2>/dev/null | egrep -q '.*'; then
    # plugin installed, do nothing
    # info "Found the pulse gst plugin"
    :
else
    if [ $DIST = "Debian" ] || [ $DIST = "Ubuntu" ]; then
        install_package "gstreamer${GST_VER}-pulseaudio"
    elif [ $DIST = "Arch" ]; then
        install_package "gst-plugins-good"
    fi
fi

# Use the first "v4l2 loopback" device as the webcam: this should help
# when loading v4l2loopback on a system that already has a regular
# webcam.
if ! can_run v4l2-ctl; then
    install_package v4l-utils
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
    warning "adb is not available: you'll have to use Wi-Fi, which will be slower. Next time, please install the Android SDK from developer.android.com/sdk or install adb package in Ubuntu"
else
    while ! phone_plugged && ! confirm "adb is available, but the phone is not plugged in. Are you sure you want to use Wi-Fi (slower)?\nIf you don't, please connect your phone to USB and allow usb debugging under developer settings."; do
        true
        sleep 1;
    done
    if phone_plugged; then
        "$ADB" $ADB_FLAGS forward tcp:$PORT tcp:$PORT
        IP=127.0.0.1
    fi
fi

BASE_URL=http://$IP:$PORT
VIDEO_URL=$BASE_URL/videofeed
AUDIO_URL=$BASE_URL/audio.$AUDIO_CODEC

# start adb daemon to avoid relaunching it in while
if can_run "$ADB"; then
  start_adb
fi

# Remind the user to open up IP Webcam and start the server
if phone_plugged && ! iw_server_is_started; then
    # If the phone is plugged to USB and we have ADB, we can start the server by sending an intent
    start_iw_server
fi

while ! iw_server_is_started; do
      if [ $CAPTURE_STREAM = av ]; then
	MESSAGE="The IP Webcam audio feed is not reachable at $AUDIO_URL.\nThe IP Webcam video feed is not reachable at $VIDEO_URL."
      elif [ $CAPTURE_STREAM = a ]; then
	  MESSAGE="The IP Webcam audio feed is not reachable at $AUDIO_URL."
      elif [ $CAPTURE_STREAM = v ]; then
	  MESSAGE="The IP Webcam video feed is not reachable at $VIDEO_URL."
      else
	  error "Incorrect CAPTURE_STREAM value ($CAPTURE_STREAM). Should be a, v or av."
      fi
    info "$MESSAGE\nPlease install and open IP Webcam in your phone and start the server.\nMake sure that values of variables IP, PORT, CAPTURE_STREAM in this script are equal with settings in IP Webcam."
done

# idea: check if default-source is correct. If two copy of script are running,
# then after ending first before second you will be set up with $SINK_NAME.monitor,
# but not with your original defauld source.
# The same issue if script was not end correctly, and you restart it.
DEFAULT_SINK=$(pacmd dump | grep set-default-sink | cut -f2 -d " ")
DEFAULT_SOURCE=$(pacmd dump | grep set-default-source | cut -f2 -d " ")

SINK_NAME="ipwebcam"
SINK_ID=$(module_id_by_sinkname $SINK_NAME)
ECANCEL_ID=$(module_id_by_sinkname "${SINK_NAME}_echo_cancel")

# Registering audio device if not yet registered
if [ -z $SINK_ID ] ; then
    SINK_ID=$(pactl load-module module-null-sink \
                    sink_name="$SINK_NAME" \
                    $PA_AUDIO_CAPS \
                    sink_properties="device.description='IP\ Webcam'")
fi

if [ -z $ECANCEL_ID ] ; then
    ECANCEL_ID=$(pactl load-module module-echo-cancel \
                       sink_name="${SINK_NAME}_echo_cancel" \
                       source_master="$SINK_NAME.monitor" \
                       sink_master="$DEFAULT_SINK" \
                       $PA_AUDIO_CAPS \
                       aec_method="webrtc" save_aec=true use_volume_sharing=true) || true
fi

pactl set-default-source $SINK_NAME.monitor

# Check for gst-launch
GSTLAUNCH=gst-launch-${GST_VER}
if [ $DIST = "Debian" ] || [ $DIST = "Ubuntu" ]; then
    if ! can_run "$GSTLAUNCH"; then
        install_package gstreamer${GST_VER}-tools
    fi
elif  [ $DIST = "Arch" ]; then
    if ! can_run "$GSTLAUNCH"; then
        error "You don't have gst-launch. Please install gstreamer and gst-plugins-good packages."
    fi
fi
if ! can_run "$GSTLAUNCH"; then
    error "Could not find gst-launch. Exiting."
    # exit 1 # you have already exited after error function.
fi

# Start the GStreamer graph needed to grab the video and audio
set +e

#sudo v4l2loopback-ctl set-caps $GST_0_10_VIDEO_CAPS $DEVICE

pipeline_video() {
  echo souphttpsrc location="$VIDEO_URL" do-timestamp=true is-live=true \
    ! multipartdemux \
    ! jpegdec \
    $GST_FLIP \
    ! $GST_VIDEO_CONVERTER \
    ! videoscale \
    ! videorate \
    ! $GST_VIDEO_CAPS \
    ! v4l2sink device="$DEVICE" sync=true
}

pipeline_audio() {
  echo souphttpsrc location="$AUDIO_URL" do-timestamp=true is-live=true \
    ! $GST_AUDIO_CAPS ! queue \
    ! pulsesink device="$SINK_NAME" sync=true
}

if [ $CAPTURE_STREAM = av ]; then
    PIPELINE="$( pipeline_audio )  $( pipeline_video )"
elif [ $CAPTURE_STREAM = a ]; then
    PIPELINE=$( pipeline_audio )
elif [ $CAPTURE_STREAM = v ]; then
    PIPELINE=$( pipeline_video )
else
    error "Incorrect CAPTURE_STREAM value ($CAPTURE_STREAM). Should be a, v or av."
fi

# echo "$PIPELINE"

"$GSTLAUNCH" -e -vt --gst-plugin-spew \
             --gst-debug="$GST_DEBUG" \
   $PIPELINE \
    >feed.log 2>&1 &
    # Maybe we need edit this pipeline to transfer it to "Monitor of IP Webcam" to be able to use it as a microphone?

GSTLAUNCH_PID=$!

if [ $CAPTURE_STREAM = av ]; then
   MESSAGE="IP Webcam audio is streaming through pulseaudio sink '$SINK_NAME'.\nIP Webcam video is streaming through v4l2loopback device $DEVICE.\n"
elif [ $CAPTURE_STREAM = a ]; then
    MESSAGE="IP Webcam audio is streaming through pulseaudio sink '$SINK_NAME'.\n"
elif [ $CAPTURE_STREAM = v ]; then
    MESSAGE="IP Webcam video is streaming through v4l2loopback device $DEVICE.\n"
else
    error "Incorrect CAPTURE_STREAM value ($CAPTURE_STREAM). Should be a, v or av."
fi
info "$MESSAGE You can now open your videochat app."

echo "Press enter to end stream"
perl -e '<STDIN>'

kill $GSTLAUNCH_PID > /dev/null 2>&1 || echo ""
stop_adb
pactl set-default-source ${DEFAULT_SOURCE}
pactl unload-module ${ECANCEL_ID}
pactl unload-module ${SINK_ID}

echo "Disconnected from IP Webcam. Have a nice day!"
# idea: capture ctrl-c signal and set default source back
