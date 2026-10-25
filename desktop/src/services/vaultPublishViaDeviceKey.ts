import { invoke } from "@tauri-apps/api/core";
import type { Address, Hex } from "viem";
import { encodeFunctionData } from "viem";
import { VAULT_REGISTRY_ADDRESS, VAULT_REGISTRY_ABI } from "../config/contracts";
import { executeViaUserOp } from "./userOpExecutor";
import type { PublishResult } from "../types";
import i18n from "../i18n";
import { PublishStepError, describeUploadError, errorText } from "../utils/publishErrors";

/**
 * Extraído de `useVaultPublish.ts::handleEnviarViaDeviceKey` — mesma cadeia
 * (publica no Arweave via `vault_publish`, depois assina/envia a
 * UserOperation `updateVault` via device key), agora reaproveitável por
 * quem precisa publicar sem estar dentro do hook React (ex:
 * `VaultEditApprovalModal.tsx`, que já chamou `vault_upsert_entry` antes de
 * publicar). Não duplica a lógica — o hook continua sendo a única outra
 * chamadora, sem mudança de comportamento nele.
 */
export async function publishVaultViaDeviceKey(
  smartAccountAddress: Address
): Promise<{ transactionHash: Hex }> {
  // Etapa 1: manifesto no Arweave.
  let result: PublishResult;
  try {
    result = await invoke<PublishResult>("vault_publish");
  } catch (e) {
    throw new PublishStepError("upload", describeUploadError(errorText(e)));
  }

  const callData = encodeFunctionData({
    abi: VAULT_REGISTRY_ABI,
    functionName: "updateVault",
    args: [result.cid, result.content_hash as `0x${string}`],
  });

  // Etapa 2: assinar e enviar a UserOperation.
  let outcome: Awaited<ReturnType<typeof executeViaUserOp>>;
  try {
    outcome = await executeViaUserOp({
      smartAccountAddress,
      dest: VAULT_REGISTRY_ADDRESS,
      value: 0n,
      callData,
    });
  } catch (e) {
    throw new PublishStepError("sign", errorText(e));
  }

  // Etapa 3: confirmação. Sem hash = o recibo não apareceu a tempo (a tx pode
  // confirmar depois); com hash e sem sucesso = reverteu.
  if (!outcome.transactionHash) {
    throw new PublishStepError("confirm", i18n.t("publishErrors.notConfirmedYet"));
  }
  if (!outcome.success) {
    throw new PublishStepError("confirm", i18n.t("publishErrors.reverted"));
  }
  return { transactionHash: outcome.transactionHash };
}
