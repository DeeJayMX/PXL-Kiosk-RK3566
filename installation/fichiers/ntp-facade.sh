#!/bin/bash
# « ntP » clignote sur la façade tant que l'heure n'est pas synchronisée (pxl-ntp-facade.service).
# La box n'a pas d'horloge sauvegardée : au démarrage, elle repart à l'heure de son dernier arrêt (fake-hwclock).
# Tant que chrony n'a pas de source, l'heure affichée — et celle de l'habillage — est FAUSSE : on le montre.
# Le message passe par /run/turbohq-facade (affiché 6 s après sa dernière écriture, par ht1628 --service).
F=/run/turbohq-facade
synchro() { chronyc -n tracking 2>/dev/null | grep -q '^Leap status *: Normal'; }
etat=0
until synchro; do
  if [ $etat = 0 ]; then echo "ntP" > $F; etat=1; else echo " " > $F; etat=0; fi
  sleep 0.5
done
echo "SYnC" > $F   # synchronisée : « SYnC » 6 s, puis l'horloge reprend la main (pas de « k » dans la police)
exit 0
