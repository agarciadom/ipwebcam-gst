#!/bin/bash

# Script for using IP Webcam as a microphone/webcam in Debian Jessie,
# Ubuntu 13.04, 14.04, 16.04 and Arch Linux

# Copyright (C) 2011-2020 Antonio García Domínguez
# Copyright (C) 2016 C.J. Adams-Collier
# Copyright (C) 2016 Laptander
# Licensed under GPLv3

# Usage: ./install-videochat.sh
#
# INSTALLATION
#
# In Arch Linux
# install ipwebcam-gst-git package from AUR
#
# MULTIPLE WEBCAMS
#
# This requires some extra work. First, you need to reload the
# v4l2loopback module yourself and specify how many loopback devices
# you want (default is 1). For instance, if you want 2:
#
#   sudo modprobe -r v4l2loopback
#   sudo modprobe v4l2loopback exclusive_caps=1 devices=2
#
# Next, run two copies of this script with explicit WIFI_IP and DEVICE
# settings (see CONFIGURATION):
#
#   ./run-videochat.sh
#   ./run-videochat-copy.sh
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
#  sudo modprobe v4l2loopback exclusive_caps=1
#  ls /dev/video*
#  (Note down the new devices: let X be the number of the first new device.)
#  v4l2-ctl -D -d /dev/videoX
#  gst-launch-1.0 videotestsrc ! v4l2sink device=/dev/videoX & mplayer -tv device=/dev/videoX tv://
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
#   gst-launch-1.0 souphttpsrc location="http://$IP:$PORT/videofeed" \
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

### FUNCTIONS

has_kernel_module() {
    # Checks if module exists in system (but does not load it)
    MODULE="$1"
    if lsmod | grep -w "$MODULE" >/dev/null 2>/dev/null; then
        # echo "$MODULE is loaded! So it exists."
        return 0
    else
       # Determining kernel object existence
       # I do not know why, but using -q in egrep makes it always return 1, so do not use it
       if [ `find /lib/modules/$(uname -r)/ -name "$MODULE.ko*" | egrep '.*' ||
          find /lib/modules/$(uname -r)/extra -name "$MODULE.ko*" | egrep '.*'||
          find /lib/modules/$(uname -r)/extramodules -name "$MODULE.ko*" | egrep '.*'||
          find /lib/modules/$(uname -r)/updates/dkms -name "$MODULE.ko*" | egrep '.*'` ]; then
        return 0
       else
        return 1
       fi
    fi
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
    echo "$@"
    exit 1
}

info() {
    echo "$@"
}

can_run() {
    # It's either the path to a file, or the name of an executable in $PATH
    which "$1" >/dev/null 2>/dev/null
}

install_package() {
    if [ $DIST = "Debian" ] || [ $DIST = "Ubuntu" ] || [ $DIST = "LinuxMint" ]; then
        echo "Trying to install $1 package."
        apt-get install -y "$1"
    elif [ $DIST = "Arch" ]; then
        echo "Please install $1 package" 1>&2
        exit 1
    fi
}

### MAIN BODY

# Exit on first error
set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo" 1>&2
   exit 1
fi

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

if ! can_run bc; then
    install_package bc
fi

set +e
check_os_version $DIST $RELEASE
set -e
if [ $? -eq 0 ]
then
    GST_VER="1.0"
fi

if ! can_run zenity; then
    install_package zenity
fi

if ! can_run curl; then
    # Some versions of Ubuntu do not have curl by default (Arch
    # has it in its core, so we don't need to check that case)
    install_package curl
fi

# Check if the user has v4l2loopback
if ! has_kernel_module v4l2loopback; then
    if [ $DIST = "Debian" ] || [ $DIST = "Ubuntu" ] || [ $DIST = "Arch" ]; then
        install_package "v4l2loopback-dkms"
        if [ $DIST = "Ubuntu" ]; then
           install_package "python-apport"
        fi

        if [ $? != 0 ]; then
            info "Installation failed. Please install v4l2loopback manually from github.com/umlaeute/v4l2loopback."
        fi
    fi

    if has_kernel_module v4l2loopback; then
        info "The v4l2loopback kernel module was installed successfully."
    else
        error "Could not install the v4l2loopback kernel module through apt-get."
    fi
fi

# check if the user has the pulse gst plugin installed
if find "/usr/lib/gstreamer-$GST_VER/libgstpulseaudio.so" "/usr/lib/gstreamer-$GST_VER/libgstpulse.so" "/usr/lib/$(uname -m)-linux-gnu/gstreamer-$GST_VER/libgstpulse.so" "/usr/lib/$(uname -m)-linux-gnu/gstreamer-$GST_VER/libgstpulseaudio.so" 2>/dev/null | egrep -q '.*'; then
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

if ! can_run v4l2-ctl; then
    install_package v4l-utils
fi

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

info "videochat installed, launch with './run-videochat.sh'"