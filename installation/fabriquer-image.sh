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
# SANS_XZ=1 : s'arrête avant la compression ; puis, plus tard (par ex. quand la clé Tailscale est prête) :
#   TS_AUTHKEY=tskey-… [TS_TAGS=tag:…] bash fabriquer-image.sh --finir /opt/pxl-image/<nom>.img
#   (pose la clé et le tag, compresse ; l'.img est GARDÉE, on peut refinir)
#   WIFI_FICHIER=… : réseaux Wi-Fi à poser (lignes « SSID<TAB>mot de passe<TAB>priorité »), l'Ethernet reste prioritaire
#   --retoucher /opt/pxl-image/<nom>.img : rejoue installer.sh + matériel dans une image DÉJÀ faite (même
#   montage, mêmes finitions), sans re-télécharger ni re-décompresser ; clé Tailscale, Wi-Fi, appli et mot de passe gardés
#   (APP=/chemin avec --retoucher : remplace aussi l'application)
#   MATERIEL=1 avec --finir : ajoute aussi le Wi-Fi et la façade (materiel-x88pro20.sh) à une image déjà faite
# Ce que l'image NE porte PAS, et qui naît au premier démarrage : clés SSH, machine-id, inscription Tailscale.
# TS_AUTHKEY : préférer une clé À USAGE UNIQUE, expirant vite, taguée — elle est effacée dès qu'elle a servi.
set -euo pipefail
ICI=$(cd "$(dirname "$0")" && pwd)
dire()  { echo "[$(date +%T)] $*"; }
meurs() { echo "🔴 $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || meurs "en root"
[ "$(uname -m)" = aarch64 ] || meurs "machine arm64 requise (le chroot exécute les paquets arm64)"
# 🔴 Tout se fait dans un espace de montage PRIVÉ. Sinon le montage de l'image se propage dans les espaces
# privés des services de l'hôte (udevd, resolved, logind, NetworkManager, chrony… vu le 01/10/2026) : ils le
# gardent ouvert, en écriture, l'image ne se démonte jamais proprement et le loop ne se détache plus.
if [ -z "${PXL_FAB_PRIVE:-}" ]; then exec env PXL_FAB_PRIVE=1 unshare --mount --propagation private "$0" "$@"; fi

compresser() {
  dire "compression (xz, 4 fils)…"
  xz -T4 -3 -k -f "$1"   # -k : l'.img reste, pour pouvoir refinir (autre clé) sans tout refabriquer
  sha256sum "$1.xz" > "$1.xz.sha256"
  dire "✅ $1.xz ($(du -h "$1.xz" | cut -f1)) — à flasher avec balenaEtcher"
}
# Connexions Wi-Fi NetworkManager, depuis un FICHIER de lignes « SSID<TAB>mot de passe<TAB>priorité »
# (WIFI_FICHIER=…) : le mot de passe ne passe ni par la ligne de commande ni par l'environnement d'un service.
poser_wifi() {  # $1 = racine de l'image
  [ -s "${WIFI_FICHIER:-}" ] || return 0
  local d="$1/etc/NetworkManager/system-connections"; mkdir -p "$d"
  while IFS=$'\t' read -r ssid psk prio; do
    [ -n "$ssid" ] || continue
    ( umask 077; cat > "$d/$ssid.nmconnection" <<EOF
[connection]
id=$ssid
type=wifi
interface-name=wlan0
autoconnect=true
autoconnect-priority=${prio:-0}

[wifi]
mode=infrastructure
ssid=$ssid

[wifi-security]
key-mgmt=wpa-psk
psk=$psk

[ipv4]
method=auto
route-metric=600

[ipv6]
method=auto
EOF
    )
    dire "Wi-Fi « $ssid » (priorité ${prio:-0}) posé"
  done < "$WIFI_FICHIER"
}
if [ "${1:-}" = --finir ]; then
  IMG=${2:?image .img}; M=$(mktemp -d); L=$(losetup -fP --show "$IMG")
  mount "${L}p2" "$M"
  if [ -n "${TS_AUTHKEY:-}" ]; then ( umask 077; printf '%s' "$TS_AUTHKEY" > "$M/etc/pxl-kiosk/ts-authkey" ); dire "clé Tailscale posée"; fi
  install -m 755 "$ICI/fichiers/premier-demarrage.sh" "$M/usr/local/lib/pxl-kiosk/premier-demarrage.sh"   # dernière version
  [ "${MATERIEL:-}" = 1 ] && bash "$ICI/materiel-x88pro20.sh" "$M" /   # Wi-Fi + façade, repris de l'hôte
  poser_wifi "$M"
  [ -n "${TS_TAGS+x}" ] && { sed -i "s|^TS_TAGS=.*|TS_TAGS=$TS_TAGS|" "$M/etc/pxl-kiosk.conf"; dire "TS_TAGS=$TS_TAGS"; }
  umount "$M"; losetup -d "$L"; rmdir "$M"
  compresser "$IMG"; exit 0
fi
RETOUCHE=
if [ "${1:-}" = --retoucher ]; then
  RETOUCHE=1; IMG=${2:?image .img}; [ -f "$IMG" ] || meurs "$IMG introuvable"
  TRAVAIL=$(dirname "$IMG"); NOM=$(basename "$IMG" .img); R=$TRAVAIL/racine; LOOP=
else
  : "${IMAGE_URL:?}" "${CONF:?}" "${APP:?}"
  [ -f "$CONF" ] && [ -d "$APP" ] || meurs "CONF ou APP introuvable"
  TRAVAIL=${TRAVAIL:-/opt/pxl-image}; EN_PLUS_GO=${EN_PLUS_GO:-3}
  NOM=pxl-kiosk-$(basename "$IMAGE_URL" .img.gz | sed 's/^Armbian_//')-$(date +%Y%m%d)
  IMG=$TRAVAIL/$NOM.img; R=$TRAVAIL/racine; LOOP=
fi

nettoyer() {
  set +e
  # 🔴 Démontage RÉCURSIF d'un arbre rendu esclave : rien ne se propage à l'hôte (piège vécu le 01/10/2026).
  mountpoint -q "$R" && { sync; umount -R "$R" || { sleep 3; umount -R "$R"; }; }
  # Système de fichiers vérifié et marqué propre avant de détacher (sinon « recovery required », vu le 01/10).
  [ -n "$LOOP" ] && { e2fsck -pf "${LOOP}p2" >/dev/null; losetup -d "$LOOP"; }
}
trap nettoyer EXIT

mkdir -p "$TRAVAIL" "$R"
if [ -n "$RETOUCHE" ]; then
  LOOP=$(losetup -fP --show "$IMG"); e2fsck -pf "${LOOP}p2" >/dev/null || true
else
GZ=$TRAVAIL/$(basename "$IMAGE_URL")
[ -s "$GZ" ] || { dire "téléchargement de l'image ophub…"; curl -fL --retry 3 -o "$GZ.part" "$IMAGE_URL" && mv "$GZ.part" "$GZ"; }
dire "décompression et agrandissement (+${EN_PLUS_GO} Go)…"
gunzip -c "$GZ" > "$IMG"
truncate -s +"${EN_PLUS_GO}"G "$IMG"
# GPT : l'en-tête de secours est resté à l'ancienne fin du fichier — parted refuse alors d'agrandir
# (« Unable to satisfy all constraints », vécu le 01/10). sfdisk le déplace, puis étend la partition 2.
sfdisk -q --relocate gpt-bak-std "$IMG"
echo ", +" | sfdisk -q --no-reread -N 2 "$IMG"
LOOP=$(losetup -fP --show "$IMG")
e2fsck -pf "${LOOP}p2" >/dev/null || true
resize2fs "${LOOP}p2" >/dev/null
fi

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
# APP= avec --retoucher : remplace aussi l'application de l'image (sinon elle est gardée telle quelle)
if [ -z "$RETOUCHE" ] || [ -n "${APP:-}" ]; then
  rsync -a --delete --exclude .git --exclude etat-local --exclude node_modules "$APP/" "$R/opt/pxl-app-source/"
  [ -z "$RETOUCHE" ] && cp "$CONF" "$R/etc/pxl-kiosk.conf"
  sed -i 's|^APP_SOURCE=.*|APP_SOURCE=/opt/pxl-app-source|' "$R/etc/pxl-kiosk.conf"
fi

dire "installer.sh dans l'image (paquets, Node, services)…"
chroot "$R" env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root TS_AUTHKEY="${TS_AUTHKEY:-}" \
  bash /opt/pxl-kiosk-installation/installer.sh

dire "matériel X88 Pro 20 (Wi-Fi SeekWave, façade HT1628), repris de l'hôte…"
bash "$ICI/materiel-x88pro20.sh" "$R" /
poser_wifi "$R"
dire "finitions propres à l'image…"
rm -f "$R/root/.not_logged_in_yet"                      # assistant de première connexion d'Armbian : personne au clavier
[ -n "${ROOT_MDP:-}" ] && echo "root:$ROOT_MDP" | chroot "$R" chpasswd
rm -f "$R"/etc/ssh/ssh_host_*                           # régénérées au premier démarrage, propres à chaque box
: > "$R/etc/machine-id"; rm -f "$R/var/lib/dbus/machine-id"   # idem (DHCP, journal, Tailscale)
rm -rf "$R/var/lib/tailscale"/*                         # aucune identité de nœud dans l'image
rm -rf "$R/etc/pxl-kiosk/github" "$R/opt/pxl-depots" "$R/etc/pxl-kiosk/maj.json"   # clés GitHub : propres à chaque box, générées sur place
chroot "$R" apt-get clean
rm -f "$R/etc/resolv.conf"; [ -n "$RESOLV" ] && ln -s "$RESOLV" "$R/etc/resolv.conf"
if [ -n "$RETOUCHE" ]; then echo "retouchée le $(date -Is)" >> "$R/etc/pxl-kiosk/image"
else echo "$NOM — fabriquée le $(date -Is) depuis $(basename "$IMAGE_URL")" > "$R/etc/pxl-kiosk/image"; fi

nettoyer; LOOP=; trap - EXIT
[ "${SANS_XZ:-}" = 1 ] && { dire "✅ $IMG prête, non compressée — finir avec : fabriquer-image.sh --finir $IMG"; exit 0; }
compresser "$IMG"
