@echo off
chcp 65001 >nul
rem Défait serveur-heure-windows.cmd : coupe le serveur NTP de Windows et ferme le port UDP 123. En ADMINISTRATEUR.
net session >nul 2>&1 || (echo Il faut lancer ce script en ADMINISTRATEUR. & pause & exit /b 1)
reg add "HKLM\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" /v Enabled /t REG_DWORD /d 0 /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Config" /v AnnounceFlags /t REG_DWORD /d 10 /f >nul
netsh advfirewall firewall delete rule name="PXL serveur de temps (NTP UDP 123)" >nul 2>&1
net stop w32time >nul 2>&1
net start w32time >nul
w32tm /config /update >nul
echo Serveur de temps coupé, port fermé.
pause
