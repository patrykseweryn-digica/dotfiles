import assert from "node:assert/strict";
import { setImmediate } from "node:timers/promises";
import { mock } from "node:test";
import prCiWatch from "../config/pi/extensions/pr-ci-watch.ts";

const url = "https://github.com/example/dotfiles/pull/42";
const entryType = "pr-ci-watch";
const handlers = new Map();
const events = [];
const calls = [];
const replies = [];
const ctx = {
  mode: "tui",
  cwd: "/tmp/dotfiles",
  ui: { notify: (message) => events.push(message) },
};
let renderer;
prCiWatch({
  on: (name, handler) => handlers.set(name, handler),
  registerEntryRenderer: (type, render) => {
    assert.equal(type, entryType);
    renderer = render;
  },
  appendEntry: (type, message) => {
    assert.equal(type, entryType);
    events.push(message);
  },
  exec: async (command, args, options) => {
    assert.equal(command, "gh");
    assert.deepEqual(args, ["pr", "checks", url, "--json", "name,bucket"]);
    assert.equal(options.cwd, ctx.cwd);
    calls.push(options.signal);
    return replies.shift();
  },
});
const created = {
  toolName: "bash",
  input: { command: "git push && gh pr create --title 'Use Make'" },
  content: [{ type: "text", text: `push output\n${url}\nhint: ...` }],
  isError: false,
};
const emit = (patch = {}, context = ctx) =>
  handlers.get("tool_result")({ ...created, ...patch }, context);
const checks = (...rows) => ({
  stdout: JSON.stringify(rows.map(([name, bucket]) => ({ name, bucket }))),
  stderr: "",
  killed: false,
});
const tick = async () => {
  mock.timers.tick(30_000);
  await setImmediate();
};

mock.timers.enable({ apis: ["setTimeout"] });
try {
  emit({ input: { command: "gh pr view" } });
  emit({ isError: true });
  emit({}, { ...ctx, mode: "print" });
  assert.deepEqual(events, []);
  assert.deepEqual(calls, []);

  replies.push(
    { stdout: "", stderr: "no checks reported on the branch", killed: false },
    checks(["Lint", "pass"]),
    checks(["Lint", "pass"], ["Build", "pending"]),
    checks(["Lint", "fail"], ["Build\x1b", "cancel"]),
    checks(["Build\x1b", "cancel"], ["Lint", "fail"]),
  );
  emit();
  emit();
  await setImmediate();
  assert.equal(calls.length, 1);
  for (let i = 0; i < 3; i++) await tick();
  assert.deepEqual(events, [`Watching CI: ${url}`]);
  await tick();
  assert.match(events[1], /CI did not pass:/);
  assert.match(events[1], /Lint \(failed\)/);
  assert.ok(events[1].includes("Build  (cancelled)"));
  assert.ok(events[1].endsWith(url));
  assert.ok(
    renderer({ data: events[1] })
      .render(42)
      .join("\n")
      .includes("CI did not pass"),
  );

  replies.push(checks(["Lint", "pass"]), checks(["Lint", "pass"]));
  emit();
  await setImmediate();
  await tick();
  assert.equal(events.at(-1), `CI passed.\n${url}`);

  let finishRequest;
  replies.push(new Promise((resolve) => (finishRequest = resolve)));
  emit();
  handlers.get("session_shutdown")();
  assert.ok(calls.at(-1).aborted);
  const eventCount = events.length;
  finishRequest(checks(["Lint", "pass"]));
  await setImmediate();
  await tick();
  assert.equal(events.length, eventCount);
} finally {
  mock.timers.reset();
}
console.log("[INFO] Pi PR CI watch smoke test passed");
