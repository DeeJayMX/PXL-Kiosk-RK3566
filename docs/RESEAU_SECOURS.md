# Wi-Fi de secours (point d'accès) et partage de connexion USB — 03/10/2026, v1.12.0

`installation/fichiers/pxl-reseau-secours.sh` (`appliquer` · `veille` · `etat`), réglé dans **/admin › Réseau**.

## Point d'accès de secours

Modèle **lu sur la TurboNode** (profil NetworkManager `turbohq-ap` : mode ap, priorité −10, 10.42.0.1/24), avec deux
différences voulues :

- **adressage et DNS par le mode « shared » de NetworkManager** (`dnsmasq-base`) — la TurboNode a ses propres serveurs
  (`turbohq-dhcp`, `turbohq-dns`, code TurboHQ privé) ; la recette reste publique et sans service à maintenir ;
- **le retour** : une radio en point d'accès ne balaie plus. La TurboNode n'en revient que par son menu ; ici
  `pxl-ap-veille.timer` (toutes les 2 min, mode auto seulement) coupe le point d'accès le temps d'un balayage —
  **jamais si un appareil y est connecté** — rejoint un Wi-Fi connu visible, sinon le remonte.

Modes : `auto` (secours) · `force` (toujours ; /admin applique en différé de 2 s pour que la réponse parte avant la
coupure du Wi-Fi client) · `off`. Nom `AP_NOM` (défaut `NOM_MACHINE`), mot de passe dans `/etc/pxl-kiosk/ap.mdp`
(0600, jamais dans le dépôt ni réaffiché ; tiré au sort s'il manque). Pays de la radio : FR (`/etc/modprobe.d/pxl-wifi-pays.conf`).

⚠️ **Une seule bande à la fois** (lu, `iw list`) : la radio n'admet deux points d'accès que sur le **même** canal. Le
« 5 + 2,4 » simultané n'est pas possible : 2,4 GHz canal 6 **ou** 5 GHz canal 36, au choix dans /admin.

**Mesuré sur la PXLnode (03/10/2026)**, chaque essai forcé sous la garde d'un retour automatique programmé à 75 s
(sans lui, couper le Wi-Fi client coupe aussi l'accès distant à la box) :

| essai | résultat |
|---|---|
| auto, Wi-Fi « PXL » visible | la box **reste** sur PXL ; pays de la radio FR |
| forcé 2,4 GHz | « PXLnode » vu depuis la TurboNode : canal 6, signal 100, WPA2 |
| forcé 5 GHz | journal de NetworkManager : fréquence 5180 MHz, `AP-ENABLED`, dnsmasq lancé (vu de la TurboNode : seulement l'ancienne entrée en cache) |
| retour en auto | Wi-Fi « PXL » rejoint **9 s** et **10 s** après |

⚠️ **Non mesuré** : un appareil réellement connecté au point d'accès (bail DHCP, console joignable sur 10.42.0.1),
et le passage « Wi-Fi connu disparu → point d'accès » (il couperait l'accès distant : à faire au labo, sur place).
Avertissement sans conséquence vu au journal : `chown of PID file /run/nm-dnsmasq-wlan0.pid failed`.

## Partage de connexion USB (Android, iPhone)

Profil `pxl-partage-usb` reconnu par le **pilote** du téléphone (`rndis_host`, `cdc_ncm`, `cdc_ether` : Android ;
`ipheth` : iPhone), DHCP, **métrique 50** : branché, le téléphone passe devant l'Ethernet (100) et le Wi-Fi (600) ;
débranché, rien ne reste. Par le pilote et non par le nom : `usb0`, `enx<mac>` changent d'un téléphone à l'autre.
iPhone : `usbmuxd` (lancé par udev au branchement) + « Se fier à cet ordinateur » la première fois.
Vérifié : les quatre modules existent dans le noyau 6.1.141 de la box, NetworkManager accepte la règle de pilote, et
les deux profils Ethernet existants sont bien attachés à `eth0` (ils ne peuvent pas prendre le téléphone).
⚠️ **Non mesuré : aucun téléphone n'a encore été branché.**
