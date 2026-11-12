@echo off
REM Corre SkonditBeats en el celular fisico conectado por USB.
REM Requisito: la API corriendo en la PC (cd D:\Angular\erp_beats\api && npm run dev)

set ADB=D:\AndroidSDK\platform-tools\adb.exe

REM Une el puerto 3000 del celular con el de la PC (por el cable USB)
%ADB% reverse tcp:3000 tcp:3000 || (echo No se encontro el celular. Revisa el cable y la depuracion USB. & exit /b 1)

REM Toma el primer dispositivo fisico (ignora emuladores)
for /f "tokens=1" %%d in ('%ADB% devices ^| findstr /v "emulator List" ^| findstr "device"') do set CEL=%%d & goto :run
echo No hay celular conectado. & exit /b 1

:run
echo Celular: %CEL%
flutter run -d %CEL% --dart-define=API_URL=http://127.0.0.1:3000/api
