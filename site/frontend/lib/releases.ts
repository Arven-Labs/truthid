// Desktop installers, APK and the browser extension package, hosted as
// GitHub Release assets. The URLs live in releases.generated.json, produced
// by scripts/gen-releases.mjs (run by deploy-docs.yml on every release), so
// nothing here needs editing when a new version is cut. Each installer comes
// from the newest release that contains it — Desktop, Mobile and the
// extension don't always ship together.
import generated from "./releases.generated.json";

const { urls } = generated;

export const desktopDownloads = {
  linux: { deb: urls.deb, appImage: urls.appImage, rpm: urls.rpm },
  windows: { exe: urls.exe, msi: urls.msi },
  // Apple Silicon only — the macos-latest CI runner doesn't produce an
  // Intel build.
  macos: { dmg: urls.dmg },
  android: { apk: urls.apk },
};

export const extensionDownloadUrl = urls.extension;

export const releasePageUrl = generated.releasePageUrl;

// APT repository (project/ROADMAP.md, "Instaladores nativos", Sessão 217) —
// unlike the URLs above, not tied to TAG: deploy-docs.yml remounts /apt/
// from the latest published release on every deploy, so this path stays
// stable across versions.
export const aptKeyringUrl =
  "https://arven-labs.github.io/truthid/apt/truthid-archive-keyring.gpg";
export const aptSourceLine =
  "deb [signed-by=/usr/share/keyrings/truthid-archive-keyring.gpg] https://arven-labs.github.io/truthid/apt stable main";
