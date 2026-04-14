@echo off
setlocal
title Conectando via Cloudflare Tunnel...

:: --- CONFIGURACION ---
:: PEGA AQUI EL LINK QUE TE DA EL TUNEL (SIN EL http:// ni https://)
:: Ejemplo: random-word-abcd.trycloudflare.com
set TUNNEL_URL=mileage-cakes-teaches-personal.trycloudflare.com
set EXE_NAME=descon.exe
:: ---------------------

echo ========================================
echo   LANZADOR CON TUNEL (CLOUDFLARE)
echo ========================================
echo.
echo URL: %TUNNEL_URL%
echo.

if not exist "%EXE_NAME%" (
    echo [ERROR] No encuentro el archivo %EXE_NAME%
    pause
    exit
)

start "" "%EXE_NAME%" --ip %TUNNEL_URL% --port 443
echo !Buen viaje, Piloto!
timeout /t 3 > nul
exit
