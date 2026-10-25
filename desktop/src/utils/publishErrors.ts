import i18n from "../i18n";

// O Enviar do Vault tem 3 etapas (subir o manifesto no Arweave, assinar e
// enviar a transação, esperar a confirmação on-chain). Antes qualquer falha
// chegava como uma string solta ("RPC error: {...}"), sem dizer em qual etapa
// nem o que fazer — este módulo põe o número/nome da etapa na frente e traduz
// os erros recorrentes do upload.

export type PublishStep = "upload" | "sign" | "confirm";

const STEP_NUMBER: Record<PublishStep, number> = { upload: 1, sign: 2, confirm: 3 };

// 1 AR = 10^12 winston.
function winstonToAr(winston: string): string {
  const value = BigInt(winston);
  const whole = value / 1_000_000_000_000n;
  const frac = (value % 1_000_000_000_000n).toString().padStart(12, "0").slice(0, 6);
  return `${whole}.${frac}`;
}

// Erros do `vault_publish` (Rust) chegam como string crua em português.
export function describeUploadError(raw: string): string {
  if (/nenhuma wallet Arweave/i.test(raw)) {
    return i18n.t("publishErrors.noWallet");
  }
  const balance = /saldo insuficiente: precisa de (\d+) winston, tem (\d+) winston/i.exec(raw);
  if (balance) {
    return i18n.t("publishErrors.insufficientBalance", {
      needed: winstonToAr(balance[1]),
      has: winstonToAr(balance[2]),
    });
  }
  if (/vault ainda não existe/i.test(raw)) {
    return i18n.t("publishErrors.nothingToPublish");
  }
  if (/error sending request|dns|connect|timed out|timeout/i.test(raw)) {
    return i18n.t("publishErrors.network", { raw });
  }
  return raw;
}

export class PublishStepError extends Error {
  readonly step: PublishStep;

  constructor(step: PublishStep, detail: string) {
    super(
      `${i18n.t("publishErrors.stepPrefix", {
        n: STEP_NUMBER[step],
        name: i18n.t(`publishErrors.steps.${step}`),
      })}: ${detail}`,
    );
    this.name = "PublishStepError";
    this.step = step;
  }

  // Os chamadores mostram `String(e)`: sem isto apareceria "PublishStepError: ...".
  toString(): string {
    return this.message;
  }
}

export function errorText(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}
