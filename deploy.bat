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

set /p UPLOAD_PCK="Deseas subir los archivos PCK (actualizaciones) por SCP a Oracle Cloud? (S/N): "
if /i "%UPLOAD_PCK%"=="S" (
    echo [5/6] Subiendo manifest.json y parches PCK directamente a Oracle Cloud...
    scp -i "E:\Descon\OracleCloud\ssh-key-2026-04-20.key" Server/public/cdn/* ubuntu@138.2.241.76:~/Descon/Server/public/cdn/
    if %errorlevel% neq 0 (
        echo [ERROR] Error al subir los parches PCK por SCP.
        pause
        exit /b %errorlevel%
    )
) else (
    echo [5/6] Omitiendo subida de archivos PCK por SCP.
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
