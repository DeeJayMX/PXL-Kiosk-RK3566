@echo off
chcp 65001 >nul
rem ============================================================================================================
rem  PC vMix : SERVEUR DE TEMPS pour la box d'habillage (et tout le car régie), sans Internet.
rem  A lancer UNE FOIS, clic droit > « Exécuter en tant qu'administrateur ».
rem  Puis, dans la page d'administration de la box (http://pxl-habillage:8791/, section Heure) : mettre l'adresse IP
rem  de ce PC dans « Serveurs de temps locaux ». La box dira si elle reçoit l'heure.
rem  Défaire : serveur-heure-windows-annuler.cmd
rem
rem  Ce que ça fait : active le serveur NTP intégré à Windows (service W32Time), le déclare « source fiable » même sans
rem  Internet (AnnounceFlags=5 : tout le car prend l'heure de ce PC), démarre le service au boot, ouvre UDP 123 entrant.
rem  ⚠ L'heure servie est celle de ce PC : la régler juste avant l'événement (ou laisser Windows la prendre sur Internet).
rem ============================================================================================================
net session >nul 2>&1 || (echo Il faut lancer ce script en ADMINISTRATEUR ^(clic droit ^> Executer en tant qu'administrateur^). & pause & exit /b 1)
echo Activation du serveur de temps Windows...
reg add "HKLM\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" /v Enabled /t REG_DWORD /d 1 /f >nul || goto echec
reg add "HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Config" /v AnnounceFlags /t REG_DWORD /d 5 /f >nul || goto echec
sc config w32time start= auto >nul
net stop w32time >nul 2>&1
net start w32time >nul || goto echec
w32tm /config /update >nul
netsh advfirewall firewall delete rule name="PXL serveur de temps (NTP UDP 123)" >nul 2>&1
netsh advfirewall firewall add rule name="PXL serveur de temps (NTP UDP 123)" dir=in action=allow protocol=UDP localport=123 profile=any >nul || goto echec
echo.
echo OK : ce PC sert l'heure sur le port UDP 123.
echo Adresses de ce PC (a mettre dans la page d'administration de la box) :
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do echo    %%a
echo.
w32tm /query /configuration | findstr /i "Enabled AnnounceFlags"
pause
exit /b 0
:echec
echo ECHEC : voir le message ci-dessus.
pause
exit /b 1
