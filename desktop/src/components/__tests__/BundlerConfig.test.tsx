import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { BundlerConfig } from "../BundlerConfig";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
}));

import { invoke } from "@tauri-apps/api/core";

describe("BundlerConfig", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(invoke).mockImplementation((cmd: string) => {
      if (cmd === "get_bundler_config") return Promise.resolve({ api_key: "", network: "base" });
      return Promise.resolve(undefined);
    });
  });

  it("keeps Save disabled until an API key is typed", async () => {
    render(<BundlerConfig />);
    expect(await screen.findByRole("button", { name: "Save" })).toBeDisabled();

    await userEvent.type(screen.getByLabelText("Pimlico API key"), "pim_abc");
    expect(screen.getByRole("button", { name: "Save" })).toBeEnabled();
  });

  it("saves the trimmed key and the chosen network", async () => {
    render(<BundlerConfig />);
    await userEvent.type(await screen.findByLabelText("Pimlico API key"), "  pim_abc ");
    await userEvent.selectOptions(screen.getByLabelText("Network"), "base-sepolia");
    await userEvent.click(screen.getByRole("button", { name: "Save" }));

    expect(invoke).toHaveBeenCalledWith("save_bundler_config", {
      config: { api_key: "pim_abc", network: "base-sepolia" },
    });
    expect(await screen.findByText("Saved.")).toBeInTheDocument();
  });

  it("loads an existing config into the form", async () => {
    vi.mocked(invoke).mockImplementation((cmd: string) =>
      cmd === "get_bundler_config"
        ? Promise.resolve({ api_key: "pim_old", network: "base" })
        : Promise.resolve(undefined),
    );
    render(<BundlerConfig />);
    expect(await screen.findByLabelText("Pimlico API key")).toHaveValue("pim_old");
  });

  it("shows the error when saving fails", async () => {
    vi.mocked(invoke).mockImplementation((cmd: string) =>
      cmd === "save_bundler_config"
        ? Promise.reject("disk full")
        : Promise.resolve({ api_key: "", network: "base" }),
    );
    render(<BundlerConfig />);
    await userEvent.type(await screen.findByLabelText("Pimlico API key"), "k");
    await userEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(await screen.findByText("disk full")).toBeInTheDocument();
  });
});
