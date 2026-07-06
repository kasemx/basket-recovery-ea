const state = {
  overview: null,
  telegramStatus: null,
  credentialsStatus: null,
  channels: [],
  targets: [],
  routes: [],
  audit: [],
  signalHistory: { items: [], page: 1, page_size: 20, total: 0 },
  signalHistoryFilters: { page: 1, page_size: 20 },
  signalHistoryView: "cards",
};

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
    subtitle: "Sinyallerin izleneceği MT5 hesapları",
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

function formatErrorMessage(payload) {
  if (payload && payload.user_message) {
    return localizeBackendMessage(payload.user_message);
  }
  if (payload && payload.error) {
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
    throw new Error(formatErrorMessage(payload));
  }
  return payload;
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
    status === "API_CONFIGURED" && configReady && telethonReady && !connected && !codeSent;
  $("#request-code-btn").disabled = !canRequestCode;
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
    canRequestCode
      ? ""
      : connected
        ? "Zaten bağlısın."
        : codeSent
          ? "Kod gönderildi. Gelen kodu yazıp doğrula."
          : !phoneConfigured
            ? "Telefon numaran kayıtlı değil."
            : !configReady
              ? "Telegram bilgileri eksik."
              : !telethonReady
                ? "Telegram bağlantı bileşeni hazır değil."
                : "Telefon kaydı tamamlandıktan sonra kod gönderebilirsin.",
    !canRequestCode
  );

  setHint(
    "#verify-code-hint",
    codeSent ? "Telegram uygulamasından veya SMS'ten gelen kodu gir." : "",
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

function renderTargets() {
  const container = $("#targets-list");
  const rows = state.targets.map((target) => [
    escapeCell(target.name),
    escapeCell(target.terminal_label),
    escapeCell(target.broker_label),
    escapeCell(target.account_mode === "DEMO" ? "Demo" : "Bilinmiyor"),
    escapeCell(target.seed_filename),
    escapeCell(target.details_filename),
    `<span class="badge badge-locked">Sadece İzle</span>`,
    `<button type="button" class="btn btn-small" data-delete-target="${target.id}">Sil</button>`,
  ]);
  renderTable(
    container,
    ["Ad", "Terminal", "Broker", "Hesap Türü", "Sinyal Dosyası", "Detay Dosyası", "Mod", "İşlem"],
    rows,
    "Henüz MT5 hesabı eklenmedi."
  );
  container.querySelectorAll("[data-delete-target]").forEach((button) => {
    button.addEventListener("click", async () => {
      const targetId = button.getAttribute("data-delete-target");
      try {
        await api(`/api/targets/${targetId}`, { method: "DELETE" });
        await refreshAll();
        showAlert("MT5 hesabı silindi.", "success");
      } catch (error) {
        showAlert(error.message);
      }
    });
  });
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

function renderRoutes() {
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
      const startDisabled = running ? "disabled" : "";
      const stopDisabled = running ? "" : "disabled";
      return `
      <article class="route-card" data-route-id="${route.id}">
        <div class="route-card-header">
          <div>
            <h4 class="route-card-title">${escapeCell(route.name)}</h4>
            <p class="route-card-route-line">${escapeCell(route.channel_title)} → ${escapeCell(route.target_name)}</p>
          </div>
          <span class="badge ${route.is_enabled ? "badge-success" : "badge-muted"}">${route.is_enabled ? "Açık" : "Kapalı"}</span>
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

async function refreshAll() {
  setLoading(true);
  hideAlert();
  try {
    const [overview, telegramStatus, credentialsStatus, channelsPayload, targetsPayload, routesPayload, auditPayload] =
      await Promise.all([
        api("/api/overview"),
        api("/api/telegram/status"),
        api("/api/telegram/credentials/status"),
        api("/api/channels"),
        api("/api/targets"),
        api("/api/routes"),
        api("/api/audit?limit=100"),
      ]);
    state.overview = overview;
    state.credentialsStatus = credentialsStatus;
    state.channels = channelsPayload.channels;
    state.targets = targetsPayload.targets;
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
        showAlert("Doğrulama kodu gönderildi. Telegram veya SMS'i kontrol et.", "success");
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
    try {
      const result = await api("/api/telegram/verify-code", {
        method: "POST",
        body: JSON.stringify({ code }),
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

  $("#import-demo-channels").addEventListener("click", async () => {
    try {
      await api("/api/channels/import-demo", { method: "POST", body: "{}" });
      await refreshAll();
      showAlert("Örnek kanallar eklendi.", "success");
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
      showAlert("MT5 hesabı eklendi.", "success");
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
