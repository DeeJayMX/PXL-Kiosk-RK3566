#!/bin/bash
# HTTPS sur l'adresse PXLnet de la box (04/10/2026, Eliott) — certificat Let's Encrypt fourni par PXLnet pour le nom
# MagicDNS (<box>.<tailnet>.ts.net), renouvelé par tailscaled lui-même. « serve » et JAMAIS « funnel » : l'adresse n'est
# joignable QUE depuis PXLnet. Les adresses en http (réseau local, vMix, Companion, admin) ne changent pas.
#   443 → relais TurboHQ (:8080) — SEUL (décision d'Eliott, 04/10 : « le reste n'a pas besoin d'https »). La raison :
#   le viewer n'a son chemin basse latence (WebCodecs) qu'en contexte sécurisé ; en http il bascule en MSE.
# « serve reset » d'abord : une règle d'avant (443 → habillage, 8443, 10000 — posées le 04/10 puis retirées) ne survit pas.
# Sans PXLnet connecté, ou sans HTTPS activé sur le réseau PXLnet (CertDomains vide), on ne fait rien — sortie 0.
# ⚠ Le nom de la box apparaît dans les journaux publics de certificats (Certificate Transparency) : le NOM, pas l'accès.
. /etc/pxl-kiosk.conf 2>/dev/null
[ "${PXLNET_HTTPS:-1}" = 1 ] || { echo "HTTPS PXLnet coupé (PXLNET_HTTPS=0)"; exit 0; }
for i in $(seq 30); do tailscale status --self --peers=false >/dev/null 2>&1 && break; sleep 2; done
tailscale status --self --peers=false >/dev/null 2>&1 || { echo "PXLnet non connecté — rien posé"; exit 0; }
if ! tailscale status --json 2>/dev/null | tr -d ' \n' | grep -q '"CertDomains":\["'; then
  echo "HTTPS non activé sur le réseau PXLnet (console d'administration du réseau → DNS → HTTPS Certificates) — rien posé"; exit 0
fi
if tailscale serve status --json 2>/dev/null | tr -d ' \n' | grep -q '^{"TCP":{"443":{"HTTPS":true}},"Web":{"[^"]*:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:8080"}}}}}$'; then
  echo "https :443 → TurboHQ (:8080) déjà posé"; exit 0
fi
tailscale serve reset >/dev/null 2>&1
timeout 60 tailscale serve --bg --yes --https=443 http://127.0.0.1:8080 >/dev/null 2>&1 \
  && echo "https :443 → TurboHQ (:8080)" || { echo "⚠ https :443 → TurboHQ non posé"; exit 1; }
