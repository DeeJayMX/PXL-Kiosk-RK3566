#!/bin/bash
# « boot » sur la façade dès l'initramfs, SANS reconstruire l'initramfs d'origine.
#   facade-initramfs.sh            pose (idempotent)      facade-initramfs.sh --retirer   revient à l'original
#
# Pourquoi pas update-initramfs : l'initramfs de l'image ophub a été fabriqué sur leur machine ; le reconstruire sur la
# box en donne un AUTRE (mesuré 02/10 : 1422 → 1219 fichiers, scripts init-top différents). On garde donc l'original
# octet pour octet et on lui COLLE une seconde archive (xz, CRC32 comme l'original) : le noyau déballe les archives
# concaténées l'une après l'autre, la seconde ajoute ht1628 et remplace scripts/init-top/ORDER (original + notre ligne).
# L'original reste dans /boot/initrd.img-<noyau> ; seul /boot/uInitrd (le lien que lit boot.scr) change de cible.
# ⚠️ /boot est en ext4 : une carte qui ne démarre plus se répare depuis un Linux (ln -sfn uInitrd-<noyau> uInitrd).
set -euo pipefail
B=/boot
# le noyau INSTALLÉ (celui de /boot), pas celui qui tourne : dans le chroot de fabrication d'image, uname -r est l'hôte
K=${K:-$(ls $B/initrd.img-* | grep -v "\.avant\|\.pxl" | head -1 | sed "s#.*/initrd.img-##")}; ORIG=$B/initrd.img-$K; U=$B/uInitrd-$K; NOUV=$B/uInitrd-$K.pxl
if [ "${1:-}" = --retirer ]; then ln -sfn "uInitrd-$K" $B/uInitrd; rm -f "$NOUV"; sync; echo "initramfs d'origine rétabli"; exit 0; fi
[ -x /usr/local/bin/ht1628 ] || { echo "pas de /usr/local/bin/ht1628 : rien à faire"; exit 0; }
for o in cpio xz mkimage unmkinitramfs lsinitramfs; do command -v $o >/dev/null || { echo "manque $o"; exit 1; }; done
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/orig" "$T/sup/usr/bin" "$T/sup/scripts/init-top"
unmkinitramfs "$ORIG" "$T/orig"
[ -d "$T/orig/main" ] && R="$T/orig/main" || R="$T/orig"
test -f "$R/scripts/init-top/ORDER" && test -e "$R/lib/aarch64-linux-gnu/libc.so.6"   # ht1628 ne demande que la libc
install -m 755 /usr/local/bin/ht1628 "$T/sup/usr/bin/ht1628"
install -m 755 "$(dirname "$0")/init-top-pxl-facade" "$T/sup/scripts/init-top/pxl-facade"
{ printf '/scripts/init-top/pxl-facade "$@"\n[ -e /conf/param.conf ] && . /conf/param.conf\n'
  grep -v pxl-facade "$R/scripts/init-top/ORDER" ; } > "$T/sup/scripts/init-top/ORDER"
# fichiers seulement, aucune entrée de répertoire : /usr/bin et /scripts existent déjà dans l'original
( cd "$T/sup" && printf 'usr/bin/ht1628\nscripts/init-top/pxl-facade\nscripts/init-top/ORDER\n' | cpio -o -H newc --quiet --owner=0:0 ) \
  | xz --check=crc32 -9 > "$T/sup.xz"
cat "$ORIG" "$T/sup.xz" > "$T/initrd"
# contrôle : l'original est recopié tel quel en tête, et l'archive ajoutée se relit seule avec nos trois fichiers.
# (lsinitramfs ne lit que la PREMIÈRE archive : il ne verrait pas l'ajout, d'où cette vérification à part)
cmp -n "$(stat -c %s "$ORIG")" "$ORIG" "$T/initrd"
LUS=$(xz -dc "$T/sup.xz" | cpio -t --quiet | sort | tr '\n' ' ')
[ "$LUS" = "scripts/init-top/ORDER scripts/init-top/pxl-facade usr/bin/ht1628 " ] || { echo "⚠️ archive ajoutée illisible ($LUS) — abandon"; exit 1; }
echo "ajout vérifié : $LUS($(stat -c %s "$T/sup.xz") octets)"
[ "${ESSAI:-}" = 1 ] && { echo "(essai : rien posé)"; exit 0; }
mkimage -A arm64 -O linux -T ramdisk -C none -n uInitrd -d "$T/initrd" "$NOUV" >/dev/null
ln -sfn "$(basename "$NOUV")" $B/uInitrd; sync
echo "posé : /boot/uInitrd -> $(readlink $B/uInitrd)  (original intact : uInitrd-$K)"
