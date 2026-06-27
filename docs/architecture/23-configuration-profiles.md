# 23. Configuration Profiles

> **Revizyon:** v2 — Recovery, Risk, TP parametreleri kod değişikliği olmadan profile dosyalarından yüklenir.

## 23.1 Tasarım Prensibi

Hard-coded EA input'ları ve entity default'ları yerine **Configuration Profile** sistemi:

```
Profile Loader → validated config objects → bound to basket at creation
```

> **S0.1:** Yükleme sırasında `CProfileBundle` (mutable, loader-only) kullanılır. Sepet oluşturulurken `CProfileSnapshotFactory.FromBundle()` ile **immutable** `CProfileSnapshot` üretilir ve `CBasket.BindProfileSnapshot()` ile tek seferlik bağlanır. Sonrasında profile değiştirilemez.

Parametre değişikliği = JSON/YAML dosyası edit + EA reload (veya hot-reload timer). Kod deploy gerekmez.

---

## 23.2 Profile Dosya Yapısı

```
MQL5/Files/BasketRecovery/profiles/
├── default/
│   ├── risk.profile.json
│   ├── recovery.profile.json
│   ├── takeprofit.profile.json
│   ├── breakeven.profile.json
│   └── execution.profile.json
├── conservative/
│   └── ...
├── aggressive/
│   └── ...
└── manifest.json              # profile list + metadata
```

### manifest.json

```json
{
  "profiles": {
    "default": { "description": "Standard 1%/1.2% risk", "active": true },
    "conservative": { "description": "Lower risk, wider recovery step" }
  },
  "default_profile": "default",
  "symbol_overrides": {
    "XAUUSD": "default",
    "EURUSD": "conservative"
  }
}
```

EA input: `ProfileName = "default"` veya symbol override otomatik.

---

## 23.3 Risk Profile Schema

```json
{
  "schema_version": 1,
  "profile_name": "default",
  "target_risk_pct": 1.0,
  "max_risk_pct": 1.2,
  "max_risk_release_threshold": 0.95,
  "break_even_realized_fraction": 0.33,
  "risk_eval_debounce_ms": 100,
  "favorable_price_window_ticks": 5,
  "favorable_price_min_pips": 0.5,
  "account_risk_cap_pct": null,
  "wait_details_timeout_minutes": 30,
  "wait_details_emergency_action": "CLOSE_ALL"
}
```

**Kullanan modüller:** RiskCalculator, RiskEvaluationHandler, TransitionEngine guards.

---

## 23.4 Recovery Profile Schema

```json
{
  "schema_version": 1,
  "profile_name": "default",
  "recovery_step_pips": 0.2,
  "recovery_lot_size": 0.01,
  "max_recovery_steps": 50,
  "max_total_positions": 20,
  "anchor_mode": "CUMULATIVE",
  "initial_position_count": 3,
  "initial_lot_size": 0.01,
  "recovery_priority": 10,
  "allow_recovery_in_tp1": true,
  "allow_recovery_in_suspended": false
}
```

**Kullanan modüller:** RecoveryEvaluator, CreateBasketCommand handler, OpenRecovery handler.

---

## 23.5 Take Profit Profile Schema

```json
{
  "schema_version": 1,
  "profile_name": "default",
  "tp1_realize_fraction": 0.33,
  "tp2_realize_fraction": 0.66,
  "tp3_action": "CLOSE_ALL",
  "require_floating_profit_positive": true,
  "tp_trigger_mode": "TOUCH",
  "partial_close_ranking": "WORST_ENTRY_FIRST",
  "tp4_enabled": false,
  "tp_open_trailing_enabled": false,
  "tp_open_trail_pips": null
}
```

**Kullanan modüller:** TakeProfitPlanner, TP command handlers, PriceMonitorHandler.

---

## 23.6 Break-Even Profile Schema

```json
{
  "schema_version": 1,
  "profile_name": "default",
  "safety_buffer_pips": 0.5,
  "include_spread": true,
  "sync_retry_count": 3,
  "sync_retry_interval_ms": 1000,
  "require_all_sl_synced_before_transition": true
}
```

---

## 23.7 Execution Profile Schema

```json
{
  "schema_version": 1,
  "profile_name": "default",
  "slippage_points": 10,
  "max_trade_retries": 3,
  "execution_timeout_ms": 5000,
  "magic_number_base": 202606000,
  "command_batch_size": 10,
  "trade_request_batch_size": 5,
  "rest_poll_interval_ms": 3000,
  "rest_poll_interval_active_ms": 2000,
  "rest_poll_interval_idle_ms": 10000
}
```

---

## 23.8 Profile Binding to Basket

Basket oluşturulduğunda profile snapshot alınır — **runtime profile değişikliği aktif basket'i etkilemez**:

```
Basket {
    ...
    ProfileSnapshot profileSnapshot    // immutable copy at creation
}

ProfileSnapshot {
    RiskProfileConfig risk
    RecoveryProfileConfig recovery
    TakeProfitProfileConfig takeProfit
    BreakEvenProfileConfig breakEven
    string profileName
    datetime boundAt
}
```

Yeni basket'ler yeni profile alır. Aktif basket'ler kendi snapshot'larıyla devam eder.

---

## 23.9 IConfigurationProfileLoader Port

```
IConfigurationProfileLoader {
    loadProfile(name) → Result<ProfileBundle>
    loadManifest() → Result<Manifest>
    resolveForSymbol(symbol) → Result<ProfileBundle>
    validate(bundle) → Result<ValidationReport>
    watchForChanges(callback) → void    // hot-reload (new baskets only)
}
```

Validation startup'ta zorunlu:
- `max_risk_pct >= target_risk_pct`
- `recovery_step_pips > 0`
- `tp1_realize_fraction < tp2_realize_fraction`
- Tüm lot sizes >= symbol min lot

Validation fail → INIT_FAILED.

---

## 23.10 Hot Reload (Optional)

```
OnTimer (every 60s):
    IF profile file mtime changed:
        newBundle = loader.loadProfile(name)
        validate(newBundle)
        configService.updateDefault(newBundle)
        log "Profile reloaded — applies to new baskets only"
```

Aktif basket profile **asla** hot reload ile değişmez — operasyonel güvenlik.

---

## 23.11 EA Input vs Profile

| Parametre | Kaynak |
|-----------|--------|
| API URL, API key | EA input (secret) |
| Profile name | EA input |
| Account ID | EA input |
| Log level | EA input |
| target_risk, recovery step, TP fractions | **Profile JSON** |
| Symbol-specific override | manifest.json |

EA input sayısı minimize — operasyonel parametreler profile'da.

---

## 23.12 Profile Versioning

```
schema_version in each profile file
Migration: ProfileMigrator v1→v2 on load
Unknown version: fail with clear error
```

---

## 23.13 Test Profiles

```
profiles/test/
├── minimal_risk.profile.json      // fast integration tests
├── zero_recovery.profile.json     // disable recovery
└── instant_tp.profile.json        // TP at 1 pip for tester
```

Strategy Tester ve backtest adapter test profile kullanır.
