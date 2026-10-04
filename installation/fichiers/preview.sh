#!/bin/bash
# Session preview : Weston (kiosk-shell, sortie fixée par weston.ini) puis Chromium en Wayland.
# Lancé par pxl-preview.service (utilisateur pxl). Si l'un des deux meurt, on sort : systemd relance le tout.
. /etc/pxl-kiosk.conf
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/pxl-preview}
export LIBSEAT_BACKEND=seatd

# Le mode demandé doit exister sur l'écran branché : sinon Weston prend le mode PRÉFÉRÉ sans rien dire — 3840x2160p60
# sur la TV du labo (mesuré le 03/10/2026 en demandant un 720p25 qu'elle ne déclare pas). Repli explicite et dit.
MODE=$SORTIE_MODE
LISTE=$(/usr/local/lib/pxl-kiosk/pxl-mode --liste "${SORTIE_NOM:-HDMI-A-1}" 2>/dev/null)
# AUTO (/admin, 04/10/2026) : le premier mode de cette liste que l'écran déclare — cadences européennes d'abord, jamais
# de 4K (Chromium écraserait la box, le flux writeback est en 1920×1080). Écran muet ⇒ 1080i50, le défaut de la régie.
# C'est aussi en AUTO que la garde HDMI relance la preview quand on branche un AUTRE écran (pxl-hdmi-garde.sh).
if [ "$MODE" = auto ]; then
  MODE=1920x1080i@50
  for m in ${SORTIE_AUTO_ORDRE:-1920x1080i@50 1920x1080@50 1280x720@50 1920x1080i@60 1920x1080@60 1280x720@60}; do
    grep -qxF "$m" <<<"$LISTE" && { MODE=$m; break; }
  done
  echo "AUTO : $MODE"
fi
if [ -n "$LISTE" ] && ! grep -qxF "$MODE" <<<"$LISTE"; then
  for repli in 1280x720@50 1920x1080@50 1280x720@60 1920x1080@60; do grep -qxF "$repli" <<<"$LISTE" && break; done
  echo "⚠ $MODE absent de l'écran branché — repli sur $repli"
  MODE=$repli
fi

# Format du LIEN HDMI (05/10/2026, demande d'Eliott : 4:2:2 10 bits pour un convertisseur SDI / un mélangeur) — posé AVANT
# tout modeset, Weston ne connaît pas ces propriétés Rockchip et ne les touche pas. Chromium dessine toujours en RGB 8 bits :
# c'est le VOP2 qui convertit vers le lien, sans coût. Le pilote retombe en RGB / 8 bits si l'écran ne déclare pas le
# format demandé — sans erreur : /admin affiche le bus_format réellement émis. Défaut : RGB 8 bits (le réglage d'origine).
LIEN_FORMAT=${LIEN_FORMAT:-rgb}; LIEN_PROFONDEUR=${LIEN_PROFONDEUR:-8}
/usr/local/lib/pxl-kiosk/pxl-mode --couleur "$LIEN_FORMAT" "$LIEN_PROFONDEUR" "${SORTIE_NOM:-HDMI-A-1}" || true
BPC=10; [ "$LIEN_PROFONDEUR" = 8 ] && BPC=8

# Mode entrelacé (1080i50) : Weston ne sait pas le choisir (il prend le 1080p50) — pxl-mode le pose d'abord, et Weston
# lit alors « mode=current ». Échec ⇒ on continue : Weston prendra le mode courant, quel qu'il soit.
case "$MODE" in *i@*) /usr/local/lib/pxl-kiosk/pxl-mode "$MODE" "${SORTIE_NOM:-HDMI-A-1}" || true; WMODE=current; sleep 1 ;; *) WMODE=$MODE ;; esac
# ⚠️ (04/10) le « sleep 1 » laisse le changement de mode se poser avant que Weston prenne la main : voir plus bas.

# Entrelacé en PsF (ENTRELACE=psf, défaut — décision d'Eliott, 03/10 ; réglé dans /admin) : Weston patché se cadence à
# l'IMAGE (25 Hz en 1080i50) au lieu de la trame — Chromium dessine 25 img/s, chaque image occupe ses deux trames (écran
# et flux propres en mouvement). Sans le Weston patché, la variable est ignorée ; en progressif, elle ne change rien.
# ⚠ Et Weston y compose avec une fenêtre de 15 ms au lieu de 7 : à 7, une image sur ~5 ratait sa trame et retombait
# sur une trame du bas (recalage, flux à 22-23 img/s) ; mesuré 03/10 : 7 ms → 43 glissements / 10 s, 12 → 3, 15 → 1 à
# 3, 18 → 0 mais Chromium perd une image. SEULEMENT en entrelacé PsF : une image y dure 40 ms ; en 50p elle en dure 20,
# et 15 ms de composition affameraient Chromium.
# Weston lit une copie de weston.ini posée dans /run (mode effectif, fenêtre) : le fichier de /etc reste celui du réglage.
[ "${ENTRELACE:-psf}" = psf ] && export PXL_PSF=1
INI="$XDG_RUNTIME_DIR/weston.ini"
FENETRE=; case "$MODE" in *i@*) [ "${ENTRELACE:-psf}" = psf ] && FENETRE=15 ;; esac
# 🔴 max-bpc=8 : la VRAIE cause de l'écran noir (04/10 au soir, prouvée par un espion libdrm sur le commit refusé) — Weston
# recopie la valeur courante de la propriété « max bpc » du connecteur, qui vaut 0 après un démarrage alors que le noyau
# n'accepte que 8..16 : tout le commit est refusé (EINVAL), Weston ne réessaie pas. 10 quand le lien est demandé en 10 bits.
sed "/^repaint-window=/d; /^max-bpc=/d; s/^mode=.*/mode=$WMODE\nmax-bpc=$BPC/${FENETRE:+; s/^\\[core\\]\$/[core]\\nrepaint-window=$FENETRE/}" /etc/pxl-kiosk/weston.ini > "$INI"

weston --config="$INI" --log="$XDG_RUNTIME_DIR/weston.log" &
WESTON=$!
for i in $(seq 100); do [ -S "$XDG_RUNTIME_DIR/wayland-1" ] && break; sleep 0.1; done
[ -S "$XDG_RUNTIME_DIR/wayland-1" ] || { echo "Weston n'a pas ouvert son socket — $XDG_RUNTIME_DIR/weston.log"; exit 1; }
# 🔴 PREMIER COMMIT REFUSÉ (mesuré le 04/10/2026 au soir, 1080i50 sur la TV Samsung, après le passage sur l'eMMC) : environ
# une fois sur deux, le premier commit atomique de Weston est rejeté (« atomic: couldn't commit new state: Invalid
# argument » puis « repaint-flush failed » ; le noyau abandonne pendant le réglage des propriétés du CONNECTEUR, avant tout
# contrôle de l'image) et Weston NE RÉESSAIE JAMAIS : signal présent, écran NOIR. La même séquence (fbdev 4K30 → pxl-mode
# 1080i50 → Weston) réussit l'essai suivant : c'est une course, pas un mode refusé. ⇒ on regarde le journal 3 s après le
# démarrage ; refus ⇒ on sort, et systemd relance tout (≈ 10 s) au lieu de laisser un écran noir.
sleep 3
# seulement « Invalid argument » : un « Device or resource busy » (EBUSY = « pas encore ») se rattrape tout seul — vu au
# démarrage du 04/10 à 21 h 19, trois EBUSY et l'image affichée quand même
if grep -q "couldn't commit new state: Invalid argument" "$XDG_RUNTIME_DIR/weston.log"; then
  echo "premier commit de Weston refusé (écran noir) — relance de la preview"
  kill "$WESTON" 2>/dev/null; exit 1
fi
export WAYLAND_DISPLAY=wayland-1

# Attendre le serveur d'habillage (sinon la page s'ouvre sur une erreur et ne se recharge pas d'elle-même)
for i in $(seq 60); do curl -s -o /dev/null "$PREVIEW_URL" && break; sleep 1; done

# Profil en mémoire (/run) : pas d'usure de l'eMMC, et un état neuf à chaque démarrage.
# DevTools sur 127.0.0.1:9222 seulement : sert au banc de mesure (scripts/banc/) et au diagnostic.
# Les drapeaux de décodage matériel et --ozone-platform-hint=wayland viennent de /etc/chromium.d (paquet PPA).
# --lang/--accept-lang : pages servies en français (dates, Accept-Language) et plus de bulle « traduire » sur une page
# française ; la traduction est en plus coupée par règle (/etc/chromium/policies/managed/pxl.json). Les menus de
# Chromium restent en anglais : le paquet du PPA ne livre que en-US.pak (vu le 02/10/2026) — aucun ne s'affiche en kiosque.
chromium --kiosk --no-first-run --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
  --lang=fr --accept-lang=fr-FR,fr \
  --user-data-dir="$XDG_RUNTIME_DIR/profil" --remote-debugging-port=9222 \
  --autoplay-policy=no-user-gesture-required "$PREVIEW_URL" &
CHROMIUM=$!

wait -n "$WESTON" "$CHROMIUM"
echo "Weston ou Chromium s'est arrêté — sortie pour relance par systemd"
kill "$WESTON" "$CHROMIUM" 2>/dev/null
exit 1
