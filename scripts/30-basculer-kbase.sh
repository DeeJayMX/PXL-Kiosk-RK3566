#!/bin/bash
# Remplace Panfrost par le pilote kbase compilé. Coupe l'affichage de la box.
# Retour : UNIQUEMENT par redémarrage (restaurer.sh le fait). 🔴 Jamais de rmmod de
# bifrost_kbase : Oops du noyau au modeset suivant (mesuré le 30/09/2026).
. "$(dirname "$0")/commun.sh"

[ -f "$KBASE_KO" ] || meurs "module absent — lancer 10-compiler-kbase.sh"

# Filet : si kbase fait planter le noyau, la box redémarre seule en 10 s — donc
# revient sur Panfrost et sur le réseau. Remis à la valeur d'origine par restaurer.sh.
sysctl -qw kernel.panic=10 kernel.panic_on_oops=1

dire "arrêt des services qui tiennent l'affichage : $SERVICES_AFFICHAGE"
systemctl stop $SERVICES_AFFICHAGE 2>/dev/null || true
sleep 2
if lsmod | grep -q '^panfrost'; then rmmod panfrost || meurs "panfrost occupé (un client GL tourne ?)"; fi
lsmod | grep -q '^bifrost_kbase' || insmod "$KBASE_KO" || meurs "insmod échoué — dmesg"
sleep 1
[ -c /dev/mali0 ] || meurs "/dev/mali0 absent — dmesg | grep -i mali"
dmesg | grep -E 'mali .*(GPU identified|Probed as)' | tail -2
# Avec patches/kbase-opp-ophub.patch : devfreq 200-800 MHz. Pour un kiosque vidéo, gouverneur
# « performance » (le simple_ondemand monte trop tard : 49 au lieu de 58 img/s en 1080p60).
grep -E ' clk_gpu ' /sys/kernel/debug/clk/clk_summary 2>/dev/null | awk '{print "clk_gpu =", $5/1e6, "MHz"}'
dire "kbase actif"
