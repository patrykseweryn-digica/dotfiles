import { basename } from "node:path";
import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

const frames = [..."⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"];
const segments = new Intl.Segmenter(undefined, { granularity: "grapheme" });

export default function terminalTitle(pi: ExtensionAPI) {
  let context: ExtensionContext | undefined;
  let timer: ReturnType<typeof setInterval> | undefined;
  let working = false;
  let compacting = false;
  let outcome = "○ idle";
  let frame = 0;

  function render() {
    if (!context) return;
    const name = (pi.getSessionName() || basename(context.cwd))
      // eslint-disable-next-line no-control-regex -- exclude OSC terminators
      .replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
      .trim();
    const chars = [...segments.segment(name)].map((part) => part.segment);
    const short =
      chars.length > 40 ? `${chars.slice(0, 39).join("")}…` : chars.join("");
    const status =
      working || compacting ? frames[frame++ % frames.length] : outcome;
    context.ui.setTitle(`${status} | π | ${short}`);
  }

  function stop() {
    clearInterval(timer);
    timer = undefined;
    context = undefined;
  }

  pi.on("session_start", (_event, ctx) => {
    stop();
    if (ctx.mode !== "tui") return;
    context = ctx;
    working = !ctx.isIdle();
    compacting = false;
    outcome = "○ idle";
    frame = 0;
    render();
    // Pi rewrites titles after async startup/reload and rename handlers.
    // Reassert ownership, including while idle; animate only while working.
    timer = setInterval(render, 120);
    timer.unref();
  });
  pi.on("session_info_changed", render);
  pi.on("agent_start", () => {
    if (!context) return;
    working = true;
    outcome = "■ ended"; // End of a turn, not verified task success.
    render();
  });
  pi.on("message_end", (event) => {
    if (!context || event.message.role !== "assistant") return;
    if (event.message.stopReason === "error") outcome = "! error";
    else if (event.message.stopReason === "aborted") outcome = "⊘ aborted";
    else outcome = "■ ended";
  });
  pi.on("agent_end", (_event, ctx) => {
    if (context && ctx.signal?.aborted) outcome = "⊘ aborted";
  });
  pi.on("agent_settled", (_event, ctx) => {
    if (!context || !ctx.isIdle() || ctx.hasPendingMessages()) return;
    working = false;
    render();
  });
  pi.on("session_before_compact", () => {
    if (!context) return;
    compacting = true;
    render();
  });
  pi.on("session_compact", () => {
    compacting = false;
    render();
  });
  pi.on("session_compact_failed", (event) => {
    compacting = false;
    if (context && event.reason === "manual") {
      outcome = event.aborted ? "⊘ aborted" : "! error";
    }
    render();
  });
  pi.on("session_shutdown", stop);
}
