@echo off
echo ==============================================
echo INICIANDO DESPLIEGUE AUTOMATICO DE DESCON V2.0
echo ==============================================

echo [1/5] Firmando y generando manifest.json de los PCKs...
node Server/tools/package_updates.js
if %errorlevel% neq 0 (
    echo [ERROR] Error al firmar los PCKs. Despliegue cancelado.
    pause
    exit /b %errorlevel%
)

echo [2/5] Agregando cambios a Git...
git add .

echo [3/5] Creando commit local...
git commit -m "build: actualizacion automatica de codigo"

echo [4/5] Subiendo cambios a GitHub...
git push origin master
if %errorlevel% neq 0 (
    echo [ERROR] Fallo al subir cambios a GitHub. Despliegue cancelado.
    pause
    exit /b %errorlevel%
)

set UPLOAD_MANIFEST=N
set /p UPLOAD_WIN="Deseas subir el parche de Windows (1.6GB) a Oracle Cloud? (S/N): "
if /i "%UPLOAD_WIN%"=="S" (
    echo [5/6] Subiendo updates_windows.pck directamente a Oracle Cloud...
    scp -i "E:\Descon\OracleCloud\ssh-key-2026-04-20.key" Server/public/cdn/updates_windows.pck ubuntu@138.2.241.76:~/Descon/Server/public/cdn/
    if %errorlevel% neq 0 (
        echo [ERROR] Error al subir updates_windows.pck.
        pause
        exit /b %errorlevel%
    )
    set UPLOAD_MANIFEST=S
)

set /p UPLOAD_AND="Deseas subir el parche de Android a Oracle Cloud? (S/N): "
if /i "%UPLOAD_AND%"=="S" (
    echo [5/6] Subiendo updates_android.pck directamente a Oracle Cloud...
    scp -i "E:\Descon\OracleCloud\ssh-key-2026-04-20.key" Server/public/cdn/updates_android.pck ubuntu@138.2.241.76:~/Descon/Server/public/cdn/
    if %errorlevel% neq 0 (
        echo [ERROR] Error al subir updates_android.pck.
        pause
        exit /b %errorlevel%
    )
    set UPLOAD_MANIFEST=S
)

if "%UPLOAD_MANIFEST%"=="S" (
    echo [5/6] Subiendo manifest.json directamente a Oracle Cloud...
    scp -i "E:\Descon\OracleCloud\ssh-key-2026-04-20.key" Server/public/cdn/manifest.json ubuntu@138.2.241.76:~/Descon/Server/public/cdn/
    if %errorlevel% neq 0 (
        echo [ERROR] Error al subir manifest.json.
        pause
        exit /b %errorlevel%
    )
) else (
    echo [5/6] Omitiendo subida de manifest y parches por SCP.
)

echo [6/6] Actualizando y reiniciando servidor Oracle Cloud...
ssh -i "E:\Descon\OracleCloud\ssh-key-2026-04-20.key" ubuntu@138.2.241.76 "cd ~/Descon && git pull origin master && pm2 restart mmo-server"
if %errorlevel% neq 0 (
    echo [ERROR] Error al actualizar servidor Oracle Cloud.
    pause
    exit /b %errorlevel%
)

echo ==============================================
echo DESPLIEGUE FINALIZADO EXITOSAMENTE
echo ==============================================
pause
