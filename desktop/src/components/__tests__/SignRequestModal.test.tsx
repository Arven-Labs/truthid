import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { encodeFunctionData, parseAbi } from "viem";
import { SignRequestModal } from "../SignRequestModal";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../hooks/useIncomingSignRequest", () => ({ useIncomingSignRequest: vi.fn() }));
vi.mock("../../services/userOpExecutor", () => ({ executeViaUserOp: vi.fn() }));
vi.mock("../../contexts/WalletModalContext", () => ({
  useWalletModal: () => ({ openConnectModal: vi.fn() }),
}));

import { invoke } from "@tauri-apps/api/core";
import { useIncomingSignRequest } from "../../hooks/useIncomingSignRequest";
import { executeViaUserOp } from "../../services/userOpExecutor";

const SMART_ACCOUNT = "0x3333333333333333333333333333333333333333" as const;
const SIGNATURE = "ping(uint256)";
const TX_HASH = `0x${"ab".repeat(32)}` as const;
const OP_HASH = `0x${"cd".repeat(32)}` as const;

const clear = vi.fn();

function setup() {
  vi.mocked(useIncomingSignRequest).mockReturnValue({
    request: {
      id: "req-1",
      appName: "Test app",
      dest: "0x1111111111111111111111111111111111111111",
      value: "0",
      callData: encodeFunctionData({ abi: parseAbi([`function ${SIGNATURE}`]), args: [1n] }),
      functionSignature: SIGNATURE,
      expiresAtMs: Date.now() + 60_000,
    },
    clear,
  } as ReturnType<typeof useIncomingSignRequest>);
  vi.mocked(executeViaUserOp).mockResolvedValue({
    userOpHash: OP_HASH,
    transactionHash: TX_HASH,
    success: true,
  });
}

describe("SignRequestModal — resposta depois de executar", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    setup();
  });

  it("responde 'executed' e fecha quando tudo dá certo", async () => {
    vi.mocked(invoke).mockResolvedValue(true);
    render(<SignRequestModal smartAccountAddress={SMART_ACCOUNT} />);
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));

    expect(invoke).toHaveBeenCalledWith("respond_to_sign_request", {
      id: "req-1",
      decision: { outcome: "executed", userOpHash: OP_HASH, transactionHash: TX_HASH },
    });
    expect(clear).toHaveBeenCalled();
  });

  it("falha ao responder DEPOIS de executar não vira 'failed', trava o Aprovar e mostra o hash", async () => {
    vi.mocked(invoke).mockImplementation(async (cmd: string) => {
      if (cmd === "check_sign_request_valid") return true;
      throw "channel closed";
    });
    render(<SignRequestModal smartAccountAddress={SMART_ACCOUNT} />);
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));

    expect(await screen.findByText(new RegExp(TX_HASH))).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Approve" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Close" })).toBeInTheDocument();
    const failedCalls = vi.mocked(invoke).mock.calls.filter(
      ([cmd, args]) =>
        cmd === "respond_to_sign_request" &&
        (args as { decision: { outcome: string } }).decision.outcome === "failed",
    );
    expect(failedCalls).toHaveLength(0);
    expect(clear).not.toHaveBeenCalled();
  });

  it("falha da transação em si ainda responde 'failed' e mostra o erro", async () => {
    vi.mocked(invoke).mockResolvedValue(true);
    vi.mocked(executeViaUserOp).mockRejectedValue(new Error("boom"));
    render(<SignRequestModal smartAccountAddress={SMART_ACCOUNT} />);
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));

    expect(await screen.findByText(/boom/)).toBeInTheDocument();
    expect(invoke).toHaveBeenCalledWith("respond_to_sign_request", {
      id: "req-1",
      decision: { outcome: "failed", error: "Error: boom" },
    });
    expect(screen.getByRole("button", { name: "Approve" })).toBeEnabled();
  });
});
