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
# 🔴 (3) LIRE LE SUMMARY LE MOINS POSSIBLE (05/10/2026, v1.24.1, décision d'Eliott) — mesuré cette nuit-là : un Oops du
#     noyau à 05:40:44 (`vop2_crtc_debugfs_dump`, déréférencement NULL, appelé par `rockchip_drm_summary_show`) dans le
#     `grep` de CETTE garde, après ~23 000 lectures en 6 h 20 (2 lectures toutes les 2 s). Le code de debugfs du pilote
#     Rockchip lit un état de l'affichage qui peut changer sous lui. Le grep a été tué, l'image a continué — mais un Oops
#     qui tomberait verrou pris pourrait figer l'affichage. Chaque lecture a la même petite chance : on en fait 15× moins.
#     · UNE lecture par vérification (`cat` dans une variable, puis motifs bash), au lieu de deux `grep` sur le fichier ;
#     · une vérification toutes les GARDE_FILET_S (15 s par défaut, /etc/pxl-kiosk.conf) — panne silencieuse rattrapée
#       en 15-20 s ;
#     · vérification IMMÉDIATE sur ÉVÉNEMENT : drm (branché / débranché), ligne de refus dans le journal de Weston
#       (« couldn't commit new state », « repaint-flush failed » — la panne du 04/10), journal recréé (preview relancée) ;
#     · lecture anormale ⇒ deux relectures de CONFIRMATION à PAS s (2 s) avant de relancer, comme avant (TENUE = 3).
#     Le journal de Weston DÉCLENCHE une vérification, il ne DÉCIDE jamais : le prédicat reste l'état du scanout.
. "${PXL_GARDE_CONF:-/etc/pxl-kiosk.conf}" 2>/dev/null
NOM=${SORTIE_NOM:-HDMI-A-1}
STATUT=${PXL_GARDE_STATUT:-/sys/class/drm/card0-$NOM/status}   # surcharges : essai hors box
EDID=${PXL_GARDE_EDID:-/sys/class/drm/card0-$NOM/edid}
CONF=${PXL_GARDE_CONF:-/etc/pxl-kiosk.conf}
RESUME=${PXL_GARDE_RESUME:-/sys/kernel/debug/dri/0/summary}
MONITEUR=${PXL_GARDE_MONITEUR:-udevadm monitor --udev --subsystem-match=drm}
WLOG=${PXL_GARDE_WESTON:-/run/pxl-preview/weston.log}   # journal de Weston (preview.sh, XDG_RUNTIME_DIR)
PAS=${PXL_GARDE_PAS:-2} ATTENTE=${PXL_GARDE_ATTENTE:-3} TENUE=3 ECART=30
FILET=${PXL_GARDE_FILET:-${GARDE_FILET_S:-15}}
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

# Un seul flux d'événements : le noyau (drm) et les refus écrits par Weston. `tail -F` suit le journal recréé à chaque
# relance de la preview. Une ligne réveille la boucle ; « weston … » demande une vérification immédiate.
evenements() {
  $MONITEUR 2>/dev/null | sed -u 's/^/drm /' &
  tail -n0 -F "$WLOG" 2>/dev/null | grep --line-buffered -E "couldn't commit new state|repaint-flush failed" | sed -u 's/^/weston /' &
  wait
}
coproc MON { evenements; }
n=0; derniere=0; rebranche=0; avant=$(cat "$STATUT" 2>/dev/null); ecran=$(empreinte)
prochaine=0; urgent=0; journal=$(stat -c %i "$WLOG" 2>/dev/null)
echo "garde HDMI : $NOM ${avant:-?} — summary lu toutes les ${FILET} s, et aussitôt sur événement"
while :; do
  # attend un événement drm OU le pas ; moniteur mort (fin de flux) ⇒ simple minuterie
  # (rebranchement en attente de décision : on relit toutes les 0,5 s)
  t=$PAS; [ $rebranche -gt 0 ] && t=0.5
  if [ -n "${MON[0]:-}" ]; then
    read -r -t "$t" -u "${MON[0]}" ligne; rc=$?
    [ $rc -ne 0 ] && [ $rc -le 128 ] && { echo "garde HDMI : moniteur d'événements arrêté — minuterie seule"; unset MON; }
    if [ $rc -eq 0 ]; then
      urgent=1
      case $ligne in weston*) echo "garde HDMI : Weston signale un refus (${ligne#weston }) — vérification immédiate" ;; esac
    fi
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
  # (3) quand lire : à l'échéance (FILET, ou PAS pendant une confirmation), ou tout de suite après un événement.
  j=$(stat -c %i "$WLOG" 2>/dev/null); [ "$j" != "$journal" ] && { journal=$j; urgent=1; }   # preview relancée
  [ $urgent = 1 ] && { prochaine=0; urgent=0; }
  if [ "$etat" != connected ] || [ ! -r "$RESUME" ]; then
    n=0
  elif [ "$maintenant" -ge "$prochaine" ]; then
    if systemctl -q is-active pxl-preview; then
      r=$(cat "$RESUME" 2>/dev/null)   # UNE lecture du summary — c'est elle qui coûte (voir (3))
      [ -n "${PXL_GARDE_TRACE:-}" ] && echo "garde HDMI : lecture du summary"
      if [[ $r =~ Video\ Port[0-9]*:\ ACTIVE ]] && [[ $r =~ win[0-9]+:\ ACTIVE ]]; then
        n=0; prochaine=$((maintenant + FILET))
      else
        n=$((n + 1)); prochaine=$((maintenant + PAS))   # anormal : on confirme vite
      fi
    else
      n=0; prochaine=$((maintenant + FILET))
    fi
  fi
  if [ $n -ge $TENUE ] && [ $((maintenant - derniere)) -ge $ECART ]; then
    relancer "$NOM branché mais rien d'affiché (Video Port ou plan éteint) depuis $n lectures"
  fi
done
