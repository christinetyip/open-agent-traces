import { spawn } from "node:child_process";

export async function runCommand(command: string, args: string[], cwd?: string): Promise<{ ok: boolean; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      cwd,
      stdio: ["ignore", "pipe", "pipe"],
      env: process.env,
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk: Buffer | string) => {
      stdout += String(chunk);
    });
    child.stderr.on("data", (chunk: Buffer | string) => {
      stderr += String(chunk);
    });
    child.on("error", (error) => {
      stderr += String(error);
      resolve({ ok: false, stdout, stderr });
    });
    child.on("close", (code) => {
      resolve({ ok: code === 0, stdout: stdout.trim(), stderr: stderr.trim() });
    });
  });
}

export function runCommandPassthrough(command: string, args: string[]): Promise<number> {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      stdio: "inherit",
      env: process.env,
    });
    child.on("error", () => resolve(1));
    child.on("close", (code) => resolve(code ?? 1));
  });
}

export async function commandExists(command: string): Promise<boolean> {
  const result = await runCommand(command, ["--help"]);
  return result.ok || !result.stderr.includes("ENOENT");
}

export async function ensureStartupTools(command: string): Promise<void> {
  const missing: string[] = [];

  if (command === "collect" || command === "upload") {
    if (!(await commandExists("huggingface-cli"))) {
      missing.push([
        "Missing required command: huggingface-cli",
        "Install it with:",
        '  python3 -m pip install --user "huggingface_hub[cli]"',
        "Then log in with:",
        "  huggingface-cli login",
      ].join("\n"));
    }
  }

  if (command === "collect" || command === "review") {
    if (!(await commandExists("pi"))) {
      missing.push([
        "Missing required command: pi",
        "Install it with:",
        "  npm install -g @mariozechner/pi-coding-agent",
      ].join("\n"));
    }
  }

  if (missing.length > 0) {
    throw new Error(missing.join("\n\n"));
  }
}
