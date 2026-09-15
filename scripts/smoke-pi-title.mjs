import assert from "node:assert/strict";
import terminalTitle from "../config/pi/extensions/terminal-title.ts";

const originalSet = globalThis.setInterval;
const originalClear = globalThis.clearInterval;
const timers = new Set();
globalThis.setInterval = (callback, ms) => {
  assert.equal(ms, 120);
  const timer = { callback, unref() {} };
  timers.add(timer);
  return timer;
};
globalThis.clearInterval = (timer) => timers.delete(timer);

try {
  for (const mode of ["tui", "rpc", "json", "print"]) {
    const handlers = new Map();
    const titles = [];
    let name;
    let idle = true;
    let pending = false;
    const ctx = {
      mode,
      cwd: "/tmp/project",
      hasUI: mode === "tui" || mode === "rpc",
      isIdle: () => idle,
      hasPendingMessages: () => pending,
      ui: { setTitle: (title) => titles.push(title) },
    };
    terminalTitle({
      on: (event, handler) => handlers.set(event, handler),
      getSessionName: () => name,
    });
    const emit = (event, data = {}) => handlers.get(event)?.(data, ctx);
    const tick = () => {
      for (const t of timers) t.callback();
    };
    const latest = () => titles.at(-1);
    emit("session_start");
    if (mode === "tui") {
      assert.equal(latest(), "○ idle | π | project");
      assert.equal(timers.size, 1);
      name = `${"👩‍💻".repeat(41)}\x1b\x07`;
      emit("session_info_changed");
      assert.equal(latest(), `○ idle | π | ${"👩‍💻".repeat(39)}…`);
      titles.push("Pi overwrote the title");
      tick();
      assert.match(latest(), /^○ idle \| π \|/);
    }
    idle = false;
    emit("agent_start");
    const frame = latest();
    tick();
    if (mode === "tui") assert.notEqual(latest(), frame);
    emit("message_end", {
      message: { role: "assistant", stopReason: "error" },
    });
    emit("agent_end");
    if (mode === "tui") assert.match(latest(), /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]/);
    emit("session_before_compact");
    emit("session_compact");
    emit("agent_start"); // Retry recovered; tool errors are not terminal.
    emit("message_end", { message: { role: "toolResult", isError: true } });
    emit("message_end", { message: { role: "assistant", stopReason: "stop" } });
    idle = true;
    pending = true;
    emit("agent_settled");
    if (mode === "tui") assert.match(latest(), /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]/);
    pending = false;
    emit("agent_settled");
    if (mode === "tui") assert.match(latest(), /^■ ended/);
    for (const [reason, status] of [
      ["error", "! error"],
      ["aborted", "⊘ aborted"],
    ]) {
      idle = false;
      emit("agent_start");
      emit("message_end", {
        message: { role: "assistant", stopReason: reason },
      });
      emit("agent_end");
      idle = true;
      emit("agent_settled");
      if (mode === "tui") assert.ok(latest().startsWith(status));
    }
    idle = false;
    emit("agent_start");
    ctx.signal = { aborted: true };
    emit("agent_end");
    ctx.signal = undefined;
    idle = true;
    emit("agent_settled");
    if (mode === "tui") assert.match(latest(), /^⊘ aborted/);
    emit("session_shutdown");
    assert.equal(timers.size, 0);
    name = "resumed";
    idle = false;
    emit("session_start", { reason: "reload" });
    emit("session_start", { reason: "resume" });
    if (mode === "tui") {
      assert.equal(timers.size, 1);
      assert.match(latest(), /\| resumed$/);
      assert.match(latest(), /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]/);
    } else {
      assert.equal(titles.length, 0);
      assert.equal(timers.size, 0);
    }
    emit("session_shutdown");
    const count = titles.length;
    tick();
    assert.equal(titles.length, count);
  }
} finally {
  globalThis.setInterval = originalSet;
  globalThis.clearInterval = originalClear;
}
console.log("[INFO] Pi title lifecycle smoke test passed");
