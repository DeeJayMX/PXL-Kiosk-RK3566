#!/bin/bash
# Fabrique les 4 clips du banc (30 s, mire en mouvement + compteur d'images, pour que
# les pertes se voient). À lancer sur un PC avec ffmpeg (libx264 + libx265), pas sur
# la box. Copier ensuite media/ à côté de v.html sur la box.
set -e; D=$(dirname "$0")/media; mkdir -p "$D"; cd "$D"
f() { ffmpeg -loglevel error -y -f lavfi \
  -i "testsrc2=size=$1:rate=$2,drawtext=text='%{n}':fontsize=96:fontcolor=white:x=40:y=40" \
  -t 30 -c:v $3 -preset veryfast -b:v $4 -pix_fmt yuv420p $5 -movflags +faststart $6; }
f 1920x1080 30 libx264 8M  "-profile:v high -g 60"  h264_1080p30.mp4 &
f 1920x1080 60 libx264 12M "-profile:v high -g 120" h264_1080p60.mp4 &
f 1920x1080 60 libx265 8M  "-tag:v hvc1 -x265-params log-level=error:keyint=120" hevc_1080p60.mp4 &
f 3840x2160 30 libx265 16M "-tag:v hvc1 -x265-params log-level=error:keyint=60"  hevc_2160p30.mp4 &
wait; ls -la
