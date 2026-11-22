#!/usr/bin/env bash
set -euo pipefail

MOD_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STEAM="${STEAM_DIR:-$HOME/.local/share/Steam}"
GAME="$STEAM/steamapps/common/Barotrauma"
WORKSHOP="$STEAM/steamapps/workshop/content/602960"
NT_ID=3190189044
LUACS_ID=2559634234

[ -d "$GAME" ] || { echo "Barotrauma not found at $GAME" >&2; exit 1; }

if [ -f "$GAME/Barotrauma.exe" ]; then
	PROTON=1
	SAVE="$STEAM/steamapps/compatdata/602960/pfx/drive_c/users/steamuser/AppData/Local/Daedalic Entertainment GmbH/Barotrauma"
else
	PROTON=0
	SAVE="$HOME/.local/share/Daedalic Entertainment GmbH/Barotrauma"
fi

echo "== mod -> LocalMods"
mkdir -p "$GAME/LocalMods"
rsync -a --delete --exclude tests --exclude tools --exclude .git --exclude panel_pos.txt "$MOD_DIR/" "$GAME/LocalMods/NTMedicAssistant/"

echo "== loader -> Neurotrauma"
NT="$SAVE/WorkshopMods/Installed/$NT_ID"
if [ -d "$NT/Lua/Autorun" ]; then
	cp "$MOD_DIR/loader.lua" "$NT/Lua/Autorun/zz_ntma_loader.lua"
	echo "   $NT/Lua/Autorun/zz_ntma_loader.lua"
else
	echo "   Neurotrauma is not installed yet (start the game once so it installs workshop mods)" >&2
fi

echo "== client-side LuaCs"
BIN="$WORKSHOP/$LUACS_ID/Binary"
LUACS_FILES=(
	0Harmony.dll BarotraumaCore.dll BarotraumaCore.pdb Barotrauma.deps.json Barotrauma.dll Barotrauma.pdb
	Basic.Reference.Assemblies.Net80.dll DedicatedServer.deps.json DedicatedServer.dll DedicatedServer.pdb
	FluentResults.dll LightInject.dll Microsoft.CodeAnalysis.CSharp.dll Microsoft.CodeAnalysis.dll
	Microsoft.Extensions.Logging.Abstractions.dll Microsoft.Toolkit.Diagnostics.dll Mono.Cecil.dll
	Mono.Cecil.Mdb.dll Mono.Cecil.Pdb.dll Mono.Cecil.Rocks.dll MonoMod.Backports.dll MonoMod.Core.dll
	MonoMod.Iced.dll MonoMod.ILHelpers.dll MonoMod.RuntimeDetour.dll MonoMod.Utils.dll
	MoonSharp.Interpreter.dll MoonSharp.VsCodeDebugger.dll OneOf.dll Publicized/BarotraumaCore.dll
	Publicized/Barotrauma.dll Publicized/DedicatedServer.dll Sigil.dll System.Collections.Immutable.dll
	System.Reflection.Metadata.dll System.Runtime.CompilerServices.Unsafe.dll
)
if [ "$PROTON" = 0 ]; then
	echo "   native Linux build: the workshop LuaCs binaries are Windows-only, install the linux client patch from"
	echo "   https://github.com/evilfactory/LuaCsForBarotrauma/releases instead"
elif [ ! -f "$BIN/Barotrauma.dll" ]; then
	echo "   Lua For Barotrauma ($LUACS_ID) is not downloaded" >&2
elif cmp -s "$BIN/Barotrauma.dll" "$GAME/Barotrauma.dll"; then
	echo "   already installed"
else
	game_ver=$(grep -m1 -oE 'v[0-9]+(\.[0-9]+){3}' "$GAME/changelog.txt" | tr -d v)
	luacs_ver=$(grep -oE 'gameversion="[^"]+"' "$WORKSHOP/$LUACS_ID/filelist.xml" | cut -d'"' -f2)
	if [ "$game_ver" != "$luacs_ver" ]; then
		echo "   LuaCs is built for $luacs_ver but the game is $game_ver: wait for a LuaCs update" >&2
		exit 1
	fi
	if ! grep -a -q LuaCsSetup "$GAME/Barotrauma.dll"; then
		mkdir -p "$GAME/Temp/Original/Publicized"
		for f in "${LUACS_FILES[@]}"; do
			if [ -f "$GAME/$f" ]; then cp -p "$GAME/$f" "$GAME/Temp/Original/$f"; fi
		done
	fi
	for f in "${LUACS_FILES[@]}"; do
		mkdir -p "$(dirname "$GAME/$f")"
		cp "$BIN/$f" "$GAME/$f"
	done
	echo "   installed LuaCs for $game_ver (vanilla files in $GAME/Temp/Original)"
fi
echo "done"
