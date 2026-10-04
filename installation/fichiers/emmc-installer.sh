#!/bin/bash
# Copie le système de la carte SD (celui qui tourne) sur l'eMMC interne, qui devient le support principal.
# La carte SD reste intacte : retirée de la box, elle devient la carte de SECOURS (insérée, elle démarre en priorité).
#
#   emmc-installer.sh --verifier      ce qui serait fait, sans rien écrire (défaut)
#   emmc-installer.sh --appliquer     ÉCRASE l'eMMC (l'Android d'origine) — exige la sauvegarde vérifiée
#
# Pourquoi la SD retirée et pas un « double boot » (relevé le 04/10/2026, lecture seule) : le chargeur des deux supports
# (U-Boot 2017.09-armbian) teste la SD AVANT l'eMMC (« boot_targets=nvme mmc1 mmc0 », mmc1 = SD, et « Boot from SDcard »
# dès qu'une carte amorçable est là). SD insérée = la box démarre la SD, sans rien dire. Carte retirée = l'eMMC.
#
# Déroulé (--appliquer) :
#   1. garde-fous : on tourne bien depuis la SD (mmcblk0), l'eMMC est mmcblk2 (type MMC), la sauvegarde de l'Android est
#      là et vérifiée (/root/sauvegarde-emmc/VERIFIE.txt), rien n'est à l'antenne ;
#   2. table GPT neuve sur l'eMMC, MÊME disposition que la SD (BOOT 512 Mo à 16 Mio, ROOTFS = le reste) ;
#   3. chargeur : idbloader.img (secteur 64) et u-boot.itb (secteur 16384) de /usr/lib/u-boot — ceux de la SD, vérifiés
#      identiques à l'octet avant d'écrire ;
#   4. ext4 neufs, UUID NEUFS (deux supports au même UUID se confondraient au montage), étiquettes BOOT / ROOTFS ;
#   5. copie du système (rsync, deux passes : à chaud, puis serveur d'habillage arrêté quelques secondes pour figer
#      etat-local) — sans /root/sauvegarde-emmc (2 Go, elle reste sur la SD) ;
#   6. sur l'eMMC seulement : fstab, armbianEnv.txt (rootdev) et extlinux (root=) pointent les nouveaux UUID ;
#   7. contrôle : les deux arbres comparés (nombre de fichiers, empreinte de etat-local), puis RIEN d'autre — pas de
#      redémarrage. La suite est à la main : éteindre, retirer la SD, rallumer.
set -euo pipefail
MODE=${1:---verifier}
SD=/dev/mmcblk0 EMMC=/dev/mmcblk2
SAUV=/root/sauvegarde-emmc
UB=/usr/lib/u-boot
M=/mnt/pxl-emmc
dire()  { echo "[$(date +%T)] $*"; }
meurs() { echo "🔴 $*" >&2; exit 1; }
ok()    { echo "  ✅ $*"; }

dire "== vérifications"
[ "$(id -u)" = 0 ] || meurs "à lancer en root"
racine=$(findmnt -no SOURCE /)
[ "$racine" = ${SD}p2 ] || meurs "le système ne tourne pas depuis la SD (${racine}) — déjà installé sur l'eMMC ?"
ok "système en marche sur la SD ($racine)"
[ "$(cat /sys/block/mmcblk2/device/type 2>/dev/null)" = MMC ] || meurs "$EMMC n'est pas l'eMMC interne"
taille=$(( $(cat /sys/block/mmcblk2/size) * 512 / 1000000000 ))
ok "eMMC interne : $EMMC, ${taille} Go"
utilise=$(df -B1M --output=used / | tail -1); utilise=$(( utilise + $(df -B1M --output=used /boot | tail -1) - $(du -sm $SAUV 2>/dev/null | cut -f1 || echo 0) ))
ok "à copier : ~${utilise} Mo (hors sauvegarde)"
[ -s $SAUV/VERIFIE.txt ] && grep -q '^OK' $SAUV/VERIFIE.txt || meurs "pas de sauvegarde VÉRIFIÉE de l'eMMC dans $SAUV"
( cd $SAUV && sha256sum -c --quiet SHA256SUMS ) || meurs "sauvegarde abîmée : SHA256SUMS ne correspond plus"
ok "sauvegarde de l'Android présente et intacte ($(du -h $SAUV/mmcblk2.img.gz | cut -f1))"
cmp -s <(dd if=$SD bs=512 skip=64 count=$(( $(stat -c %s $UB/idbloader.img) / 512 )) status=none) $UB/idbloader.img \
  || meurs "le chargeur de la SD n'est pas $UB/idbloader.img — on n'écrirait pas celui qui démarre aujourd'hui"
cmp -s <(dd if=$SD bs=512 skip=16384 count=$(( ($(stat -c %s $UB/u-boot.itb) + 511) / 512 )) status=none | head -c $(stat -c %s $UB/u-boot.itb)) $UB/u-boot.itb \
  || meurs "u-boot de la SD différent de $UB/u-boot.itb"
ok "chargeur à écrire = celui de la SD, à l'octet"
antenne=$(curl -s -m 3 http://127.0.0.1:8765/api/tally | grep -o '"[a-z0-9]*":"antenne"' | grep -v sponsors || true)
[ -z "$antenne" ] || meurs "quelque chose est à l'antenne : $antenne"
ok "rien à l'antenne"
for o in sfdisk wipefs mkfs.ext4 rsync blkid partprobe; do command -v $o >/dev/null || meurs "$o absent"; done

if [ "$MODE" != --appliquer ]; then
  echo
  echo "Essai seulement : rien n'a été écrit. Avec --appliquer, l'eMMC (l'Android d'origine, sauvegardé) sera effacée et"
  echo "recevra : table GPT (BOOT 512 Mo + ROOTFS ~$(( taille - 1 )) Go), chargeur de la SD, copie du système."
  exit 0
fi

dire "== effacement de l'eMMC et nouvelle table"
for p in $(lsblk -nro NAME $EMMC | tail -n +2); do umount /dev/$p 2>/dev/null || true; done
wipefs -a -q $EMMC
dd if=/dev/zero of=$EMMC bs=1M count=16 conv=fsync status=none
printf 'label: gpt\nunit: sectors\n\nstart=32768, size=1046528, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="primary"\nstart=1081344, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="primary"\n' | sfdisk -q $EMMC
partprobe $EMMC; sleep 2
dire "== chargeur"
dd if=$UB/idbloader.img of=$EMMC seek=64 conv=notrunc,fsync status=none
dd if=$UB/u-boot.itb of=$EMMC seek=16384 conv=notrunc,fsync status=none
dire "== systèmes de fichiers"
mkfs.ext4 -q -F -L BOOT ${EMMC}p1
mkfs.ext4 -q -F -L ROOTFS ${EMMC}p2
UB_UUID=$(blkid -s UUID -o value ${EMMC}p1); RT_UUID=$(blkid -s UUID -o value ${EMMC}p2)
mkdir -p $M && mount ${EMMC}p2 $M && mkdir -p $M/boot && mount ${EMMC}p1 $M/boot
trap 'umount $M/boot $M 2>/dev/null || true' EXIT
EXCL=(--exclude=/boot/* --exclude=/proc/* --exclude=/sys/* --exclude=/dev/* --exclude=/run/* --exclude=/tmp/* --exclude=/mnt/* --exclude=/media/*
      --exclude=/lost+found --exclude=$SAUV)
dire "== copie à chaud"
rsync -aHAXx --numeric-ids "${EXCL[@]}" / $M/
rsync -aHAX --numeric-ids /boot/ $M/boot/
dire "== copie finale, serveur d'habillage arrêté (quelques secondes)"
systemctl stop pxl-serveur
rsync -aHAXx --numeric-ids --delete "${EXCL[@]}" / $M/
rsync -aHAX --numeric-ids --delete /boot/ $M/boot/
systemctl start pxl-serveur
dire "== l'eMMC pointe sur ses propres UUID"
VIEUX_RT=$(blkid -s UUID -o value ${SD}p2) VIEUX_BT=$(blkid -s UUID -o value ${SD}p1)
sed -i "s/$VIEUX_RT/$RT_UUID/g; s/$VIEUX_BT/$UB_UUID/g" $M/etc/fstab
sed -i "s/$VIEUX_RT/$RT_UUID/g" $M/boot/armbianEnv.txt
for f in $M/boot/extlinux/*; do [ -f "$f" ] && sed -i "s/$VIEUX_RT/$RT_UUID/g" "$f"; done
grep -q "$RT_UUID" $M/etc/fstab && grep -q "rootdev=UUID=$RT_UUID" $M/boot/armbianEnv.txt || meurs "UUID non posés sur l'eMMC"
dire "== contrôle"
n1=$(find / -xdev -path $SAUV -prune -o -print | wc -l); n2=$(find $M -xdev -print | wc -l)
e1=$(find /opt/pxl-app/etat-local -type f -exec sha256sum {} + | sort -k2 | sha256sum | cut -c1-16)
e2=$(cd $M && find opt/pxl-app/etat-local -type f -exec sha256sum {} + | sed "s# opt/# /opt/#" | sort -k2 | sha256sum | cut -c1-16)
ok "fichiers : SD $n1 · eMMC $n2 (l'écart = /boot monté à part et la sauvegarde exclue)"
[ "$e1" = "$e2" ] && ok "etat-local identique ($e1)" || echo "  ⚠️ etat-local diffère (le serveur a écrit depuis la copie finale ?) — relancer --appliquer"
sync
echo
echo "✅ eMMC prête. Pour démarrer dessus : éteindre (/admin › Machine), RETIRER la carte SD, rallumer."
echo "   La SD est inchangée : c'est la carte de secours. Insérée, elle redémarre la box en priorité."
