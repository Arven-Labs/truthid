import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { invoke } from "@tauri-apps/api/core";

interface BundlerConfigData {
  api_key: string;
  network: string;
}

const NETWORKS = ["base", "base-sepolia"];

// Configuração do bundler Pimlico (chave de API + rede) — antes só dava pra
// configurar editando ~/.truthid/bundler_config.json na mão, e o erro
// "Bundler not configured" não dizia onde. Usa os comandos
// get_bundler_config/save_bundler_config que já existiam.
export function BundlerConfig() {
  const { t } = useTranslation();

  const [apiKey, setApiKey] = useState("");
  const [network, setNetwork] = useState("base");
  const [showKey, setShowKey] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    invoke<BundlerConfigData>("get_bundler_config")
      .then((config) => {
        setApiKey(config.api_key ?? "");
        if (config.network) setNetwork(config.network);
      })
      .catch(() => {})
      .finally(() => setLoaded(true));
  }, []);

  async function handleSave() {
    setBusy(true);
    setError(null);
    setSaved(false);
    try {
      await invoke("save_bundler_config", { config: { api_key: apiKey.trim(), network } });
      setSaved(true);
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <p className="muted" style={{ lineHeight: "1.5" }}>{t("bundlerConfig.explanation")}</p>

      {!loaded && <p className="muted">{t("bundlerConfig.loading")}</p>}

      {loaded && (
        <>
          <div className="field">
            <label htmlFor="bundler-api-key">{t("bundlerConfig.apiKeyLabel")}</label>
            <input
              id="bundler-api-key"
              type={showKey ? "text" : "password"}
              value={apiKey}
              onChange={(e) => {
                setApiKey(e.target.value);
                setSaved(false);
              }}
              disabled={busy}
              autoComplete="off"
              spellCheck={false}
            />
          </div>
          <div className="actions-row">
            <button type="button" onClick={() => setShowKey((v) => !v)}>
              {showKey ? t("bundlerConfig.hideKey") : t("bundlerConfig.showKey")}
            </button>
          </div>
          <div className="field" style={{ marginTop: "0.5rem" }}>
            <label htmlFor="bundler-network">{t("bundlerConfig.networkLabel")}</label>
            <select
              id="bundler-network"
              value={network}
              onChange={(e) => {
                setNetwork(e.target.value);
                setSaved(false);
              }}
              disabled={busy}
            >
              {NETWORKS.map((n) => (
                <option key={n} value={n}>{n}</option>
              ))}
            </select>
          </div>
          {error && <p className="error-text">{error}</p>}
          {saved && <p className="muted">{t("bundlerConfig.saved")}</p>}
          <div className="actions-row">
            <button onClick={handleSave} disabled={!apiKey.trim() || busy}>
              {busy ? t("bundlerConfig.saving") : t("bundlerConfig.saveButton")}
            </button>
          </div>
        </>
      )}
    </div>
  );
}
