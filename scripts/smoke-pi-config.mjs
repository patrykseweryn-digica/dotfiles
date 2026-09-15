import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  cpSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { validateThemeJson } from "../config/pi/node_modules/@earendil-works/pi-coding-agent/dist/modes/interactive/theme/theme-json.js";
import { loadThemeFromPath } from "../config/pi/node_modules/@earendil-works/pi-coding-agent/dist/modes/interactive/theme/theme.js";
import moon from "../config/pi/themes/rose-pine-moon.json" with { type: "json" };
import settings from "../config/pi/settings.json" with { type: "json" };

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const config = join(root, "config/pi");
const themeFile = join(config, "themes/rose-pine-moon.json");
validateThemeJson("rose-pine-moon", moon);
const theme = loadThemeFromPath(themeFile, "truecolor");
assert.ok(theme.fg("accent", "iris").includes("196;167;231"));
assert.notEqual(moon.colors.toolSuccessBg, moon.colors.toolErrorBg);
assert.equal(settings.theme, "rose-pine-moon");
assert.equal(settings.images.blockImages, false);
assert.equal(settings.terminal.showImages, false);
assert.equal(settings.terminal.trueColor, true);
assert.equal(settings.steeringMode, "all");
assert.equal(settings.followUpMode, "all");
for (const key of ["quietStartup", "hideThinkingBlock", "collapseChangelog"]) {
  assert.equal(settings[key], true);
}

const temp = mkdtempSync(join(tmpdir(), "pi-config-test-"));
try {
  const source = join(temp, "source");
  const home = join(temp, "home");
  const agent = join(home, ".pi/agent");
  mkdirSync(source);
  mkdirSync(join(agent, "extensions"), { recursive: true });
  for (const path of ["themes", "extensions", "models.json"]) {
    cpSync(join(config, path), join(source, path), { recursive: true });
  }
  // Package installation has its own fixture and real clean-HOME check.
  writeFileSync(
    join(source, "settings.json"),
    JSON.stringify({ ...settings, packages: [] }),
  );
  const localModels = {
    providers: {
      "openai-codex": {
        modelOverrides: {
          "gpt-5.6-sol": { maxTokens: 8192 },
          "gpt-6-astra": { contextWindow: 1000000 },
        },
      },
      custom: { apiKey: "private-test-sentinel" },
    },
  };
  writeFileSync(join(agent, "models.json"), JSON.stringify(localModels));
  writeFileSync(join(agent, "auth.json"), "private-test-sentinel");
  writeFileSync(
    join(agent, "extensions/herdr-agent-state.ts"),
    "herdr-sentinel",
  );
  const env = {
    ...process.env,
    HOME: home,
    PI_CODING_AGENT_DIR: agent,
    PI_SETTINGS_TEMPLATE: join(source, "settings.json"),
    PI_SETTINGS_FILE: join(agent, "settings.json"),
    PI_MCP_CONFIG: join(home, "mcp.json"),
  };
  const run = (action) =>
    execFileSync(join(root, "sync-agents.sh"), [action], {
      env,
      stdio: "pipe",
    });
  run("pi-install");
  run("pi-check");
  const before = readFileSync(join(agent, "settings.json"), "utf8");
  run("pi-install");
  run("pi-check");
  assert.equal(readFileSync(join(agent, "settings.json"), "utf8"), before);
  const actual = JSON.parse(readFileSync(join(agent, "models.json"), "utf8"));
  for (const name of ["luna", "sol", "terra"]) {
    assert.equal(
      actual.providers["openai-codex"].modelOverrides[`gpt-5.6-${name}`]
        .contextWindow,
      272000,
    );
  }
  assert.equal(
    actual.providers["openai-codex"].modelOverrides["gpt-5.6-sol"].maxTokens,
    8192,
  );
  assert.deepEqual(actual.providers.custom, localModels.providers.custom);
  assert.deepEqual(
    actual.providers["openai-codex"].modelOverrides["gpt-6-astra"],
    localModels.providers["openai-codex"].modelOverrides["gpt-6-astra"],
  );
  assert.equal(
    readFileSync(join(agent, "auth.json"), "utf8"),
    "private-test-sentinel",
  );
  assert.equal(
    readFileSync(join(agent, "extensions/herdr-agent-state.ts"), "utf8"),
    "herdr-sentinel",
  );
  assert.throws(() => readFileSync(join(home, ".dotfiles-backup")));
  writeFileSync(
    join(agent, "settings.json"),
    JSON.stringify(
      Object.fromEntries(Object.entries(JSON.parse(before)).toReversed()),
    ),
  );
  run("pi-check");
  actual.providers["openai-codex"].modelOverrides["gpt-5.6-sol"].contextWindow =
    42;
  writeFileSync(join(agent, "models.json"), JSON.stringify(actual));
  assert.throws(() => run("pi-check"));
  run("pi-install");
  rmSync(join(agent, "themes/rose-pine-moon.json"));
  assert.throws(() => run("pi-check"));
  run("pi-install");
  run("pi-check");
} finally {
  rmSync(temp, { recursive: true, force: true });
}
console.log("[INFO] Pi theme, overrides and sync smoke test passed");
