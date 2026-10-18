// Gera lib/releases.generated.json com as URLs dos instaladores a partir dos
// GitHub Releases. Pra cada instalador, usa o release mais recente que
// contém o asset (Desktop, Mobile e extensão nem sempre saem juntos).
// Rodado pelo deploy-docs.yml antes do build; o JSON commitado serve de
// fallback pro `npm run dev` local.
import { writeFileSync } from "node:fs";

const REPO = process.env.GITHUB_REPOSITORY || "masterlxz/truthid";
const headers = { Accept: "application/vnd.github+json" };
if (process.env.GH_TOKEN) headers.Authorization = `Bearer ${process.env.GH_TOKEN}`;

const res = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=30`, { headers });
if (!res.ok) throw new Error(`GitHub API ${res.status}: ${await res.text()}`);
const releases = (await res.json()).filter((r) => !r.draft && !r.prerelease);

const patterns = {
  deb: /_amd64\.deb$/,
  appImage: /_amd64\.AppImage$/,
  rpm: /\.x86_64\.rpm$/,
  exe: /_x64-setup\.exe$/,
  msi: /_x64_en-US\.msi$/,
  dmg: /_aarch64\.dmg$/,
  apk: /^app-release\.apk$/,
  extension: /^truthid-vault-extension-.*-chrome\.zip$/,
};

const urls = {};
for (const [key, re] of Object.entries(patterns)) {
  for (const r of releases) {
    const asset = r.assets.find((a) => re.test(a.name));
    if (asset) {
      urls[key] = asset.browser_download_url;
      break;
    }
  }
  if (!urls[key]) throw new Error(`Nenhum release contém o asset "${key}"`);
}

const out = { releasePageUrl: releases[0].html_url, urls };
writeFileSync(new URL("../lib/releases.generated.json", import.meta.url), JSON.stringify(out, null, 2) + "\n");
console.log(`releases.generated.json: ${releases[0].tag_name}`);
