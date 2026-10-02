#!/bin/bash
# Les étapes du démarrage, sur l'écran PXL (thème Plymouth « pxl ») — pxl-etapes.service.
# Lit l'état réel de la box toutes les demi-secondes et l'envoie à Plymouth (« pxl|étape|état|détail », voir pxl.script).
# Même vocabulaire que la façade : « ntP » tant que l'heure n'est pas synchronisée, puis « SYnC ».
# S'arrête quand l'écran de démarrage a disparu (la preview l'a refermé : fin-ecran-demarrage.sh), au plus tard après 5 min.
. /etc/pxl-kiosk.conf 2>/dev/null
APP_PORT=${APP_PORT:-8765}
SECOURS=$(sed -n 's/^SECOURS_ADR=\([0-9.]*\).*/\1/p' /etc/default/pxl-secours-reseau 2>/dev/null)
declare -A dernier
envoyer() {   # étape (1-6, F), état (0 attente · 1 en cours · 2 fait · 3 défaut · 4 avertissement), détail — seulement si ça change
  local m="pxl|$1|$2|$3"
  [ "${dernier[$1]}" = "$m" ] && return
  dernier[$1]=$m; plymouth update --status="$m" 2>/dev/null
}
secondes() { cut -d. -f1 /proc/uptime; }   # pas l'horloge : elle saute au moment de la synchronisation
adresse() { ip -4 -o addr show dev "$1" scope global 2>/dev/null | awk '{sub(/\/.*/, "", $4); print $4}' | grep -vx "${SECOURS:-x}" | head -1; }

V=$(sed -n 's/^recette=//p' /etc/pxl-kiosk/version 2>/dev/null); A=$(cat "${APP_DIR:-/opt/pxl-app}/VERSION" 2>/dev/null)
envoyer F 0 "$(hostname)${V:+  ·  box v$V}${A:+  ·  habillage v$A}"
while plymouth --ping 2>/dev/null && [ "$(secondes)" -lt 300 ]; do
  t=$(secondes)

  # 1 · système
  if systemctl is-active -q multi-user.target; then envoyer 1 2 "démarré en ${t} s"
  elif systemctl is-active -q basic.target; then envoyer 1 2 "services en cours de lancement"; fi

  # 2 · réseau : Ethernet d'abord, puis Wi-Fi ; l'adresse de secours seule = aucun DHCP
  eth=$(adresse eth0); wifi=$(adresse wlan0)
  if [ -n "$eth" ]; then envoyer 2 2 "Ethernet · $eth"
  elif [ -n "$wifi" ]; then envoyer 2 2 "Wi-Fi $(iw dev wlan0 link 2>/dev/null | sed -n 's/^\s*SSID: //p') · $wifi"
  elif [ -n "$SECOURS" ] && ip -4 -o addr show dev eth0 2>/dev/null | grep -q " $SECOURS/"; then envoyer 2 4 "aucun DHCP — adresse de secours $SECOURS"
  elif [ "$(cat /sys/class/net/eth0/carrier 2>/dev/null)" = 1 ]; then envoyer 2 1 "câble branché, attente d'une adresse…"
  else envoyer 2 1 "recherche (Ethernet débranché, Wi-Fi…)"; fi

  # 3 · heure : la box n'a pas d'horloge sauvegardée
  if chronyc -n tracking 2>/dev/null | grep -q '^Leap status *: Normal'; then
    src=$(timeout 2 chronyc tracking 2>/dev/null | sed -n 's/^Reference ID *: [0-9A-F]* (\(.*\))$/\1/p')
    envoyer 3 2 "synchronisée${src:+ sur $src} — $(date +%H:%M:%S)   (façade : SYnC)"
  elif [ "$t" -gt 90 ]; then envoyer 3 4 "aucun serveur de temps — heure NON fiable   (façade : ntP)"
  else envoyer 3 1 "synchronisation…   (façade : ntP)"; fi

  # 4 · PXLnet (Tailscale)
  ts=$(tailscale ip -4 2>/dev/null | head -1)
  if [ -n "$ts" ] && tailscale status --json 2>/dev/null | grep -q '"BackendState": *"Running"'; then envoyer 4 2 "$ts"
  elif systemctl is-active -q tailscaled; then envoyer 4 1 "connexion…"
  else envoyer 4 0 ""; fi

  # 5 · serveur d'habillage (il attend l'heure 60 s au plus)
  if curl -sf -m 1 -o /dev/null "http://127.0.0.1:$APP_PORT/api/sante"; then envoyer 5 2 "prêt · port $APP_PORT"
  elif systemctl is-active -q pxl-serveur; then envoyer 5 1 "démarrage…"
  elif systemctl is-active -q chrony-wait; then envoyer 5 1 "attend l'heure (60 s au plus)"
  else envoyer 5 1 "attente…"; fi

  # 6 · preview (elle referme cet écran au moment de s'afficher)
  if systemctl is-active -q pxl-preview || [ "$(systemctl show -p ActiveState --value pxl-preview)" = activating ]; then envoyer 6 1 "ouverture de l'affichage…"
  else envoyer 6 0 "après le serveur"; fi

  sleep 0.5
done
exit 0
