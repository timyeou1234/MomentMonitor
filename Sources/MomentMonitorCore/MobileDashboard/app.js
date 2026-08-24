"use strict";

// AutomationRuntimeStage is encoded by Swift as its stable integer raw value.
const stageOrder = [0, 1, 2, 3, 4];
const stageTitles = ["Prepare", "Develop", "Validate", "Review", "Publish"];
const state = {
  snapshot: null,
  connected: false,
  lastSuccess: null,
  timer: null,
  polling: false,
  manualRefresh: false
};

const byID = (id) => document.getElementById(id);
const setText = (id, value) => { byID(id).textContent = value; };

function relativeTime(value, now = new Date()) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  const seconds = Math.max(0, Math.round((now.getTime() - date.getTime()) / 1000));
  if (seconds < 5) return "now";
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

function duration(value, now = new Date()) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  const seconds = Math.max(0, Math.floor((now.getTime() - date.getTime()) / 1000));
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ${seconds % 60}s`;
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}

function untilTime(value, now = new Date()) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  const seconds = Math.max(0, Math.ceil((date.getTime() - now.getTime()) / 1000));
  if (seconds < 60) return `retry in ${seconds}s`;
  return `retry in ${Math.floor(seconds / 60)}m ${seconds % 60}s`;
}

function elapsedMilliseconds(value) {
  if (!Number.isFinite(value) || value < 0) return "—";
  const seconds = Math.floor(value / 1000);
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  if (hours < 24) return remainingMinutes ? `${hours}h ${remainingMinutes}m` : `${hours}h`;
  return `${Math.floor(hours / 24)}d`;
}

function usageWindowTitle(minutes) {
  if (minutes === 300) return "5-hour window";
  if (minutes === 1440) return "Daily window";
  if (minutes === 10080) return "Weekly window";
  if (minutes > 0 && minutes % 1440 === 0) return `${minutes / 1440}-day window`;
  if (minutes > 0 && minutes % 60 === 0) return `${minutes / 60}-hour window`;
  return `${minutes}-minute window`;
}

function resetTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "unknown reset time";
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit"
  }).format(date);
}

function latestDataUpdate(snapshot) {
  if (!snapshot) return null;
  const candidates = [
    snapshot.generatedAt,
    snapshot.runtime?.updatedAt,
    snapshot.runtime?.activity?.observedAt,
    snapshot.codexUsage?.fetchedAt,
    snapshot.oxAudit?.updatedAt
  ]
    .filter(Boolean)
    .map((value) => new Date(value))
    .filter((date) => !Number.isNaN(date.getTime()));
  if (!candidates.length) return null;
  return new Date(Math.max(...candidates.map((date) => date.getTime())));
}

function updateTime(value, now = new Date()) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  const sameDay = date.getFullYear() === now.getFullYear()
    && date.getMonth() === now.getMonth()
    && date.getDate() === now.getDate();
  return new Intl.DateTimeFormat(undefined, sameDay ? {
    hour: "numeric",
    minute: "2-digit",
    second: "2-digit"
  } : {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit"
  }).format(date);
}

function renderStages(activeStage, completed) {
  const bars = byID("stage-bars");
  const labels = byID("stage-labels");
  bars.replaceChildren();
  labels.replaceChildren();
  const activeIndex = stageOrder.indexOf(activeStage);
  stageTitles.forEach((title, index) => {
    const bar = document.createElement("span");
    bar.className = `stage-bar${completed || (activeIndex >= 0 && index <= activeIndex) ? " done" : ""}`;
    bars.append(bar);
    const label = document.createElement("span");
    label.textContent = title;
    if (index === activeIndex) label.className = "active";
    labels.append(label);
  });
}

function runtimeBadge(runtime) {
  switch (runtime.availability) {
    case "live": return ["LIVE", "status-live"];
    case "terminal": return [(runtime.outcome || "terminal").toUpperCase(), runtime.outcome === "completed" ? "status-success" : "status-warning"];
    case "stale": return ["STALE", "status-warning"];
    case "invalid": return ["INVALID", "status-danger"];
    default: return ["IDLE", "status-idle"];
  }
}

function renderStrategy(strategy) {
  const container = byID("strategy-progress");
  const steps = byID("strategy-steps");
  steps.replaceChildren();
  if (!strategy || !Array.isArray(strategy.steps) || !strategy.steps.length) {
    container.hidden = true;
    container.removeAttribute("aria-label");
    return;
  }

  setText("strategy-title", strategy.title);
  setText("strategy-current", strategy.currentStepTitle);
  steps.style.setProperty("--strategy-step-count", String(strategy.steps.length));
  strategy.steps.forEach((step) => {
    const node = document.createElement("span");
    node.className = `strategy-step ${step.kind} ${step.state}`;
    node.textContent = step.shortLabel;
    node.setAttribute("aria-hidden", "true");
    steps.append(node);
  });
  const summary = strategy.steps.map((step) => `${step.title} ${step.state}`).join(", ");
  container.setAttribute("aria-label", `${strategy.title}. ${strategy.currentStepTitle}. ${summary}`);
  container.hidden = false;
}

function activityTitle(action, state) {
  const titles = {
    model: ["Model turn", "Model turn"],
    inspect: ["Inspecting files", "File inspection"],
    repository: ["Checking repository", "Repository check"],
    test: ["Running tests", "Tests"],
    build: ["Building project", "Build"],
    format: ["Formatting code", "Formatting"],
    package: ["Resolving packages", "Package resolution"],
    command: ["Running command", "Command"],
    file_change: ["Applying file changes", "File changes"],
    tool: ["Using tool", "Tool call"],
    plan: ["Updating plan", "Plan update"],
    agent: ["Preparing response", "Response"]
  };
  const labels = titles[action] || ["Worker activity", "Worker activity"];
  if (state === "completed") return `${labels[1]} completed`;
  if (state === "failed") return `${labels[1]} failed`;
  return labels[0];
}

function renderActivity(activity, now, isLive) {
  const container = byID("runtime-activity");
  const recent = byID("activity-recent");
  recent.replaceChildren();
  if (!isLive || !activity) {
    container.hidden = true;
    return;
  }
  const source = activity.source === "app_server" ? "APP SERVER" : "CODEX EXEC";
  setText("activity-source", source);
  setText("activity-title", activityTitle(activity.action, activity.state));
  setText("activity-time", relativeTime(activity.observedAt, now));
  setText(
    "activity-counts",
    `${activity.completedCommands} commands · ${activity.completedFileChanges} file changes · ${activity.completedTools} tools${activity.failedCommands ? ` · ${activity.failedCommands} failed` : ""}`
  );
  (activity.recent || []).slice(-4).reverse().forEach((event) => {
    const item = document.createElement("li");
    const title = document.createElement("span");
    title.textContent = activityTitle(event.action, event.state);
    const time = document.createElement("time");
    time.dateTime = event.observedAt;
    time.textContent = relativeTime(event.observedAt, now);
    item.append(title, time);
    recent.append(item);
  });
  container.setAttribute(
    "aria-label",
    `${source}. ${activityTitle(activity.action, activity.state)}. Updated ${relativeTime(activity.observedAt, now)}.`
  );
  container.hidden = false;
}

function renderRuntime(runtime, now) {
  const [badge, badgeClass] = runtimeBadge(runtime);
  const badgeNode = byID("runtime-badge");
  badgeNode.textContent = badge;
  badgeNode.className = `status-badge ${badgeClass}`;

  const hasPhase = Boolean(runtime.phaseTitle);
  let title = hasPhase ? runtime.phaseTitle : "No local automation running";
  if (runtime.outcome && runtime.outcome !== "active" && runtime.lastActivePhaseTitle && runtime.outcome !== "completed") {
    title = `${runtime.phaseTitle} during ${runtime.lastActivePhaseTitle}`;
  }
  setText("runtime-heading", title);
  setText("runtime-kicker", runtime.availability === "terminal" ? "LAST CONTROLLER OUTCOME" : "CURRENT AUTOMATION");

  const detail = [];
  if (runtime.model) detail.push(runtime.model === "gpt-5.6-luna" ? "Luna" : "Sol");
  if (runtime.role) detail.push(runtime.role);
  if (runtime.roundNumber && runtime.totalRounds) detail.push(`round ${runtime.roundNumber} of ${runtime.totalRounds}`);
  if (runtime.repairAttempt) detail.push(`repair ${runtime.repairAttempt}`);
  setText("runtime-detail", detail.length ? detail.join(" · ") : "Controller-reported phase; GitHub remains authoritative for completion.");

  setText("runtime-issue", runtime.issueNumber ? `Issue #${runtime.issueNumber}` : "Issue —");
  setText(
    "runtime-issue-time",
    runtime.issueDurationMilliseconds == null
      ? "Codex time not recorded"
      : `Codex ${elapsedMilliseconds(runtime.issueDurationMilliseconds)}`
  );
  setText("runtime-pr", runtime.pullRequestNumber ? `PR #${runtime.pullRequestNumber}` : "PR not created yet");
  setText("runtime-time", runtime.availability === "live" ? `${duration(runtime.phaseStartedAt, now)} in phase` : relativeTime(runtime.updatedAt, now));

  const message = byID("runtime-message");
  message.hidden = !runtime.message;
  message.textContent = runtime.message || "";
  renderStages(runtime.activeStage, runtime.outcome === "completed");
  renderStrategy(runtime.strategy);
  renderActivity(runtime.activity, now, runtime.availability === "live");
}

function renderCodexUsage(usage) {
  const badge = byID("usage-badge");
  const bar = byID("usage-bar");
  const fill = byID("usage-bar-fill");
  const secondary = byID("usage-secondary");
  const primary = usage && usage.availability === "live" ? usage.primary : null;

  if (!primary) {
    setText("usage-remaining", "—");
    setText("usage-detail", usage?.message || "Codex usage is unavailable.");
    const isStale = usage?.availability === "stale";
    badge.textContent = isStale ? "STALE" : "UNAVAILABLE";
    badge.className = `status-badge ${isStale ? "status-warning" : "status-idle"}`;
    fill.style.width = "0%";
    bar.removeAttribute("aria-valuenow");
    bar.setAttribute("aria-label", "Codex usage unavailable");
    secondary.hidden = true;
    return;
  }

  const remaining = Math.max(0, Math.min(100, Math.round(100 - primary.usedPercent)));
  setText("usage-remaining", remaining);
  setText("usage-detail", `${usageWindowTitle(primary.windowDurationMinutes)} · resets ${resetTime(primary.resetsAt)}`);
  badge.textContent = "LIVE";
  badge.className = "status-badge status-live";
  fill.style.width = `${remaining}%`;
  bar.setAttribute("aria-valuenow", String(remaining));
  bar.setAttribute("aria-label", `${remaining}% Codex capacity remaining`);

  if (usage.secondary) {
    const secondaryRemaining = Math.max(0, Math.min(100, Math.round(100 - usage.secondary.usedPercent)));
    secondary.textContent = `${usageWindowTitle(usage.secondary.windowDurationMinutes)}: ${secondaryRemaining}% remaining · resets ${resetTime(usage.secondary.resetsAt)}`;
    secondary.hidden = false;
  } else {
    secondary.hidden = true;
  }
}

function oxStateTitle(value) {
  switch (value) {
    case "starting": return "Starting";
    case "probing": return "Checking free route";
    case "available": return "Free route available";
    case "scanning": return "Reviewing Issues";
    case "backoff": return "Waiting to retry";
    case "completed": return "Issue sweep completed";
    case "stopped": return "Stopped";
    default: return "Status unavailable";
  }
}

function renderOxAudit(ox, now) {
  const card = byID("ox-card");
  card.hidden = !ox || ox.availability === "absent";
  if (card.hidden) return;

  const badge = byID("ox-badge");
  const progress = byID("ox-progress");
  const fill = byID("ox-progress-fill");
  const completed = Number.isInteger(ox.completedCount) ? ox.completedCount : 0;
  const total = Number.isInteger(ox.totalCount) ? ox.totalCount : 0;
  const percent = total > 0 ? Math.max(0, Math.min(100, Math.round(completed / total * 100))) : 0;

  setText("ox-heading", oxStateTitle(ox.state));
  setText("ox-count", `${completed}/${total} Issues`);
  setText("ox-issue", ox.issueNumber ? `Issue #${ox.issueNumber}` : "Issue —");
  setText("ox-http", ox.lastHTTPStatus ? `HTTP ${ox.lastHTTPStatus}` : "HTTP —");
  setText("ox-next", ox.nextAttemptAt ? untilTime(ox.nextAttemptAt, now) : relativeTime(ox.updatedAt, now));
  fill.style.width = `${percent}%`;
  progress.setAttribute("aria-valuenow", String(percent));
  progress.setAttribute("aria-valuemax", "100");
  progress.setAttribute("aria-label", `${completed} of ${total} Ox Issue classifications completed`);

  const warning = ox.availability === "stale" || ox.state === "backoff";
  const danger = ox.availability === "invalid";
  const success = ox.state === "completed";
  badge.textContent = danger ? "INVALID" : ox.availability === "stale" ? "STALE" : (ox.state || "current").toUpperCase();
  badge.className = `status-badge ${danger ? "status-danger" : warning ? "status-warning" : success ? "status-success" : "status-live"}`;
  const message = byID("ox-message");
  message.textContent = ox.message || "";
  message.hidden = !ox.message;
}

function createWorkItem(item, now) {
  const link = document.createElement("a");
  link.className = `work-item item-${item.severity}`;
  link.href = item.url;
  link.target = "_blank";
  link.rel = "noopener noreferrer";

  const top = document.createElement("div");
  top.className = "item-top";
  const title = document.createElement("p");
  title.className = "item-title";
  title.textContent = item.title;
  const status = document.createElement("span");
  status.className = "item-status";
  status.textContent = item.statusText || item.lane;
  top.append(title, status);

  const detail = document.createElement("p");
  detail.className = "item-detail";
  detail.textContent = item.detail;
  const time = document.createElement("time");
  time.className = "item-time";
  time.dateTime = item.updatedAt;
  time.textContent = `Updated ${relativeTime(item.updatedAt, now)}`;
  const timing = document.createElement("div");
  timing.className = "item-timing";
  if (item.issueNumber != null) {
    const codexTime = document.createElement("span");
    codexTime.className = `item-codex-time${item.automationDurationMilliseconds == null ? " unavailable" : ""}`;
    codexTime.textContent = item.automationDurationMilliseconds == null
      ? "Codex —"
      : `Codex ${elapsedMilliseconds(item.automationDurationMilliseconds)}`;
    codexTime.setAttribute(
      "aria-label",
      item.automationDurationMilliseconds == null
        ? "Codex time not recorded"
        : `Recorded Codex time ${elapsedMilliseconds(item.automationDurationMilliseconds)}`
    );
    timing.append(codexTime);
  }
  timing.append(time);
  link.append(top, detail, timing);
  return link;
}

function renderLanes(lanes, now) {
  const container = byID("lanes");
  container.replaceChildren();
  if (!lanes.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No tracked repository work is visible.";
    container.append(empty);
    return;
  }
  lanes.forEach((lane) => {
    const section = document.createElement("section");
    section.className = "lane";
    section.dataset.lane = lane.lane;
    const header = document.createElement("div");
    header.className = "lane-header";
    const title = document.createElement("div");
    title.className = "lane-title";
    const dot = document.createElement("span");
    dot.className = "lane-dot";
    dot.setAttribute("aria-hidden", "true");
    const titleText = document.createElement("span");
    titleText.textContent = lane.title;
    title.append(dot, titleText);
    const count = document.createElement("span");
    count.className = "lane-count";
    count.textContent = String(lane.items.length);
    header.append(title, count);
    section.append(header);
    lane.items.forEach((item) => section.append(createWorkItem(item, now)));
    container.append(section);
  });
}

function render() {
  const snapshot = state.snapshot;
  const now = new Date();
  byID("connection-banner").hidden = state.connected;
  byID("connection-dot").classList.toggle("connected", state.connected);
  byID("connection-dot-top").classList.toggle("connected", state.connected);
  setText("connection-text", state.connected ? "Mac connected" : "Mac unavailable");
  setText("connection-text-top", state.connected ? "Mac connected" : "Mac unavailable");
  setText("updated-time", state.lastSuccess ? `Received ${relativeTime(state.lastSuccess, now)}` : "Not updated yet");

  const refreshButton = byID("refresh-button");
  refreshButton.disabled = state.polling;
  refreshButton.classList.toggle("refreshing", state.manualRefresh);
  refreshButton.setAttribute("aria-busy", String(state.manualRefresh));
  setText("refresh-label", state.manualRefresh ? "Refreshing" : "Refresh");

  const dataUpdatedAt = latestDataUpdate(snapshot);
  const lastUpdate = byID("last-update-time");
  if (dataUpdatedAt) {
    lastUpdate.dateTime = dataUpdatedAt.toISOString();
  } else {
    lastUpdate.removeAttribute("datetime");
  }
  lastUpdate.textContent = dataUpdatedAt
    ? `Last update at ${updateTime(dataUpdatedAt, now)}`
    : "Last update at —";
  if (!snapshot) return;

  setText("repository-name", snapshot.repository);
  const progress = snapshot.projectProgress;
  const percentage = progress.totalCount > 0 ? Math.round((progress.completedCount / progress.totalCount) * 100) : 0;
  setText("progress-completed", progress.completedCount);
  setText("progress-total", progress.totalCount);
  setText("progress-percent", percentage);
  setText("progress-copy", progress.totalCount ? "Closed M1 Issues out of the complete M1 scope." : "No M1 Issues found.");
  const ring = byID("progress-ring");
  ring.style.setProperty("--progress", `${percentage * 3.6}deg`);
  ring.setAttribute("aria-label", `${percentage}% closed, ${progress.completedCount} of ${progress.totalCount} M1 Issues`);

  renderCodexUsage(snapshot.codexUsage);
  renderOxAudit(snapshot.oxAudit, now);
  renderRuntime(snapshot.runtime, now);
  renderLanes(snapshot.lanes, now);
}

async function poll({ manual = false } = {}) {
  if (state.polling) return;
  state.polling = true;
  state.manualRefresh = manual;
  render();
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 4000);
  try {
    const response = await fetch("/api/v1/snapshot", { cache: "no-store", signal: controller.signal });
    if (!response.ok) throw new Error(`Snapshot request failed: ${response.status}`);
    const snapshot = await response.json();
    if (snapshot.schemaVersion !== 5) throw new Error("Unsupported snapshot schema");
    state.snapshot = snapshot;
    state.connected = true;
    state.lastSuccess = new Date(snapshot.servedAt);
  } catch (_) {
    state.connected = false;
  } finally {
    window.clearTimeout(timeout);
    state.polling = false;
    state.manualRefresh = false;
    render();
    window.clearTimeout(state.timer);
    state.timer = window.setTimeout(poll, document.hidden ? 10000 : 1000);
  }
}

byID("refresh-button").addEventListener("click", () => {
  if (state.polling) return;
  window.clearTimeout(state.timer);
  poll({ manual: true });
});

document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    window.clearTimeout(state.timer);
    poll();
  }
});

renderStages(null, false);
render();
poll();
window.setInterval(render, 1000);
