#!/bin/bash
# pxl-reseau-secours.sh — le Wi-Fi en POINT D'ACCÈS quand aucun réseau connu n'est là, et le PARTAGE DE CONNEXION USB
# d'un téléphone (Android, iPhone). Réglé dans /admin › Réseau (AP_* de /etc/pxl-kiosk.conf, mot de passe à part).
#
#   pxl-reseau-secours.sh appliquer   (ré)écrit les deux profils NetworkManager et applique le mode
#   pxl-reseau-secours.sh veille      en mode « auto » : revenir sur un Wi-Fi connu s'il est là, sinon le point d'accès
#   pxl-reseau-secours.sh etat        une ligne JSON (pour /admin)
#
# POINT D'ACCÈS — modèle repris de la TurboNode (profil `turbohq-ap`) : un profil NetworkManager en mode ap, priorité
# −10, que NetworkManager ne prend que si aucun Wi-Fi connu n'est visible. Différences voulues :
#  - adressage et DNS par le mode « shared » de NetworkManager (dnsmasq-base) : rien de propre à maintenir ;
#  - ⭐ le RETOUR. Une radio en point d'accès ne balaie plus : sans aide, la box resterait en point d'accès même quand le
#    Wi-Fi du lieu revient. La veille (toutes les 2 min) coupe le point d'accès le temps d'un balayage — SEULEMENT si
#    aucun appareil n'y est connecté — puis rejoint un Wi-Fi connu visible, ou remonte le point d'accès.
#  - ⚠ UNE SEULE BANDE À LA FOIS : la radio n'a qu'un canal ; ses combinaisons (iw list) n'admettent deux points d'accès
#    que sur le MÊME canal (lu le 03/10/2026). 2,4 GHz canal 6, ou 5 GHz canal 36.
# Modes : auto (secours) · force (point d'accès toujours, le Wi-Fi client est délaissé) · off.
#
# PARTAGE USB : un profil Ethernet reconnu par le PILOTE du téléphone (rndis_host, cdc_ncm, cdc_ether : Android ;
# ipheth : iPhone, avec usbmuxd pour l'appairage — « Se fier à cet ordinateur » au premier branchement), en DHCP, de
# métrique 50 : branché, le téléphone passe devant l'Ethernet (100) et le Wi-Fi (600) pour Internet ; débranché, rien
# ne reste. Reconnu par le pilote et non par le nom d'interface : les noms usb0 / enx<mac> changent d'un téléphone à
# l'autre.
set -u
. /etc/pxl-kiosk.conf
NM=/etc/NetworkManager/system-connections
MDP_F=/etc/pxl-kiosk/ap.mdp
MODE=${AP_MODE:-auto}
NOM=${AP_NOM:-${NOM_MACHINE:-PXLnode}}
BANDE=${AP_BANDE:-bg}
IF=${AP_IF:-wlan0}
dire() { echo "[reseau-secours] $*"; }
ap_actif() { nmcli -t -f NAME con show --active | grep -qx pxl-ap; }
clients_ap() { iw dev "$IF" station dump 2>/dev/null | grep -c '^Station'; }

appliquer() {
  # le pays de la radio : les canaux permis en point d'accès en dépendent (sans pays : « 00 », le plus restrictif)
  iw reg set FR 2>/dev/null || true
  [ -s "$MDP_F" ] || { head -c 9 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 12 > "$MDP_F"; chmod 600 "$MDP_F"; dire "mot de passe tiré au sort (à régler dans /admin)"; }
  local canal=6; [ "$BANDE" = a ] && canal=36
  local prio=-10 auto=true; [ "$MODE" = force ] && prio=999; [ "$MODE" = off ] && auto=false
  # fichier écrit directement (jamais `nmcli … psk <mdp>`) : le mot de passe ne passe dans aucune ligne de commande
  umask 077
  { printf '[connection]\nid=pxl-ap\nuuid=%s\ntype=wifi\ninterface-name=%s\nautoconnect=%s\nautoconnect-priority=%s\n\n' \
      "$(nmcli -g connection.uuid con show pxl-ap 2>/dev/null || cat /proc/sys/kernel/random/uuid)" "$IF" "$auto" "$prio"
    printf '[wifi]\nmode=ap\nssid=%s\nband=%s\nchannel=%s\n\n' "$NOM" "$BANDE" "$canal"
    printf '[wifi-security]\nkey-mgmt=wpa-psk\nproto=rsn\npairwise=ccmp\ngroup=ccmp\npsk=%s\n\n' "$(sed 's/\\/\\\\/g' "$MDP_F")"
    printf '[ipv4]\nmethod=shared\naddress1=10.42.0.1/24\n\n[ipv6]\nmethod=disabled\n'; } > "$NM/pxl-ap.nmconnection"
  { printf '[connection]\nid=pxl-partage-usb\nuuid=%s\ntype=ethernet\nautoconnect=true\nautoconnect-priority=50\n\n' \
      "$(nmcli -g connection.uuid con show pxl-partage-usb 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
    printf '[match]\ndriver=rndis_host;cdc_ncm;cdc_ether;ipheth;\n\n'
    printf '[ipv4]\nmethod=auto\nroute-metric=50\n\n[ipv6]\nmethod=auto\nroute-metric=50\n'; } > "$NM/pxl-partage-usb.nmconnection"
  nmcli con load "$NM/pxl-ap.nmconnection" && nmcli con load "$NM/pxl-partage-usb.nmconnection" || { dire "🔴 profils refusés par NetworkManager"; return 1; }
  case "$MODE" in
    force) dire "point d'accès FORCÉ ($NOM, $([ "$BANDE" = a ] && echo 5 || echo 2,4) GHz)"; nmcli con up pxl-ap >/dev/null || dire "🔴 point d'accès impossible à monter" ;;
    off)   dire "point d'accès coupé"; ap_actif && nmcli con down pxl-ap >/dev/null ;;
    *)     # repasser en auto depuis « force » : le profil actif garde l'ancienne priorité, la veille tranche tout de suite
           ap_actif && nmcli con down pxl-ap >/dev/null; veille ;;
  esac
  sync
}

# Rejoindre le meilleur Wi-Fi connu visible ; rend 0 si c'est fait.
rejoindre_connu() {
  nmcli dev wifi rescan ifname "$IF" >/dev/null 2>&1; sleep 6
  local vus; vus=$(nmcli -t -f SSID dev wifi list ifname "$IF" --rescan no 2>/dev/null | sort -u)
  local nom
  while IFS=: read -r nom _; do
    [ -n "$nom" ] && [ "$nom" != pxl-ap ] || continue
    local ssid; ssid=$(nmcli -g 802-11-wireless.ssid con show "$nom" 2>/dev/null)
    [ "$(nmcli -g 802-11-wireless.mode con show "$nom" 2>/dev/null)" = ap ] && continue
    grep -qxF "$ssid" <<<"$vus" && nmcli con up "$nom" >/dev/null 2>&1 && { dire "Wi-Fi « $ssid » rejoint"; return 0; }
  done < <(nmcli -t -f NAME,TYPE,AUTOCONNECT-PRIORITY con show | awk -F: '$2=="802-11-wireless"{print $3":"$1}' | sort -t: -k1,1nr | cut -d: -f2-)
  return 1
}

veille() {
  # image préparée hors ligne : NetworkManager ne tournait pas, les profils s'écrivent au premier passage
  [ -f "$NM/pxl-ap.nmconnection" ] || { appliquer; return; }
  [ "$MODE" = auto ] || return 0
  if ap_actif; then
    local n; n=$(clients_ap)
    [ "$n" -gt 0 ] && return 0                                   # quelqu'un s'en sert : on ne coupe jamais
    nmcli -t -f TYPE con show | grep -qx 802-11-wireless || return 0
    nmcli con down pxl-ap >/dev/null 2>&1; sleep 2
    rejoindre_connu && return 0
    nmcli con up pxl-ap >/dev/null 2>&1 || dire "🔴 point d'accès impossible à remonter"
  elif ! nmcli -t -f DEVICE,STATE dev | grep -qx "$IF:connected"; then
    rejoindre_connu && return 0
    nmcli con up pxl-ap >/dev/null 2>&1 && dire "aucun Wi-Fi connu visible — point d'accès « $NOM » monté"
  fi
}

etat() {
  local actif=false n=0; ap_actif && { actif=true; n=$(clients_ap); }
  local usb=""
  for d in /sys/class/net/*; do
    local drv; drv=$(basename "$(readlink -f "$d/device/driver" 2>/dev/null)" 2>/dev/null)
    case "$drv" in rndis_host|cdc_ncm|cdc_ether|ipheth)
      local i; i=$(basename "$d")
      local ip; ip=$(ip -4 -o addr show "$i" | awk '{print $4}' | head -1)
      local gw; gw=$(ip -4 route show default dev "$i" | awk '{print $3}' | head -1)
      usb="$usb${usb:+,}{\"interface\":\"$i\",\"pilote\":\"$drv\",\"adresse\":\"$ip\",\"passerelle\":\"$gw\"}" ;;
    esac
  done
  printf '{"actif":%s,"clients":%s,"usb":[%s],"usbmuxd":%s}\n' "$actif" "$n" "$usb" "$(command -v usbmuxd >/dev/null && echo true || echo false)"
}

case "${1:-}" in
  appliquer) appliquer ;;
  veille)    veille ;;
  etat)      etat ;;
  *) echo "usage : $0 appliquer|veille|etat" >&2; exit 2 ;;
esac
