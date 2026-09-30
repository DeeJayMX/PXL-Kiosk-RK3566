#!/bin/bash
# Photographie l'état de la box AVANT toute modification. restaurer.sh compare à ça.
# À lancer UNE fois, avant le reste. Ne l'écrase pas s'il existe déjà
# (une seconde photo prise en cours de route ferait de l'état modifié la référence).
. "$(dirname "$0")/commun.sh"

if [ -f "$ETAT/versions.avant" ] && [ "${1:-}" != "--forcer" ]; then
  dire "état initial déjà photographié le $(stat -c %y "$ETAT/versions.avant" | cut -c1-16) — rien à faire (--forcer pour refaire)"
  exit 0
fi
dpkg-query -W -f='${Package} ${Version}\n' | sort > "$ETAT/versions.avant"
dpkg --get-selections | sort                   > "$ETAT/selections.avant"
lsmod | awk 'NR>1{print $1}' | sort            > "$ETAT/modules.avant"
systemctl list-units --type=service --state=active --no-legend --plain \
  | awk '{print $1}' | grep -E '^(turbohq|pxl)' | sort > "$ETAT/unites.actives.avant" || true
cat /sys/kernel/debug/dri/0/summary            > "$ETAT/summary.avant" 2>/dev/null || true
sysctl -n kernel.panic kernel.panic_on_oops    > "$ETAT/sysctl.avant"
: > "$ETAT/manifeste"
dire "état initial photographié dans $ETAT"
