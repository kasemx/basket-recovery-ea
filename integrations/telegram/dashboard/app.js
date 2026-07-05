const state = {
  overview: null,
  channels: [],
  targets: [],
  routes: [],
  audit: [],
};

const views = {
  overview: { title: "Overview", subtitle: "System status and counts" },
  telegram: { title: "Telegram", subtitle: "Local session configuration (no credentials sent to API)" },
  channels: { title: "Channels", subtitle: "Local channel tracking selections" },
  targets: { title: "MT5 Targets", subtitle: "Observer-only FILE_COMMON targets" },
  routes: { title: "Routes", subtitle: "Channel to target routing (observer-only)" },
  audit: { title: "Audit Log", subtitle: "Redacted local audit events" },
  safety: { title: "Safety", subtitle: "Execution capability matrix" },
};

function $(selector) {
  return document.querySelector(selector);
}

function showAlert(message, type = "error") {
  const alert = $("#alert");
  alert.textContent = message;
  alert.className = `alert ${type}`;
  alert.classList.remove("hidden");
}

function hideAlert() {
  $("#alert").classList.add("hidden");
}

function setLoading(isLoading) {
  $("#loading").classList.toggle("hidden", !isLoading);
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
    ...options,
  });
  let payload = null;
  try {
    payload = await response.json();
  } catch (_error) {
    payload = null;
  }
  if (!response.ok) {
    const message = payload && payload.error ? payload.error : `Request failed (${response.status})`;
    throw new Error(message);
  }
  return payload;
}

function escapeCell(value) {
  const span = document.createElement("span");
  span.textContent = value == null ? "" : String(value);
  return span.outerHTML;
}

function renderOverview() {
  const container = $("#overview-cards");
  container.innerHTML = "";
  if (!state.overview) {
    return;
  }
  const cards = [
    ["Telegram Status", state.overview.telegram.status],
    ["Tracked Channels", state.overview.counts.tracked_channels],
    ["MT5 Targets", state.overview.counts.mt5_targets],
    ["Routes", state.overview.counts.routes],
    ["Broker Execution", state.overview.safety.broker_execution],
    ["FILE_COMMON Write", state.overview.safety.file_common_write],
  ];
  cards.forEach(([label, value]) => {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `<div class="card-label">${escapeCell(label)}</div><div class="card-value">${escapeCell(value)}</div>`;
    container.appendChild(card);
  });
}

function renderTelegramStatus(statusPayload) {
  const box = $("#telegram-status");
  box.innerHTML = `
    <div><strong>Status:</strong> ${escapeCell(statusPayload.status)}</div>
    <div><strong>Phone:</strong> ${escapeCell(statusPayload.phone_masked || "—")}</div>
    <div><strong>Channel count:</strong> ${escapeCell(statusPayload.channel_count)}</div>
  `;
}

function renderTable(container, headers, rows) {
  if (!rows.length) {
    container.innerHTML = `<p class="muted">No records yet.</p>`;
    return;
  }
  const thead = `<tr>${headers.map((h) => `<th>${escapeCell(h)}</th>`).join("")}</tr>`;
  const tbody = rows.map((cells) => `<tr>${cells.map((c) => `<td>${c}</td>`).join("")}</tr>`).join("");
  container.innerHTML = `<table><thead>${thead}</thead><tbody>${tbody}</tbody></table>`;
}

function renderChannels() {
  const container = $("#channels-list");
  const rows = state.channels.map((channel) => [
    escapeCell(channel.title),
    escapeCell(channel.channel_type),
    escapeCell(channel.username || "—"),
    `<label class="checkbox"><input type="checkbox" data-channel-id="${channel.id}" class="track-toggle" ${channel.is_tracking ? "checked" : ""}> Track</label>`,
    escapeCell(channel.route_count),
    `<button type="button" class="btn" data-delete-channel="${channel.id}">Delete</button>`,
  ]);
  renderTable(container, ["Title", "Type", "Username", "Tracking", "Routes", "Actions"], rows);
  container.querySelectorAll(".track-toggle").forEach((input) => {
    input.addEventListener("change", async (event) => {
      const channelId = event.target.getAttribute("data-channel-id");
      try {
        await api(`/api/channels/${channelId}`, {
          method: "PATCH",
          body: JSON.stringify({ is_tracking: event.target.checked ? 1 : 0 }),
        });
        await refreshAll();
        showAlert("Channel tracking updated.", "success");
      } catch (error) {
        showAlert(error.message);
      }
    });
  });
  container.querySelectorAll("[data-delete-channel]").forEach((button) => {
    button.addEventListener("click", async () => {
      const channelId = button.getAttribute("data-delete-channel");
      try {
        await api(`/api/channels/${channelId}`, { method: "DELETE" });
        await refreshAll();
        showAlert("Channel deleted.", "success");
      } catch (error) {
        showAlert(error.message);
      }
    });
  });
}

function renderTargets() {
  const container = $("#targets-list");
  const rows = state.targets.map((target) => [
    escapeCell(target.name),
    escapeCell(target.terminal_label),
    escapeCell(target.broker_label),
    escapeCell(target.account_mode),
    escapeCell(target.seed_filename),
    escapeCell(target.details_filename),
    `<span class="badge badge-locked">OBSERVER_ONLY</span>`,
    `<button type="button" class="btn" data-delete-target="${target.id}">Delete</button>`,
  ]);
  renderTable(
    container,
    ["Name", "Terminal", "Broker", "Mode", "Seed File", "Details File", "Safety", "Actions"],
    rows
  );
  container.querySelectorAll("[data-delete-target]").forEach((button) => {
    button.addEventListener("click", async () => {
      const targetId = button.getAttribute("data-delete-target");
      try {
        await api(`/api/targets/${targetId}`, { method: "DELETE" });
        await refreshAll();
        showAlert("Target deleted.", "success");
      } catch (error) {
        showAlert(error.message);
      }
    });
  });
}

function renderRoutes() {
  const channelSelect = $("#route-channel-select");
  const targetSelect = $("#route-target-select");
  channelSelect.innerHTML = state.channels.map((c) => `<option value="${c.id}">${escapeCell(c.title)}</option>`).join("");
  targetSelect.innerHTML = state.targets.map((t) => `<option value="${t.id}">${escapeCell(t.name)}</option>`).join("");

  const container = $("#routes-list");
  const rows = state.routes.map((route) => [
    escapeCell(route.name),
    escapeCell(route.channel_title),
    escapeCell(route.target_name),
    escapeCell(route.parser_profile),
    escapeCell(route.mode),
    route.is_enabled ? "Enabled" : "Disabled",
    escapeCell(route.last_publish_status || "Not implemented"),
    `<button type="button" class="btn" data-delete-route="${route.id}">Delete</button>`,
  ]);
  renderTable(
    container,
    ["Name", "Channel", "Target", "Parser", "Mode", "Enabled", "Last Publish", "Actions"],
    rows
  );
  container.querySelectorAll("[data-delete-route]").forEach((button) => {
    button.addEventListener("click", async () => {
      const routeId = button.getAttribute("data-delete-route");
      try {
        await api(`/api/routes/${routeId}`, { method: "DELETE" });
        await refreshAll();
        showAlert("Route deleted.", "success");
      } catch (error) {
        showAlert(error.message);
      }
    });
  });
}

function renderAudit() {
  const severity = $("#audit-severity").value;
  const container = $("#audit-list");
  const events = state.audit.filter((event) => !severity || event.severity === severity);
  container.innerHTML = "";
  if (!events.length) {
    container.innerHTML = `<p class="muted">No audit events.</p>`;
    return;
  }
  events.forEach((event) => {
    const item = document.createElement("div");
    item.className = "audit-item";
    item.innerHTML = `
      <div class="meta">
        <span>${escapeCell(event.created_at_utc)}</span>
        <span>${escapeCell(event.severity)}</span>
        <span>${escapeCell(event.event_type)}</span>
      </div>
      <div>${escapeCell(event.message)}</div>
    `;
    container.appendChild(item);
  });
}

function renderSafetyMatrix() {
  const rows = [
    ["Telegram login", "NOT_IMPLEMENTED"],
    ["Channel live sync", "NOT_IMPLEMENTED"],
    ["FILE_COMMON publish", "NOT_IMPLEMENTED"],
    ["EA attach", "NOT_IMPLEMENTED"],
    ["Broker submit", "DISABLED_BY_DESIGN"],
    ["Token issue", "NOT_IMPLEMENTED"],
  ];
  const container = $("#safety-matrix");
  container.innerHTML = rows
    .map(
      ([label, value]) =>
        `<div class="matrix-row"><div>${escapeCell(label)}</div><div>${escapeCell(value)}</div></div>`
    )
    .join("");
}

async function refreshAll() {
  setLoading(true);
  hideAlert();
  try {
    const [overview, telegramStatus, channelsPayload, targetsPayload, routesPayload, auditPayload] =
      await Promise.all([
        api("/api/overview"),
        api("/api/telegram/status"),
        api("/api/channels"),
        api("/api/targets"),
        api("/api/routes"),
        api("/api/audit?limit=100"),
      ]);
    state.overview = overview;
    state.channels = channelsPayload.channels;
    state.targets = targetsPayload.targets;
    state.routes = routesPayload.routes;
    state.audit = auditPayload.events;
    renderOverview();
    renderTelegramStatus(telegramStatus);
    renderChannels();
    renderTargets();
    renderRoutes();
    renderAudit();
    renderSafetyMatrix();
  } catch (error) {
    showAlert(error.message);
  } finally {
    setLoading(false);
  }
}

function activateView(viewName) {
  document.querySelectorAll(".nav-item").forEach((button) => {
    button.classList.toggle("active", button.dataset.view === viewName);
  });
  document.querySelectorAll(".view").forEach((section) => {
    section.classList.toggle("active", section.id === `view-${viewName}`);
  });
  const meta = views[viewName];
  $("#view-title").textContent = meta.title;
  $("#view-subtitle").textContent = meta.subtitle;
}

function bindEvents() {
  $("#nav").addEventListener("click", (event) => {
    const button = event.target.closest(".nav-item");
    if (!button) {
      return;
    }
    activateView(button.dataset.view);
  });

  $("#telegram-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    hideAlert();
    const phone = $("#phone-input").value.trim();
    try {
      await api("/api/telegram/configure", {
        method: "POST",
        body: JSON.stringify({
          api_id_present: $("#api-id-present").checked,
          api_hash_present: $("#api-hash-present").checked,
          phone,
        }),
      });
      await refreshAll();
      showAlert("Local Telegram configuration saved (masked phone only).", "success");
    } catch (error) {
      showAlert(error.message);
    }
  });

  $("#import-demo-channels").addEventListener("click", async () => {
    try {
      await api("/api/channels/import-demo", { method: "POST", body: "{}" });
      await refreshAll();
      showAlert("Demo channels imported.", "success");
    } catch (error) {
      showAlert(error.message);
    }
  });

  $("#target-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = event.target;
    const payload = Object.fromEntries(new FormData(form).entries());
    try {
      await api("/api/targets", { method: "POST", body: JSON.stringify(payload) });
      form.reset();
      form.querySelector('[name="seed_filename"]').value = "basket_recovery_fasttrack_seed.txt";
      form.querySelector('[name="details_filename"]').value = "basket_recovery_fasttrack_details.txt";
      await refreshAll();
      showAlert("Target created.", "success");
    } catch (error) {
      showAlert(error.message);
    }
  });

  $("#route-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = event.target;
    const payload = Object.fromEntries(new FormData(form).entries());
    payload.channel_id = Number(payload.channel_id);
    payload.target_id = Number(payload.target_id);
    try {
      await api("/api/routes", { method: "POST", body: JSON.stringify(payload) });
      form.reset();
      form.querySelector('[name="parser_profile"]').value = "FASTTRACK_GOLD_NOW";
      await refreshAll();
      showAlert("Observer-only route created.", "success");
    } catch (error) {
      showAlert(error.message);
    }
  });

  $("#refresh-audit").addEventListener("click", refreshAll);
  $("#audit-severity").addEventListener("change", renderAudit);
  $("#demo-audit").addEventListener("click", async () => {
    try {
      await api("/api/audit/demo-event", { method: "POST", body: "{}" });
      await refreshAll();
      showAlert("Demo audit event added.", "success");
    } catch (error) {
      showAlert(error.message);
    }
  });
}

document.addEventListener("DOMContentLoaded", () => {
  bindEvents();
  activateView("overview");
  refreshAll();
});
