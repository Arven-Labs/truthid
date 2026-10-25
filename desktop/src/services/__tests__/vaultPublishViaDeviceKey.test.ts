import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../userOpExecutor", () => ({ executeViaUserOp: vi.fn() }));

import { invoke } from "@tauri-apps/api/core";
import { executeViaUserOp } from "../userOpExecutor";
import { publishVaultViaDeviceKey } from "../vaultPublishViaDeviceKey";
import { PublishStepError } from "../../utils/publishErrors";

const ACCOUNT = "0x3333333333333333333333333333333333333333" as const;
const TX = `0x${"ab".repeat(32)}` as const;
const OP = `0x${"cd".repeat(32)}` as const;

describe("publishVaultViaDeviceKey — etapa que falhou", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(invoke).mockResolvedValue({ cid: "ar://abc", content_hash: `0x${"11".repeat(32)}` });
    vi.mocked(executeViaUserOp).mockResolvedValue({ userOpHash: OP, transactionHash: TX, success: true });
  });

  it("sucesso devolve o hash", async () => {
    await expect(publishVaultViaDeviceKey(ACCOUNT)).resolves.toEqual({ transactionHash: TX });
  });

  it("falha no upload é etapa 1 e vem traduzida; a tx nem é tentada", async () => {
    vi.mocked(invoke).mockRejectedValue("saldo insuficiente: precisa de 5000000000000 winston, tem 0 winston");
    const err = await publishVaultViaDeviceKey(ACCOUNT).catch((e) => e);

    expect(err).toBeInstanceOf(PublishStepError);
    expect(err.step).toBe("upload");
    expect(String(err)).toContain("Step 1 of 3");
    expect(String(err)).toContain("5.000000 AR");
    expect(executeViaUserOp).not.toHaveBeenCalled();
  });

  it("falha ao assinar/enviar é etapa 2 e mantém a mensagem do bundler", async () => {
    vi.mocked(executeViaUserOp).mockRejectedValue(new Error("This desktop is not authorized"));
    const err = await publishVaultViaDeviceKey(ACCOUNT).catch((e) => e);

    expect(err.step).toBe("sign");
    expect(String(err)).toContain("Step 2 of 3");
    expect(String(err)).toContain("not authorized");
  });

  it("sem recibo a tempo é etapa 3 e NÃO diz que reverteu", async () => {
    vi.mocked(executeViaUserOp).mockResolvedValue({ userOpHash: OP, transactionHash: null, success: false });
    const err = await publishVaultViaDeviceKey(ACCOUNT).catch((e) => e);

    expect(err.step).toBe("confirm");
    expect(String(err)).toContain("not confirmed in time");
    expect(String(err)).not.toContain("reverted");
  });

  it("tx com hash e sem sucesso é etapa 3 e diz que reverteu", async () => {
    vi.mocked(executeViaUserOp).mockResolvedValue({ userOpHash: OP, transactionHash: TX, success: false });
    const err = await publishVaultViaDeviceKey(ACCOUNT).catch((e) => e);

    expect(err.step).toBe("confirm");
    expect(String(err)).toContain("reverted");
  });
});
