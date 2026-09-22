/**
 * Rich status line - replaces pi's footer with the two-line Claude Code status
 * line from ~/.claude/statusline.mjs.
 *
 * Line 1:  [vendor]  model(gradient)  [ctx bar, 22 wide, 20% marker]  pct%  effort   …right…  branch  (+ins,-del)
 * Line 2:  5-hour: x% (r: ym) | weekly: x% (r: xd zh ym)
 *
 * Palette and behaviour are copied verbatim from the PowerShell version. Line 2
 * is derived from Anthropic's unified rate-limit response headers (present once
 * pi runs Claude on the Max plan via pi-claude-auth), confirmed off a live
 * message:
 *   anthropic-ratelimit-unified-5h-utilization  0.45   (fraction, = 45%)
 *   anthropic-ratelimit-unified-5h-reset        1787674800  (unix seconds)
 *   anthropic-ratelimit-unified-5h-status       allowed
 *   ...and the 7d-* equivalents for the weekly window.
 * Every response is still dumped to ~/.pi/statusline-ratelimit.json (also on
 * demand via /statusline-debug) in case the header shapes ever change.
 *
 * Z.ai (GLM) sends no rate-limit headers at all on 200 responses (verified
 * 2026-08-25 on both the OpenAI and the Anthropic protocol endpoints), so for
 * zai sessions line 2 is fed from the quota dashboard API instead:
 *   GET https://api.z.ai/api/monitor/usage/quota/limit   (Bearer ZAI_API_KEY)
 * Confirmed live-response shape (credits plans, post-2026-07-30; older plans
 * report type TOKENS_LIMIT instead of CREDIT_LIMIT with the same unit codes):
 *   data.limits[] = { type, unit, percentage, usage, currentValue, remaining,
 *                     nextResetTime }
 *     unit 3 = 5-hour window, unit 6 = weekly window, nextResetTime is ms epoch.
 *     Field naming is misleading: `usage` is the window SIZE, `currentValue`
 *     is what was consumed.
 *   data.level = plan tier ("lite" | "pro" | "max").
 */

import { execFile } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type {
	ExtensionAPI,
	ExtensionContext,
	ReadonlyFooterDataProvider,
	Theme,
} from "@earendil-works/pi-coding-agent";
import type { Component, TUI } from "@earendil-works/pi-tui";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

// pi's own set is wider; these are the ones the status line displays.
type ThinkingLevel = "off" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max";

interface UsageWindow {
	usedPercent: number | null;
	resetsAtMs: number | null;
}

// ── ANSI helpers ──────────────────────────────────────────────────────
const ESC = "\x1b";
const paint = (text: string, code: string) => `${ESC}[${code}m${text}${ESC}[0m`;

// ── Shared state (captured by the footer closure and event handlers) ──
let ctxRef: ExtensionContext | null = null;
let tuiRef: TUI | null = null;
let thinkingLevel: ThinkingLevel = "medium";
let footerActive = false;

let gitState = { ins: 0, del: 0, sha: "" };
let gitTimer: ReturnType<typeof setTimeout> | null = null;

const rateLimits: { fiveHour: UsageWindow | null; weekly: UsageWindow | null } = {
	fiveHour: null,
	weekly: null,
};
let lastHeaders: Record<string, string> | null = null;
let lastStatus = 0;

// ── Z.ai (GLM) quota polling ──────────────────────────────────────────
const ZAI_QUOTA_URL = "https://api.z.ai/api/monitor/usage/quota/limit";
const ZAI_MIN_POLL_MS = 60_000;
let zaiFetchInFlight = false;
let zaiLastFetchMs = 0;
let zaiLastError: string | null = null;

function isActiveProviderZai(): boolean {
	return ctxRef?.model?.provider === "zai";
}

/**
 * Fetch the Z.ai quota dashboard and feed it into the same line-2 windows the
 * Anthropic headers fill. Only runs while the active model is a zai model, so
 * Claude sessions never touch the endpoint. Throttled to one call a minute;
 * forced on session start and model switches. Failures keep the last known
 * windows and are only surfaced through the debug dump.
 */
async function refreshZaiQuota(force = false): Promise<void> {
	const ctx = ctxRef;
	if (!ctx || !isActiveProviderZai() || zaiFetchInFlight) return;
	if (!force && Date.now() - zaiLastFetchMs < ZAI_MIN_POLL_MS) return;

	zaiFetchInFlight = true;
	try {
		const key = await ctx.modelRegistry.getApiKeyForProvider("zai");
		if (!key) {
			zaiLastError = "no API key available for provider zai";
			return;
		}
		const res = await fetch(ZAI_QUOTA_URL, {
			headers: { Authorization: `Bearer ${key}` },
			signal: AbortSignal.timeout(10_000),
		});
		// The endpoint answers 200 with { success: false, msg } on bad tokens.
		const body = (await res.json().catch(() => null)) as {
			success?: boolean;
			msg?: string;
			code?: number;
			data?: {
				limits?: Array<{
					type?: string;
					unit?: number;
					percentage?: number;
					usage?: number;
					currentValue?: number;
					nextResetTime?: number;
				}>;
			};
		} | null;
		if (!body || body.success === false) {
			zaiLastError = `quota API error: ${body?.msg ?? `HTTP ${res.status}`}`;
			return;
		}

		const parsed: { fiveHour?: UsageWindow; weekly?: UsageWindow } = {};
		for (const limit of body.data?.limits ?? []) {
			if (limit.type !== "CREDIT_LIMIT" && limit.type !== "TOKENS_LIMIT") continue;
			let usedPercent: number | null =
				typeof limit.percentage === "number" ? limit.percentage : null;
			// Fallback when percentage is absent: currentValue / usage, where the
			// misleadingly named `usage` field is the window size.
			if (usedPercent == null && typeof limit.currentValue === "number" && typeof limit.usage === "number" && limit.usage > 0) {
				usedPercent = (limit.currentValue / limit.usage) * 100;
			}
			const resetsAtMs = typeof limit.nextResetTime === "number" ? limit.nextResetTime : null;
			if (limit.unit === 3) parsed.fiveHour = { usedPercent, resetsAtMs };
			else if (limit.unit === 6) parsed.weekly = { usedPercent, resetsAtMs };
		}

		zaiLastError = null;
		if (applyRateLimits(parsed)) tuiRef?.requestRender();
		// Re-dump once the fetch settles: the handler-time dump cannot see the
		// result of this async call, and lastError/lastFetchAt are exactly what
		// /statusline-debug exists to reveal.
		dumpDebug(lastStatus, lastHeaders ?? {});
	} catch (err) {
		zaiLastError = err instanceof Error ? err.message : String(err);
	} finally {
		zaiLastFetchMs = Date.now();
		zaiFetchInFlight = false;
	}
}

// ── Line 1: model name gradient ───────────────────────────────────────
function gradient(text: string): string {
	const ramp = [60, 67, 73, 74, 80];
	const len = text.length;
	let out = "";
	for (let i = 0; i < len; i++) {
		let slot = Math.floor((i / Math.max(1, len)) * ramp.length);
		if (slot >= ramp.length) slot = ramp.length - 1;
		out += `${ESC}[1m${ESC}[38;5;${ramp[slot]}m${text[i]}`;
	}
	return out + `${ESC}[0m`;
}

// ── Line 1: context bar with the 20% "start a new chat" marker ────────
function buildBar(pct: number): { bar: string; label: string } {
	const BAR_WIDTH = 22;
	const MARKER_PCT = 20;
	const clamped = Math.max(0, Math.min(100, pct));
	const filled = Math.round((clamped / 100) * BAR_WIDTH);
	const markerIdx = Math.round((MARKER_PCT / 100) * BAR_WIDTH);

	const past = clamped >= MARKER_PCT;
	const fillColor = past ? "38;5;215" : "38;5;114";
	const markerColor = past ? "38;5;203" : "38;5;244";

	let bar = "";
	for (let i = 0; i < BAR_WIDTH; i++) {
		if (i === markerIdx) bar += paint("|", markerColor);
		else if (i < filled) bar += paint("\u2588", fillColor); // █
		else bar += paint("\u2591", "38;5;238"); // ░
	}
	return { bar, label: paint(`${Math.round(clamped)}%`, fillColor) };
}

// ── Line 2: usage windows ─────────────────────────────────────────────
function remaining(resetsAtMs: number | null): string | null {
	if (resetsAtMs == null) return null;
	let s = Math.floor((resetsAtMs - Date.now()) / 1000);
	if (s <= 0) return "0m";
	const d = Math.floor(s / 86400);
	s -= d * 86400;
	const h = Math.floor(s / 3600);
	s -= h * 3600;
	const m = Math.floor(s / 60);
	const parts: string[] = [];
	if (d > 0) parts.push(`${d}d`);
	if (h > 0) parts.push(`${h}h`);
	parts.push(`${m}m`);
	return parts.join(" ");
}

function usagePart(label: string, w: UsageWindow | null): string | null {
	if (!w || w.usedPercent == null) return null;
	let text = `${label}: ${Math.round(w.usedPercent)}%`;
	const left = remaining(w.resetsAtMs);
	if (left) text += ` (r: ${left})`;
	return paint(text, "38;5;111");
}

// ── Rate-limit header parsing (confirmed anthropic-ratelimit-unified-*) ─
function toNum(v: string): number | null {
	const n = parseFloat(v.replace(/[%,\s]/g, ""));
	return Number.isNaN(n) ? null : n;
}

// Utilization arrives as a 0..1 fraction (0.45 = 45%). Tolerate a future
// 0..100 form: anything above 1 is taken as an already-scaled percentage.
function toPercent(v: string): number | null {
	const n = toNum(v);
	if (n == null) return null;
	return n <= 1 ? n * 100 : n;
}

/**
 * Turn a reset value into an epoch in ms, tolerating the shapes Anthropic
 * might use: ISO 8601 string, unix seconds, unix ms, or seconds-from-now.
 */
function parseReset(v: string): number | null {
	const s = v.trim();
	if (/^\d+(\.\d+)?$/.test(s)) {
		const n = parseFloat(s);
		if (n > 1e12) return n; // ms epoch
		if (n > 1e9) return n * 1000; // s epoch
		return Date.now() + n * 1000; // seconds from now
	}
	const t = Date.parse(s);
	return Number.isNaN(t) ? null : t;
}

function parseRateLimitHeaders(headers: Record<string, string>): {
	fiveHour?: UsageWindow;
	weekly?: UsageWindow;
} {
	type Raw = {
		limit?: number | null;
		remaining?: number | null;
		usedPercent?: number | null;
		percent?: number | null;
		reset?: string;
		status?: string;
	};
	const buckets: { fiveHour: Raw; weekly: Raw } = { fiveHour: {}, weekly: {} };

	for (const [rawKey, rawVal] of Object.entries(headers)) {
		const lk = rawKey.toLowerCase();
		if (!lk.includes("ratelimit")) continue;

		// The window token splits the key; everything after it is the field name.
		// Matching the field on that suffix (not the whole key) is what keeps the
		// "ratelimit" prefix from being misread as a "limit" field.
		const segs = lk.split(/[-_]/);
		let bucket: "fiveHour" | "weekly" | null = null;
		let fieldIdx = -1;
		for (let i = 0; i < segs.length; i++) {
			const s = segs[i];
			if (s === "7d" || s === "7day" || s === "sevenday" || s === "week" || s === "weekly") {
				bucket = "weekly";
				fieldIdx = i + 1;
				break;
			}
			if (s === "5h" || s === "5hour" || s === "fivehour") {
				bucket = "fiveHour";
				fieldIdx = i + 1;
				break;
			}
		}
		if (!bucket || fieldIdx >= segs.length) continue;

		const field = segs.slice(fieldIdx).join("");
		const val = String(rawVal).trim();
		const b = buckets[bucket];
		if (field.includes("reset")) b.reset = val;
		else if (field.includes("remaining")) b.remaining = toNum(val);
		else if (field.includes("utiliz") || field.includes("percent") || field.includes("pct"))
			b.percent = toPercent(val);
		else if (field.includes("used")) b.usedPercent = toPercent(val);
		else if (field.includes("limit")) b.limit = toNum(val);
		else if (field.includes("status")) b.status = val;
	}

	const out: { fiveHour?: UsageWindow; weekly?: UsageWindow } = {};
	for (const key of ["fiveHour", "weekly"] as const) {
		const b = buckets[key];
		let usedPercent: number | null = null;
		if (b.usedPercent != null) usedPercent = b.usedPercent;
		else if (b.percent != null) usedPercent = b.percent;
		else if (b.limit != null && b.remaining != null && b.limit > 0)
			usedPercent = ((b.limit - b.remaining) / b.limit) * 100;
		const resetsAtMs = b.reset != null ? parseReset(b.reset) : null;
		// Never fabricate: only emit a window we could actually read something for.
		if (usedPercent != null || resetsAtMs != null) out[key] = { usedPercent, resetsAtMs };
	}
	return out;
}

function applyRateLimits(parsed: { fiveHour?: UsageWindow; weekly?: UsageWindow }): boolean {
	let changed = false;
	for (const key of ["fiveHour", "weekly"] as const) {
		const next = parsed[key];
		if (!next) continue;
		const prev = rateLimits[key];
		if (!prev || prev.usedPercent !== next.usedPercent || prev.resetsAtMs !== next.resetsAtMs) {
			rateLimits[key] = next;
			changed = true;
		}
	}
	return changed;
}

const DEBUG_PATH = join(homedir(), ".pi", "statusline-ratelimit.json");

function dumpDebug(status: number, headers: Record<string, string>): void {
	try {
		const relevant: Record<string, string> = {};
		for (const [k, v] of Object.entries(headers)) {
			const nk = k.toLowerCase();
			if (
				nk.includes("ratelimit") ||
				nk.includes("rate-limit") ||
				nk.includes("retry-after") ||
				nk.includes("quota") ||
				nk.includes("usage")
			)
				relevant[k] = v;
		}
		const payload = {
			capturedAt: new Date().toISOString(),
			status,
			// Full name list (no values) so every present header is visible for confirming names.
			headerNames: Object.keys(headers).sort(),
			// Values only for the rate-limit-ish subset.
			rateLimitHeaders: relevant,
			parsed: { fiveHour: rateLimits.fiveHour, weekly: rateLimits.weekly },
			zai: {
				active: isActiveProviderZai(),
			lastFetchAt: zaiLastFetchMs ? new Date(zaiLastFetchMs).toISOString() : null,
			lastError: zaiLastError,
		},
		};
		mkdirSync(dirname(DEBUG_PATH), { recursive: true });
		writeFileSync(DEBUG_PATH, JSON.stringify(payload, null, 2));
	} catch {
		// Debug dump is best-effort; never break the footer over it.
	}
}

// ── git diff / detached sha (async, debounced - never in render) ──────
function git(cwd: string, args: string[]): Promise<string> {
	return new Promise((resolve) => {
		execFile("git", ["-C", cwd, ...args], { windowsHide: true, timeout: 5000 }, (err, stdout) => {
			resolve(err ? "" : String(stdout));
		});
	});
}

async function runGitRefresh(cwd: string): Promise<void> {
	const [numstat, sha] = await Promise.all([
		git(cwd, ["diff", "--numstat", "HEAD"]),
		git(cwd, ["rev-parse", "--short", "HEAD"]),
	]);
	let ins = 0;
	let del = 0;
	for (const line of numstat.split("\n")) {
		const parts = line.split("\t");
		if (parts.length >= 2) {
			// binary files report "-" on both counts
			if (/^\d+$/.test(parts[0])) ins += parseInt(parts[0], 10);
			if (/^\d+$/.test(parts[1])) del += parseInt(parts[1], 10);
		}
	}
	const next = { ins, del, sha: sha.trim() };
	if (next.ins !== gitState.ins || next.del !== gitState.del || next.sha !== gitState.sha) {
		gitState = next;
		tuiRef?.requestRender();
	}
}

function scheduleGitRefresh(cwd: string): void {
	if (gitTimer) clearTimeout(gitTimer);
	gitTimer = setTimeout(() => {
		gitTimer = null;
		void runGitRefresh(cwd);
	}, 250);
}

// ── Render ────────────────────────────────────────────────────────────
function renderFooter(width: number, footerData: ReadonlyFooterDataProvider): string[] {
	const ctx = ctxRef;

	// A non-Anthropic session gets badged. The thing that must never happen is
	// believing you are on GLM while spending Anthropic quota. Set by scripts/glm.ps1.
	const vendorEnv = process.env.M2_VENDOR;
	const vendor = vendorEnv ? paint(` ${vendorEnv.toUpperCase()} `, "1;38;5;231;48;5;97") : "";

	const modelName = ctx?.model?.name ?? "";
	const model = modelName ? gradient(modelName) : "";

	let bar = "";
	let ctxLabel = "";
	const usage = ctx?.getContextUsage?.();
	const pct = usage && usage.percent != null ? usage.percent : null;
	if (pct != null) {
		const built = buildBar(pct);
		bar = built.bar;
		ctxLabel = built.label;
	}

	const effort =
		thinkingLevel && thinkingLevel !== "off" ? paint(thinkingLevel, "38;5;96") : "";

	const left = [vendor, model, bar, ctxLabel, effort].filter(Boolean).join("  ");

	// Right side: branch + diff.
	const rawBranch = footerData.getGitBranch();
	let branch = "";
	if (rawBranch) {
		// detached HEAD reports "detached" - show the short sha instead
		const label = rawBranch === "detached" ? gitState.sha || "detached" : rawBranch;
		branch = paint(label, "38;5;109");
	}
	const diff =
		gitState.ins > 0 || gitState.del > 0
			? paint(`(+${gitState.ins},-${gitState.del})`, "38;5;178")
			: "";
	const right = [branch, diff].filter(Boolean).join("  ");

	let line1 = left;
	if (right) {
		const pad = Math.max(1, width - visibleWidth(left) - visibleWidth(right));
		line1 = left + " ".repeat(pad) + right;
	}
	line1 = truncateToWidth(line1, width);

	const parts2 = [usagePart("5-hour", rateLimits.fiveHour), usagePart("weekly", rateLimits.weekly)].filter(
		Boolean,
	) as string[];
	const line2 = parts2.length ? truncateToWidth(parts2.join(paint(" | ", "38;5;240")), width) : "";

	return line2 ? [line1, line2] : [line1];
}

function makeFooter(
	_tui: TUI,
	_theme: Theme,
	footerData: ReadonlyFooterDataProvider,
): Component & { dispose?(): void } {
	tuiRef = _tui;
	const unsub = footerData.onBranchChange(() => {
		if (ctxRef) scheduleGitRefresh(ctxRef.cwd);
		_tui.requestRender();
	});
	// Keep the line-2 countdown fresh while idle.
	const timer = setInterval(() => _tui.requestRender(), 30000);

	return {
		invalidate() {},
		dispose() {
			unsub();
			clearInterval(timer);
			if (tuiRef === _tui) tuiRef = null;
		},
		render(width: number): string[] {
			return renderFooter(width, footerData);
		},
	};
}

function installFooter(ctx: ExtensionContext): void {
	ctx.ui.setFooter(makeFooter);
	footerActive = true;
}

// ── Entry point ───────────────────────────────────────────────────────
export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		ctxRef = ctx;
		try {
			thinkingLevel = (pi.getThinkingLevel?.() as ThinkingLevel) ?? thinkingLevel;
		} catch {
			// getThinkingLevel may be unavailable in some contexts; keep the default.
		}
		if (ctx.thinkingLevel) thinkingLevel = ctx.thinkingLevel as ThinkingLevel;
		if (!ctx.hasUI) return;
		installFooter(ctx);
		scheduleGitRefresh(ctx.cwd);
		// GLM sessions: seed line 2 before the first turn completes.
		void refreshZaiQuota(true);
	});

	pi.on("model_select", (_event, ctx) => {
		ctxRef = ctx;
		tuiRef?.requestRender();
		// Switching onto a GLM model (or away) changes whether line 2 is zai-fed.
		void refreshZaiQuota(true);
	});

	pi.on("thinking_level_select", (event, ctx) => {
		ctxRef = ctx;
		thinkingLevel = event.level as ThinkingLevel;
		tuiRef?.requestRender();
	});

	pi.on("tool_execution_end", (_event, ctx) => {
		ctxRef = ctx;
		scheduleGitRefresh(ctx.cwd);
	});

	pi.on("turn_end", (_event, ctx) => {
		ctxRef = ctx;
		scheduleGitRefresh(ctx.cwd);
	});

	pi.on("after_provider_response", (event, ctx) => {
		ctxRef = ctx;
		lastHeaders = event.headers;
		lastStatus = event.status;
		const changed = applyRateLimits(parseRateLimitHeaders(event.headers));
		// zai responses carry no rate-limit headers; usage comes from the quota
		// dashboard instead. Throttled inside; a no-op on non-zai sessions.
		if (isActiveProviderZai()) void refreshZaiQuota();
		dumpDebug(event.status, event.headers);
		if (changed) tuiRef?.requestRender();
	});

	pi.registerCommand("statusline", {
		description: "Toggle the rich Claude-style status line",
		handler: async (_args, ctx) => {
			if (footerActive) {
				ctx.ui.setFooter(undefined);
				footerActive = false;
				ctx.ui.notify("Status line restored to default", "info");
			} else {
				installFooter(ctx);
				ctx.ui.notify("Rich status line enabled", "info");
			}
		},
	});

	pi.registerCommand("statusline-debug", {
		description: "Dump the latest provider response headers for rate-limit parsing",
		handler: async (_args, ctx) => {
			if (!lastHeaders && !zaiLastFetchMs) {
				ctx.ui.notify("No provider response captured yet. Send a message first.", "warning");
				return;
			}
			// Also re-poll the zai quota when running GLM, so the dump is fresh.
			await refreshZaiQuota(true);
			dumpDebug(lastStatus, lastHeaders ?? {});
			ctx.ui.notify(`Wrote ${DEBUG_PATH}`, "info");
		},
	});
}
