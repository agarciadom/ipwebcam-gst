#!/bin/bash

# Script for using IP Webcam as a microphone/webcam in Debian Jessie,
# Ubuntu 13.04, 14.04, 16.04 and Arch Linux

# Copyright (C) 2011-2021 Antonio García Domínguez
# Copyright (C) 2016 C.J. Adams-Collier
# Copyright (C) 2016 Laptander
# Licensed under GPLv3

# Usage: ./run-videochat.sh [flip method]
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
#
# If you want to be able to hear other applications sounds, for example from web-browser,
# then while it is playing some sound, go to pavucontrol's Playback tab and choose your
# default sound card for web-browser.

# --
#
# Last tested with:
# - souphttpsrc version 1.0.6
# - v4l2sink version 1.0.6
# - v4l2loopback version 0.7.0

### FUNCTIONS

show_help() {
    echo "Usage:"
    echo " $0 [options]"
    echo
    echo "Script for using IP Webcam as a microphone/webcam."
    echo
    echo "Options:"
    echo " -a, --audio            capture only audio"
    echo " -b, --adb-path <path>  set adb location if not in PATH"
    echo " -C, --no-echo-cancel   do not set up echo cancellation"
    echo " -d, --device <device>  force video device to use"
    echo " -f, --flip <flip>      flip image"
    echo " -h, --height <height>  set image height (default 480)"
    echo " -l, --adb-flags <id>   adb flags to specify device id"
    echo " -i, --use-wifi <ip>    use wi-fi mode with specified ip"
    echo " -p, --port <port>      port on which IP Webcam is listening (default 8080)"
    echo " -P, --password <pass>  password for accesing the IP Webcam"
    echo " -s, --no-sync          No force syncing to timestamps"
    echo " -t, --with-tee         adds the 'tee' multiplexer to the pipeline, to workaround 'single-frame' capture issue (see issue #97)"
    echo " -u, --username <user>  username for accesing the IP Webcam"
    echo " -v, --video            capture only video"
    echo " -w, --width <width>    set image width (default 640)"
    echo " -x, --no-proxy         disable proxy while acessing IP"
    echo "     --help             show this help"
}
check_os_version() {
    # checks if the OS version can use newer GStreamer version
    DIST="$1"
    RELEASE="$2"

    case "$DIST" in
        "Debian")       return "`echo "$RELEASE < 8.0"   | bc`" ;;
        "Ubuntu")       return "`echo "$RELEASE < 14.04" | bc`" ;;
        "LinuxMint")    return "`echo "$RELEASE < 14.04" | bc`" ;;
        "Arch")         return 0 ;;
    esac
    # assume other Distributions are also new enough, by now
    return 0
}

error() {
    zenity --error --no-wrap --text "$@" > /dev/null 2>&1
    exit 1
}

warning() {
    zenity --warning --no-wrap --text "$@" > /dev/null 2>&1
}

info() {
    zenity --info --no-wrap --text "$@" > /dev/null 2>&1
}

confirm() {
    zenity --question --no-wrap --text "$@" > /dev/null 2>&1
}

can_run() {
    # It's either the path to a file, or the name of an executable in $PATH
    which "$1" >/dev/null 2>/dev/null
}

start_adb() {
    can_run "$ADB" && "$ADB" $ADB_FLAGS start-server
}

phone_plugged() {
    test "$("$ADB" $ADB_FLAGS get-state 2>/dev/null)" = "device"
}

url_reachable() {
    CURL_OPTIONS=""
    if [ $DISABLE_PROXY = 1 ]; then
        CURL_OPTIONS+="--noproxy $IP"
    fi

    if [[ $USERNAME != "" && $PASSWORD != "" ]]; then
        CURL_OPTIONS+="-u $USERNAME:$PASSWORD"
    fi
    # -f produces a non-zero status code when answer is 4xx or 5xx
    curl $CURL_OPTIONS -f -m 5 -sI "$1" >/dev/null
}

iw_server_is_started() {
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
}

module_id_by_sinkname() {
    pactl list sinks | grep -e "Name:" -e "Module:" |grep -A1 "Name: $1$" | grep Module: | cut -f2 -d: | tr -d ' '
}

### CONFIGURATION

# Exit on first error
set -e

# Choose which stream to capture.
# a - audio only, v - video only, av - audio and video.
# Make sure that IP webcam is streaming corresponding streams, otherwise error will occur.
# Defaults to audio and video, ovverrided by command line options.
CAPTURE_STREAM=av

# Choose audio codec from wav, aac or opus
# do not choose opus until editing pipeline. If choose opus, pipeline will not work
# and some errors will appear in feed.log.
# I do not know how to edit pipelines for now.
AUDIO_CODEC=wav

# Port on which IP Webcam is listening
# Defaults to 8080, ovverrided by command line options.
PORT=8080

# If your "adb" is not in your $PATH, specify it on command line.
if can_run adb; then ADB=$(which adb); fi

# Flags for ADB.
# when you need to pick from several devices, specify deviceid on command line (list deviceids with 'adb devices').
ADB_FLAGS=

# set on command line
FLIP_METHOD=

# Default dimensions of video, can be overridden on command line.
# Make sure both dimensions are multiples of 16 (see issue #97).
WIDTH=640
HEIGHT=480

# Force syncing to timestamps. Useful to keep audio and video in sync,
# but may impact performance in slow connections. If you see errors about
# timestamping or you do not need audio, you can try changing this to false from command line.
SYNC=true

# To disable proxy while acessing IP (set value 1 to disable, 0 for not)
# For cases when host m/c is connected to a Proxy-Server and IP belongs to local network
DISABLE_PROXY=0

# To disable echo cancellation
DISABLE_ECHO_CANCEL=0

# Use exclusive caps by default (required by Chrome, Cheese and others)
V4L2_OPTS="exclusive_caps=1"

USERNAME=""
PASSWORD=""

OPTS=`getopt -o ab:Cd:f:h:l:i:p:P:stu:vw:x --long audio,adb-path:,no-echo-cancel,device:,flip:,height:,help,adb-flags:,use-wifi:,port:,password:,no-sync,with-tee,username:,video,width:,no-proxy -n "$0" -- "$@"`
eval set -- "$OPTS"

while true; do
    case "$1" in
        -a | --audio ) CAPTURE_STREAM="a"; shift;;
        -b | --adb-path ) ADB="$2"; shift 2;;
	    -C | --no-echo-cancel ) DISABLE_ECHO_CANCEL=1; shift;;
        -d | --device ) DEVICE="$2"; shift 2;;
        -f | --flip ) FLIP_METHOD="$2"; shift 2;;
        -h | --height ) HEIGHT="$2"; shift 2;;
        -l | --adb-flags ) ADB_FLAGS="-s $2"; shift 2;;
        -i | --use-wifi ) IP="$2"; shift 2;;
        -p | --port ) PORT="$2"; shift 2;;
        -P | --password) PASSWORD="$2"; shift 2;;
        -u | --username) USERNAME="$2"; shift 2;;
        -s | --no-sync ) SYNC=false; shift;;
        -t | --with-tee ) USE_TEE=true; shift;;
        -v | --video ) CAPTURE_STREAM="v"; shift;;
        -w | --width ) WIDTH="$2"; shift 2;;
        -x | --no-proxy) DISABLE_PROXY=1; shift;;
        --help) show_help; exit; shift;;
        -- ) shift; break;;
        * ) echo "Internal error!" ; exit 1 ;;
    esac
done

declare -A DISTS
DISTS=(["Debian"]=1 ["Ubuntu"]=2 ["Arch"]=3 ["LinuxMint"]=4)

if can_run lsb_release; then
    DIST=`lsb_release -i | cut -f2 -d ":"`
    RELEASE=`lsb_release -r | cut -f2 -d ":"`
fi
if [ -z "$DIST" ] || [ -z "${DISTS[$DIST]}" ] ; then 
    if [ -f "/etc/arch-release" ]; then
        DIST="Arch"
        RELEASE=""
    elif [ -f "/etc/debian_version" ] ; then
        DIST="Debian"
        RELEASE=`perl -ne 'chomp; if(m:(jessie|testing|sid):){print "8.0"}elsif(m:[\d\.]+:){print}else{print "0.0"}' < /etc/debian_version`
    fi
fi

GST_VER="0.10"
GST_VIDEO_CONVERTER="ffmpegcolorspace"
GST_VIDEO_MIMETYPE="video/x-raw-yuv"
GST_VIDEO_FORMAT="format=(fourcc)YUY2"

GST_AUDIO_MIMETYPE="audio/x-raw-int"
GST_AUDIO_FORMAT="width=16,depth=16,endianness=1234,signed=true"
GST_AUDIO_RATE="rate=44100"
GST_AUDIO_CHANNELS="channels=1"
GST_AUDIO_LAYOUT=""

set +e
check_os_version $DIST $RELEASE
set -e
if [ $? -eq 0 ]
then
    GST_VER="1.0"
    GST_VIDEO_CONVERTER="videoconvert"
    GST_VIDEO_MIMETYPE="video/x-raw"
    GST_VIDEO_FORMAT="format=YUY2"

    GST_AUDIO_MIMETYPE="audio/x-raw"
    GST_AUDIO_FORMAT="format=S16LE"
    GST_AUDIO_LAYOUT=",layout=interleaved"
fi

DIMENSIONS="width=$WIDTH,height=$HEIGHT"

GST_VIDEO_CAPS="$GST_VIDEO_MIMETYPE,$GST_VIDEO_FORMAT,$DIMENSIONS"
GST_AUDIO_CAPS="$GST_AUDIO_MIMETYPE,$GST_AUDIO_FORMAT$GST_AUDIO_LAYOUT,$GST_AUDIO_RATE,$GST_AUDIO_CHANNELS"
PA_AUDIO_CAPS="$GST_AUDIO_FORMAT $GST_AUDIO_RATE $GST_AUDIO_CHANNELS"

# GStreamer debug string (see gst-launch manpage)
GST_DEBUG=souphttpsrc:0,videoflip:0,$GST_CONVERTER:0,v4l2sink:0,pulse:0
# Is $GST_CONVERTER defined anywhere? Maybe you mean videoconvert vs ffmpegcolorspace? It is in GST_VIDEO_CONVERTER

### MAIN BODY


# Probe module if not probed yet
if lsmod | grep -w v4l2loopback >/dev/null 2>/dev/null; then
    # module is already loaded, do nothing
    :
elif [ $CAPTURE_STREAM = v -o $CAPTURE_STREAM = av ]; then
    if can_run sudo; then
        echo Loading module
        sudo modprobe v4l2loopback $V4L2_OPTS #-q > /dev/null 2>&1
        sleep .05
    else
        echo Load module with \"modprobe v4l2loopback $V4L2_OPTS\"
    fi
fi

# If the user hasn't manually specified which /dev/video* to use
# through DEVICE, use the first "v4l2 loopback" device as the webcam:
# this should help when loading v4l2loopback on a system that already
# has a regular webcam. If that doesn't work, fall back to /dev/video0.
if [ -z "$DEVICE" ]; then
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
fi

# Test that we can read from and write to the device
if ! test -r "$DEVICE"; then
    error "$DEVICE is not readable: please fix your permissions"
fi
if ! test -w "$DEVICE"; then
    error "$DEVICE is not writable: please fix your permissions"
fi

# Decide whether to connect through USB or through wi-fi
if [ -z $IP ]; then
    # start adb daemon to avoid relaunching it in while
    if ! can_run "$ADB"; then
        error "adb is not available: you'll have to use Wi-Fi, which will be slower.\nNext time, please install the Android SDK from developer.android.com/sdk or install adb package."
    fi
    start_adb
    if ! phone_plugged; then
        error "adb is available, but the phone is not plugged in.\nConnect your phone to USB and allow usb debugging under developer settings or use Wi-Fi (slower)."
    fi
    if ss -ln src ":$PORT" | grep -q ":$PORT"; then
        PIDOF_ADB="$(pidof adb)"
        if test -n "$PIDOF_ADB" && ss -lptn src ":$PORT" | grep -q "pid=${PIDOF_ADB}"; then
            if confirm "Your port $PORT seems to be in use by ADB: would you like to clear the previous port before continuing?"; then
                adb forward --remove tcp:$PORT
            else
                exit 1
            fi
        else
            error "Your port $PORT seems to be in use: try using Wi-Fi.\nIf you would like to use USB forwarding, please free it up and try again."
        fi
    fi
    "$ADB" $ADB_FLAGS forward tcp:$PORT tcp:$PORT
    IP=127.0.0.1
    MODE=adb
else
    MODE=wifi
fi

BASE_URL=http://$IP:$PORT
VIDEO_URL=$BASE_URL/videofeed
AUDIO_URL=$BASE_URL/audio.$AUDIO_CODEC

if ! iw_server_is_started; then
    if [ $CAPTURE_STREAM = av ]; then
        MESSAGE="The IP Webcam audio feed is not reachable at <a href=\"$AUDIO_URL\">$AUDIO_URL</a>.\nThe IP Webcam video feed is not reachable at <a href=\"$VIDEO_URL\">$VIDEO_URL</a>."
    elif [ $CAPTURE_STREAM = a ]; then
        MESSAGE="The IP Webcam audio feed is not reachable at <a href=\"$AUDIO_URL\">$AUDIO_URL</a>."
    elif [ $CAPTURE_STREAM = v ]; then
        MESSAGE="The IP Webcam video feed is not reachable at <a href=\"$VIDEO_URL\">$VIDEO_URL</a>."
    else
        error "Incorrect CAPTURE_STREAM value ($CAPTURE_STREAM). Should be a, v or av."
    fi
    error "$MESSAGE\nPlease install and open IP Webcam in your phone and start the server.\nMake sure that values of variables IP, PORT, CAPTURE_STREAM in this script are equal with settings in IP Webcam."
fi

# Test if audio server is running on pipewire
if pactl info | grep -q PipeWire; then
    if [ "$CAPTURE_STREAM" = v ]; then
        :
    else
    # currently setting audio sinks errors out, so give user a workaround
        error "Only video streams on Pipewire are currently supported. Audio is a WIP. Please set CAPTURE_STREAM value to v."
    fi
fi

if [ $CAPTURE_STREAM = a -o $CAPTURE_STREAM = av ]; then
    # idea: check if default-source is correct. If two copy of script are running,
    # then after ending first before second you will be set up with $SINK_NAME.monitor,
    # but not with your original defauld source.
    # The same issue if script was not end correctly, and you restart it.
    DEFAULT_SINK=$(pactl info | grep "Sink" | cut -f3 -d " ")
    DEFAULT_SOURCE=$(pactl info | grep "Source" | cut -f3 -d " ")

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

    if [ $DISABLE_ECHO_CANCEL = 1 ]; then
        :
    elif [ -z $ECANCEL_ID ] ; then
        ECANCEL_ID=$(pactl load-module module-echo-cancel \
                   sink_name="${SINK_NAME}_echo_cancel" \
                   source_master="$SINK_NAME.monitor" \
                   sink_master="$DEFAULT_SINK" \
                   $PA_AUDIO_CAPS \
                   aec_method="webrtc" save_aec=true use_volume_sharing=true) || true
    fi

    pactl set-default-source $SINK_NAME.monitor
fi

# Check for gst-launch
GSTLAUNCH=gst-launch-${GST_VER}
if ! can_run "$GSTLAUNCH"; then
    error "Could not find gst-launch. Exiting."
fi

# Start the GStreamer graph needed to grab the video and audio
set +e

#sudo v4l2loopback-ctl set-caps $GST_0_10_VIDEO_CAPS $DEVICE

pipeline_video() {
    GST_FLIP=""
    GST_TEE=""
    if [ $FLIP_METHOD ]; then
        GST_FLIP="! videoflip method=\"$FLIP_METHOD\" "
    fi
    # Due to what seems an issue between v4l2loopback and gst-1.0 (https://github.com/umlaeute/v4l2loopback/issues/83),
    # the pipeline might need the "tee" multiplexer to enforce an additional buffer copy.
    # Here we enable it if the user explicitly asked to.
    # TODO: consider automatically enabling this if using gst-1.0 and specific version ranges of v4l2loopback.
    if [ "$USE_TEE" = "true" ]; then
        GST_TEE="! tee "
    fi

    echo souphttpsrc location="$VIDEO_URL" do-timestamp=true is-live=true user-id="$USERNAME" user-pw="$PASSWORD" \
      ! queue \
      ! multipartdemux \
      ! decodebin \
      $GST_FLIP \
      ! $GST_VIDEO_CONVERTER \
      ! videoscale \
      ! $GST_VIDEO_CAPS \
      $GST_TEE \
      ! v4l2sink device="$DEVICE" sync=$SYNC
}

pipeline_audio() {
  echo souphttpsrc location="$AUDIO_URL" do-timestamp=true is-live=true user-id="$USERNAME" user-pw="$PASSWORD" \
    ! $GST_AUDIO_CAPS ! queue \
    ! pulsesink device="$SINK_NAME" sync=$SYNC
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

if [ $DISABLE_PROXY = 1 ]; then
    # Disabling proxy to access WIFI_IP viz. on local network
    unset http_proxy
fi

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
info "${MESSAGE}You can now open your videochat app."

echo "Press enter to end stream"
read

kill $GSTLAUNCH_PID > /dev/null 2>&1 || echo ""
if [ $CAPTURE_STREAM = a -o $CAPTURE_STREAM = av ]; then
    pactl set-default-source ${DEFAULT_SOURCE}
    pactl unload-module ${ECANCEL_ID}
    pactl unload-module ${SINK_ID}
fi

# Remove the port forwarding, to avoid issues on the next run
if [ $MODE = adb ]; then "$ADB" $ADB_FLAGS forward --remove tcp:$PORT; fi

echo "Disconnected from IP Webcam. Have a nice day!"
# idea: capture ctrl-c signal and set default source back
