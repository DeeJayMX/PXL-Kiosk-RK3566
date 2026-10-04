#!/bin/bash
# Garde de la sortie HDMI (pxl-hdmi-garde.service, root) : relance la preview (1) quand on branche un AUTRE écran en
# mode AUTO, et (2) quand un écran est branché mais que rien n'est balayé.
#
# Pourquoi (mesuré le 04/10/2026 sur la TV Samsung de la régie) : après un débranchement / rebranchement, le premier
# commit de Weston est parfois refusé (« atomic: couldn't commit new state: Invalid argument », puis « repaint-flush
# failed ») et Weston NE RÉESSAIE JAMAIS : le Video Port reste éteint, la TV dit « aucun signal ».
# Relancer pxl-preview refait tout dans l'ordre (pxl-mode pour un mode entrelacé, puis Weston, puis Chromium).
#
# (1) REBRANCHEMENT — décision d'Eliott, 04/10 : relancer à chaque rebranchement coûtait ~10 s de noir (« un peu
#     long »). Désormais : mode FORCÉ (SORTIE_MODE=1920x1080i@50…) ⇒ rien, la box n'a jamais cessé d'émettre et
#     l'image revient dès que la TV accroche ; mode AUTO ⇒ relance seulement si l'EDID a changé (un AUTRE écran, dont
#     preview.sh doit relire les modes). Réveil par `udevadm monitor` (événements drm) ; la transition se lit sur
#     `status`, l'écran sur l'empreinte de `edid`, qu'on relit après ATTENTE s (un câble qu'on enfonce rebondit).
# (2) FILET — prédicat = l'état du SCANOUT (debugfs), jamais le journal de Weston : aucun « Video Port: ACTIVE », OU
#     aucun plan « winN: ACTIVE » (signal sans image — écran noir mais allumé, vu le 04/10), pendant 3 lectures de suite (6 s ; une relance normale l'éteint quelques secondes), au plus une fois / 30 s
#     (un écran qui refuserait tout ne doit pas faire tourner la box en boucle).
. "${PXL_GARDE_CONF:-/etc/pxl-kiosk.conf}" 2>/dev/null
NOM=${SORTIE_NOM:-HDMI-A-1}
STATUT=${PXL_GARDE_STATUT:-/sys/class/drm/card0-$NOM/status}   # surcharges : essai hors box
EDID=${PXL_GARDE_EDID:-/sys/class/drm/card0-$NOM/edid}
CONF=${PXL_GARDE_CONF:-/etc/pxl-kiosk.conf}
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

empreinte() { md5sum < "$EDID" 2>/dev/null | cut -c1-32; }
VIDE=$(md5sum < /dev/null | cut -c1-32)
mode_sortie() { (. "$CONF" 2>/dev/null; echo "${SORTIE_MODE:-}"); }   # relu à chaque fois : /admin le change à chaud

coproc MON { exec $MONITEUR 2>/dev/null; }
n=0; derniere=0; rebranche=0; avant=$(cat "$STATUT" 2>/dev/null); ecran=$(empreinte)
echo "garde HDMI : $NOM ${avant:-?}"
while :; do
  # attend un événement drm OU le pas ; moniteur mort (fin de flux) ⇒ simple minuterie
  # (rebranchement en attente de décision : on relit toutes les 0,5 s)
  t=$PAS; [ $rebranche -gt 0 ] && t=0.5
  if [ -n "${MON[0]:-}" ]; then
    read -r -t "$t" -u "${MON[0]}" _; rc=$?
    [ $rc -ne 0 ] && [ $rc -le 128 ] && { echo "garde HDMI : moniteur udev arrêté — minuterie seule"; unset MON; }
  else
    sleep "$t"
  fi
  etat=$(cat "$STATUT" 2>/dev/null); maintenant=$(date +%s)
  if [ "$etat" != "$avant" ]; then
    echo "garde HDMI : $NOM ${etat:-?}"
    if [ "$etat" = connected ]; then rebranche=$maintenant; else rebranche=0; fi
    avant=$etat
  fi
  # (1) rebranchement : une fois l'écran branché depuis ATTENTE s, AUTO + autre écran ⇒ relance ; sinon rien
  if [ $rebranche -gt 0 ]; then
    if [ $((maintenant - rebranche)) -ge "$ATTENTE" ]; then
      rebranche=0; nouveau=$(empreinte); m=$(mode_sortie)
      if [ "$m" != auto ]; then
        echo "garde HDMI : $NOM rebranché, mode forcé ($m) — rien à relancer"
      elif [ "$nouveau" = "$ecran" ] && [ "$nouveau" != "$VIDE" ]; then
        echo "garde HDMI : $NOM rebranché, même écran (AUTO) — rien à relancer"
      else
        systemctl -q is-active pxl-preview && relancer "$NOM rebranché, autre écran (AUTO)"
      fi
      [ "$nouveau" != "$VIDE" ] && ecran=$nouveau
    else
      continue
    fi
  fi
  # (2) filet : écran branché, preview censée tourner (pas arrêtée exprès), et aucun Video Port actif
  # 04/10 au soir, après le passage sur l'eMMC : écran NOIR en 1080i50 avec le Video Port ACTIF — pxl-mode avait posé le
  # mode (tampon noir), puis le premier commit de Weston a été refusé (« repaint-flush failed ») et aucun plan n'affichait
  # plus rien. « Video Port actif » ne suffit donc pas : il faut aussi un plan (winN) ACTIF, c'est-à-dire une image.
  if [ -r "$RESUME" ] && [ "$etat" = connected ] && systemctl -q is-active pxl-preview \
     && { ! grep -q 'Video Port[0-9]*: ACTIVE' "$RESUME" || ! grep -qE 'win[0-9]+: ACTIVE' "$RESUME"; }; then
    n=$((n + 1))
  else
    n=0
  fi
  if [ $n -ge $TENUE ] && [ $((maintenant - derniere)) -ge $ECART ]; then
    relancer "$NOM branché mais rien d'affiché (Video Port ou plan éteint) depuis $n lectures"
  fi
done
