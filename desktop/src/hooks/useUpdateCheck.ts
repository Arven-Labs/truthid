import { useCallback, useEffect, useRef, useState } from "react";
import { check, type Update } from "@tauri-apps/plugin-updater";
import { relaunch } from "@tauri-apps/plugin-process";

export type UpdateStatus = "idle" | "available" | "downloading" | "ready" | "error";
// Resultado da última checagem, separado de `status` (que é o ciclo de
// vida do download): a checagem do início continua silenciosa no banner, mas
// agora o motivo da falha fica guardado pra tela de Configurações mostrar.
export type CheckState = "idle" | "checking" | "upToDate" | "failed";

export function useUpdateCheck() {
  const [status, setStatus] = useState<UpdateStatus>("idle");
  const [updateVersion, setUpdateVersion] = useState<string | null>(null);
  const [pendingUpdate, setPendingUpdate] = useState<Update | null>(null);
  const [checkState, setCheckState] = useState<CheckState>("idle");
  const [checkError, setCheckError] = useState<string | null>(null);
  const [installError, setInstallError] = useState<string | null>(null);
  const cancelled = useRef(false);

  const runCheck = useCallback(async () => {
    setCheckState("checking");
    setCheckError(null);
    try {
      const result = await check();
      if (cancelled.current) return;
      if (!result) {
        setCheckState("upToDate");
        return;
      }
      setPendingUpdate(result);
      setUpdateVersion(result.version);
      setStatus("available");
      setCheckState("idle");
    } catch (e) {
      if (cancelled.current) return;
      // O banner segue sem aparecer (checar atualização nunca deve interromper
      // o uso normal do app), mas o motivo fica disponível em Configurações.
      setCheckError(String(e));
      setCheckState("failed");
    }
  }, []);

  useEffect(() => {
    cancelled.current = false;
    void runCheck();
    return () => {
      cancelled.current = true;
    };
  }, [runCheck]);

  const installUpdate = useCallback(async () => {
    if (!pendingUpdate) return;
    setStatus("downloading");
    setInstallError(null);
    try {
      await pendingUpdate.downloadAndInstall();
      setStatus("ready");
    } catch (e) {
      setInstallError(String(e));
      setStatus("error");
    }
  }, [pendingUpdate]);

  // Passo separado de `installUpdate` de propósito — reiniciar fecha
  // qualquer trabalho em andamento no app (assinatura de identidade,
  // wallet), então quem usa o hook decide o momento certo, não o download
  // em si.
  const restartNow = useCallback(() => {
    void relaunch();
  }, []);

  return {
    status,
    updateVersion,
    installUpdate,
    restartNow,
    checkState,
    checkError,
    installError,
    checkNow: runCheck,
  };
}
