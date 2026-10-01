#!/bin/bash
# Fabrique une IMAGE DE CARTE SD prête à l'emploi : ophub Ubuntu noble + installer.sh joué dedans + l'application.
# À lancer en root sur une machine Linux **arm64** (la TurboNode, par exemple) : le chroot exécute de l'arm64.
#
#   IMAGE_URL=https://…/Armbian_…_x88pro20_noble_….img.gz \
#   CONF=/chemin/pxl-kiosk.conf  APP=/chemin/vers/application \
#   [TS_AUTHKEY=tskey-…]  [ROOT_MDP=…]  [TRAVAIL=/opt/pxl-image]  [EN_PLUS_GO=3] \
#   bash installation/fabriquer-image.sh
#
# Produit $TRAVAIL/<nom>.img.xz — à flasher avec balenaEtcher.
# Ce que l'image NE porte PAS, et qui naît au premier démarrage : clés SSH, machine-id, inscription Tailscale.
# TS_AUTHKEY : préférer une clé À USAGE UNIQUE, expirant vite, taguée — elle est effacée dès qu'elle a servi.
set -euo pipefail
ICI=$(cd "$(dirname "$0")" && pwd)
dire()  { echo "[$(date +%T)] $*"; }
meurs() { echo "🔴 $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || meurs "en root"
[ "$(uname -m)" = aarch64 ] || meurs "machine arm64 requise (le chroot exécute les paquets arm64)"
: "${IMAGE_URL:?}" "${CONF:?}" "${APP:?}"
[ -f "$CONF" ] && [ -d "$APP" ] || meurs "CONF ou APP introuvable"
TRAVAIL=${TRAVAIL:-/opt/pxl-image}; EN_PLUS_GO=${EN_PLUS_GO:-3}
NOM=pxl-kiosk-$(basename "$IMAGE_URL" .img.gz | sed 's/^Armbian_//')-$(date +%Y%m%d)
IMG=$TRAVAIL/$NOM.img; R=$TRAVAIL/racine; LOOP=

nettoyer() {
  set +e
  # 🔴 Démontage RÉCURSIF d'un arbre rendu esclave : rien ne se propage à l'hôte (piège vécu le 01/10/2026).
  mountpoint -q "$R" && umount -R "$R"
  [ -n "$LOOP" ] && losetup -d "$LOOP"
}
trap nettoyer EXIT

mkdir -p "$TRAVAIL" "$R"
GZ=$TRAVAIL/$(basename "$IMAGE_URL")
[ -s "$GZ" ] || { dire "téléchargement de l'image ophub…"; curl -fL --retry 3 -o "$GZ.part" "$IMAGE_URL" && mv "$GZ.part" "$GZ"; }
dire "décompression et agrandissement (+${EN_PLUS_GO} Go)…"
gunzip -c "$GZ" > "$IMG"
truncate -s +"${EN_PLUS_GO}"G "$IMG"
parted -s "$IMG" resizepart 2 100%
LOOP=$(losetup -fP --show "$IMG")
e2fsck -pf "${LOOP}p2" >/dev/null || true
resize2fs "${LOOP}p2" >/dev/null

dire "montage (arbre esclave)…"
mount "${LOOP}p2" "$R"
mount "${LOOP}p1" "$R/boot"
mount -t proc proc "$R/proc"
mount --rbind /sys "$R/sys"; mount --make-rslave "$R/sys"
mount --rbind /dev "$R/dev"; mount --make-rslave "$R/dev"
mount -t tmpfs tmpfs "$R/tmp"
mount -t tmpfs tmpfs "$R/run"   # sans /run/systemd/system : installer.sh se sait « dans une image »
grep -q noble "$R/etc/os-release" || meurs "l'image n'est pas une Ubuntu noble"

# DNS le temps de la fabrication (resolv.conf de l'image est souvent un lien vers systemd-resolved)
RESOLV=$(readlink "$R/etc/resolv.conf" || true)
rm -f "$R/etc/resolv.conf"; cp /etc/resolv.conf "$R/etc/resolv.conf"

dire "copie de la recette, de la configuration et de l'application…"
rm -rf "$R/opt/pxl-kiosk-installation"; cp -r "$ICI" "$R/opt/pxl-kiosk-installation"
rsync -a --delete --exclude .git --exclude etat-local --exclude node_modules "$APP/" "$R/opt/pxl-app-source/"
cp "$CONF" "$R/etc/pxl-kiosk.conf"
sed -i 's|^APP_SOURCE=.*|APP_SOURCE=/opt/pxl-app-source|' "$R/etc/pxl-kiosk.conf"

dire "installer.sh dans l'image (paquets, Node, services)…"
chroot "$R" env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root TS_AUTHKEY="${TS_AUTHKEY:-}" \
  bash /opt/pxl-kiosk-installation/installer.sh

dire "finitions propres à l'image…"
rm -f "$R/root/.not_logged_in_yet"                      # assistant de première connexion d'Armbian : personne au clavier
[ -n "${ROOT_MDP:-}" ] && echo "root:$ROOT_MDP" | chroot "$R" chpasswd
rm -f "$R"/etc/ssh/ssh_host_*                           # régénérées au premier démarrage, propres à chaque box
: > "$R/etc/machine-id"; rm -f "$R/var/lib/dbus/machine-id"   # idem (DHCP, journal, Tailscale)
rm -rf "$R/var/lib/tailscale"/*                         # aucune identité de nœud dans l'image
chroot "$R" apt-get clean
rm -f "$R/etc/resolv.conf"; [ -n "$RESOLV" ] && ln -s "$RESOLV" "$R/etc/resolv.conf"
echo "$NOM — fabriquée le $(date -Is) depuis $(basename "$IMAGE_URL")" > "$R/etc/pxl-kiosk/image"

nettoyer; LOOP=; trap - EXIT
dire "compression (xz, 4 fils)…"
xz -T4 -3 -f "$IMG"
sha256sum "$IMG.xz" > "$IMG.xz.sha256"
dire "✅ $IMG.xz ($(du -h "$IMG.xz" | cut -f1)) — à flasher avec balenaEtcher"
