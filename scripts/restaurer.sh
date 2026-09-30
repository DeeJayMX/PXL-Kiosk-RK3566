#!/bin/bash
# Remet la box dans l'état photographié par 00-etat-initial.sh, puis LE VÉRIFIE.
# Défait : kiosque, fichiers du manifeste, versions de paquets modifiées, paquets
# ajoutés (exécution ET compilation), kbase → panfrost, sysctl, services.
# Garde : $KIOSQUE (sources, module, Xorg compilé, paquets décompressés) — pour
# supprimer aussi ça : restaurer.sh --tout
. "$(dirname "$0")/commun.sh"
[ -f "$ETAT/versions.avant" ] || meurs "pas d'état initial — rien à comparer"
export DEBIAN_FRONTEND=noninteractive

systemctl stop pxl-kiosque 2>/dev/null; systemctl reset-failed pxl-kiosque 2>/dev/null
pkill -x chromium-bin; pkill -x Xorg; sleep 2

while read -r f; do [ -n "$f" ] && rm -f "$f"; done < "$ETAT/manifeste"
: > "$ETAT/manifeste"

CHG=$(join "$ETAT/versions.avant" <(dpkg-query -W -f='${Package} ${Version}\n' | sort) | awk '$2!=$3{print $1"="$2}')
[ -n "$CHG" ] && apt-get install -y -qq --allow-downgrades $CHG >/dev/null
NEW=$(comm -13 <(awk '{print $1}' "$ETAT/versions.avant") \
               <(dpkg-query -W -f='${Package} ${db:Status-Abbrev}\n' | awk '$2=="ii"{print $1}' | sort))
[ -n "$NEW" ] && apt-get purge -y -qq $NEW >/dev/null

if lsmod | grep -q '^bifrost_kbase'; then rmmod bifrost_kbase; fi
lsmod | grep -q '^panfrost' || modprobe panfrost
read -r P PO < <(tr '\n' ' ' < "$ETAT/sysctl.avant")
sysctl -qw kernel.panic="$P" kernel.panic_on_oops="$PO"

for u in $(cat "$ETAT/unites.actives.avant"); do systemctl is-active -q "$u" || systemctl start "$u"; done
sleep 8

ok=0
v() { if diff -q "$2" "$3" >/dev/null; then echo "  ✅ $1 identique"; else echo "  🔴 $1 DIFFÉRENT"; diff "$2" "$3" | head -5; ok=1; fi; }
echo "== vérification"
v "versions de paquets" "$ETAT/versions.avant" <(dpkg-query -W -f='${Package} ${Version}\n' | sort)
v "modules noyau"       "$ETAT/modules.avant"  <(lsmod | awk 'NR>1{print $1}' | sort)
v "unités turbohq/pxl"  "$ETAT/unites.actives.avant" <(systemctl list-units --type=service --state=active --no-legend --plain | awk '{print $1}' | grep -E '^(turbohq|pxl)' | sort)
F='Display mode|win[0-9]: ACTIVE|format:|src:|dst:'
v "affichage (summary)" <(grep -E "$F" "$ETAT/summary.avant") <(grep -E "$F" /sys/kernel/debug/dri/0/summary)
v "sysctl panic"        "$ETAT/sysctl.avant" <(sysctl -n kernel.panic kernel.panic_on_oops)

if [ "${1:-}" = "--tout" ]; then
  cp -r "$ETAT" /root/pxl-kiosk-etat-$(date +%Y%m%d-%H%M) 2>/dev/null
  rm -rf "$KIOSQUE"; dire "$KIOSQUE supprimé (état copié dans /root/pxl-kiosk-etat-*)"
fi
exit $ok
