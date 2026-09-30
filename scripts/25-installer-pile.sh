#!/bin/bash
# Pose la pile utilisateur : libmali, Chromium Rockchip (Radxa 126), libv4l-rkmpp,
# libv4l2 patchée — DÉCOMPRESSÉS sous $RACINE, pas installés. Plus les quatre
# prérequis système de libv4l-rkmpp, notés au manifeste.
. "$(dirname "$0")/commun.sh"

export DEBIAN_FRONTEND=noninteractive
dire "paquets d'exécution apt : $APT_EXECUTION"
apt-get install -y -qq --no-install-recommends $APT_EXECUTION >/dev/null

mkdir -p "$KIOSQUE/debs" "$RACINE"
cd "$KIOSQUE/debs"
for u in "$DEB_CHROMIUM" "$DEB_V4L_RKMPP" "$DEB_LIBV4L" "$DEB_LIBMALI"; do
  f=$(basename "$u"); [ -f "$f" ] || curl -sSfO "$u" || meurs "téléchargement : $u"
  dpkg-deb -x "$f" "$RACINE"
done
dire "paquets Radxa décompressés dans $RACINE"

M=$ETAT/manifeste
poser() { echo "$1" >> "$M"; }   # tout fichier système créé ici est noté pour restaurer.sh

# 1. le greffon libv4l qui présente MPP comme un périphérique V4L2
P=/usr/lib/aarch64-linux-gnu/libv4l/plugins/libv4l-rkmpp.so
cp "$RACINE$P" "$P" && poser "$P"

# 2. 🔴 Chromium charge /usr/lib/libv4l2.so en DUR — et il faut la libv4l2 de Radxa
#    (1.22.1-5, patch mmap). Avec celle de Debian (1.22.1-5+b2) : « mmap() failed:
#    No such device », repli logiciel. Mesuré le 30/09/2026. Le lien pointe vers la
#    copie décompressée : la libv4l2 du système n'est pas remplacée.
ln -sfn "$RACINE/usr/lib/aarch64-linux-gnu/libv4l2.so.0.0.0" /usr/lib/libv4l2.so && poser /usr/lib/libv4l2.so
[ -e /usr/lib64 ] || { ln -Ts lib /usr/lib64 && poser /usr/lib64; }

# 3. Le faux nœud que Chromium ouvre. ⚠️ le script Radxa (rockchip-chromium-prep) ne
#    reconnaît que « rk3568 » et, sur une RK3566, écrit juste « dec » — tailles max à 0.
#    On écrit la liste RK356x à la main (pas d'AV1 sur cette puce).
printf 'type=dec\ncodecs=VP8:VP9:H.264:H.265\nmax-width=3840\nmax-height=2160\n' > /dev/video-dec0
echo enc > /dev/video-enc0
chmod 660 /dev/video-dec0 /dev/video-enc0
poser /dev/video-dec0; poser /dev/video-enc0
dire "pile posée — /dev/video-dec0 est en tmpfs : à reposer après chaque démarrage"
