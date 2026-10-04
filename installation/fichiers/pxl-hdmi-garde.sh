#!/bin/bash
# Garde de la sortie HDMI (pxl-hdmi-garde.service, root) : relance la preview (1) à CHAQUE rebranchement d'un écran,
# et (2) quand un écran est branché mais que rien n'est balayé.
#
# Pourquoi (mesuré le 04/10/2026 sur la TV Samsung de la régie) : après un débranchement / rebranchement, le premier
# commit de Weston est parfois refusé (« atomic: couldn't commit new state: Invalid argument », puis « repaint-flush
# failed ») et Weston NE RÉESSAIE JAMAIS : le Video Port reste éteint, la TV dit « aucun signal ». Et en 1080i50 la TV a
# aussi montré un signal NOIR après un rebranchement, Video Port actif — cas que le scanout ne voit pas.
# Relancer pxl-preview refait tout dans l'ordre (pxl-mode pour un mode entrelacé, puis Weston, puis Chromium).
#
# (1) ÉVÉNEMENT — décision d'Eliott, 04/10 (option A) : tout passage débranché → branché déclenche une relance, une fois
#     l'écran branché depuis ATTENTE s (un câble qu'on enfonce rebondit). Coût assumé : ~10 s de noir à chaque
#     rebranchement, contre un signal toujours reposé à neuf. Réveil par `udevadm monitor` (événements drm), sans
#     attendre le pas de la boucle ; la transition se lit sur `status`, pas sur l'événement (une relecture d'EDID ou la
#     relance elle-même émettent aussi des « change »).
# (2) FILET — prédicat = l'état du SCANOUT (debugfs), jamais le journal de Weston : aucun « Video Port: ACTIVE »
#     pendant 3 lectures de suite (6 s ; une relance normale l'éteint quelques secondes), au plus une fois / 30 s
#     (un écran qui refuserait tout ne doit pas faire tourner la box en boucle).
. /etc/pxl-kiosk.conf 2>/dev/null
NOM=${SORTIE_NOM:-HDMI-A-1}
STATUT=${PXL_GARDE_STATUT:-/sys/class/drm/card0-$NOM/status}   # surcharges : essai hors box
RESUME=${PXL_GARDE_RESUME:-/sys/kernel/debug/dri/0/summary}
MONITEUR=${PXL_GARDE_MONITEUR:-udevadm monitor --udev --subsystem-match=drm}
PAS=${PXL_GARDE_PAS:-2} ATTENTE=${PXL_GARDE_ATTENTE:-3} TENUE=3 ECART=30
[ -n "${PXL_GARDE_RESUME:-}" ] || mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null
[ -r "$RESUME" ] || echo "garde HDMI : $RESUME illisible — seul le rebranchement est surveillé"

relancer() {
  echo "garde HDMI : $1 — relance de la preview"
  systemctl restart pxl-preview
  # le flux writeback se branche sur la socket de la preview, recréée par la relance
  systemctl -q is-active pxl-wb && systemctl restart pxl-wb
  derniere=$(date +%s); n=0
}

coproc MON { exec $MONITEUR 2>/dev/null; }
n=0; derniere=0; rebranche=0; avant=$(cat "$STATUT" 2>/dev/null)
echo "garde HDMI : $NOM ${avant:-?}"
while :; do
  # attend un événement drm OU le pas ; moniteur mort (fin de flux) ⇒ simple minuterie
  if [ -n "${MON[0]:-}" ]; then
    read -r -t "$PAS" -u "${MON[0]}" _; rc=$?
    [ $rc -ne 0 ] && [ $rc -le 128 ] && { echo "garde HDMI : moniteur udev arrêté — minuterie seule"; unset MON; }
  else
    sleep "$PAS"
  fi
  etat=$(cat "$STATUT" 2>/dev/null); maintenant=$(date +%s)
  if [ "$etat" != "$avant" ]; then
    echo "garde HDMI : $NOM ${etat:-?}"
    if [ "$etat" = connected ]; then rebranche=$maintenant; else rebranche=0; fi
    avant=$etat
  fi
  # (1) rebranchement : relance dès que l'écran est branché depuis ATTENTE s (on repasse aussitôt sur la boucle)
  if [ $rebranche -gt 0 ]; then
    if [ $((maintenant - rebranche)) -ge "$ATTENTE" ]; then
      rebranche=0
      systemctl -q is-active pxl-preview && relancer "$NOM rebranché"
    else
      sleep 0.5; continue
    fi
  fi
  # (2) filet : écran branché, preview censée tourner (pas arrêtée exprès), et aucun Video Port actif
  if [ -r "$RESUME" ] && [ "$etat" = connected ] && systemctl -q is-active pxl-preview \
     && ! grep -q 'Video Port[0-9]*: ACTIVE' "$RESUME"; then
    n=$((n + 1))
  else
    n=0
  fi
  if [ $n -ge $TENUE ] && [ $((maintenant - derniere)) -ge $ECART ]; then
    relancer "$NOM branché mais aucun Video Port actif depuis $n lectures"
  fi
done
