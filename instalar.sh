#!/bin/bash
# Compila Dictado, arma el .app, lo firma ad-hoc y lo instala en ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Dictado.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Dictado "$APP/Contents/MacOS/Dictado"
cp Recursos/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Recursos/Dictado.icns "$APP/Contents/Resources/Dictado.icns"
# Con el certificado local "Dictado Local" (ver README) los permisos sobreviven a las actualizaciones;
# sin él, firma ad-hoc y macOS vuelve a pedir micrófono y Accesibilidad tras cada instalación.
if security find-certificate -c "Dictado Local" >/dev/null 2>&1; then FIRMA="Dictado Local"; else FIRMA="-"; fi
codesign --force --sign "$FIRMA" --identifier app.dictado "$APP"

pkill -x Dictado 2>/dev/null || true
mkdir -p "$HOME/Applications"
ditto "$APP" "$HOME/Applications/Dictado.app"
open "$HOME/Applications/Dictado.app"
echo "Dictado instalado en ~/Applications/Dictado.app"
