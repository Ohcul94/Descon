@echo off
echo ==============================================
echo INICIANDO DESPLIEGUE AUTOMATICO DE DESCON V2.0
echo ==============================================

echo [1/6] Firmando y generando manifest.json de los PCKs...
set GODOT_BIN=E:\PROGRAMAS\Godot\Godot_v4.7-stable_win64_console.exe
node Server/tools/package_updates.js
if %errorlevel% neq 0 (
    echo [ERROR] Error al firmar los PCKs. Despliegue cancelado.
    pause
    exit /b %errorlevel%
)

echo [2/6] Agregando cambios a Git...
git add .

echo [3/6] Creando commit local...
git commit -m "build: actualizacion automatica de codigo"

echo [4/6] Subiendo cambios a GitHub...
git push origin master
if %errorlevel% neq 0 (
    echo [ERROR] Fallo al subir cambios a GitHub. Despliegue cancelado.
    pause
    exit /b %errorlevel%
)

echo [5/6] Actualizando codigo en el servidor Oracle Cloud...
ssh -i "E:\Descon\OracleCloud\ssh-key-2026-04-20.key" ubuntu@138.2.241.76 "cd ~/Descon && git pull origin master"
if %errorlevel% neq 0 (
    echo [ERROR] Error al hacer git pull en el servidor Oracle Cloud.
    pause
    exit /b %errorlevel%
)

echo [6/6] Subiendo parches y manifest.json a Oracle Cloud CDN...
ssh -i "E:\Descon\OracleCloud\ssh-key-2026-04-20.key" ubuntu@138.2.241.76 "mkdir -p ~/Descon/Server/public/cdn"

if exist "Server\public\cdn\Actualizacion_Windows.pck" (
    echo Subiendo Actualizacion_Windows.pck...
    scp -i "E:\Descon\OracleCloud\ssh-key-2026-04-20.key" "Server/public/cdn/Actualizacion_Windows.pck" ubuntu@138.2.241.76:~/Descon/Server/public/cdn/
)

if exist "Server\public\cdn\Actualizacion_Android.pck" (
    echo Subiendo Actualizacion_Android.pck...
    scp -i "E:\Descon\OracleCloud\ssh-key-2026-04-20.key" "Server/public/cdn/Actualizacion_Android.pck" ubuntu@138.2.241.76:~/Descon/Server/public/cdn/
)

if exist "Server\public\cdn\manifest.json" (
    echo Subiendo manifest.json...
    scp -i "E:\Descon\OracleCloud\ssh-key-2026-04-20.key" "Server/public/cdn/manifest.json" ubuntu@138.2.241.76:~/Descon/Server/public/cdn/
)


echo [6/6] Reiniciando servidor en Oracle Cloud...
ssh -i "E:\Descon\OracleCloud\ssh-key-2026-04-20.key" ubuntu@138.2.241.76 "pm2 restart mmo-server"
if %errorlevel% neq 0 (
    echo [ERROR] Error al reiniciar el servidor en Oracle Cloud.
    pause
    exit /b %errorlevel%
)

echo ==============================================
echo DESPLIEGUE FINALIZADO EXITOSAMENTE
echo ==============================================
pause
