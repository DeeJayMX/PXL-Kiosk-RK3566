#!/bin/bash
# Joue les 4 clips dans le kiosque en marche et imprime, par clip : la mesure DevTools
# (mesure.mjs), le CPU système (sur 400 %), la température, et le nombre de sessions
# rkvdec ouvertes dans MPP — la PREUVE du décodage matériel (0 = logiciel).
# ⚠️ Arrêter d'abord tout autre décodeur MPP (turbohq-presente…), sinon le compte ment.
cd "$(dirname "$0")"
cpu(){ awk '/^cpu /{print $2+$3+$4+$6+$7+$8, $5}' /proc/stat; }
for c in h264_1080p30.mp4 h264_1080p60.mp4 hevc_1080p60.mp4 hevc_2160p30.mp4; do
  [ -f media/$c ] || { echo "manque media/$c (fabriquer-clips.sh)"; continue; }
  ( sleep 8; read b1 i1 < <(cpu); sleep 18; read b2 i2 < <(cpu)
    echo "   $c : CPU $(( 400*(b2-b1)/((b2-b1)+(i2-i1)) ))% / 400 · $(( $(cat /sys/class/thermal/thermal_zone0/temp)/1000 )) °C · sessions rkvdec : $(grep -c rkvdec /proc/mpp_service/sessions-summary)" ) &
  node mesure.mjs $c 20; wait
done
