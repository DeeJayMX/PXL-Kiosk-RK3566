#!/bin/bash
# Garde de la sortie HDMI (pxl-hdmi-garde.service, root) : relance la preview quand un écran est BRANCHÉ mais que
# rien n'est balayé.
#
# Pourquoi (mesuré le 04/10/2026 sur la TV Samsung de la régie) : après un débranchement / rebranchement, le premier
# commit de Weston est refusé (« atomic: couldn't commit new state: Invalid argument », puis « repaint-flush failed »)
# et Weston NE RÉESSAIE JAMAIS : le Video Port reste éteint, la TV dit « aucun signal » jusqu'à une relance à la main.
# Relancer pxl-preview refait tout dans l'ordre (pxl-mode pour un mode entrelacé, puis Weston, puis Chromium).
#
# Prédicat = l'état du SCANOUT (debugfs), jamais le journal de Weston : c'est ce que voit la TV, quelle que soit la
# cause (rebranchement, Weston qui démarre écran débranché, mode refusé). Il doit tenir 3 lectures de suite (6 s) —
# une relance normale de la preview éteint le Video Port quelques secondes — et on ne relance pas plus d'une fois
# toutes les 30 s (un écran qui refuserait tout ne doit pas faire tourner la box en boucle).
. /etc/pxl-kiosk.conf 2>/dev/null
NOM=${SORTIE_NOM:-HDMI-A-1}
STATUT=${PXL_GARDE_STATUT:-/sys/class/drm/card0-$NOM/status}   # surcharges : essai hors box
RESUME=${PXL_GARDE_RESUME:-/sys/kernel/debug/dri/0/summary}
PAS=${PXL_GARDE_PAS:-2} TENUE=3 ECART=30
[ -n "${PXL_GARDE_RESUME:-}" ] || mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null
[ -r "$RESUME" ] || { echo "garde HDMI : $RESUME illisible — rien à surveiller"; exec sleep infinity; }

n=0; derniere=0; avant=
while sleep $PAS; do
  etat=$(cat "$STATUT" 2>/dev/null)
  [ "$etat" != "$avant" ] && echo "garde HDMI : $NOM ${etat:-?}"; avant=$etat
  # écran branché, preview censée tourner (pas arrêtée exprès), et aucun Video Port actif
  if [ "$etat" = connected ] && systemctl -q is-active pxl-preview && ! grep -q 'Video Port[0-9]*: ACTIVE' "$RESUME"; then
    n=$((n + 1))
  else
    n=0
  fi
  maintenant=$(date +%s)
  if [ $n -ge $TENUE ] && [ $((maintenant - derniere)) -ge $ECART ]; then
    echo "garde HDMI : $NOM branché mais aucun Video Port actif depuis $n lectures — relance de la preview"
    systemctl restart pxl-preview
    # le flux writeback se branche sur la socket de la preview, recréée par la relance
    systemctl -q is-active pxl-wb && systemctl restart pxl-wb
    derniere=$maintenant; n=0
  fi
done
