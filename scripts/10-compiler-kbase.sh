#!/bin/bash
# Compile le pilote noyau Mali « kbase » (bifrost, g29p1) HORS ARBRE, pour le noyau
# qui tourne — sans recompiler le noyau. Mesuré le 30/09/2026 : 3 min 37 sur la box,
# vermagic 6.1.141-rk35xx-ophub, aucun symbole indéfini.
#
# Prérequis : les en-têtes du noyau (/lib/modules/$(uname -r)/build) — fournis par le
# paquet linux-headers d'ophub/Armbian — et gcc/make/git.
. "$(dirname "$0")/commun.sh"

KDIR=/lib/modules/$(uname -r)/build
[ -d "$KDIR" ] || meurs "en-têtes du noyau absents ($KDIR)"
grep -q '^CONFIG_MALI_BIFROST=' <(zcat /proc/config.gz 2>/dev/null) && dire "⚠️ le noyau a déjà MALI_BIFROST — ce script est inutile ici"

D=$SRC/kbase
if [ ! -d "$D/.git" ]; then
  dire "récupération des sources du pilote (sparse, quelques Mo)"
  git clone -q --depth 1 --filter=blob:none --sparse "$KBASE_DEPOT" "$D"
  git -C "$D" sparse-checkout set drivers/gpu/arm/bifrost include/uapi/gpu/arm/bifrost
fi

# Correctif PXL (patches/kbase-opp-ophub.patch) — sans lui, sur le DT ophub : « no
# supported OPPs », pas de devfreq, GPU figé à 166 MHz (mesuré 30/09/2026). Deux
# causes : la table déclare « rockchip,supported-hw » sans qu'aucune entrée ne porte
# « opp-supported-hw » (le noyau 6.1 les rejette alors toutes), et l'horloge s'y nomme
# « gpu » là où le pilote demande « clk_mali » (nom du DT Rockchip/Android).
DEPOT=$(cd "$(dirname "$0")/.." && pwd)
git -C "$D" checkout -q -- drivers/gpu/arm/bifrost
git -C "$D" apply "$DEPOT/patches/kbase-opp-ophub.patch" || meurs "correctif OPP non applicable"
dire "correctif OPP appliqué"

# 🔴 Piège 1 — les en-têtes du noyau ophub portent une version_compat_defs.h PLUS
# ANCIENNE que celle attendue par ce pilote, et elle passe devant dans le chemin
# d'inclusion (LINUXINCLUDE avant ccflags). On FORCE la bonne en tête : sa garde
# d'inclusion neutralise l'ancienne. Ne forcer QUE celle-là — forcer aussi
# memory_group_manager.h (variante valhall) casse la compilation.
INC=$SRC/kbase-inc; mkdir -p "$INC/linux"
for f in $(git -C "$D" ls-tree --name-only HEAD include/linux/ | grep -iE 'mali|bifrost|memory_group|protected|priority|version_compat'); do
  git -C "$D" show "HEAD:$f" > "$INC/linux/$(basename "$f")"
done

# 🔴 Piège 2 — NE PAS passer EXTRA_CFLAGS en ligne de commande : le Makefile du
# pilote y met ses propres -DCONFIG_MALI_*, et l'écraser fait disparaître les membres
# devfreq de struct kbase_device. Nos options passent par KCFLAGS.
cd "$D/drivers/gpu/arm/bifrost"
make clean >/dev/null 2>&1 || true
dire "compilation (quelques minutes sur 4×A55)"
nice -n 19 make -j"$(nproc)" KDIR="$KDIR" \
  CONFIG_MALI_BIFROST=m CONFIG_MALI_PLATFORM_NAME=rk \
  CONFIG_MALI_BIFROST_DEVFREQ=y CONFIG_MALI_CSF_SUPPORT=n \
  KCFLAGS="-I$INC -include $INC/linux/version_compat_defs.h" > "$SRC/kbase-build.log" 2>&1 \
  || { grep -E 'error' "$SRC/kbase-build.log" | head; meurs "compilation échouée (voir $SRC/kbase-build.log)"; }

mkdir -p "$(dirname "$KBASE_KO")"
cp bifrost_kbase.ko "$KBASE_KO"
modinfo "$KBASE_KO" | grep -E '^(version|vermagic)'
dire "module prêt : $KBASE_KO (non installé dans /lib/modules — chargé à la main par 30-basculer-kbase.sh)"
