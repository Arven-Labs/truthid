#!/usr/bin/env bash
# P99 — remove as libwayland-* que o bundler do Tauri embute no AppImage.
#
# O AppImage sai com as libwayland do Ubuntu 22.04 dentro, que não combinam
# com a pilha gráfica (Mesa) de distros mais novas: no Arch/Wayland o app
# morre com "Could not create default EGL display: EGL_BAD_PARAMETER".
# Sem as libs embutidas, ele usa as do sistema e abre normalmente.
#
# Roda depois do tauri-action, sobre o release (rascunho) da tag:
#   1. baixa o AppImage e o latest.json do release;
#   2. extrai, apaga usr/lib/libwayland-*, reempacota com o MESMO runtime;
#   3. reassina (o .sig antigo deixa de valer com o conteúdo novo);
#   4. substitui AppImage, .sig e as assinaturas linux-* do latest.json.
#
# Env: REPO (dono/repo), TAG, GH_TOKEN, TAURI_SIGNING_PRIVATE_KEY e
#      TAURI_SIGNING_PRIVATE_KEY_PASSWORD (os mesmos do tauri-action).
# DRY_RUN=1 faz tudo menos subir os arquivos pro release.
# TAURI_BIN: comando do CLI do Tauri (padrão: npx tauri, dentro de desktop/).
set -euo pipefail

: "${REPO:?}" "${TAG:?}"
DRY_RUN="${DRY_RUN:-0}"
WORK="${WORK:-$(mktemp -d)}"
TAURI_BIN="${TAURI_BIN:-npx --prefix desktop tauri}"

# appimagetool fixado por versão e hash: é código que roda no CI com acesso à
# chave de assinatura do updater.
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage"
APPIMAGETOOL_SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"

api() { gh api "repos/$REPO/$1" "${@:2}"; }

# Rascunhos não aparecem em /releases/tags/{tag}; acha pelo listing.
RELEASE_JSON="$WORK/release.json"
api "releases?per_page=100" --paginate \
  | python3 -c '
import json, sys
tag = sys.argv[1]
text = sys.stdin.read()
# --paginate concatena arrays JSON; junta tudo
dec, i, items = json.JSONDecoder(), 0, []
while i < len(text):
    while i < len(text) and text[i].isspace():
        i += 1
    if i >= len(text):
        break
    obj, i = dec.raw_decode(text, i)
    items += obj
match = [r for r in items if r["tag_name"] == tag]
if len(match) != 1:
    sys.exit(f"release da tag {tag}: esperava 1, achei {len(match)}")
json.dump(match[0], sys.stdout)
' "$TAG" > "$RELEASE_JSON"

RELEASE_ID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$RELEASE_JSON")

asset_id() {
  python3 -c '
import json, sys
a = [x for x in json.load(open(sys.argv[1]))["assets"] if x["name"] == sys.argv[2]]
print(a[0]["id"] if a else "")
' "$RELEASE_JSON" "$1"
}

download() { # nome -> arquivo em $WORK
  local id; id=$(asset_id "$1")
  [ -n "$id" ] || { echo "asset $1 não existe no release $TAG" >&2; exit 1; }
  api "releases/assets/$id" -H "Accept: application/octet-stream" > "$WORK/$1"
}

upload() { # arquivo em $WORK, substitui o asset de mesmo nome
  local name="$1" id
  if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] não sobe $name"; return; fi
  id=$(asset_id "$name")
  [ -z "$id" ] || api "releases/assets/$id" -X DELETE
  gh api --method POST -H "Content-Type: application/octet-stream" \
    "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$name" \
    --input "$WORK/$name" > /dev/null
  echo "enviado: $name"
}

APPIMAGE_NAME=$(python3 -c '
import json, sys
n = [a["name"] for a in json.load(open(sys.argv[1]))["assets"] if a["name"].endswith(".AppImage")]
if len(n) != 1:
    sys.exit(f"esperava 1 .AppImage, achei {n}")
print(n[0])
' "$RELEASE_JSON")

echo "AppImage: $APPIMAGE_NAME"
download "$APPIMAGE_NAME"
download latest.json
chmod +x "$WORK/$APPIMAGE_NAME"

curl -fsSL "$APPIMAGETOOL_URL" -o "$WORK/appimagetool"
echo "$APPIMAGETOOL_SHA256  $WORK/appimagetool" | sha256sum -c -
chmod +x "$WORK/appimagetool"

cd "$WORK"
# --appimage-extract-and-run / --appimage-extract: o runner não tem FUSE.
OFFSET=$("./$APPIMAGE_NAME" --appimage-offset)
head -c "$OFFSET" "$APPIMAGE_NAME" > runtime.bin   # runtime original, preservado

rm -rf squashfs-root
"./$APPIMAGE_NAME" --appimage-extract > /dev/null
shopt -s nullglob
WL=(squashfs-root/usr/lib/libwayland-*)
if [ ${#WL[@]} -eq 0 ]; then
  echo "AppImage já está sem libwayland-*; nada a fazer."
  exit 0
fi
echo "removendo: ${WL[*]##*/}"
rm -f "${WL[@]}"

ARCH=x86_64 ./appimagetool --appimage-extract-and-run \
  --runtime-file runtime.bin squashfs-root "fixed.AppImage" > /dev/null
mv fixed.AppImage "$APPIMAGE_NAME"
chmod +x "$APPIMAGE_NAME"

# Garante que o resultado realmente saiu sem as libs.
rm -rf check && mkdir check && (cd check && "../$APPIMAGE_NAME" --appimage-extract > /dev/null)
if compgen -G "check/squashfs-root/usr/lib/libwayland-*" > /dev/null; then
  echo "libwayland-* ainda presente no AppImage reempacotado" >&2; exit 1
fi

# Reassina. O CLI lê TAURI_SIGNING_PRIVATE_KEY(_PASSWORD) do ambiente.
cd - > /dev/null
$TAURI_BIN signer sign "$WORK/$APPIMAGE_NAME"
[ -s "$WORK/$APPIMAGE_NAME.sig" ] || { echo "assinatura não foi gerada" >&2; exit 1; }

# latest.json: o campo signature é o conteúdo do .sig, nas duas chaves linux.
python3 - "$WORK/latest.json" "$WORK/$APPIMAGE_NAME.sig" "$APPIMAGE_NAME" <<'PY'
import json, sys
path, sig_path, name = sys.argv[1:]
sig = open(sig_path).read().strip()
d = json.load(open(path))
n = 0
for key, plat in d["platforms"].items():
    if plat["url"].endswith("/" + name):
        plat["signature"] = sig
        n += 1
if n == 0:
    sys.exit(f"nenhuma entrada do latest.json aponta pra {name}")
json.dump(d, open(path, "w"), indent=2)
print(f"latest.json: {n} entradas atualizadas")
PY

upload "$APPIMAGE_NAME"
upload "$APPIMAGE_NAME.sig"
upload latest.json
echo "pronto: $WORK"
