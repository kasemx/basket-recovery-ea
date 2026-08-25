const state = {
  overview: null,
  telegramStatus: null,
  credentialsStatus: null,
  channels: [],
  targets: [],
  mt5Targets: { targets: [], summary: {} },
  mt5Discoveries: { discoveries: [], path_results: [], duplicate_paths: [], scan_id: null },
  mt5TerminalPaths: [],
  routes: [],
  audit: [],
  signalHistory: { items: [], page: 1, page_size: 20, total: 0 },
  signalHistoryFilters: { page: 1, page_size: 20 },
  signalHistoryView: "cards",
  listenerWorker: null,
  dashboardHealth: null,
  pendingDiscoveryAddId: null,
  mt5AccountFilters: { type: "ALL", status: "ALL", search: "" },
  mt5Drawer: { open: false, mode: null, targetId: null, discoveryId: null, tab: "overview" },
  mt5RowMenu: { open: false, targetId: null, trigger: null },
  pendingRealAccountDiscoveryId: null,
};

const MT5_QUICK_PATHS = [
  { label: "MetaTrader 5", path: "C:\\Program Files\\MetaTrader 5\\terminal64.exe" },
  { label: "FundedNext", path: "C:\\Program Files\\FundedNext MT5 Terminal\\terminal64.exe" },
  { label: "FTMO", path: "C:\\Program Files\\FTMO Global Markets MT5 Terminal\\terminal64.exe" },
];

const SIGNAL_HISTORY_VIEW_KEY = "br_dashboard_signal_history_view";

const views = {
  overview: {
    title: "Genel Bakış",
    subtitle: "Adım adım kurulum rehberi",
  },
  telegram: {
    title: "Telegram Bağlantısı",
    subtitle: "Üç adımda Telegram hesabına bağlan",
  },
  channels: {
    title: "Kanallarım",
    subtitle: "Takip etmek istediğin Telegram kanalları",
  },
  targets: {
    title: "MT5 Hesaplarım",
    subtitle: "Terminallerini tara, hesaplarını otomatik bul ve EA eşleşmesini yönet",
  },
  routes: {
    title: "Sinyal Yönlendirmeleri",
    subtitle: "Kanal ile MT5 hesabını eşleştir",
  },
  "signal-history": {
    title: "Sinyal Geçmişi",
    subtitle: "Doğrulanmış sinyaller · işlem sonucu ayrı gösterilir",
  },
  audit: {
    title: "İşlem Geçmişi",
    subtitle: "Yerel güvenli kayıtlar (hassas bilgi içermez)",
  },
  safety: {
    title: "Güvenlik",
    subtitle: "Panel yetkileri ve sınırlar",
  },
};

const STATUS_LABELS = {
  DISCONNECTED: "Bağlı Değil",
  API_CONFIGURED: "Bağlanmaya Hazır",
  CODE_SENT: "Kod Gönderildi",
  TWO_FACTOR_REQUIRED: "Ek Şifre Gerekli",
  CONNECTED: "Bağlandı",
  TELEGRAM_CONNECTED: "Bağlandı",
  ERROR: "Hata",
};

const LISTENER_WORKER_STATE_LABELS = {
  STOPPED: "Kapalı",
  STARTING: "Başlatılıyor",
  CONNECTING: "Bağlanıyor",
  CONNECTED: "Bağlı",
  RECONNECTING: "Yeniden Bağlanıyor",
  DEGRADED: "Sorun Var",
  STOPPING: "Durduruluyor",
  ERROR: "Hata",
};

const CHANNEL_TYPE_LABELS = {
  channel: "Kanal",
  supergroup: "Süper Grup",
  group: "Grup",
};

const ERROR_MESSAGES = {
  CREDENTIAL_VAULT_INVALID:
    "API kimliği veya anahtarı geçersiz. Anahtarı my.telegram.org adresinden tam yapıştır.",
  TELEGRAM_CONFIG_MISSING: "Telegram bağlantı bilgileri eksik.",
  TELETHON_NOT_INSTALLED: "Telegram bağlantı bileşeni hazır değil.",
  TELEGRAM_FLOOD_WAIT: "Telegram istek sınırına ulaşıldı. Biraz bekleyip tekrar dene.",
  TELEGRAM_API_ID_INVALID: "Telegram API kimliğini reddetti. Kayıtlı bilgileri kontrol et.",
  TELEGRAM_PHONE_INVALID: "Telefon numarası formatı geçersiz.",
  TELEGRAM_NETWORK_ERROR: "Telegram'a bağlanırken ağ hatası oluştu.",
  TELEGRAM_CODE_REQUEST_FAILED: "Doğrulama kodu isteği başarısız oldu.",
  TELEGRAM_SESSION_PATH_ERROR: "Oturum klasörü hazırlanamadı.",
  TELEGRAM_INTERNAL_ERROR: "Beklenmeyen bir hata oluştu.",
  TELEGRAM_AUTH_FAILED: "Giriş doğrulanamadı. Bilgileri kontrol edip tekrar dene.",
  TELEGRAM_2FA_REQUIRED: "Telegram iki aşamalı doğrulama şifrenizi istiyor.",
};

function $(selector) {
  return document.querySelector(selector);
}

function localizeBackendMessage(message) {
  const text = String(message || "");
  if (text.includes("Telegram API credentials are missing")) {
    return ERROR_MESSAGES.TELEGRAM_CONFIG_MISSING;
  }
  if (text.includes("Telethon is not installed")) {
    return ERROR_MESSAGES.TELETHON_NOT_INSTALLED;
  }
  if (text.includes("Phone must be in international format")) {
    return "Telefon numarasını +90 ile başlayan uluslararası formatta gir.";
  }
  if (text.includes("api_id and api_hash are required")) {
    return "API kimliği ve anahtarı zorunludur.";
  }
  return text;
}

function setButtonBusy(button, busy) {
  if (!button) {
    return;
  }
  button.disabled = busy;
  button.dataset.busy = busy ? "1" : "0";
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

function setHint(id, message, visible) {
  const el = $(id);
  if (!el) {
    return;
  }
  el.textContent = message || "";
  el.classList.toggle("hidden", !visible || !message);
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
    const error = new Error(formatErrorMessage(payload, response.status));
    error.status = response.status;
    error.payload = payload;
    throw error;
  }
  return payload;
}

function formatErrorMessage(payload, statusCode = 0) {
  if (statusCode === 404) {
    return "Bu özellik mevcut dashboard sürümünde yok. Terminalde sunucuyu durdurup yeniden başlat, ardından sayfayı Ctrl+Shift+R ile yenile.";
  }
  if (payload && payload.user_message) {
    return localizeBackendMessage(payload.user_message);
  }
  if (payload && payload.error) {
    if (String(payload.error).toLowerCase() === "not found") {
      return "İstenen işlem bulunamadı. Dashboard sunucusunu yeniden başlatıp tekrar dene.";
    }
    return localizeBackendMessage(payload.error);
  }
  if (payload && payload.error_code) {
    if (payload.error_code === "TELEGRAM_FLOOD_WAIT" && payload.flood_wait_seconds) {
      return `Telegram istek sınırına ulaşıldı. ${payload.flood_wait_seconds} saniye bekle.`;
    }
    return ERROR_MESSAGES[payload.error_code] || "İşlem tamamlanamadı.";
  }
  return "İşlem tamamlanamadı.";
}

function escapeCell(value) {
  const span = document.createElement("span");
  span.textContent = value == null ? "" : String(value);
  return span.outerHTML;
}

function mergeTelegramStatus(statusPayload, credentialsStatus) {
  const merged = { ...statusPayload };
  if (credentialsStatus) {
    merged.credentials_saved = credentialsStatus.credentials_saved;
    merged.vault_supported = credentialsStatus.vault_supported;
    merged.config_ready = credentialsStatus.config_ready;
  }
  return merged;
}

function formatSessionLabel(statusPayload) {
  if (statusPayload.session_pending || !statusPayload.session_file_exists) {
    return "İlk girişte oluşturulacak";
  }
  if (statusPayload.session_path_masked) {
    return "Kayıtlı oturum mevcut";
  }
  return "Henüz yok";
}

function formatTelegramStatusLabel(status) {
  return STATUS_LABELS[status] || status || "Bilinmiyor";
}

function formatChannelType(type) {
  return CHANNEL_TYPE_LABELS[type] || type || "—";
}

function isTelegramConnected(statusPayload) {
  const status = statusPayload.status;
  return status === "TELEGRAM_CONNECTED" || status === "CONNECTED";
}

function roadmapStepState(done, locked) {
  if (done) {
    return { label: "Hazır", className: "step-ready" };
  }
  if (locked) {
    return { label: "Kilitli", className: "step-locked" };
  }
  return { label: "Bekliyor", className: "step-waiting" };
}

function renderOverviewRoadmap() {
  const container = $("#overview-roadmap");
  if (!container) {
    return;
  }
  const tg = state.telegramStatus || {};
  const credentialsSaved = Boolean(tg.credentials_saved);
  const connected = isTelegramConnected(tg);
  const hasChannels = state.channels.length > 0;
  const trackedCount = state.channels.filter((c) => c.is_tracking).length;
  const hasTargets = state.targets.length > 0;
  const hasRoutes = state.routes.length > 0;

  const steps = [
    {
      title: "Telegram bilgilerini kaydet",
      ...roadmapStepState(credentialsSaved, false),
    },
    {
      title: "Telegram hesabına bağlan",
      ...roadmapStepState(connected, !credentialsSaved),
    },
    {
      title: "Kanallarını getir",
      ...roadmapStepState(hasChannels, !connected),
    },
    {
      title: "Takip etmek istediğin kanalı seç",
      ...roadmapStepState(trackedCount > 0, !hasChannels),
    },
    {
      title: "MT5 hesabını ekle",
      ...roadmapStepState(hasTargets, !connected),
    },
    {
      title: "Sinyali yalnız izle ve kontrol et",
      ...roadmapStepState(hasRoutes, !hasTargets || trackedCount === 0),
    },
  ];

  container.innerHTML = steps
    .map(
      (step, index) => `
      <div class="roadmap-item ${step.className}">
        <div class="roadmap-index">${index + 1}</div>
        <div class="roadmap-content">
          <div class="roadmap-title">${escapeCell(step.title)}</div>
          <span class="roadmap-state">${escapeCell(step.label)}</span>
        </div>
      </div>`
    )
    .join("");

  let banner = "Başlamak için Telegram bilgilerini kaydet.";
  if (connected && !hasChannels) {
    banner = "Telegram hesabın bağlandı. Şimdi kanallarını getirebilirsin.";
  } else if (connected && hasChannels && !hasTargets) {
    banner = "Henüz bir MT5 hedefi eklemedin.";
  } else if (connected && hasTargets && trackedCount === 0) {
    banner = "Kanallarından en az birini takibe al.";
  } else if (connected && hasRoutes) {
    banner = "Kurulum tamamlandı. Sinyaller yalnız izleme modunda.";
  } else if (credentialsSaved && !connected) {
    banner = "Telegram bilgilerin hazır. Bağlantı adımlarına geç.";
  }

  const bannerEl = document.createElement("p");
  bannerEl.className = "roadmap-banner muted";
  bannerEl.textContent = banner;
  container.prepend(bannerEl);
}

function renderOverview() {
  renderOverviewRoadmap();
  const container = $("#overview-cards");
  container.innerHTML = "";
  if (!state.overview) {
    return;
  }
  const cards = [
    ["Telegram Durumu", formatTelegramStatusLabel(state.overview.telegram.status)],
    ["Takip Edilen Kanallar", state.overview.counts.tracked_channels],
    ["MT5 Hesapları", state.overview.counts.mt5_targets],
    ["Yönlendirmeler", state.overview.counts.routes],
    ["İşlem Açma", "Kapalı"],
    ["MT5'e Sinyal Gönderme", "Henüz Kapalı"],
  ];
  cards.forEach(([label, value]) => {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `<div class="card-label">${escapeCell(label)}</div><div class="card-value">${escapeCell(value)}</div>`;
    container.appendChild(card);
  });
}

function renderTelegramBadges(statusPayload) {
  const container = $("#telegram-badges");
  if (!container) {
    return;
  }
  const vaultBadge = statusPayload.vault_supported
    ? `<span class="badge badge-success">Güvenli Windows Kasası Hazır</span>`
    : `<span class="badge badge-muted">Güvenli kasa kullanılamıyor</span>`;
  const credentialsBadge = statusPayload.credentials_saved
    ? `<span class="badge badge-success">Telegram Bilgileri Kaydedildi</span>`
    : `<span class="badge badge-muted">Telegram Bilgileri Eksik</span>`;
  const configBadge = statusPayload.config_ready
    ? `<span class="badge badge-success">Bağlantı Ayarları Hazır</span>`
    : `<span class="badge badge-muted">Telegram Bilgileri Eksik</span>`;
  const telethonBadge = statusPayload.telethon_available
    ? `<span class="badge badge-success">Telegram Bağlantısı Hazır</span>`
    : `<span class="badge badge-muted">Telegram bileşeni eksik</span>`;
  container.innerHTML = vaultBadge + credentialsBadge + configBadge + telethonBadge;
}

function updateWizardStages(statusPayload) {
  const credentialsSaved = Boolean(statusPayload.credentials_saved);
  const phoneConfigured = Boolean(statusPayload.phone_masked);
  const status = statusPayload.status;
  const connected = isTelegramConnected(statusPayload);
  const codeSent = status === "CODE_SENT";
  const twoFactor = status === "TWO_FACTOR_REQUIRED";
  const configReady = statusPayload.config_ready;
  const telethonReady = statusPayload.telethon_available;

  const step2 = $("#wizard-step-2");
  const step3 = $("#wizard-step-3");
  const configureBtn = $("#configure-phone-btn");
  const phoneInput = $("#phone-input");

  if (step2) {
    step2.classList.toggle("wizard-locked", !credentialsSaved);
  }
  if (step3) {
    step3.classList.toggle("wizard-locked", !(credentialsSaved && phoneConfigured));
  }

  if (configureBtn) {
    configureBtn.disabled = !credentialsSaved;
  }
  if (phoneInput) {
    phoneInput.disabled = !credentialsSaved;
  }

  setHint(
    "#phone-stage-hint",
    credentialsSaved
      ? ""
      : "Önce 1. adımda Telegram bilgilerini kaydetmelisin.",
    !credentialsSaved
  );

  const canRequestCode =
    (status === "API_CONFIGURED" || status === "CODE_SENT") &&
    configReady &&
    telethonReady &&
    !connected;
  $("#request-code-btn").disabled = !canRequestCode;
  if ($("#request-code-btn")) {
    $("#request-code-btn").textContent = codeSent ? "Doğrulama Kodunu Yeniden Gönder" : "Doğrulama Kodu Gönder";
  }
  $("#verify-code-btn").disabled = !(configReady && telethonReady && codeSent);
  $("#sync-channels-btn").disabled = !connected;
  $("#disconnect-btn").disabled = status === "DISCONNECTED";
  $("#password-field").classList.toggle("hidden", !twoFactor);
  $("#verify-password-btn").classList.toggle("hidden", !twoFactor);
  $("#code-input").disabled = !codeSent && !twoFactor;

  setHint(
    "#connect-stage-hint",
    credentialsSaved && phoneConfigured
      ? ""
      : "Önce telefon numaranı kaydetmelisin.",
    !(credentialsSaved && phoneConfigured)
  );

  setHint(
    "#request-code-hint",
    codeSent
      ? "Kod Telegram uygulamanıza gider (Ayarlar → Cihazlar). Gerekirse yeniden gönderebilirsin."
      : canRequestCode
        ? "Doğrulama kodu Telegram uygulamanıza gönderilir."
        : connected
          ? "Zaten bağlısın."
          : !phoneConfigured
            ? "Telefon numaran kayıtlı değil."
            : !configReady
              ? "Telegram bilgileri eksik."
              : !telethonReady
                ? "Telegram bağlantı bileşeni hazır değil."
                : "Telefon kaydı tamamlandıktan sonra kod gönderebilirsin.",
    codeSent || !canRequestCode
  );

  setHint(
    "#verify-code-hint",
    codeSent
      ? "Kodu Telegram uygulamanızdan alın (Ayarlar → Cihazlar). 12345 gibi test kodu çalışmaz."
      : "",
    codeSent
  );

  setHint(
    "#sync-channels-hint",
    connected ? "" : "Kanalları getirmek için önce Telegram'a bağlanmalısın.",
    !connected
  );
}

function renderTelegramStatus(statusPayload) {
  state.telegramStatus = statusPayload;
  renderTelegramBadges(statusPayload);
  updateWizardStages(statusPayload);
  renderListenerWorkerPanel();

  const box = $("#telegram-status");
  const channelLabel =
    statusPayload.channel_count > 0
      ? `${statusPayload.channel_count} kanal`
      : "Henüz getirilmedi";

  box.innerHTML = `
    <div><strong>Telegram Durumu:</strong> ${escapeCell(formatTelegramStatusLabel(statusPayload.status))}</div>
    <div><strong>Telefon:</strong> ${escapeCell(statusPayload.phone_masked || "—")}</div>
    <div><strong>Kanallar:</strong> ${escapeCell(channelLabel)}</div>
    <div><strong>Güvenli Kasa:</strong> ${escapeCell(statusPayload.vault_supported ? "Aktif" : "Kapalı")}</div>
    <div><strong>İşlem Açma:</strong> Kapalı</div>
  `;

  const technical = $("#telegram-technical-body");
  if (technical) {
    technical.innerHTML = `
      <div><strong>Oturum:</strong> ${escapeCell(formatSessionLabel(statusPayload))}</div>
      <div><strong>Bilgi kaynağı:</strong> ${escapeCell(statusPayload.credential_source || "—")}</div>
      <div><strong>Bağlantı bileşeni:</strong> ${escapeCell(statusPayload.telethon_available ? "Hazır" : "Eksik")}</div>
      <div><strong>Ayar durumu:</strong> ${escapeCell(statusPayload.config_ready ? "Hazır" : "Eksik")}</div>
      <div><strong>Teknik hata kodu:</strong> ${escapeCell(statusPayload.last_error_code || "—")}</div>
    `;
  }
}

function formatListenerWorkerStateLabel(worker) {
  if (!worker) {
    return "Kapalı";
  }
  return worker.state_label || LISTENER_WORKER_STATE_LABELS[worker.state] || worker.state || "Kapalı";
}

function formatUtcShort(value) {
  if (!value) {
    return "—";
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return "—";
  }
  return parsed.toLocaleString("tr-TR");
}

function renderListenerWorkerPanel() {
  const container = $("#listener-worker-status");
  const startBtn = $("#listener-worker-start-btn");
  const stopBtn = $("#listener-worker-stop-btn");
  if (!container) {
    return;
  }
  const worker = state.listenerWorker;
  if (!worker) {
    container.innerHTML = `<p class="muted">Dinleme servisi durumu yükleniyor…</p>`;
    if (startBtn) startBtn.disabled = false;
    if (stopBtn) stopBtn.disabled = true;
    return;
  }
  const activeCount = worker.active_route_count || 0;
  const running = ["CONNECTED", "RECONNECTING", "CONNECTING", "STARTING"].includes(worker.state);
  container.innerHTML = `
    <div><strong>Durum:</strong> ${escapeCell(formatListenerWorkerStateLabel(worker))}</div>
    <div><strong>Aktif Route:</strong> ${escapeCell(String(activeCount))}</div>
    <div><strong>Son Bağlantı:</strong> ${escapeCell(formatUtcShort(worker.started_at_utc))}</div>
    <div><strong>Son Kontrol:</strong> ${escapeCell(formatUtcShort(worker.last_heartbeat_at_utc))}</div>
    ${worker.safe_last_error ? `<div class="muted">${escapeCell(worker.safe_last_error)}</div>` : ""}
  `;
  if (startBtn) startBtn.disabled = running;
  if (stopBtn) stopBtn.disabled = !running && worker.state !== "DEGRADED" && worker.state !== "ERROR";
}

function renderRoutesWorkerHint() {
  const hint = $("#routes-worker-hint");
  if (!hint) {
    return;
  }
  const worker = state.listenerWorker;
  const active = worker && ["CONNECTED", "RECONNECTING"].includes(worker.state);
  hint.textContent = active
    ? "Telegram Dinleme Servisi Aktif"
    : "Önce Telegram Dinleme Servisini Başlat";
  hint.classList.toggle("hidden", false);
}

function routeConnectionLabels(listener) {
  const workerLabel = listener.worker_state_label || formatListenerWorkerStateLabel({ state: listener.worker_state });
  const telegramLabel = listener.telegram_connected ? "Bağlı" : "Bağlı Değil";
  const routeLabel = listener.running ? "Aktif" : "Kapalı";
  return { routeLabel, workerLabel, telegramLabel };
}

function renderTable(container, headers, rows, emptyMessage) {
  if (!rows.length) {
    container.innerHTML = `<p class="muted">${escapeCell(emptyMessage)}</p>`;
    return;
  }
  const thead = `<tr>${headers.map((h) => `<th>${escapeCell(h)}</th>`).join("")}</tr>`;
  const tbody = rows.map((cells) => `<tr>${cells.map((c) => `<td>${c}</td>`).join("")}</tr>`).join("");
  container.innerHTML = `<table><thead>${thead}</thead><tbody>${tbody}</tbody></table>`;
}

function renderChannels() {
  const container = $("#channels-list");
  const emptyHint = $("#channels-empty-hint");
  if (emptyHint) {
    emptyHint.classList.toggle("hidden", state.channels.length > 0);
  }

  const rows = state.channels.map((channel) => {
    const trackingBtn = channel.is_tracking
      ? `<button type="button" class="btn btn-small track-toggle" data-channel-id="${channel.id}" data-tracking="0">Takibi Durdur</button>`
      : `<button type="button" class="btn btn-small primary track-toggle" data-channel-id="${channel.id}" data-tracking="1">Takibi Aç</button>`;
    return [
      escapeCell(channel.title),
      escapeCell(formatChannelType(channel.channel_type)),
      escapeCell(channel.is_tracking ? "Açık" : "Kapalı"),
      escapeCell(channel.route_count),
      trackingBtn,
      `<button type="button" class="btn btn-small" data-delete-channel="${channel.id}">Sil</button>`,
    ];
  });

  renderTable(
    container,
    ["Kanal Adı", "Kanal Tipi", "Takip Durumu", "Bağlı MT5", "Takip", "İşlem"],
    rows,
    "Henüz kanal bulunmuyor. Önce Telegram sayfasından “Kanallarımı Getir” düğmesine bas."
  );

  container.querySelectorAll(".track-toggle").forEach((button) => {
    button.addEventListener("click", async () => {
      const channelId = button.getAttribute("data-channel-id");
      const isTracking = button.getAttribute("data-tracking") === "1";
      try {
        await api(`/api/channels/${channelId}`, {
          method: "PATCH",
          body: JSON.stringify({ is_tracking: isTracking ? 1 : 0 }),
        });
        await refreshAll();
        showAlert(isTracking ? "Kanal takibe alındı." : "Kanal takibi durduruldu.", "success");
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
        showAlert("Kanal silindi.", "success");
      } catch (error) {
        showAlert(error.message);
      }
    });
  });
}

function accountTypeBadgeClass(type) {
  if (type === "REAL") return "badge-danger";
  if (type === "DEMO") return "badge-success";
  if (type === "CONTEST") return "badge-warn";
  return "badge-muted";
}

function accountTypeLabel(type) {
  const labels = {
    DEMO: "DEMO",
    REAL: "GERÇEK",
    CONTEST: "YARIŞMA",
    UNKNOWN: "BİLİNMİYOR",
  };
  return labels[type] || "BİLİNMİYOR";
}

function truncatePath(path, maxLength = 44) {
  if (!path) return "—";
  const text = String(path);
  if (text.length <= maxLength) return text;
  const normalized = text.replace(/\//g, "\\");
  const parts = normalized.split("\\").filter(Boolean);
  if (parts.length < 3) return text;
  return `${parts[0]}\\...\\${parts[parts.length - 1]}`;
}

function terminalChipLabel(path) {
  const lower = String(path || "").toLowerCase();
  if (lower.includes("ftmo")) return "FTMO";
  if (lower.includes("fundednext") || lower.includes("funded")) return "FundedNext";
  if (lower.includes("metatrader")) return "MetaTrader 5";
  const parts = String(path).replace(/\//g, "\\").split("\\").filter(Boolean);
  if (parts.length && parts[parts.length - 1].toLowerCase().endsWith(".exe")) {
    return parts.length > 1 ? parts[parts.length - 2] : parts[parts.length - 1];
  }
  return parts[parts.length - 1] || "Terminal";
}

function syncMt5PathsTextarea() {
  const textarea = $("#mt5-discovery-paths");
  if (textarea) {
    textarea.value = state.mt5TerminalPaths.join("\n");
  }
  const scanBtn = $("#mt5-discovery-scan-btn");
  const hint = $("#mt5-scan-hint");
  const hasPaths = state.mt5TerminalPaths.length > 0;
  if (scanBtn) scanBtn.disabled = !hasPaths;
  if (hint) {
    hint.textContent = hasPaths
      ? `${state.mt5TerminalPaths.length} terminal yolu hazır. Taramaya başlayabilirsin.`
      : "Önce en az bir terminal yolu ekle.";
  }
}

function addMt5TerminalPath(path) {
  const cleaned = String(path || "").trim();
  if (!cleaned) return false;
  if (state.mt5TerminalPaths.includes(cleaned)) return false;
  state.mt5TerminalPaths.push(cleaned);
  syncMt5PathsTextarea();
  renderMt5PathChips();
  renderMt5QuickPaths();
  return true;
}

function notifyMt5PathAdded(wasAdded) {
  if (wasAdded) {
    showAlert("Terminal yolu eklendi. Taramak için Terminalleri Tara düğmesine bas.", "success");
  } else {
    showAlert("Bu terminal yolu zaten listede.", "error");
  }
}

async function runMt5TerminalDiscovery(options = {}) {
  const { busyButton = null, successPrefix = null } = options;
  hideAlert();
  if (!isDiscoveryApiReady()) {
    showAlert(
      "Terminal tarama API'si hazır değil. Dashboard sunucusunu yeniden başlatıp sayfayı Ctrl+Shift+R ile yenile.",
      "error"
    );
    renderMt5ServerHint();
    return null;
  }
  if (!state.mt5TerminalPaths.length) {
    showAlert("Önce en az bir terminal yolu ekle.");
    return null;
  }
  setButtonBusy(busyButton, true);
  try {
    const payload = await api("/api/mt5-terminals/discover", {
      method: "POST",
      body: JSON.stringify({ paths_text: state.mt5TerminalPaths.join("\n") }),
    });
    state.mt5Discoveries = payload;
    renderMt5Discoveries();
    const count = (payload.discoveries || []).length;
    const prefix = successPrefix ? `${successPrefix} ` : "";
    showAlert(
      count > 0
        ? `${prefix}${count} hesap bulundu. Eklemek için satıra tıkla veya “Hesap Olarak Ekle” düğmesini kullan.`
        : "Tarama tamamlandı ancak açık terminal bulunamadı. MT5'yi açıp tekrar tara.",
      count > 0 ? "success" : "error"
    );
    return payload;
  } catch (error) {
    showAlert(error.message);
    renderMt5ServerHint();
    return null;
  } finally {
    setButtonBusy(busyButton, false);
  }
}

function handleQuickPathAdd(path) {
  notifyMt5PathAdded(addMt5TerminalPath(path));
}

async function handleQuickPathScan(path) {
  addMt5TerminalPath(path);
  await runMt5TerminalDiscovery({ successPrefix: "Terminal yolu eklendi ve tarama tamamlandı." });
}

function renderMt5QuickPaths() {
  const container = $("#mt5-quick-paths");
  if (!container) return;
  container.innerHTML = `
    <span class="muted mt5-quick-label">Hızlı ekle:</span>
    ${MT5_QUICK_PATHS.map(
      (item, index) => `
        <span class="mt5-quick-path-item">
          <button type="button" class="mt5-quick-path-btn" data-quick-index="${index}" title="${escapeCell(item.path)}">${escapeCell(item.label)}</button>
          <button type="button" class="mt5-quick-scan-btn" data-quick-scan-index="${index}" aria-label="${escapeCell(item.label)} ekle ve tara" title="Ekle ve tara">⌕</button>
        </span>`
    ).join("")}
  `;
  container.querySelectorAll("[data-quick-index]").forEach((button) => {
    let clickTimer = null;
    button.addEventListener("click", () => {
      const index = Number(button.getAttribute("data-quick-index"));
      const item = MT5_QUICK_PATHS[index];
      if (!item) return;
      if (clickTimer) {
        clearTimeout(clickTimer);
        clickTimer = null;
        handleQuickPathScan(item.path);
        return;
      }
      clickTimer = window.setTimeout(() => {
        clickTimer = null;
        handleQuickPathAdd(item.path);
      }, 260);
    });
  });
  container.querySelectorAll("[data-quick-scan-index]").forEach((button) => {
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      const index = Number(button.getAttribute("data-quick-scan-index"));
      const item = MT5_QUICK_PATHS[index];
      if (item) handleQuickPathScan(item.path);
    });
  });
}

function isDiscoveryApiReady() {
  return Boolean(state.dashboardHealth?.features?.mt5_terminal_discovery);
}

function renderMt5ServerHint() {
  const hint = $("#mt5-server-hint");
  if (!hint) return;
  if (!state.dashboardHealth) {
    hint.classList.add("hidden");
    return;
  }
  if (isDiscoveryApiReady()) {
    hint.classList.add("hidden");
    return;
  }
  hint.className = "mt5-server-hint warn";
  hint.innerHTML = `
    <strong>Terminal tarama henüz kullanılamıyor.</strong>
    Dashboard sunucusu eski sürümle çalışıyor olabilir.
    PowerShell'de sunucuyu durdur (Ctrl+C), sonra şunu çalıştır:
    <code>python integrations/telegram/dashboard_server.py</code>
    Ardından bu sayfayı Ctrl+Shift+R ile yenile.
  `;
}

function openAddAccountModal(discoveryId, defaultName) {
  state.pendingDiscoveryAddId = discoveryId;
  const input = $("#mt5-add-account-name-input");
  if (input) input.value = defaultName || "";
  openMt5Modal("mt5-add-account-modal");
  input?.focus();
}

function isDiscoveryAlreadyAdded(discovery) {
  if (discovery.can_add_as_target || isDiscoveryOffline(discovery)) {
    return false;
  }
  const reason = String(discovery.blocking_reason || "").toLowerCase();
  return (
    reason.includes("zaten")
    || reason.includes("başka aktif hedefte")
    || reason.includes("kombinasyonu")
  );
}

function canAddDiscoveryAsTarget(discovery) {
  return Boolean(
    discovery
    && discovery.can_add_as_target
    && !isDiscoveryOffline(discovery)
    && !isDiscoveryAlreadyAdded(discovery)
  );
}

async function submitDiscoveryAsTarget(discoveryId, displayName) {
  await api(`/api/mt5-terminals/discoveries/${discoveryId}/add-target`, {
    method: "POST",
    body: JSON.stringify({ display_name: displayName || undefined }),
  });
  await refreshAll();
}

function discoveryAddSuccessMessage(tradeType) {
  if (tradeType === "REAL") {
    return "Gerçek hesap yalnız izleme modunda eklendi. İşlem yetkisi kilitli.";
  }
  if (tradeType === "DEMO") {
    return "Demo hesap eklendi. EA ayarlarını daha sonra tamamlayabilirsin.";
  }
  return "Hesap eklendi. EA ayarlarını daha sonra Ayarlar'dan ekleyebilirsin.";
}

async function requestAddDiscoveryAccount(discoveryId) {
  const discovery = findMt5Discovery(discoveryId);
  if (!discovery || !canAddDiscoveryAsTarget(discovery)) {
    return;
  }
  const tradeType = String(discovery.detected_trade_mode || "UNKNOWN").toUpperCase();
  if (tradeType === "REAL") {
    state.pendingRealAccountDiscoveryId = discoveryId;
    openMt5Modal("mt5-real-account-modal");
    return;
  }
  try {
    await submitDiscoveryAsTarget(discoveryId, discovery.display_label || "");
    showAlert(discoveryAddSuccessMessage(tradeType), "success");
  } catch (error) {
    showAlert(error.message);
  }
}

async function confirmRealAccountAdd() {
  const discoveryId = state.pendingRealAccountDiscoveryId;
  const discovery = findMt5Discovery(discoveryId);
  if (!discoveryId || !discovery) return;
  try {
    await submitDiscoveryAsTarget(discoveryId, discovery.display_label || "");
    closeMt5Modal("mt5-real-account-modal");
    state.pendingRealAccountDiscoveryId = null;
    showAlert(discoveryAddSuccessMessage("REAL"), "success");
  } catch (error) {
    showAlert(error.message);
  }
}

async function confirmAddDiscoveryAccount() {
  const discoveryId = state.pendingDiscoveryAddId;
  const input = $("#mt5-add-account-name-input");
  const displayName = input?.value.trim();
  if (!discoveryId) return;
  try {
    await submitDiscoveryAsTarget(discoveryId, displayName || undefined);
    closeMt5Modal("mt5-add-account-modal");
    state.pendingDiscoveryAddId = null;
    const discovery = findMt5Discovery(discoveryId);
    const tradeType = String(discovery?.detected_trade_mode || "UNKNOWN").toUpperCase();
    showAlert(discoveryAddSuccessMessage(tradeType), "success");
  } catch (error) {
    showAlert(error.message);
  }
}

function openMt5Modal(modalId) {
  const modal = document.getElementById(modalId);
  if (modal) modal.classList.remove("hidden");
}

function closeMt5Modal(modalId) {
  const modal = document.getElementById(modalId);
  if (modal) modal.classList.add("hidden");
}

function setTargetModalTab(tabName) {
  document.querySelectorAll("[data-target-tab]").forEach((button) => {
    button.classList.toggle("active", button.getAttribute("data-target-tab") === tabName);
  });
  document.querySelectorAll("[data-target-panel]").forEach((panel) => {
    panel.classList.toggle("active", panel.getAttribute("data-target-panel") === tabName);
  });
}

function routeCountForTarget(targetId) {
  return (state.routes || []).filter((route) => Number(route.target_id) === Number(targetId)).length;
}

function eaDisplayName(target) {
  const pending = "_discovery_pending_seed.txt";
  if (!target.ea_name || target.seed_filename === pending) {
    return "Henüz Eşleştirilmedi";
  }
  return target.ea_name;
}

function magicDisplayStatus(target) {
  if (target.magic_number == null || target.magic_number === "") return "Henüz girilmedi";
  return String(target.magic_number);
}

function fileMatchStatus(target) {
  if (target.ea_config_match?.status === "OK") return "Tamam";
  return "Kontrol Gerekli";
}

function isDiscoveryOffline(discovery) {
  return (
    discovery.verification_status === "TERMINAL_OFFLINE"
    || discovery.terminal_status_label === "Terminal Çevrimdışı"
  );
}

function renderMt5PathChips() {
  const container = $("#mt5-path-chips");
  if (!container) return;
  if (!state.mt5TerminalPaths.length) {
    container.innerHTML = `<p class="muted mt5-path-empty">Terminal yolunu ekleyip açık hesaplarını otomatik bul.</p>`;
    return;
  }
  container.innerHTML = state.mt5TerminalPaths
    .map(
      (path, index) => `
        <span class="mt5-path-chip">
          <span class="mt5-path-chip-label">[ ${escapeCell(terminalChipLabel(path))} ]</span>
          <span class="mt5-path-chip-path" title="${escapeCell(path)}">${escapeCell(truncatePath(path))}</span>
          <button type="button" class="mt5-path-chip-remove" data-remove-path="${index}" aria-label="Yolu kaldır">×</button>
        </span>`
    )
    .join("");
  container.querySelectorAll("[data-remove-path]").forEach((button) => {
    button.addEventListener("click", () => {
      const index = Number(button.getAttribute("data-remove-path"));
      state.mt5TerminalPaths.splice(index, 1);
      syncMt5PathsTextarea();
      renderMt5PathChips();
    });
  });
}

function resolvedAccountType(item) {
  const detected = item.detected_trade_mode && item.last_verified_at_utc
    ? item.detected_trade_mode
    : item.expected_account_type || item.detected_trade_mode;
  return String(detected || "UNKNOWN").toUpperCase();
}

function targetStatusBucket(target) {
  const status = target.card_status || "";
  if (status.includes("Çevrimdışı")) return "OFFLINE";
  if (status.includes("Doğrulandı")) return "VERIFIED";
  return "ATTENTION";
}

function targetStatusDisplayLabel(target) {
  const status = target.card_status || "";
  if (status.includes("Devre Dışı")) return "Devre Dışı";
  if (status.includes("Çevrimdışı")) return "Terminal Çevrimdışı";
  if (status.includes("Doğrulandı")) return "Doğrulandı";
  if (status.includes("EA")) return "EA Eşleşmesi Bekliyor";
  if (resolvedAccountType(target) === "REAL") return "Gerçek Hesap Uyarısı";
  return "Kontrol Gerekli";
}

function terminalInstanceSubLabel(target) {
  const instanceStatus = target.terminal_instance_status || "";
  if (instanceStatus === "Doğrulandı" || instanceStatus === "Kullanıcı Tarafından Girildi") {
    return "Instance doğrulandı";
  }
  return "Kontrol gerekli";
}

function discoveryTerminalLabel(discovery) {
  const dataPath = discovery.detected_terminal_data_path || "";
  if (dataPath) {
    const parts = dataPath.replace(/\//g, "\\").split("\\").filter(Boolean);
    const hash = parts[parts.length - 1] || "";
    if (hash.length >= 3) return hash.slice(0, 3).toUpperCase();
  }
  return terminalChipLabel(discovery.terminal_exe_path || discovery.source_path || "Terminal");
}

function discoveryStatusLabel(discovery) {
  if (isDiscoveryAlreadyAdded(discovery)) return "Zaten Eklendi";
  if (isDiscoveryOffline(discovery)) return "Terminal Çevrimdışı";
  if (discovery.can_add_as_target) return "Eklenebilir";
  if (discovery.blocking_reason) return "Kontrol Gerekli";
  return discovery.verification_message_safe || "Kontrol Gerekli";
}

function sortMt5Targets(targets) {
  const typeRank = { REAL: 0, CONTEST: 1, DEMO: 2, UNKNOWN: 3 };
  const statusRank = (target) => {
    const bucket = targetStatusBucket(target);
    if (bucket === "VERIFIED") return 1;
    if (bucket === "ATTENTION") return 2;
    return 3;
  };
  return [...targets].sort((left, right) => {
    const leftType = typeRank[resolvedAccountType(left)] ?? 9;
    const rightType = typeRank[resolvedAccountType(right)] ?? 9;
    if (leftType !== rightType) return leftType - rightType;
    const leftStatus = statusRank(left);
    const rightStatus = statusRank(right);
    if (leftStatus !== rightStatus) return leftStatus - rightStatus;
    return String(left.display_name || left.name || "").localeCompare(
      String(right.display_name || right.name || ""),
      "tr"
    );
  });
}

function filterMt5Targets(targets) {
  const filters = state.mt5AccountFilters;
  const search = String(filters.search || "").trim().toLowerCase();
  return targets.filter((target) => {
    const type = resolvedAccountType(target);
    if (filters.type !== "ALL" && type !== filters.type) return false;
    const bucket = targetStatusBucket(target);
    if (filters.status !== "ALL" && bucket !== filters.status) return false;
    if (!search) return true;
    const haystack = [
      target.display_name,
      target.name,
      target.broker_label,
      target.detected_server,
      target.terminal_label,
      target.detected_account_login_masked,
      target.expected_account_login_masked,
      target.ea_name,
    ]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();
    return haystack.includes(search);
  });
}

function mt5CellStack(primary, secondary) {
  return `
    <div class="mt5-cell-stack">
      <strong>${primary}</strong>
      ${secondary ? `<span class="muted mt5-cell-sub">${secondary}</span>` : ""}
    </div>
  `;
}

function mt5RowMenu(targetId) {
  return `
    <button type="button" class="btn btn-small mt5-menu-trigger" data-menu-target="${targetId}" aria-label="İşlemler" aria-haspopup="menu">⋯</button>
  `;
}

function closeMt5RowMenu() {
  const portal = $("#mt5-row-menu-portal");
  if (portal) {
    portal.classList.add("hidden");
    portal.innerHTML = "";
  }
  state.mt5RowMenu = { open: false, targetId: null, trigger: null };
}

function positionMt5RowMenu(trigger) {
  const portal = $("#mt5-row-menu-portal");
  const panel = portal?.querySelector(".mt5-menu-panel");
  if (!portal || !panel || !trigger) return;

  const rect = trigger.getBoundingClientRect();
  const menuHeight = panel.offsetHeight || 168;
  const menuWidth = panel.offsetWidth || 184;
  const gap = 6;
  const padding = 8;
  const mobile = window.innerWidth <= 640;
  const row = trigger.closest(".mt5-account-row");
  const rowRect = row?.getBoundingClientRect();

  portal.style.width = "";
  if (mobile && rowRect) {
    portal.style.top = `${Math.min(rowRect.bottom + gap, window.innerHeight - padding)}px`;
    portal.style.left = `${Math.max(padding, rowRect.left)}px`;
    portal.style.width = `${Math.min(rowRect.width, window.innerWidth - padding * 2)}px`;
    panel.classList.toggle("opens-up", false);
    return;
  }

  let top = rect.bottom + gap;
  let openUp = false;
  if (top + menuHeight > window.innerHeight - padding) {
    top = rect.top - menuHeight - gap;
    openUp = true;
  }
  if (top < padding) {
    top = padding;
  }

  let left = rect.right - menuWidth;
  if (left < padding) left = padding;
  if (left + menuWidth > window.innerWidth - padding) {
    left = window.innerWidth - menuWidth - padding;
  }

  portal.style.top = `${top}px`;
  portal.style.left = `${left}px`;
  panel.classList.toggle("opens-up", openUp);
}

async function handleMt5RowMenuAction(action, targetId) {
  if (action === "details") {
    openMt5TargetDrawer(targetId);
    return;
  }
  if (action === "settings") {
    closeMt5TargetDrawer();
    openTargetSettingsModal(targetId, "general");
    return;
  }
  if (action === "verify") {
    try {
      await api(`/api/mt5-targets/${targetId}/verify`, { method: "POST", body: "{}" });
      await refreshAll();
      showAlert("Hesap doğrulaması güncellendi.", "success");
    } catch (error) {
      showAlert(error.message);
    }
    return;
  }
  if (action === "disable") {
    try {
      await api(`/api/mt5-targets/${targetId}/disable`, { method: "POST", body: "{}" });
      await refreshAll();
      showAlert("Hesap devre dışı bırakıldı.", "success");
    } catch (error) {
      showAlert(error.message);
    }
  }
}

function openMt5RowMenu(trigger, targetId) {
  if (state.mt5RowMenu.open && String(state.mt5RowMenu.targetId) === String(targetId)) {
    closeMt5RowMenu();
    return;
  }
  closeMt5RowMenu();
  const portal = $("#mt5-row-menu-portal");
  if (!portal || !trigger) return;

  portal.innerHTML = `
    <div class="mt5-menu-panel" role="menu">
      <button type="button" role="menuitem" data-menu-action="details">Ayrıntılar</button>
      <button type="button" role="menuitem" data-menu-action="verify">Doğrula</button>
      <button type="button" role="menuitem" data-menu-action="settings">Ayarlar</button>
      <button type="button" role="menuitem" data-menu-action="disable">Devre Dışı Bırak</button>
    </div>
  `;
  portal.classList.remove("hidden");
  state.mt5RowMenu = { open: true, targetId, trigger };

  portal.querySelectorAll("[data-menu-action]").forEach((button) => {
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      handleMt5RowMenuAction(button.getAttribute("data-menu-action"), targetId);
      closeMt5RowMenu();
    });
  });

  positionMt5RowMenu(trigger);
}

function renderMt5DiscoveryMessages(scanPayload) {
  const container = $("#mt5-discovery-path-errors");
  if (!container) return;
  const messages = [];
  for (const item of scanPayload.path_results || []) {
    if (item.status !== "OK") {
      messages.push(`${item.source_path}: ${item.message}`);
    }
  }
  for (const dup of scanPayload.duplicate_paths || []) {
    messages.push(`${dup}: Bu terminal yolu listede zaten var.`);
  }
  container.innerHTML = messages
    .map((message) => `<div class="mt5-warning">${escapeCell(message)}</div>`)
    .join("");
}

function renderMt5DiscoveryRow(discovery) {
  const tradeType = discovery.detected_trade_mode || "UNKNOWN";
  const offline = isDiscoveryOffline(discovery);
  const alreadyAdded = isDiscoveryAlreadyAdded(discovery);
  const canAdd = canAddDiscoveryAsTarget(discovery);
  const realClass = tradeType === "REAL" && !alreadyAdded ? " is-real-warning" : "";
  const xauClass = discovery.xauusd_available ? "badge-success" : "badge-muted";
  const statusClass = alreadyAdded
    ? "badge-muted"
    : offline
      ? "badge-muted"
      : canAdd
        ? "badge-success"
        : "badge-warn";
  const rowStateClass = alreadyAdded
    ? " is-already-added"
    : canAdd
      ? " is-addable"
      : offline
        ? " is-offline"
        : "";
  const realNote =
    tradeType === "REAL" && !alreadyAdded
      ? `<div class="mt5-row-note">Gerçek hesap algılandı. İşlem yetkisi kilitli kalacaktır.</div>`
      : "";
  return `
    <div class="mt5-table-row mt5-discovery-row${realClass}${rowStateClass}" data-discovery-id="${discovery.id}" role="row"${canAdd ? ' tabindex="0"' : ""}>
      <div class="col-account" role="cell">
        ${mt5CellStack(
          escapeCell(discovery.display_label || "MT5 Hesabı"),
          escapeCell(`${discovery.detected_server || "—"} · ${discovery.detected_account_login_masked || "—"}`)
        )}
      </div>
      <div class="col-type" role="cell"><span class="badge ${accountTypeBadgeClass(tradeType)}">${escapeCell(accountTypeLabel(tradeType))}</span></div>
      <div class="col-terminal" role="cell">
        ${mt5CellStack(
          escapeCell(discoveryTerminalLabel(discovery)),
          escapeCell(offline ? "Terminal kapalı" : discovery.terminal_status_label || "Terminal açık")
        )}
      </div>
      <div class="col-server" role="cell">${escapeCell(discovery.detected_server || "—")}</div>
      <div class="col-equity" role="cell">${discovery.detected_equity != null ? escapeCell(String(discovery.detected_equity)) : "—"}</div>
      <div class="col-xauusd" role="cell"><span class="badge ${xauClass}">${escapeCell(discovery.xauusd_status || "—")}</span></div>
      <div class="col-status" role="cell"><span class="badge ${statusClass}">${escapeCell(discoveryStatusLabel(discovery))}</span></div>
      <div class="col-actions" role="cell">
        <div class="mt5-row-actions">
          <button type="button" class="btn btn-small primary" data-add-discovery-target="${discovery.id}" ${canAdd ? "" : "disabled"}>${alreadyAdded ? "Zaten Eklendi" : "Hesap Olarak Ekle"}</button>
          <button type="button" class="btn btn-small" data-open-discovery-drawer="${discovery.id}">Ayrıntılar</button>
          <button type="button" class="btn btn-small subtle" data-refresh-discovery="${discovery.id}">Yeniden Tara</button>
        </div>
      </div>
      ${realNote}
    </div>
  `;
}

function renderMt5Discoveries() {
  renderMt5DiscoveryMessages(state.mt5Discoveries);
  renderMt5PathChips();
  const container = $("#mt5-discovery-results");
  if (!container) return;
  const discoveries = state.mt5Discoveries.discoveries || [];
  if (!discoveries.length) {
    container.innerHTML = `<p class="muted">Henüz terminal taraması yapılmadı. Terminal yolu ekleyip “Terminalleri Tara” düğmesine bas.</p>`;
    return;
  }
  container.innerHTML = `
    <div class="mt5-data-table mt5-discovery-table" role="table">
      <div class="mt5-table-head" role="row">
        <div role="columnheader">Hesap</div>
        <div role="columnheader">Tür</div>
        <div role="columnheader">Terminal</div>
        <div role="columnheader">Sunucu</div>
        <div role="columnheader">Equity</div>
        <div role="columnheader">XAUUSD</div>
        <div role="columnheader">Durum</div>
        <div role="columnheader">İşlem</div>
      </div>
      <div class="mt5-table-body" role="rowgroup">
        ${discoveries.map(renderMt5DiscoveryRow).join("")}
      </div>
    </div>
  `;
  bindMt5DiscoveryTableActions(container);
}

function bindMt5DiscoveryTableActions(container) {
  container.querySelectorAll("[data-add-discovery-target]").forEach((button) => {
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      requestAddDiscoveryAccount(button.getAttribute("data-add-discovery-target"));
    });
  });
  container.querySelectorAll("[data-refresh-discovery]").forEach((button) => {
    button.addEventListener("click", async (event) => {
      event.stopPropagation();
      const discoveryId = button.getAttribute("data-refresh-discovery");
      try {
        const payload = await api(`/api/mt5-terminals/discoveries/${discoveryId}/refresh`, {
          method: "POST",
          body: "{}",
        });
        const items = state.mt5Discoveries.discoveries || [];
        state.mt5Discoveries.discoveries = items.map((item) =>
          String(item.id) === String(discoveryId) ? payload.discovery : item
        );
        renderMt5Discoveries();
        showAlert("Tarama sonucu güncellendi.", "success");
      } catch (error) {
        showAlert(error.message);
      }
    });
  });
  container.querySelectorAll("[data-open-discovery-drawer]").forEach((button) => {
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      openMt5DiscoveryDrawer(button.getAttribute("data-open-discovery-drawer"));
    });
  });
  container.querySelectorAll(".mt5-discovery-row.is-addable").forEach((row) => {
    row.addEventListener("click", (event) => {
      if (event.target.closest("button")) return;
      requestAddDiscoveryAccount(row.getAttribute("data-discovery-id"));
    });
    row.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        requestAddDiscoveryAccount(row.getAttribute("data-discovery-id"));
      }
    });
  });
}

function renderMt5Summary() {
  const container = $("#mt5-target-summary");
  const extraContainer = $("#mt5-target-summary-extra");
  const extraWrap = $("#mt5-summary-extra");
  if (!container) return;
  const summary = state.mt5Targets.summary || {};
  const primary = [
    ["Toplam Hesap", summary.total || 0],
    ["Demo", summary.demo_accounts || 0],
    ["Gerçek", summary.real_accounts || 0],
    ["Doğrulanmayı Bekleyen", summary.pending_verification || 0],
    ["Sorunlu Eşleşme", summary.pending_ea_match || 0],
  ];
  const secondary = [
    ["Yarışma Hesabı", summary.contest_accounts || 0],
    ["Terminal Çevrimdışı", summary.terminal_offline || 0],
    ["Terminal Instance Çakışması", summary.terminal_instance_conflicts || 0],
  ];
  container.innerHTML = primary
    .map(
      ([label, value]) =>
        `<div class="mt5-summary-card"><span class="muted">${escapeCell(label)}</span><strong>${escapeCell(String(value))}</strong></div>`
    )
    .join("");
  if (extraContainer && extraWrap) {
    const hasExtra = secondary.some(([, value]) => Number(value) > 0);
    extraWrap.classList.toggle("hidden", !hasExtra);
    extraContainer.innerHTML = secondary
      .map(
        ([label, value]) =>
          `<div class="mt5-summary-card"><span class="muted">${escapeCell(label)}</span><strong>${escapeCell(String(value))}</strong></div>`
      )
      .join("");
  }
}

function targetStatusBadgeClass(target) {
  const status = target.card_status || "";
  if (status.includes("Doğrulandı")) return "badge-success";
  if (status.includes("Çevrimdışı")) return "badge-muted";
  return "badge-warn";
}

function renderMt5TargetRow(target) {
  const accountType = resolvedAccountType(target);
  const realClass = accountType === "REAL" ? " is-real-warning" : "";
  const disabledClass = target.is_enabled ? "" : " is-disabled";
  const statusLabel = targetStatusDisplayLabel(target);
  const statusClass = targetStatusBadgeClass(target);
  const xauClass = String(target.xauusd_status || "").includes("Haz") ? "badge-success" : "badge-muted";
  const eaName = eaDisplayName(target);
  const magicLine =
    target.magic_number != null && target.magic_number !== ""
      ? `Magic ${escapeCell(String(target.magic_number))}`
      : "Henüz eşleştirilmedi";
  const subtitle = `${escapeCell(target.broker_label || target.detected_server || "MT5")} · ${escapeCell(target.detected_account_login_masked || target.expected_account_login_masked || "—")}`;
  return `
    <div class="mt5-table-row mt5-account-row${realClass}${disabledClass}" data-target-id="${target.id}" role="row" tabindex="0">
      <div class="col-account" role="cell">
        ${mt5CellStack(escapeCell(target.display_name || target.name), subtitle)}
      </div>
      <div class="col-type" role="cell"><span class="badge ${accountTypeBadgeClass(accountType)}">${escapeCell(accountTypeLabel(accountType))}</span></div>
      <div class="col-terminal" role="cell">
        ${mt5CellStack(
          escapeCell(target.terminal_label || "—"),
          escapeCell(terminalInstanceSubLabel(target))
        )}
      </div>
      <div class="col-server" role="cell">${escapeCell(target.detected_server || target.broker_label || "—")}</div>
      <div class="col-xauusd" role="cell"><span class="badge ${xauClass}">${escapeCell(target.xauusd_status || "Kontrol Bekliyor")}</span></div>
      <div class="col-ea" role="cell">${mt5CellStack(escapeCell(eaName), magicLine)}</div>
      <div class="col-routes" role="cell">${escapeCell(String(routeCountForTarget(target.id)))}</div>
      <div class="col-status" role="cell"><span class="badge ${statusClass}">${escapeCell(statusLabel)}</span></div>
      <div class="col-permission" role="cell"><span class="badge badge-locked">Kilitli</span></div>
      <div class="col-actions" role="cell">
        <div class="mt5-row-actions">
          <button type="button" class="btn btn-small" data-open-target-drawer="${target.id}">Ayrıntılar</button>
          ${mt5RowMenu(target.id)}
        </div>
      </div>
    </div>
  `;
}

function renderMt5AccountsTable() {
  const container = $("#targets-list");
  if (!container) return;
  const allTargets = state.mt5Targets.targets || [];
  const targets = sortMt5Targets(filterMt5Targets(allTargets));
  if (!allTargets.length) {
    container.innerHTML = `<p class="muted">Henüz MT5 hesabı eklemedin. Terminal taraması yap veya alttaki “Manuel Hesap Ekle” bağlantısını kullan.</p>`;
    return;
  }
  if (!targets.length) {
    container.innerHTML = `<p class="muted">Filtreye uyan hesap bulunamadı. Arama veya filtreleri değiştir.</p>`;
    return;
  }
  container.innerHTML = `
    <div class="mt5-data-table mt5-accounts-table" role="table">
      <div class="mt5-table-head" role="row">
        <div role="columnheader">Hesap Adı</div>
        <div role="columnheader">Tür</div>
        <div role="columnheader">Terminal</div>
        <div role="columnheader">Sunucu</div>
        <div role="columnheader">XAUUSD</div>
        <div role="columnheader">EA</div>
        <div role="columnheader">Route</div>
        <div role="columnheader">Durum</div>
        <div role="columnheader">İşlem Yetkisi</div>
        <div role="columnheader">İşlem</div>
      </div>
      <div class="mt5-table-body" role="rowgroup">
        ${targets.map(renderMt5TargetRow).join("")}
      </div>
    </div>
  `;
  bindMt5AccountsTableActions(container);
}

function bindMt5AccountsTableActions(container) {
  container.querySelectorAll("[data-open-target-drawer]").forEach((button) => {
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      openMt5TargetDrawer(button.getAttribute("data-open-target-drawer"));
    });
  });
  container.querySelectorAll(".mt5-account-row").forEach((row) => {
    row.addEventListener("click", (event) => {
      if (event.target.closest("button")) return;
      openMt5TargetDrawer(row.getAttribute("data-target-id"));
    });
    row.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        openMt5TargetDrawer(row.getAttribute("data-target-id"));
      }
    });
  });
  container.querySelectorAll(".mt5-menu-trigger").forEach((button) => {
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      openMt5RowMenu(button, button.getAttribute("data-menu-target"));
    });
  });
}

function renderMt5DetailGrid(items) {
  return `
    <dl class="mt5-detail-grid">
      ${items
        .map(
          ([label, value]) =>
            `<div><dt>${escapeCell(label)}</dt><dd>${value}</dd></div>`
        )
        .join("")}
    </dl>
  `;
}

function renderMt5DrawerRoutes(targetId) {
  const routes = routesForTarget(targetId);
  if (!routes.length) {
    return `<p class="muted">Bu hesaba bağlı sinyal yönlendirmesi yok.</p>`;
  }
  return `
    <ul class="mt5-drawer-route-list">
      ${routes
        .map(
          (route) =>
            `<li><strong>${escapeCell(route.channel_title || "Kanal")}</strong><span class="muted">→ ${escapeCell(route.target_name || route.name || "Hedef")}</span></li>`
        )
        .join("")}
    </ul>
  `;
}

function setMt5DrawerTab(tabName) {
  state.mt5Drawer.tab = tabName;
  document.querySelectorAll("[data-drawer-tab]").forEach((button) => {
    button.classList.toggle("active", button.getAttribute("data-drawer-tab") === tabName);
  });
  document.querySelectorAll("[data-drawer-panel]").forEach((panel) => {
    panel.classList.toggle("active", panel.getAttribute("data-drawer-panel") === tabName);
  });
}

function findMt5Target(targetId) {
  return (state.mt5Targets.targets || []).find((item) => String(item.id) === String(targetId));
}

function findMt5Discovery(discoveryId) {
  return (state.mt5Discoveries.discoveries || []).find((item) => String(item.id) === String(discoveryId));
}

function routesForTarget(targetId) {
  return (state.routes || []).filter((route) => Number(route.target_id) === Number(targetId));
}

function openMt5TargetDrawer(targetId, tab = "overview") {
  if (!findMt5Target(targetId)) return;
  state.mt5Drawer = { open: true, mode: "target", targetId, discoveryId: null, tab };
  renderMt5TargetDrawer();
  const overlay = $("#mt5-target-drawer-overlay");
  overlay?.classList.remove("hidden");
  overlay?.setAttribute("aria-hidden", "false");
  document.body.classList.add("mt5-drawer-open");
  $("#mt5-target-drawer")?.focus();
}

function openMt5DiscoveryDrawer(discoveryId) {
  if (!findMt5Discovery(discoveryId)) return;
  state.mt5Drawer = { open: true, mode: "discovery", targetId: null, discoveryId, tab: "overview" };
  renderMt5TargetDrawer();
  const overlay = $("#mt5-target-drawer-overlay");
  overlay?.classList.remove("hidden");
  overlay?.setAttribute("aria-hidden", "false");
  document.body.classList.add("mt5-drawer-open");
  $("#mt5-target-drawer")?.focus();
}

function closeMt5TargetDrawer() {
  state.mt5Drawer.open = false;
  const overlay = $("#mt5-target-drawer-overlay");
  overlay?.classList.add("hidden");
  overlay?.setAttribute("aria-hidden", "true");
  document.body.classList.remove("mt5-drawer-open");
}

function renderMt5TargetDrawer() {
  const drawer = $("#mt5-target-drawer");
  if (!drawer || !state.mt5Drawer.open) return;

  if (state.mt5Drawer.mode === "discovery") {
    const discovery = findMt5Discovery(state.mt5Drawer.discoveryId);
    if (!discovery) {
      closeMt5TargetDrawer();
      return;
    }
    const tradeType = discovery.detected_trade_mode || "UNKNOWN";
    drawer.innerHTML = `
      <div class="mt5-drawer-header">
        <div>
          <h4 id="mt5-drawer-title">${escapeCell(discovery.display_label || "MT5 Hesabı")}</h4>
          <p class="muted">${escapeCell(`${discovery.detected_server || "—"} · ${discovery.detected_account_login_masked || "—"}`)}</p>
          <div class="mt5-drawer-badges">
            <span class="badge ${accountTypeBadgeClass(tradeType)}">${escapeCell(accountTypeLabel(tradeType))}</span>
            <span class="badge badge-locked">İşlem Yetkisi Kilitli</span>
          </div>
        </div>
        <button type="button" class="icon-btn" data-close-drawer aria-label="Kapat">×</button>
      </div>
      <div class="mt5-drawer-body">
        ${renderMt5DetailGrid([
          ["Terminal etiketi", escapeCell(discoveryTerminalLabel(discovery))],
          ["Terminal program yolu", escapeCell(discovery.terminal_exe_path || "—")],
          ["Terminal instance klasörü", escapeCell(discovery.detected_terminal_data_path || "—")],
          ["Hesap türü", escapeCell(accountTypeLabel(tradeType))],
          ["Sunucu", escapeCell(discovery.detected_server || "—")],
          ["Para birimi", escapeCell(discovery.detected_currency || "—")],
          ["Equity", discovery.detected_equity != null ? escapeCell(String(discovery.detected_equity)) : "—"],
          ["XAUUSD durumu", escapeCell(discovery.xauusd_status || "—")],
          ["Son doğrulama", escapeCell(formatLocalDateTime(discovery.last_verified_at_utc))],
          ["Durum", escapeCell(discoveryStatusLabel(discovery))],
          ["Instance anahtarı", escapeCell(discovery.terminal_instance_key || "—")],
          ["Doğrulama kodu", escapeCell(discovery.verification_status || "—")],
        ])}
        ${(discovery.warnings || []).map((warning) => `<div class="mt5-warning">${escapeCell(warning)}</div>`).join("")}
        ${discovery.blocking_reason ? `<div class="mt5-warning">${escapeCell(discovery.blocking_reason)}</div>` : ""}
      </div>
      <div class="mt5-drawer-footer">
        <button type="button" class="btn primary" data-add-discovery-target="${discovery.id}" ${canAddDiscoveryAsTarget(discovery) ? "" : "disabled"}>${isDiscoveryAlreadyAdded(discovery) ? "Zaten Eklendi" : "Hesap Olarak Ekle"}</button>
        <button type="button" class="btn" data-refresh-discovery="${discovery.id}">Yeniden Tara</button>
      </div>
    `;
    drawer.querySelector("[data-close-drawer]")?.addEventListener("click", closeMt5TargetDrawer);
    drawer.querySelector("[data-add-discovery-target]")?.addEventListener("click", () => {
      requestAddDiscoveryAccount(discovery.id);
    });
    drawer.querySelector("[data-refresh-discovery]")?.addEventListener("click", async () => {
      try {
        const payload = await api(`/api/mt5-terminals/discoveries/${discovery.id}/refresh`, {
          method: "POST",
          body: "{}",
        });
        const items = state.mt5Discoveries.discoveries || [];
        state.mt5Discoveries.discoveries = items.map((item) =>
          String(item.id) === String(discovery.id) ? payload.discovery : item
        );
        renderMt5Discoveries();
        renderMt5TargetDrawer();
        showAlert("Tarama sonucu güncellendi.", "success");
      } catch (error) {
        showAlert(error.message);
      }
    });
    return;
  }

  const target = findMt5Target(state.mt5Drawer.targetId);
  if (!target) {
    closeMt5TargetDrawer();
    return;
  }
  const accountType = resolvedAccountType(target);
  const subtitle = `${target.broker_label || target.detected_server || "MT5"} · ${target.detected_account_login_masked || target.expected_account_login_masked || "—"}`;
  const warnings = (target.warnings || [])
    .map((warning) => `<div class="mt5-warning">${escapeCell(warning)}</div>`)
    .join("");
  const conflictIssues = (target.ea_config_match?.issues || [])
    .map((issue) => `<div class="mt5-warning">${escapeCell(issue)}</div>`)
    .join("");
  drawer.innerHTML = `
    <div class="mt5-drawer-header">
      <div>
        <h4 id="mt5-drawer-title">${escapeCell(target.display_name || target.name)}</h4>
        <p class="muted">${escapeCell(subtitle)}</p>
        <div class="mt5-drawer-badges">
          <span class="badge ${accountTypeBadgeClass(accountType)}">${escapeCell(accountTypeLabel(accountType))}</span>
          <span class="badge badge-locked">İşlem Yetkisi Kilitli</span>
        </div>
      </div>
      <button type="button" class="icon-btn" data-close-drawer aria-label="Kapat">×</button>
    </div>
    <div class="mt5-drawer-tabs" role="tablist">
      <button type="button" class="mt5-tab ${state.mt5Drawer.tab === "overview" ? "active" : ""}" data-drawer-tab="overview" role="tab">Genel Bakış</button>
      <button type="button" class="mt5-tab ${state.mt5Drawer.tab === "ea" ? "active" : ""}" data-drawer-tab="ea" role="tab">EA Eşleştirmesi</button>
      <button type="button" class="mt5-tab ${state.mt5Drawer.tab === "routes" ? "active" : ""}" data-drawer-tab="routes" role="tab">Sinyal Yönlendirmeleri</button>
      <button type="button" class="mt5-tab ${state.mt5Drawer.tab === "technical" ? "active" : ""}" data-drawer-tab="technical" role="tab">Teknik Ayrıntılar</button>
    </div>
    <div class="mt5-drawer-body">
      <div class="mt5-drawer-panel ${state.mt5Drawer.tab === "overview" ? "active" : ""}" data-drawer-panel="overview">
        ${renderMt5DetailGrid([
          ["Terminal etiketi", escapeCell(target.terminal_label || "—")],
          ["Terminal program yolu", escapeCell(target.terminal_exe_path || "—")],
          ["Terminal instance klasörü", escapeCell(target.terminal_data_path || target.detected_terminal_data_path || "—")],
          ["Hesap türü", escapeCell(accountTypeLabel(accountType))],
          ["Sunucu", escapeCell(target.detected_server || target.broker_label || "—")],
          ["Para birimi", escapeCell(target.detected_currency || "—")],
          ["Equity", target.detected_equity != null ? escapeCell(String(target.detected_equity)) : "—"],
          ["XAUUSD durumu", escapeCell(target.xauusd_status || "—")],
          ["Son doğrulama", escapeCell(formatLocalDateTime(target.last_verified_at_utc))],
          ["Instance durumu", escapeCell(target.terminal_instance_status || "—")],
          ["Kart durumu", escapeCell(target.card_status || "—")],
        ])}
        ${warnings}
      </div>
      <div class="mt5-drawer-panel ${state.mt5Drawer.tab === "ea" ? "active" : ""}" data-drawer-panel="ea">
        ${renderMt5DetailGrid([
          ["EA adı", escapeCell(eaDisplayName(target))],
          ["Chart sembolü", escapeCell(target.chart_symbol || "—")],
          ["Zaman dilimi", escapeCell(target.chart_timeframe || "—")],
          ["Magic number", escapeCell(magicDisplayStatus(target))],
          ["Seed dosyası", escapeCell(target.seed_filename || "—")],
          ["Details dosyası", escapeCell(target.details_filename || "—")],
          ["Dosya eşleşmesi", escapeCell(fileMatchStatus(target))],
          ["EA doğrulama durumu", escapeCell(target.ea_live_verification?.status || "Henüz doğrulanmadı")],
        ])}
        ${conflictIssues}
      </div>
      <div class="mt5-drawer-panel ${state.mt5Drawer.tab === "routes" ? "active" : ""}" data-drawer-panel="routes">
        ${renderMt5DrawerRoutes(target.id)}
      </div>
      <div class="mt5-drawer-panel ${state.mt5Drawer.tab === "technical" ? "active" : ""}" data-drawer-panel="technical">
        ${renderMt5DetailGrid([
          ["Terminal data path", escapeCell(target.detected_terminal_data_path || target.terminal_data_path || "—")],
          ["Instance key", escapeCell(target.terminal_instance_key || "—")],
          ["Verification status", escapeCell(target.verification_status || "—")],
          ["Doğrulama mesajı", escapeCell(target.verification_message_safe || "—")],
          ["FILE_COMMON", escapeCell(target.file_common_root || "—")],
          ["Terminal bağlı", target.terminal_connected ? "Evet" : "Hayır"],
        ])}
        ${conflictIssues}
      </div>
    </div>
    <div class="mt5-drawer-footer">
      <button type="button" class="btn primary" data-drawer-verify="${target.id}">Doğrula</button>
      <button type="button" class="btn" data-drawer-edit="${target.id}">Ayarları Düzenle</button>
      <button type="button" class="btn danger" data-drawer-disable="${target.id}">Hedefi Devre Dışı Bırak</button>
    </div>
  `;
  drawer.querySelector("[data-close-drawer]")?.addEventListener("click", closeMt5TargetDrawer);
  drawer.querySelectorAll("[data-drawer-tab]").forEach((button) => {
    button.addEventListener("click", () => setMt5DrawerTab(button.getAttribute("data-drawer-tab")));
  });
  drawer.querySelector(`[data-drawer-verify="${target.id}"]`)?.addEventListener("click", async () => {
    try {
      await api(`/api/mt5-targets/${target.id}/verify`, { method: "POST", body: "{}" });
      await refreshAll();
      renderMt5TargetDrawer();
      showAlert("Hesap doğrulaması güncellendi.", "success");
    } catch (error) {
      showAlert(error.message);
    }
  });
  drawer.querySelector(`[data-drawer-edit="${target.id}"]`)?.addEventListener("click", () => {
    closeMt5TargetDrawer();
    openTargetSettingsModal(target.id, "ea");
  });
  drawer.querySelector(`[data-drawer-disable="${target.id}"]`)?.addEventListener("click", async () => {
    try {
      await api(`/api/mt5-targets/${target.id}/disable`, { method: "POST", body: "{}" });
      closeMt5TargetDrawer();
      await refreshAll();
      showAlert("Hesap devre dışı bırakıldı.", "success");
    } catch (error) {
      showAlert(error.message);
    }
  });
}

function renderTargets() {
  renderMt5ServerHint();
  renderMt5Summary();
  renderMt5QuickPaths();
  renderMt5Discoveries();
  renderMt5AccountsTable();
  if (state.mt5Drawer.open) {
    renderMt5TargetDrawer();
  }
}

function resetTargetFormDefaults() {
  const form = $("#target-form");
  if (!form) return;
  form.reset();
  delete form.dataset.editTargetId;
  delete form.dataset.createMode;
  form.querySelector('[name="seed_filename"]').value = "basket_recovery_fasttrack_seed.txt";
  form.querySelector('[name="details_filename"]').value = "basket_recovery_fasttrack_details.txt";
  form.querySelector('[name="ea_name"]').value = "Basket Recovery EA";
  form.querySelector('[name="chart_symbol"]').value = "XAUUSD";
  form.querySelector('[name="chart_timeframe"]').value = "M1";
  const saveBtn = $("#target-save-btn");
  if (saveBtn) saveBtn.textContent = "Kaydet";
  setTargetModalTab("general");
}

function openTargetSettingsModal(targetId, initialTab = "general") {
  const target = (state.mt5Targets.targets || []).find((item) => String(item.id) === String(targetId));
  const form = $("#target-form");
  if (!target || !form) return;
  form.querySelector('[name="display_name"]').value = target.display_name || target.name || "";
  form.querySelector('[name="name"]').value = target.display_name || target.name || "";
  form.querySelector('[name="terminal_label"]').value = target.terminal_label || "";
  form.querySelector('[name="terminal_exe_path"]').value = target.terminal_exe_path || "";
  form.querySelector('[name="terminal_data_path"]').value = target.terminal_data_path || "";
  form.querySelector('[name="broker_label"]').value = target.broker_label || "";
  form.querySelector('[name="expected_server"]').value = target.expected_server || "";
  form.querySelector('[name="expected_account_login"]').value = "";
  form.querySelector('[name="expected_account_type"]').value = target.expected_account_type || "UNKNOWN";
  form.querySelector('[name="file_common_root"]').value = target.file_common_root || "";
  form.querySelector('[name="seed_filename"]').value = target.seed_filename || "basket_recovery_fasttrack_seed.txt";
  form.querySelector('[name="details_filename"]').value = target.details_filename || "basket_recovery_fasttrack_details.txt";
  form.querySelector('[name="ea_name"]').value = target.ea_name || "Basket Recovery EA";
  form.querySelector('[name="chart_symbol"]').value = target.chart_symbol || "XAUUSD";
  form.querySelector('[name="chart_timeframe"]').value = target.chart_timeframe || "M1";
  form.querySelector('[name="magic_number"]').value = target.magic_number ?? "";
  form.dataset.editTargetId = targetId;
  delete form.dataset.createMode;
  const saveBtn = $("#target-save-btn");
  if (saveBtn) saveBtn.textContent = "Değişiklikleri Kaydet";
  $("#mt5-target-modal-title").textContent = "Hesap Ayarları";
  setTargetModalTab(initialTab);
  openMt5Modal("mt5-target-modal");
}

function openManualTargetModal() {
  resetTargetFormDefaults();
  const form = $("#target-form");
  if (form) form.dataset.createMode = "manual";
  $("#mt5-target-modal-title").textContent = "Manuel Hesap Ekle";
  const saveBtn = $("#target-save-btn");
  if (saveBtn) saveBtn.textContent = "Hesabı Kaydet";
  openMt5Modal("mt5-target-modal");
}

function formatLocalDateTime(isoUtc) {
  if (!isoUtc) return "—";
  const date = new Date(isoUtc);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString(undefined, {
    year: "numeric",
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function formatEntryRange(summary) {
  if (!summary) return "—";
  const low = summary.entry_low;
  const high = summary.entry_high;
  if (low != null && high != null) return `${low} – ${high}`;
  if (low != null || high != null) return String(low ?? high);
  return "Piyasa Fiyatından";
}

function formatTakeProfitsCompact(values) {
  if (!values || !values.length) return "Belirtilmedi";
  return values
    .map((item) => {
      const text = String(item).toUpperCase();
      return text === "OPEN" ? "Açık" : text;
    })
    .join(" · ");
}

function signalStatusLabel(status) {
  const labels = {
    WAITING: "Sinyal Bekleniyor",
    SEED_DETECTED: "Detay Bekleniyor",
    DETAILS_DETECTED: "Algılandı",
    PUBLISH_READY: "Simülasyon Başarılı",
    PUBLISH_SKIPPED: "Tekrar Sinyal, İşlenmedi",
    PUBLISH_FAILED: "Hedefe Ulaştırılamadı",
    LISTENER_STOPPED: "Takip Kapalı",
  };
  return labels[status] || "Sinyal Durumu";
}

function executionStatusLabel(status) {
  const labels = {
    NOT_EXECUTED: "İşlem Açılmadı",
    PENDING: "Sonuç Bekleniyor",
    OPEN: "Pozisyon Açık",
    CLOSED: "Pozisyon Kapalı",
  };
  return labels[status] || "—";
}

function tradeOutcomeLabel(outcome) {
  const labels = {
    NOT_APPLICABLE: "İşlem Açılmadı",
    PENDING: "Sonuç Bekleniyor",
    PROFIT: "Kâr",
    LOSS: "Zarar",
    BREAKEVEN: "Başabaş",
  };
  return labels[outcome] || "—";
}

function formatRealizedPnl(value, currency) {
  if (value == null || value === "") return "—";
  const suffix = currency ? ` ${currency}` : "";
  return `${value}${suffix}`;
}

function formatTakeProfits(values) {
  if (!values || !values.length) return "Belirtilmedi";
  return values
    .map((item) => {
      const text = String(item).toUpperCase();
      return text === "OPEN" ? "Açık" : text;
    })
    .join(" / ");
}

function signalHeadlineClass(status) {
  if (status === "PUBLISH_READY") return "is-success";
  if (status === "PUBLISH_SKIPPED") return "is-warn";
  if (status === "PUBLISH_FAILED") return "is-error";
  if (status === "LISTENER_STOPPED" || status === "WAITING") return "is-muted";
  return "";
}

function signalProgressRank(status) {
  const ranks = {
    WAITING: 0,
    SEED_DETECTED: 1,
    DETAILS_DETECTED: 2,
    PUBLISH_READY: 3,
    PUBLISH_SKIPPED: 3,
    PUBLISH_FAILED: 3,
    LISTENER_STOPPED: 0,
  };
  return ranks[status] ?? 0;
}

function buildSignalJourney(summary, listener) {
  const status = summary?.status || listener?.listener_status || "WAITING";
  const dryRun = summary?.is_dry_run !== false;
  const rank = signalProgressRank(status);
  const failed = status === "PUBLISH_FAILED";
  const steps = [
    { label: "Telegram'dan Alındı", minRank: 1 },
    { label: "Sinyal Tanındı", minRank: 1 },
    { label: "Kanal Eşleşti", minRank: 1 },
    { label: "MT5 Hesabı Seçildi", minRank: 2 },
    { label: "MT5 İçin Hazırlandı", minRank: 3 },
    { label: "İşlem Açma", minRank: 99, locked: true },
  ];
  return steps.map((step, index) => {
    if (step.locked) {
      return { ...step, state: "locked", icon: "🔒", note: "Kapalı" };
    }
    if (failed && index === 4) {
      return { ...step, state: "error", icon: "!", note: "Hata" };
    }
    if (rank >= step.minRank) {
      return { ...step, state: "complete", icon: "✓", note: "Tamam" };
    }
    if (rank + 1 === step.minRank || (rank === 0 && index === 0 && status === "WAITING")) {
      return { ...step, state: "waiting", icon: "…", note: "Bekliyor" };
    }
    return { ...step, state: "waiting", icon: "…", note: "Bekliyor" };
  });
}

function journeyStatusMessage(summary, listener) {
  const status = summary?.status || listener?.listener_status || "WAITING";
  const dryRun = summary?.is_dry_run !== false;
  if (status === "WAITING") return "Sinyal bekleniyor.";
  if (status === "SEED_DETECTED") return "İlk sinyal alındı, detay bekleniyor.";
  if (status === "DETAILS_DETECTED") return "Sinyal ayrıntıları alındı.";
  if (status === "PUBLISH_READY" && dryRun) {
    return "Simülasyon başarıyla tamamlandı. MT5'e dosya yazılmadı.";
  }
  if (status === "PUBLISH_SKIPPED") return "Bu sinyal daha önce işlendi. Tekrar gönderilmedi.";
  if (status === "PUBLISH_FAILED") return "Sinyal hazırlandı ancak hedefe ulaştırılamadı.";
  if (status === "LISTENER_STOPPED") return "Takip kapalı. Yeni sinyaller dinlenmiyor.";
  return summary?.user_message || listener?.last_signal_status || "—";
}

function renderSignalJourney(summary, listener) {
  const steps = buildSignalJourney(summary, listener);
  return `
    <div class="journey-steps">
      ${steps
        .map(
          (step) => `
        <div class="journey-step ${step.state}">
          <div class="journey-icon">${step.icon}</div>
          <div>
            <div>${escapeCell(step.label)}</div>
            <div class="muted">${escapeCell(step.note)}</div>
          </div>
        </div>`
        )
        .join("")}
    </div>
    <p class="muted">${escapeCell(journeyStatusMessage(summary, listener))}</p>
    <p class="muted">Bu yönlendirme yalnız sinyali izler ve doğrular. İşlem Açma: Kapalı${
      summary?.is_dry_run !== false ? " · MT5'e henüz dosya gönderilmez." : ""
    }</p>
  `;
}

function renderCompactJourney(summary, listener) {
  const steps = buildSignalJourney(summary, listener);
  const labels = [
    "Telegram",
    "Tanındı",
    "Kanal",
    "MT5 Hedef",
    "Simülasyon",
    "İşlem",
  ];
  return `
    <div class="journey-rail">
      ${steps
        .map(
          (step, index) => `
        <div class="journey-rail-item ${step.state}" title="${escapeCell(step.label)}">
          <div>${escapeCell(labels[index] || step.label)}</div>
          <div class="muted">${escapeCell(step.note)}</div>
        </div>`
        )
        .join("")}
    </div>
  `;
}

function renderSignalField(label, valueHtml, options = {}) {
  const spanClass = options.span2 ? " signal-field-span-2" : "";
  const valueClass = options.emphasis ? " signal-field-value is-emphasis" : " signal-field-value";
  return `
    <div class="${spanClass.trim() || "signal-card-cell"}">
      <div class="signal-field-label">${escapeCell(label)}</div>
      <div class="${valueClass.trim()}">${valueHtml}</div>
    </div>`;
}

function renderLastSignalCard(route) {
  const summary = route.last_signal_summary;
  const listener = route.listener || {};
  if (!summary) {
    return `<div class="empty-signal">Henüz bu yönlendirmede bir sinyal algılanmadı. Takibi başlatıp Telegram kanalından yeni bir sinyal bekleyin.</div>`;
  }
  const side = summary.side ? summary.side.toUpperCase() : null;
  const sideClass = side === "BUY" ? "buy" : side === "SELL" ? "sell" : "";
  const symbol = summary.symbol || "—";
  const signalHtml = side
    ? `<span class="side-badge ${sideClass}">${escapeCell(side)}</span> ${escapeCell(symbol)}`
    : escapeCell(symbol);
  return `
    <p class="signal-note">Bu sinyal Telegram'dan alındı ve doğrulandı. MT5'e henüz dosya gönderilmedi. İşlem açma kapalı olduğu için kâr/zarar henüz oluşmadı.</p>
    <div class="signal-card-grid">
      ${renderSignalField("Sinyal", signalHtml, { emphasis: true, span2: true })}
      ${renderSignalField("Kaynak Kanal", escapeCell(summary.channel_title || route.channel_title || "—"))}
      ${renderSignalField("Alınma Tarihi", escapeCell(formatLocalDateTime(summary.received_at_utc)))}
      ${renderSignalField("Hedef MT5", escapeCell(summary.target_name || route.target_name || "—"))}
      ${renderSignalField("Giriş Bölgesi", escapeCell(formatEntryRange(summary)))}
      ${renderSignalField("Stop Loss", escapeCell(summary.stop_loss != null ? String(summary.stop_loss) : "Belirtilmedi"))}
      ${renderSignalField("Kar Alma", escapeCell(formatTakeProfitsCompact(summary.take_profits)), { span2: true })}
      ${renderSignalField("Sinyal Durumu", escapeCell(signalStatusLabel(summary.status)))}
      ${renderSignalField("İşlem Sonucu", escapeCell(executionStatusLabel(summary.execution_status || "NOT_EXECUTED")))}
      ${renderSignalField("Gerçekleşen K/Z", escapeCell(formatRealizedPnl(summary.realized_pnl, summary.currency)), { span2: true })}
    </div>
    <div class="security-strip">
      <span class="badge badge-observer">Sadece İzle</span>
      <span class="badge badge-muted">${summary.is_dry_run !== false ? "MT5'e dosya yazılmadı" : "Canlı dosya modu"}</span>
      <span class="badge badge-muted">İşlem açılmadı</span>
    </div>
  `;
}

function renderTechnicalTimeline(timeline) {
  if (!timeline || !timeline.length) {
    return `<p class="muted">Henüz teknik kayıt yok.</p>`;
  }
  return `
    <div class="tech-timeline">
      ${timeline
        .map(
          (event) => `
        <div class="tech-event">
          <div><strong>${escapeCell(event.event_type)}</strong> · ${escapeCell(event.status)}</div>
          <div class="muted">${escapeCell(formatLocalDateTime(event.created_at_utc))}</div>
          <div class="muted">
            ${event.fingerprint_short ? `Fingerprint: ${escapeCell(event.fingerprint_short)} · ` : ""}
            ${event.seed_bytes != null ? `Seed bytes: ${escapeCell(String(event.seed_bytes))} · ` : ""}
            ${event.details_bytes != null ? `Details bytes: ${escapeCell(String(event.details_bytes))}` : ""}
          </div>
        </div>`
        )
        .join("")}
    </div>
  `;
}

function listenerStatusLabel(status) {
  const labels = {
    WAITING: "Sinyal bekleniyor.",
    SEED_DETECTED: "Tohum sinyal algılandı.",
    DETAILS_DETECTED: "Detay sinyal algılandı.",
    PUBLISH_READY: "Yayına hazır (yalnız izleme).",
    PUBLISH_SKIPPED: "Yayın atlandı.",
    PUBLISH_FAILED: "Yayın başarısız.",
    LISTENER_STOPPED: "Dinleme durduruldu.",
  };
  return labels[status] || status || "—";
}

function formatListenerError(code) {
  if (!code) return "—";
  const labels = {
    LISTENER_TELEGRAM_NOT_CONNECTED: "Telegram bağlantısı gerekli.",
    LISTENER_CHANNEL_TRACKING_OFF: "Kanal takibi kapalı.",
    LISTENER_ROUTE_DISABLED: "Yönlendirme aktif değil.",
    LISTENER_TARGET_DISABLED: "MT5 hedefi aktif değil.",
    LISTENER_TARGET_NOT_OBSERVER: "MT5 hedefi yalnız izleme modunda değil.",
    LISTENER_ROUTE_MODE_INVALID: "Bu yönlendirme yalnız izleme modunda olmalı.",
    PUBLISH_FAILED: "Yayın başarısız oldu.",
  };
  return labels[code] || code;
}

async function startRouteListener(routeId) {
  await api(`/api/routes/${routeId}/listener/start`, { method: "POST", body: JSON.stringify({}) });
  showAlert("Kanal dinlenmeye hazır. Bu yönlendirme işlem açmaz.", "success");
  await refreshAll();
}

async function stopRouteListener(routeId) {
  await api(`/api/routes/${routeId}/listener/stop`, { method: "POST", body: JSON.stringify({}) });
  showAlert("Dinleme durduruldu.", "success");
  await refreshAll();
}

let pendingCandidateTestRouteId = null;

function isCandidateTestArmEligible(route) {
  const ct = route.candidate_test || {};
  return Boolean(ct.arm_eligible);
}

function candidateTestStatusLabel(status) {
  const labels = {
    OBSERVER_ONLY: "Yalnız İzleme",
    CANDIDATE_TEST_ARMED: "Candidate Test Hazır",
    CANDIDATE_TEST_CONSUMED: "Candidate Test Tüketildi",
    CANDIDATE_TEST_EXPIRED: "Candidate Test Süresi Doldu",
    CANDIDATE_TEST_BLOCKED: "Candidate Test Engellendi",
  };
  return labels[status] || status || "Yalnız İzleme";
}

function formatCandidateTestRemaining(expiresAtUtc) {
  if (!expiresAtUtc) return "—";
  const expiresMs = Date.parse(String(expiresAtUtc).replace("Z", "+00:00"));
  if (Number.isNaN(expiresMs)) return "—";
  const remainingSec = Math.max(0, Math.floor((expiresMs - Date.now()) / 1000));
  const minutes = Math.floor(remainingSec / 60);
  const seconds = remainingSec % 60;
  return `${minutes} dk ${seconds} sn`;
}

function buildCandidateTestArmSummaryHtml() {
  return `
    <ul class="candidate-test-summary">
      <li><strong>Hedef:</strong> Vantage Demo Altın / D0E</li>
      <li><strong>Kaynak:</strong> JustGold / JustGoldDan</li>
      <li><strong>Hesap türü:</strong> DEMO</li>
      <li><strong>Sembol:</strong> XAUUSD</li>
      <li><strong>Lot limiti:</strong> 0.01</li>
      <li><strong>Magic:</strong> 91001</li>
      <li><strong>İşlem yetkisi:</strong> Kilitli kalacak</li>
      <li><strong>Dosya yayını:</strong> Armed iken 1 gerçek FILE_COMMON yazımı</li>
      <li><strong>Broker emri:</strong> Bu adımda açılmayacak</li>
      <li><strong>Test süresi:</strong> 15 dakika</li>
      <li><strong>İzin:</strong> Tek seed/details çifti (tek mesaj da yeterli)</li>
    </ul>
    <p class="muted">Tek bir “Gold sell now … / SL:” mesajı yeter. Broker emri için EA FastTrack + authorization gerekir.</p>`;
}

function openCandidateTestArmModal(routeId) {
  pendingCandidateTestRouteId = routeId;
  const summary = $("#candidate-test-arm-summary");
  if (summary) {
    summary.innerHTML = buildCandidateTestArmSummaryHtml();
  }
  openMt5Modal("candidate-test-arm-modal");
}

async function confirmCandidateTestArm() {
  if (!pendingCandidateTestRouteId) return;
  const routeId = pendingCandidateTestRouteId;
  try {
    await api(`/api/routes/${routeId}/candidate-test/arm`, { method: "POST", body: JSON.stringify({}) });
    closeMt5Modal("candidate-test-arm-modal");
    pendingCandidateTestRouteId = null;
    showAlert("Candidate test hazırlığı aktif. Publish hakkı: 1", "success");
    await refreshAll();
  } catch (error) {
    showAlert(error.message);
  }
}

async function disarmCandidateTestRoute(routeId) {
  try {
    await api(`/api/routes/${routeId}/candidate-test/disarm`, { method: "POST", body: JSON.stringify({}) });
    showAlert("Candidate test hazırlığı iptal edildi.", "success");
    await refreshAll();
  } catch (error) {
    showAlert(error.message);
  }
}

function renderCandidateTestControls(route) {
  const ct = route.candidate_test || {};
  const status = ct.status || "OBSERVER_ONLY";
  if (status === "CANDIDATE_TEST_ARMED") {
    const remaining = formatCandidateTestRemaining(ct.expires_at_utc);
    return `
      <div class="candidate-test-panel">
        <p><strong>Candidate test:</strong> ${escapeCell(candidateTestStatusLabel(status))}</p>
        <p class="muted">Kalan süre: ${escapeCell(remaining)} · Publish hakkı: ${escapeCell(String(ct.publish_remaining ?? 0))}</p>
        <p class="muted">Tek bir Gold buy/sell now + SL mesajı yeter. Broker emri için EA FastTrack + authorization gerekir.</p>
        <button type="button" class="btn btn-small btn-muted" data-disarm-candidate-test="${route.id}">Test Hazırlığını İptal Et</button>
      </div>`;
  }
  if (isCandidateTestArmEligible(route)) {
    return `
      <div class="candidate-test-panel">
        <button type="button" class="btn btn-small" data-arm-candidate-test="${route.id}">Tek Candidate Testini Hazırla</button>
      </div>`;
  }
  if (status !== "OBSERVER_ONLY") {
    return `
      <div class="candidate-test-panel">
        <p class="muted"><strong>Candidate test:</strong> ${escapeCell(candidateTestStatusLabel(status))}</p>
      </div>`;
  }
  return "";
}

function renderRoutes() {
  renderRoutesWorkerHint();
  const channelSelect = $("#route-channel-select");
  const targetSelect = $("#route-target-select");
  const tracked = state.channels.filter((c) => c.is_tracking);
  channelSelect.innerHTML = tracked.length
    ? tracked.map((c) => `<option value="${c.id}">${escapeCell(c.title)}</option>`).join("")
    : `<option value="">Takip edilen kanal yok</option>`;
  targetSelect.innerHTML = state.targets.length
    ? state.targets.map((t) => `<option value="${t.id}">${escapeCell(t.name)}</option>`).join("")
    : `<option value="">MT5 hesabı yok</option>`;

  const emptyHint = $("#routes-empty-hint");
  if (emptyHint) {
    emptyHint.classList.toggle("hidden", tracked.length > 0 && state.targets.length > 0);
  }

  const container = $("#routes-list");
  if (!state.routes.length) {
    container.innerHTML = `<p class="muted">Önce takip edilen bir kanal ve en az bir MT5 hesabı eklemelisin.</p>`;
    return;
  }

  container.innerHTML = state.routes
    .map((route) => {
      const listener = route.listener || {};
      const running = Boolean(listener.running);
      const connections = routeConnectionLabels(listener);
      const startDisabled = running ? "disabled" : "";
      const stopDisabled = running ? "" : "disabled";
      return `
      <article class="route-card" data-route-id="${route.id}">
        <div class="route-card-header">
          <div>
            <h4 class="route-card-title">${escapeCell(route.name)}</h4>
            <p class="route-card-route-line">${escapeCell(route.channel_title)} → ${escapeCell(route.target_name)}</p>
          </div>
          <span class="badge ${route.is_enabled ? "badge-success" : "badge-muted"}">${route.is_enabled ? "Route: Aktif" : "Route: Kapalı"}</span>
        </div>
        <div class="route-status-grid">
          <div><strong>Route</strong><span>${escapeCell(connections.routeLabel)}</span></div>
          <div><strong>Dinleme Servisi</strong><span>${escapeCell(connections.workerLabel)}</span></div>
          <div><strong>Telegram</strong><span>${escapeCell(connections.telegramLabel)}</span></div>
          <div><strong>İşlem Açma</strong><span>Kapalı</span></div>
        </div>
        <div class="route-card-badges">
          <span class="badge badge-observer">Sadece İzle</span>
          <span class="badge badge-muted">İşlem Açma Kapalı</span>
          <span class="badge ${signalHeadlineClass(route.last_signal_summary?.status || listener.listener_status || "WAITING") === "is-success" ? "badge-success" : "badge-muted"}">${escapeCell(route.last_signal_summary?.headline || signalStatusLabel(listener.listener_status || "WAITING"))}</span>
        </div>

        <h5 class="signal-section-title">Son Algılanan Sinyal</h5>
        ${renderLastSignalCard(route)}

        <h5 class="signal-section-title journey-section-title">Sinyal Yolculuğu</h5>
        ${renderCompactJourney(route.last_signal_summary, listener)}
        <p class="muted">${escapeCell(journeyStatusMessage(route.last_signal_summary, listener))}</p>
        <p class="muted">Gerçekleşen K/Z, yalnız işlem sonucu geldiğinde gösterilir.</p>

        <details class="tech-details">
          <summary>Teknik Ayrıntılar</summary>
          ${renderTechnicalTimeline(route.signal_timeline)}
        </details>

        ${renderCandidateTestControls(route)}

        <div class="route-card-actions">
          <button type="button" class="btn btn-small" data-start-listener="${route.id}" ${startDisabled}>Takibi Başlat</button>
          <button type="button" class="btn btn-small btn-muted" data-stop-listener="${route.id}" ${stopDisabled}>Takibi Durdur</button>
          <button type="button" class="btn btn-small" data-delete-route="${route.id}">Sil</button>
        </div>
      </article>`;
    })
    .join("");
  container.querySelectorAll("[data-start-listener]").forEach((button) => {
    button.addEventListener("click", async () => {
      const routeId = button.getAttribute("data-start-listener");
      try {
        await startRouteListener(routeId);
      } catch (error) {
        showAlert(error.message);
      }
    });
  });
  container.querySelectorAll("[data-stop-listener]").forEach((button) => {
    button.addEventListener("click", async () => {
      const routeId = button.getAttribute("data-stop-listener");
      try {
        await stopRouteListener(routeId);
      } catch (error) {
        showAlert(error.message);
      }
    });
  });
  container.querySelectorAll("[data-delete-route]").forEach((button) => {
    button.addEventListener("click", async () => {
      const routeId = button.getAttribute("data-delete-route");
      try {
        await api(`/api/routes/${routeId}`, { method: "DELETE" });
        await refreshAll();
        showAlert("Yönlendirme silindi.", "success");
      } catch (error) {
        showAlert(error.message);
      }
    });
  });
  container.querySelectorAll("[data-arm-candidate-test]").forEach((button) => {
    button.addEventListener("click", () => {
      openCandidateTestArmModal(button.getAttribute("data-arm-candidate-test"));
    });
  });
  container.querySelectorAll("[data-disarm-candidate-test]").forEach((button) => {
    button.addEventListener("click", async () => {
      try {
        await disarmCandidateTestRoute(button.getAttribute("data-disarm-candidate-test"));
      } catch (error) {
        showAlert(error.message);
      }
    });
  });
}

function buildSignalHistoryQuery(filters) {
  const params = new URLSearchParams();
  Object.entries(filters).forEach(([key, value]) => {
    if (value != null && String(value).trim() !== "") {
      params.set(key, String(value));
    }
  });
  return params.toString();
}

function loadSignalHistoryViewPreference() {
  try {
    const saved = localStorage.getItem(SIGNAL_HISTORY_VIEW_KEY);
    if (saved === "cards" || saved === "list") {
      state.signalHistoryView = saved;
    }
  } catch (_error) {
    state.signalHistoryView = "cards";
  }
}

function setSignalHistoryView(mode) {
  if (mode !== "cards" && mode !== "list") {
    return;
  }
  state.signalHistoryView = mode;
  try {
    localStorage.setItem(SIGNAL_HISTORY_VIEW_KEY, mode);
  } catch (_error) {
    /* localStorage unavailable */
  }
  applySignalHistoryViewVisibility();
  renderSignalHistory();
}

function applySignalHistoryViewVisibility() {
  const mode = state.signalHistoryView;
  const cardsPanel = $("#signal-history-cards-panel");
  const listPanel = $("#signal-history-list-panel");
  if (cardsPanel) {
    cardsPanel.classList.toggle("hidden", mode !== "cards");
  }
  if (listPanel) {
    listPanel.classList.toggle("hidden", mode !== "list");
  }
  document.querySelectorAll("[data-history-view]").forEach((button) => {
    button.classList.toggle("active", button.getAttribute("data-history-view") === mode);
  });
}

function populateHistoryFilterSelects() {
  const channelSelect = $("#history-channel");
  const targetSelect = $("#history-target");
  if (!channelSelect || !targetSelect) return;
  channelSelect.innerHTML =
    `<option value="">Tüm kanallar</option>` +
    state.channels.map((c) => `<option value="${c.id}">${escapeCell(c.title)}</option>`).join("");
  targetSelect.innerHTML =
    `<option value="">Tüm hesaplar</option>` +
    state.targets.map((t) => `<option value="${t.id}">${escapeCell(t.name)}</option>`).join("");
}

async function loadSignalHistory(page = 1) {
  const filters = {
    page,
    page_size: state.signalHistoryFilters.page_size || 20,
    from: $("#history-from")?.value || "",
    to: $("#history-to")?.value || "",
    channel_id: $("#history-channel")?.value || "",
    target_id: $("#history-target")?.value || "",
    symbol: $("#history-symbol")?.value.trim() || "",
    side: $("#history-side")?.value || "",
    signal_status: $("#history-signal-status")?.value || "",
    outcome: $("#history-outcome")?.value || "",
    pnl_state: $("#history-pnl-state")?.value || "",
  };
  state.signalHistoryFilters = filters;
  const query = buildSignalHistoryQuery(filters);
  const payload = await api(`/api/signal-history?${query}`);
  state.signalHistory = payload;
  renderSignalHistory();
}

function renderHistoryCard(item) {
  const side = item.side ? item.side.toUpperCase() : null;
  const sideClass = side === "BUY" ? "buy" : side === "SELL" ? "sell" : "";
  const signalHtml = side
    ? `<span class="side-badge ${sideClass}">${escapeCell(side)}</span> ${escapeCell(item.symbol || "—")}`
    : escapeCell(item.symbol || "—");
  return `
    <article class="history-card" data-history-id="${item.id}">
      <div class="history-card-header">
        <div>
          <strong>${signalHtml}</strong>
          <div class="muted">${escapeCell(item.channel_name || "—")} · ${escapeCell(formatLocalDateTime(item.received_at_utc))}</div>
        </div>
        <span class="badge badge-observer">${escapeCell(signalStatusLabel(item.signal_status))}</span>
      </div>
      <div class="history-card-meta">
        <span class="badge badge-muted">${escapeCell(item.target_name || "—")}</span>
        <span class="badge badge-muted">${escapeCell(formatEntryRange(item))}</span>
        <span class="badge badge-muted">SL: ${escapeCell(item.stop_loss != null ? String(item.stop_loss) : "—")}</span>
      </div>
      <div class="signal-card-grid">
        ${renderSignalField("Kar Alma", escapeCell(formatTakeProfitsCompact(item.take_profits)), { span2: true })}
        ${renderSignalField("İşlem Sonucu", escapeCell(tradeOutcomeLabel(item.trade_outcome)))}
        ${renderSignalField("Gerçekleşen K/Z", escapeCell(formatRealizedPnl(item.realized_pnl, item.currency)))}
      </div>
      <details class="tech-details">
        <summary>Detayları Gör</summary>
        <div class="tech-event">
          <div class="muted">Kanal: ${escapeCell(item.channel_name || "—")}</div>
          <div class="muted">Hedef: ${escapeCell(item.target_name || "—")}</div>
          <div class="muted">Durum: ${escapeCell(signalStatusLabel(item.signal_status))}</div>
          <div class="muted">İşlem: ${escapeCell(executionStatusLabel(item.execution_status))}</div>
          ${item.fingerprint_short ? `<div class="muted">Fingerprint: ${escapeCell(item.fingerprint_short)}</div>` : ""}
        </div>
      </details>
    </article>
  `;
}

function renderSignalHistoryPagination() {
  const container = $("#signal-history-pagination");
  if (!container) return;
  const { page = 1, page_size = 20, total = 0 } = state.signalHistory;
  const totalPages = Math.max(Math.ceil(total / page_size), 1);
  container.innerHTML = `
    <span class="muted">${total} kayıt · Sayfa ${page}/${totalPages}</span>
    <div class="actions">
      <button type="button" class="btn btn-small" id="history-prev" ${page <= 1 ? "disabled" : ""}>Önceki</button>
      <button type="button" class="btn btn-small" id="history-next" ${page >= totalPages ? "disabled" : ""}>Sonraki</button>
    </div>
  `;
  $("#history-prev")?.addEventListener("click", () => loadSignalHistory(page - 1));
  $("#history-next")?.addEventListener("click", () => loadSignalHistory(page + 1));
}

function renderHistoryTableRow(item) {
  const side = item.side ? item.side.toUpperCase() : "—";
  return `
    <tr>
      <td>${escapeCell(formatLocalDateTime(item.received_at_utc))}</td>
      <td>${escapeCell(item.channel_name || "—")}</td>
      <td>${escapeCell(item.symbol || "—")} ${side !== "—" ? `<span class="side-badge ${side === "BUY" ? "buy" : "sell"}">${escapeCell(side)}</span>` : ""}</td>
      <td>${escapeCell(formatEntryRange(item))}</td>
      <td>${escapeCell(item.stop_loss != null ? String(item.stop_loss) : "—")}</td>
      <td>${escapeCell(formatTakeProfitsCompact(item.take_profits))}</td>
      <td>${escapeCell(item.target_name || "—")}</td>
      <td>${escapeCell(signalStatusLabel(item.signal_status))}</td>
      <td>${escapeCell(tradeOutcomeLabel(item.trade_outcome))}</td>
      <td>${escapeCell(formatRealizedPnl(item.realized_pnl, item.currency))}</td>
    </tr>
  `;
}

function renderSignalHistoryTable(items) {
  const container = $("#signal-history-table");
  if (!container) return;
  if (!items.length) {
    container.innerHTML = `<p class="muted">Liste görünümünde kayıt yok.</p>`;
    return;
  }
  container.innerHTML = `
    <table class="history-table">
      <thead>
        <tr>
          <th>Tarih</th>
          <th>Kanal</th>
          <th>Sembol / Yön</th>
          <th>Giriş</th>
          <th>SL</th>
          <th>TP</th>
          <th>MT5 Hedef</th>
          <th>Sinyal Durumu</th>
          <th>İşlem Sonucu</th>
          <th>K/Z</th>
        </tr>
      </thead>
      <tbody>
        ${items.map(renderHistoryTableRow).join("")}
      </tbody>
    </table>
  `;
}

function renderSignalHistory() {
  const cardsContainer = $("#signal-history-list");
  const tableContainer = $("#signal-history-table");
  if (!cardsContainer || !tableContainer) return;
  applySignalHistoryViewVisibility();
  const items = state.signalHistory.items || [];
  const emptyMessage = `<p class="muted">Henüz filtreye uygun sinyal bulunamadı.</p>`;
  if (!items.length) {
    cardsContainer.innerHTML = emptyMessage;
    tableContainer.innerHTML = emptyMessage;
    renderSignalHistoryPagination();
    return;
  }
  if (state.signalHistoryView === "cards") {
    cardsContainer.innerHTML = items.map(renderHistoryCard).join("");
    tableContainer.innerHTML = "";
  } else {
    tableContainer.innerHTML = "";
    renderSignalHistoryTable(items);
    cardsContainer.innerHTML = "";
  }
  renderSignalHistoryPagination();
}

function renderAudit() {
  const severity = $("#audit-severity").value;
  const container = $("#audit-list");
  const events = state.audit.filter((event) => !severity || event.severity === severity);
  container.innerHTML = "";
  if (!events.length) {
    container.innerHTML = `<p class="muted">Henüz kayıt yok.</p>`;
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
  const safety = state.overview ? state.overview.safety : {};
  const rows = [
    ["Telegram girişi", "Yalnız bu bilgisayarda"],
    ["Kanal senkronu", "İstek üzerine"],
    ["MT5'e sinyal gönderme", "Henüz kapalı"],
    ["EA kontrolü", "Henüz kapalı"],
    ["Broker emri", "Kapalı"],
    ["Token üretimi", "Kapalı"],
  ];
  const container = $("#safety-matrix");
  container.innerHTML = rows
    .map(
      ([label, value]) =>
        `<div class="matrix-row"><div>${escapeCell(label)}</div><div>${escapeCell(value)}</div></div>`
    )
    .join("");
}

async function apiOptional(path, options = {}, fallback = null) {
  try {
    return await api(path, options);
  } catch (_error) {
    return fallback;
  }
}

function isBackendFeatureReady(health) {
  return Boolean(
    health?.features?.listener_worker
    && health?.features?.mt5_targets
    && health?.features?.mt5_terminal_discovery
  );
}

async function refreshAll() {
  setLoading(true);
  hideAlert();
  try {
    const health = await apiOptional("/api/health", {}, null);
    state.dashboardHealth = health;
    const [
      overview,
      telegramStatus,
      credentialsStatus,
      listenerStatus,
      channelsPayload,
      targetsPayload,
      mt5TargetsPayload,
      mt5DiscoveriesPayload,
      routesPayload,
      auditPayload,
    ] = await Promise.all([
      api("/api/overview"),
      api("/api/telegram/status"),
      api("/api/telegram/credentials/status"),
      apiOptional("/api/listener/status", {}, { worker: null, active_route_count: 0 }),
      api("/api/channels"),
      api("/api/targets"),
      apiOptional("/api/mt5-targets", {}, { targets: [], summary: {} }),
      apiOptional("/api/mt5-terminals/discoveries", {}, { discoveries: [], path_results: [], duplicate_paths: [] }),
      api("/api/routes"),
      apiOptional("/api/audit?limit=100", {}, { events: [] }),
    ]);
    state.overview = overview;
    state.credentialsStatus = credentialsStatus;
    state.listenerWorker = listenerStatus?.worker || null;
    state.channels = channelsPayload.channels;
    state.targets = targetsPayload.targets;
    state.mt5Targets = mt5TargetsPayload;
    state.mt5Discoveries = mt5DiscoveriesPayload;
    state.routes = routesPayload.routes;
    state.audit = auditPayload.events;
    const mergedStatus = mergeTelegramStatus(telegramStatus, credentialsStatus);
    renderOverview();
    renderTelegramStatus(mergedStatus);
    renderChannels();
    renderTargets();
    renderRoutes();
    populateHistoryFilterSelects();
    if (document.querySelector("#view-signal-history.active")) {
      await loadSignalHistory(state.signalHistory.page || 1);
    }
    renderAudit();
    renderSafetyMatrix();
    if (health && !isBackendFeatureReady(health)) {
      const missingDiscovery = !health.features?.mt5_terminal_discovery;
      showAlert(
        missingDiscovery
          ? "Dashboard sunucusu güncel değil — terminal tarama çalışmayabilir. Sunucuyu yeniden başlatıp sayfayı Ctrl+Shift+R ile yenile."
          : "Dashboard sunucusu güncel değil (eski sürüm çalışıyor). Terminalde sunucuyu durdurup yeniden başlatın, ardından sayfayı Ctrl+Shift+R ile yenileyin.",
        "error"
      );
    }
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
  if (viewName === "signal-history") {
    loadSignalHistoryViewPreference();
    applySignalHistoryViewVisibility();
    populateHistoryFilterSelects();
    loadSignalHistory(state.signalHistory.page || 1).catch((error) => showAlert(error.message));
  }
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
        body: JSON.stringify({ phone }),
      });
      await refreshAll();
      showAlert("Telefon numaran kaydedildi.", "success");
    } catch (error) {
      showAlert(error.message);
    }
  });

  $("#credentials-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    hideAlert();
    const apiId = $("#api-id-input").value.trim();
    const apiHash = $("#api-hash-input").value.trim();
    if (!apiId || !apiHash) {
      showAlert("API kimliği ve anahtarı zorunludur.");
      return;
    }
    if (apiHash.length < 8) {
      showAlert("API anahtarı en az 8 karakter olmalı. my.telegram.org adresinden kopyala.");
      return;
    }
    try {
      await api("/api/telegram/credentials", {
        method: "POST",
        body: JSON.stringify({ api_id: apiId, api_hash: apiHash }),
      });
      $("#api-id-input").value = "";
      $("#api-hash-input").value = "";
      await refreshAll();
      showAlert("Telegram bağlantı bilgileri hazır.", "success");
    } catch (error) {
      showAlert(error.message);
    }
  });

  $("#clear-credentials-btn").addEventListener("click", async () => {
    hideAlert();
    if (!window.confirm("Kayıtlı Telegram bilgileri silinecek. Devam etmek istiyor musun?")) {
      return;
    }
    try {
      await api("/api/telegram/credentials", { method: "DELETE" });
      $("#api-id-input").value = "";
      $("#api-hash-input").value = "";
      await refreshAll();
      showAlert("Kayıtlı bilgiler silindi.", "success");
    } catch (error) {
      showAlert(error.message);
    }
  });

  $("#request-code-btn").addEventListener("click", async () => {
    hideAlert();
    const button = $("#request-code-btn");
    const phone = $("#phone-input").value.trim();
    if (!phone) {
      showAlert("Telefon numarasını gir, ardından doğrulama kodu gönder.");
      return;
    }
    setButtonBusy(button, true);
    try {
      const result = await api("/api/telegram/request-code", {
        method: "POST",
        body: JSON.stringify({ phone }),
      });
      await refreshAll();
      if (result.status === "CODE_SENT") {
        showAlert(
          "Doğrulama kodu Telegram uygulamanıza gönderildi. Telegram → Ayarlar → Cihazlar veya 'Telegram' sohbetinden 5 haneli kodu alın. SMS gelmeyebilir.",
          "success"
        );
      } else {
        showAlert(formatErrorMessage(result));
      }
    } catch (error) {
      showAlert(error.message);
      await refreshAll();
    } finally {
      setButtonBusy(button, false);
      if (state.telegramStatus) {
        updateWizardStages(state.telegramStatus);
      }
    }
  });

  $("#verify-code-btn").addEventListener("click", async () => {
    hideAlert();
    const code = $("#code-input").value.trim();
    const phone = $("#phone-input").value.trim();
    if (!code) {
      showAlert("Telegram uygulamasından gelen doğrulama kodunu gir.");
      return;
    }
    if (!phone) {
      showAlert("Telefon numarasını tekrar gir; sunucu yeniden başladıysa numara gerekir.");
      return;
    }
    try {
      const result = await api("/api/telegram/verify-code", {
        method: "POST",
        body: JSON.stringify({ code, phone }),
      });
      await refreshAll();
      if (result.status === "TWO_FACTOR_REQUIRED") {
        showAlert("Telegram ek şifre istiyor.", "success");
      } else {
        showAlert("Telegram hesabına bağlandın.", "success");
      }
    } catch (error) {
      showAlert(error.message);
    }
  });

  $("#verify-password-btn").addEventListener("click", async () => {
    hideAlert();
    const password = $("#password-input").value;
    try {
      await api("/api/telegram/verify-password", {
        method: "POST",
        body: JSON.stringify({ password }),
      });
      await refreshAll();
      showAlert("Telegram hesabına bağlandın.", "success");
    } catch (error) {
      showAlert(error.message);
    }
  });

  $("#sync-channels-btn").addEventListener("click", async () => {
    hideAlert();
    try {
      const result = await api("/api/telegram/sync-channels", { method: "POST", body: "{}" });
      await refreshAll();
      showAlert(`${result.synced} kanal getirildi.`, "success");
    } catch (error) {
      showAlert(error.message);
    }
  });

  $("#disconnect-btn").addEventListener("click", async () => {
    hideAlert();
    try {
      await api("/api/telegram/disconnect", { method: "POST", body: "{}" });
      await refreshAll();
      showAlert("Telegram bağlantısı kesildi.", "success");
    } catch (error) {
      showAlert(error.message);
    }
  });

  const workerStartBtn = $("#listener-worker-start-btn");
  if (workerStartBtn) {
    workerStartBtn.addEventListener("click", async () => {
      hideAlert();
      try {
        await api("/api/listener/worker/start", { method: "POST", body: "{}" });
        await refreshAll();
        showAlert("Telegram dinleme servisi başlatıldı.", "success");
      } catch (error) {
        showAlert(error.message);
      }
    });
  }

  const workerStopBtn = $("#listener-worker-stop-btn");
  if (workerStopBtn) {
    workerStopBtn.addEventListener("click", async () => {
      hideAlert();
      try {
        await api("/api/listener/worker/stop", { method: "POST", body: "{}" });
        await refreshAll();
        showAlert("Telegram dinleme servisi durduruldu.", "success");
      } catch (error) {
        showAlert(error.message);
      }
    });
  }

  $("#import-demo-channels").addEventListener("click", async () => {
    try {
      await api("/api/channels/import-demo", { method: "POST", body: "{}" });
      await refreshAll();
      showAlert("Örnek kanallar eklendi.", "success");
    } catch (error) {
      showAlert(error.message);
    }
  });

  const discoveryPaths = $("#mt5-discovery-paths");
  $("#mt5-discovery-add-path-btn")?.addEventListener("click", () => {
    const input = $("#mt5-path-modal-input");
    if (input) input.value = "";
    openMt5Modal("mt5-path-modal");
  });
  $("#mt5-path-modal-add-btn")?.addEventListener("click", () => {
    const input = $("#mt5-path-modal-input");
    if (addMt5TerminalPath(input?.value)) {
      closeMt5Modal("mt5-path-modal");
      notifyMt5PathAdded(true);
    } else if (input?.value.trim()) {
      notifyMt5PathAdded(false);
    }
  });
  $("#mt5-path-modal-input")?.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      $("#mt5-path-modal-add-btn")?.click();
    }
  });
  $("#mt5-discovery-scan-btn")?.addEventListener("click", async () => {
    await runMt5TerminalDiscovery({ busyButton: $("#mt5-discovery-scan-btn") });
  });
  $("#mt5-add-account-confirm-btn")?.addEventListener("click", confirmAddDiscoveryAccount);
  $("#mt5-real-account-confirm-btn")?.addEventListener("click", confirmRealAccountAdd);
  $("#candidate-test-arm-confirm-btn")?.addEventListener("click", confirmCandidateTestArm);
  $("#mt5-add-account-name-input")?.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      confirmAddDiscoveryAccount();
    }
  });
  $("#mt5-manual-add-link")?.addEventListener("click", openManualTargetModal);
  document.querySelectorAll("[data-mt5-type-filter]").forEach((button) => {
    button.addEventListener("click", () => {
      state.mt5AccountFilters.type = button.getAttribute("data-mt5-type-filter");
      document.querySelectorAll("[data-mt5-type-filter]").forEach((chip) => {
        chip.classList.toggle("active", chip === button);
      });
      renderMt5AccountsTable();
    });
  });
  document.querySelectorAll("[data-mt5-status-filter]").forEach((button) => {
    button.addEventListener("click", () => {
      state.mt5AccountFilters.status = button.getAttribute("data-mt5-status-filter");
      document.querySelectorAll("[data-mt5-status-filter]").forEach((chip) => {
        chip.classList.toggle("active", chip === button);
      });
      renderMt5AccountsTable();
    });
  });
  $("#mt5-accounts-search")?.addEventListener("input", (event) => {
    state.mt5AccountFilters.search = event.target.value;
    renderMt5AccountsTable();
  });
  $("#mt5-target-drawer-overlay")?.addEventListener("click", (event) => {
    if (event.target.id === "mt5-target-drawer-overlay") {
      closeMt5TargetDrawer();
    }
  });
  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    if (state.mt5Drawer.open) closeMt5TargetDrawer();
    if (state.mt5RowMenu.open) closeMt5RowMenu();
  });
  document.addEventListener("click", (event) => {
    if (
      !event.target.closest(".mt5-menu-trigger")
      && !event.target.closest("#mt5-row-menu-portal")
    ) {
      closeMt5RowMenu();
    }
  });
  window.addEventListener("scroll", () => {
    if (state.mt5RowMenu.open && state.mt5RowMenu.trigger) {
      positionMt5RowMenu(state.mt5RowMenu.trigger);
    }
  }, true);
  window.addEventListener("resize", () => {
    if (state.mt5RowMenu.open && state.mt5RowMenu.trigger) {
      positionMt5RowMenu(state.mt5RowMenu.trigger);
    }
  });
  document.querySelectorAll("[data-close-modal]").forEach((button) => {
    button.addEventListener("click", () => closeMt5Modal(button.getAttribute("data-close-modal")));
  });
  document.querySelectorAll("[data-target-tab]").forEach((button) => {
    button.addEventListener("click", () => setTargetModalTab(button.getAttribute("data-target-tab")));
  });
  document.querySelectorAll(".mt5-modal-overlay").forEach((overlay) => {
    overlay.addEventListener("click", (event) => {
      if (event.target === overlay) overlay.classList.add("hidden");
    });
  });
  if (discoveryPaths && !state.mt5TerminalPaths.length && discoveryPaths.value.trim()) {
    state.mt5TerminalPaths = discoveryPaths.value
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean);
  }
  syncMt5PathsTextarea();
  renderMt5PathChips();

  $("#target-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = event.target;
    const payload = Object.fromEntries(new FormData(form).entries());
    payload.display_name = payload.display_name || payload.name;
    payload.name = payload.display_name;
    if (payload.magic_number === "") {
      delete payload.magic_number;
    } else if (payload.magic_number != null) {
      payload.magic_number = Number(payload.magic_number);
    }
    const editTargetId = form.dataset.editTargetId;
    const createMode = form.dataset.createMode;
    try {
      if (editTargetId) {
        await api(`/api/mt5-targets/${editTargetId}`, {
          method: "PATCH",
          body: JSON.stringify(payload),
        });
      } else {
        const created = await api("/api/mt5-targets", { method: "POST", body: JSON.stringify(payload) });
        if (created.target?.id && payload.terminal_exe_path) {
          try {
            await api(`/api/mt5-targets/${created.target.id}/verify`, { method: "POST", body: "{}" });
          } catch (verifyError) {
            showAlert(verifyError.message);
          }
        }
      }
      closeMt5Modal("mt5-target-modal");
      resetTargetFormDefaults();
      await refreshAll();
      showAlert(
        editTargetId ? "Hesap ayarları güncellendi." : "Hesap eklendi.",
        "success"
      );
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
    if (!payload.channel_id || !payload.target_id) {
      showAlert("Önce takip edilen bir kanal ve MT5 hesabı seçmelisin.");
      return;
    }
    try {
      await api("/api/routes", { method: "POST", body: JSON.stringify(payload) });
      form.reset();
      const hiddenParser = form.querySelector('input[name="parser_profile"]');
      if (hiddenParser) {
        hiddenParser.value = "FASTTRACK_GOLD_NOW";
      }
      await refreshAll();
      showAlert("Yönlendirme oluşturuldu.", "success");
    } catch (error) {
      showAlert(error.message);
    }
  });

  $("#refresh-audit").addEventListener("click", refreshAll);
  $("#audit-severity").addEventListener("change", renderAudit);

  $("#signal-history-filters")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      await loadSignalHistory(1);
    } catch (error) {
      showAlert(error.message);
    }
  });

  $("#history-clear-filters")?.addEventListener("click", async () => {
    ["history-from", "history-to", "history-symbol"].forEach((id) => {
      const el = document.getElementById(id);
      if (el) el.value = "";
    });
    ["history-channel", "history-target", "history-side", "history-signal-status", "history-outcome", "history-pnl-state"].forEach((id) => {
      const el = document.getElementById(id);
      if (el) el.value = "";
    });
    try {
      await loadSignalHistory(1);
    } catch (error) {
      showAlert(error.message);
    }
  });

  document.querySelectorAll("[data-history-view]").forEach((button) => {
    button.addEventListener("click", () => {
      setSignalHistoryView(button.getAttribute("data-history-view"));
    });
  });

  $("#demo-audit").addEventListener("click", async () => {
    try {
      await api("/api/audit/demo-event", { method: "POST", body: "{}" });
      await refreshAll();
      showAlert("Örnek kayıt eklendi.", "success");
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
