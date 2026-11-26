import timers from "node:timers/promises";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";

const entryType = "pr-ci-watch";
const createCommand = /(?:^|[;&|])[ \t]*gh[ \t]+pr[ \t]+create(?=\s|[;&|]|$)/m;
const prUrl = /^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/pull\/[1-9]\d*$/;
const buckets = ["pass", "fail", "pending", "skipping", "cancel"];

function readChecks(stdout: string, stderr: string) {
  if (!stdout.trim() && stderr.startsWith("no checks reported")) return [];
  try {
    const checks: unknown = JSON.parse(stdout);
    if (!Array.isArray(checks)) return;
    return checks.map((row: unknown) => {
      if (
        !row ||
        typeof row !== "object" ||
        !("name" in row) ||
        typeof row.name !== "string" ||
        !("bucket" in row) ||
        typeof row.bucket !== "string" ||
        !buckets.includes(row.bucket)
      ) {
        throw new Error("Invalid GitHub check");
      }
      return {
        name: row.name.replace(/[\p{Cc}\p{Cf}]/gu, " ").slice(0, 160),
        bucket: row.bucket,
      };
    });
  } catch {
    return;
  }
}

export default function prCiWatch(pi: ExtensionAPI) {
  const active = new Map<string, AbortController>();
  pi.registerEntryRenderer<string>(
    entryType,
    (entry) => new Text(entry.data ?? "", 1, 0),
  );

  async function watch(url: string, cwd: string, signal: AbortSignal) {
    const deadline = Date.now() + 90 * 60_000;
    let errors = 0;
    let previous = "";
    while (Date.now() < deadline) {
      const result = await pi
        .exec("gh", ["pr", "checks", url, "--json", "name,bucket"], {
          cwd,
          signal,
          timeout: 10_000,
        })
        .catch(() => undefined);
      if (signal.aborted) return;
      const checks =
        result && !result.killed && readChecks(result.stdout, result.stderr);
      if (!checks) {
        if (++errors === 3) return "Could not read CI status from GitHub.";
      } else {
        errors = 0;
      }
      // GitHub may register jobs in batches just after opening a PR.
      if (
        checks &&
        checks.length &&
        !checks.some(({ bucket }) => bucket === "pending")
      ) {
        const current = JSON.stringify(
          checks.map((check) => JSON.stringify(check)).sort(),
        );
        if (current === previous) {
          const problems = checks.filter(
            ({ bucket }) => bucket === "fail" || bucket === "cancel",
          );
          if (problems.length) {
            return `CI did not pass:\n${problems.map(({ name, bucket }) => `- ${name} (${bucket === "cancel" ? "cancelled" : "failed"})`).join("\n")}`;
          }
          return checks.some(({ bucket }) => bucket === "pass")
            ? "CI passed."
            : "CI finished: all checks skipped.";
        }
        previous = current;
      } else {
        previous = "";
      }
      await timers.setTimeout(30_000, undefined, { signal, ref: false });
    }
    return "CI watch timed out after 90 minutes.";
  }

  pi.on("tool_result", (event, ctx) => {
    if (ctx.mode !== "tui" || event.toolName !== "bash" || event.isError)
      return;
    const command = event.input.command;
    if (typeof command !== "string" || !createCommand.test(command)) return;
    const urls = new Set(
      event.content.flatMap((part) =>
        part.type === "text"
          ? part.text
              .split(/\r?\n/)
              .map((line) => line.trim())
              .filter((line) => prUrl.test(line))
          : [],
      ),
    );
    if (urls.size !== 1) return;
    const [url] = urls;
    if (active.has(url)) return;
    const controller = new AbortController();
    active.set(url, controller);
    const { signal } = controller;
    ctx.ui.notify(`Watching CI: ${url}`, "info");
    void watch(url, ctx.cwd, signal)
      .catch(() => "CI watch stopped unexpectedly.")
      .then((status) => {
        if (signal.aborted) return;
        active.delete(url);
        pi.appendEntry(entryType, `${status}\n${url}`);
      });
  });

  pi.on("session_shutdown", () => {
    for (const controller of active.values()) controller.abort();
    active.clear();
  });
}
