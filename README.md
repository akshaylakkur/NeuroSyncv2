# 🧠 NeuroSync — AI-Powered Stress Intelligence

**NeuroSync** is an iOS application that fuses **real-time physiological data from Apple HealthKit** with **AI-driven social sentiment analysis** to give you a holistic picture of your stress levels. It doesn't just track how your body feels — it also monitors your digital communications (Discord, email) to understand what's stressing you out and takes action when you need it most.

---

## 📱 What it does

NeuroSync is split into two major layers that work together:

### 1. Physiological Stress Monitoring (iOS + HealthKit)

The iOS app reads seven health metrics from **Apple HealthKit**:
- **Heart Rate** — resting and current
- **Heart Rate Variability (HRV)** — the gold standard for stress detection
- **Sleep Hours** — how much rest you actually got
- **Step Count** — daily activity baseline
- **Exercise Minutes** — active energy expenditure
- **Mindful Minutes** — meditation / breath work
- **Respiratory Rate** — breathing patterns

These metrics are sent to **NVIDIA's Nemotron-3 Ultra 550B** model (via the NIM API) for analysis. The LLM returns a structured assessment:
- **Stress Level** (low / moderate / high)
- **Confidence Score**
- **Clinical Reasoning** (why it thinks what it thinks)
- **Actionable Suggestion** (what you can do about it)

If stress levels are **high**, NeuroSync automatically creates an **iOS Reminder** with the AI's suggestion — so you get a push notification like "Try a 5-minute breathing exercise: inhale for 4 seconds, hold for 4, exhale for 6."

### 2. Social Sentiment Monitoring (Server + OpenClaw)

The backend server runs an **OpenClaw orchestrator** that polls **Discord** and **Gmail** every 15 seconds, feeding every message through an LLM stress analyser. It detects:
- **Urgent messages** and **crisis events** in real-time
- **Sentiment trends** across channels and senders
- **Volume anomalies** — sudden spikes in message traffic
- **Cross-channel stress aggregation** — is everyone stressed or just one channel?

The iOS app polls this server and displays a real-time social sentiment dashboard alongside your health data. If the server detects a social crisis, the app creates a reminder and correlates social stress with physiological stress (`Health: high / Social: critical`).

### 3. Simulation & Demo Mode

Because not everyone has a Discord bot token and a Gmail OAuth setup handy, NeuroSync includes a **standalone simulator server** that generates 1000+ realistic messages across multiple **stress scenarios**:
- 🟢 **normal_day** — moderate traffic, occasional spikes
- 🔴 **incident_escalation** — starts calm, builds to crisis, resolves
- 🟢 **weekend_calm** — very low traffic, positive vibes
- 🔴 **crisis_spike** — sudden massive burst, then decline
- 🟡 **gradual_buildup** — slow burn over time
- 🔴 **rollercoaster** — alternating high/low stress
- 🔴 **sustained_pressure** — consistent high volume & stress

You can switch scenarios live via API to demo different stress patterns.

---

## 🏗️ How we built it

### Frontend: iOS (SwiftUI)

| Component | Technology |
|-----------|-----------|
| UI Framework | SwiftUI with NavigationStack, TabView |
| State Management | `@MainActor` ViewModels, `@Published`, `@EnvironmentObject` |
| Health Data | `HealthKit` (HKHealthStore, HKObserverQuery) |
| Reminders | `EventKit` (EKReminder, EKAlarm) |
| Secure Storage | iOS Keychain (API key storage) |
| Background Tasks | `BGTaskScheduler` for periodic stress checks |
| Auto-refresh | Task-based polling loop (5 min health, 30s social) |

The iOS app has four tabs:
1. **Dashboard** — stress indicator ring, AI insights card, live health metrics grid
2. **Sentiment** — social sentiment overview, channel breakdowns, message feed
3. **History** — searchable, filterable stress event log with detail view
4. **Settings** — NVIDIA API key management, permissions, data management

### Backend: Python + OpenClaw + FastAPI

| Component | Technology |
|-----------|-----------|
| Orchestrator | Async Python with `asyncio` |
| Message Polling | OpenClaw CLI + SDK (Discord, Gmail) |
| LLM Analysis | OpenClaw agent → any LLM (GPT-4o-mini, Claude, etc.) |
| Fallback Engine | Keyword-based heuristic analyser |
| Storage | RollingBuffer + JSONL persistence |
| REST API | FastAPI with Pydantic models |
| Simulation | Standalone FastAPI server with scenario engine |
| HTTP Poller | `httpx` AsyncClient for simulated polling |

### AI Stack

| Model | Provider | Use Case |
|-------|----------|----------|
| **Nemotron-3 550B** (NVIDIA NIM) | NVIDIA API | Physiological stress analysis (iOS → cloud) |
| **GPT-4o-mini** (or configurable) | OpenClaw Gateway | Social message sentiment analysis (server) |

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     iOS App (SwiftUI)                        │
│  ┌──────────────┐  ┌─────────────────┐  ┌───────────────┐  │
│  │   HealthKit   │  │  SocialMonitor   │  │   Reminders   │  │
│  │  (HR, HRV,   │  │  (polls server   │  │  (EventKit)   │  │
│  │   sleep, …)  │  │   every 30s)     │  │   auto-create │  │
│  └──────┬───────┘  └────────┬────────┘  └───────┬───────┘  │
│         │                   │                    │          │
│         ▼                   ▼                    │          │
│  ┌──────────────────────────────────────────────┐│          │
│  │        NVIDIA NIM (Nemotron-3 550B)          ││          │
│  │   "Given HR=88, HRV=24, sleep=5.2h →        ││          │
│  │    stress=moderate, confidence=0.78"         ││          │
│  └──────────────────────────────────────────────┘│          │
└──────────────────────┬───────────────────────────┘          │
                       │ HTTP (REST)                          │
                       ▼                                      │
┌─────────────────────────────────────────────────────────────────┐
│             NeuroSync Server (FastAPI + OpenClaw)               │
│                                                                 │
│  ┌──────────────────┐   ┌──────────────┐   ┌────────────────┐ │
│  │   Discord Poller  │   │  Gmail Poller│   │ Simulated      │ │
│  │   (every 15s)    │   │  (every 15s)  │   │ HTTP Poller*   │ │
│  └────────┬─────────┘   └──────┬───────┘   └───────┬────────┘ │
│           └─────────┬──────────┘         ┌─────────┘           │
│                     ▼                     ▼                    │
│           ┌──────────────────────────────────────┐             │
│           │          MessageStore                 │            │
│           │  (Rolling buffer + JSONL persistence) │            │
│           └──────────────────┬───────────────────┘             │
│                              ▼                                 │
│           ┌──────────────────────────────────────┐             │
│           │          StressAnalyser               │            │
│           │   (LLM agent OR keyword fallback)     │            │
│           └──────────────────┬───────────────────┘             │
│                              ▼                                 │
│           ┌──────────────────────────────────────┐             │
│           │      Aggregated Summary              │            │
│           │  → REST API → iOS App               │            │
│           └──────────────────────────────────────┘             │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  OpenClaw Gateway (ws://127.0.0.1:18789)                │   │
│  │  Manages channels + routes LLM inference                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Simulator Server (standalone, port 8081)                │   │
│  │  • 7 stress scenarios                                   │   │
│  │  • 1000+ realistic messages per seed                     │   │
│  │  • Live scenario switching via API                       │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘

*Simulated pollers used when NEUROSYNC_SIM_MODE=true
```

---

## 🚧 Challenges we ran into

**1. HealthKit authorization is a multi-step dance.** You can't just request access and assume it works. The first time a user opens the app, HealthKit prompts might not fire properly, and background `HKObserverQuery` callbacks require careful lifecycle management. We added a polling loop that waits up to 15 seconds for authorization before fetching data.

**2. Getting reliable HRV data from HealthKit.** HRV (Heart Rate Variability) is arguably the most important stress metric, but it's also the most sparse. Not all Apple Watch models record SDNN consistently, and some users may never have HRV data. We made all metrics optional and only run analysis when at least 3 metrics have real values.

**3. LLM output parsing without the hallucinations.** Getting the Nemotron model to return valid JSON every single time without markdown fences or stray characters required careful prompt engineering AND a defensive parser that strips ```json blocks, handles whitespace, and validates the output before treating it as a real analysis.

**4. The OpenClaw gateway is a moving target.** During development, the OpenClaw CLI's agent mode kept changing. We built a dual-path analyser: if the LLM agent is available, use it; if not, fall back to a keyword-based engine that scans for crisis signals, stress keywords, and sentiment markers. This made the system resilient to gateway issues.

**5. Cross-device networking during the hackathon.** The iOS app needs to reach the server running on a MacBook. We hardcoded a local IP (`172.18.92.67`) but this breaks as soon as you switch networks. The `launch_demo.sh` script now auto-detects the local IP and prints it for easy configuration.

**6. iOS Reminders permissions changed in iOS 17.** Apple introduced `requestFullAccessToReminders()` vs `requestWriteOnlyAccessToReminders()`, and the old `requestAccess(to:)` is deprecated. We had to add availability checks for both paths.

---

## 🏆 Accomplishments that we're proud of

- **Won "Best Use of NVIDIA NIM"**, **"Best Overall"**, and **"Best in Health & Wellness"** at the NVIDIA + SendChow Techathon 🏅🏅🏅
- **Merging two completely different stress signals** — physiological (heart rate, HRV, sleep) and social (Discord messages, emails) — into a single, coherent dashboard
- **A fully working simulation engine** with 7 stress scenarios, each with realistic message content across Discord and Gmail, weighted by sentiment, and controllable via REST API. It made demoing the product compelling without needing real channel access.
- **The stress indicator ring animation** — a custom SwiftUI circular gauge that smoothly animates between green/yellow/orange/red based on the LLM's analysis. It's the kind of polish that makes a demo memorable.
- **Automatic Reminders integration** — when stress is detected (either physiologically or socially), NeuroSync doesn't just show you a notification; it creates a proper iOS Reminder with the AI's suggestion, complete with an alarm. This means you actually get pinged to take action.
- **Automatic re-pooling in the simulator** — when the message pool runs out, it regenerates 1000 new messages seamlessly, so the demo never runs dry.

---

## 📚 What we learned

**On the AI side:**
- Prompt engineering for structured JSON output is an art. You have to be absurdly specific ("Respond ONLY with valid JSON in this exact format — no markdown, no code fences") and even then, you need defensive parsing.
- Temperature matters. We used `temperature: 0.3` for stress analysis because you want consistent, evidence-based results — not creative interpretations.
- Nemotron-3 550B is remarkably capable at medical-style reasoning with structured outputs.

**On the iOS side:**
- SwiftUI's `@MainActor` ViewModels with Combine publishers and async/await can feel clean when done right. The `DashboardViewModel` coordinating HealthKit, the NIM API, EventKit, and persistence all from one place was a design pattern that worked well.
- Background tasks in iOS are finicky. `BGTaskScheduler` doesn't guarantee execution timing, and the expiration handler must be handled with extreme care (we used a lock to prevent double-completion).

**On the backend side:**
- `asyncio.gather` with `return_exceptions=True` is the right way to poll multiple channels concurrently without one failure bringing down the whole cycle.
- A generic keyword fallback analyser is surprisingly effective. It doesn't match the nuance of an LLM, but it catches 80% of real crises with simple pattern matching.
- Building a message generator with template banks and filler words produces far more realistic test data than random string generation.

---

## 🔮 What's next for NeuroSync

- **More health metrics:** Add blood oxygen (SpO2), blood pressure (where available), and glucose data for richer physiological context
- **More social channels:** Slack, Teams, WhatsApp — the OpenClaw SDK theoretically supports them
- **On-device AI:** Run a distilled model (e.g., via CoreML or Apple's MLX) directly on the iPhone for privacy-preserving stress analysis without sending health data to the cloud
- **Watch app:** An Apple Watch companion that shows live stress levels and haptic feedback when the system detects a spike
- **Trend analysis:** Show stress patterns over days/weeks/months — "Your stress is highest on Tuesday afternoons"
- **Personalized interventions:** Learn which suggestions work best for each user and tailor the AI's advice over time
- **Shared dashboards:** Optionally share anonymized stress data with therapists or coaches
- **Calendar integration:** Correlate stress spikes with calendar events — "Your stress peaks during the weekly engineering standup"

---

## 🛠️ Quick Start

### iOS App

1. Open `NeuroSyncv2.xcodeproj` in Xcode
2. Update `AppConfig.serverBaseURL` in `Models/AppConfig.swift` to your Mac's local IP
3. Build and run on a physical iPhone (HealthKit doesn't work on simulator)
4. Get an NVIDIA API key from [build.nvidia.com](https://build.nvidia.com/nvidia/nemotron-3-ultra-550b-a55b) and enter it in Settings

### Server (for social sentiment)

```bash
cd server

# Install dependencies
pip install -r requirements.txt

# Launch the full demo (simulator server + main server)
bash launch_demo.sh

# Or manually:
python3 simulator_server.py --port 8081 --scenario normal_day
python3 -m uvicorn main:app --host 0.0.0.0 --port 8080
```

### Available Demo Scenarios

```bash
# Change scenario live:
curl -X POST "http://localhost:8081/sim/scenario?scenario=crisis_spike"
curl -X POST "http://localhost:8081/sim/scenario?scenario=weekend_calm"
curl -X POST "http://localhost:8081/sim/scenario?scenario=incident_escalation"
```

### Server API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Server health check |
| `GET` | `/social/dashboard` | Full social sentiment dashboard (what the iOS app polls) |
| `GET` | `/social/messages` | Recent messages with sentiment |
| `GET` | `/social/urgent` | Urgent/crisis messages |
| `POST` | `/social/health-correlation` | Receive health stress from iOS |
| `POST` | `/social/create-reminder` | Queue a social stress reminder |
| `GET` | `/social/pending-reminders` | Poll pending reminders for iOS |
| `GET` | `/analysis/latest` | Latest aggregated stress analysis |
| `GET` | `/analysis/history` | Historical analyses |
| `GET` | `/sim/status` | Simulator status and scenario info |
| `GET` | `/sim/scenarios` | List all available scenarios |

---

## 📁 Project Structure

```
NeuroSyncv2/
├── NeuroSyncv2/                  # iOS App
│   ├── NeuroSyncv2App.swift      # App entry point
│   ├── ContentView.swift         # Tab navigation
│   ├── Models/
│   │   ├── HealthMetrics.swift   # Health data model
│   │   ├── StressResult.swift    # LLM analysis result
│   │   ├── StressEvent.swift     # Stored stress check
│   │   ├── SocialMessage.swift   # Social message model
│   │   └── AppConfig.swift       # Global configuration
│   ├── ViewModels/
│   │   ├── DashboardViewModel.swift
│   │   ├── SocialSentimentViewModel.swift
│   │   ├── StressHistoryViewModel.swift
│   │   └── SettingsViewModel.swift
│   ├── Views/
│   │   ├── DashboardView.swift
│   │   ├── StressIndicatorView.swift    # Custom ring gauge
│   │   ├── LlmSuggestionView.swift      # AI insights card
│   │   ├── MetricCardView.swift
│   │   ├── SocialSentimentView.swift
│   │   ├── MessageRowView.swift
│   │   ├── ChannelBreakdownCard.swift
│   │   ├── StressHistoryView.swift
│   │   └── SettingsView.swift
│   └── Services/
│       ├── HealthKitService.swift       # Apple Health integration
│       ├── NIMService.swift             # NVIDIA NIM API client
│       ├── SocialSentimentService.swift # Server API client
│       ├── EventKitService.swift        # Reminders integration
│       ├── BackgroundTaskService.swift  # BGTaskScheduler
│       └── KeychainHelper.swift         # Secure API key storage
├── server/                       # Python Backend
│   ├── main.py                   # FastAPI bridge server
│   ├── run_orchestrator.py       # CLI orchestrator runner
│   ├── simulator_server.py       # Standalone simulator
│   ├── launch_demo.sh            # One-command demo launcher
│   ├── orchestrator.yaml         # Example config
│   ├── requirements.txt          # Python dependencies
│   ├── orchestrator/
│   │   ├── orchestrator.py       # Main poll-analyse loop
│   │   ├── poller.py             # Discord + Gmail pollers
│   │   ├── simulated_http_poller.py  # HTTP simulator client
│   │   ├── analyser.py           # LLM + fallback analysis
│   │   ├── storage.py            # Rolling buffer persistence
│   │   ├── social_api.py         # Social sentiment REST API
│   │   └── config.py             # All configuration
│   └── simulator/
│       ├── generator.py          # Realistic message templates
│       ├── poller.py             # Scenario-based burst patterns
│       └── api.py                # Sim control endpoints
├── Info.plist                    # App permissions & capabilities
└── .gitignore
```

---

## 🧪 Tech Stack Summary

| Layer | Technology |
|-------|-----------|
| Mobile | SwiftUI, HealthKit, EventKit, Keychain, BGTaskScheduler |
| AI (Physiological) | NVIDIA NIM — Nemotron-3 Ultra 550B |
| AI (Social) | OpenClaw + GPT-4o-mini (configurable) |
| Backend | Python, FastAPI, asyncio, httpx |
| Message Platform | OpenClaw SDK / Gateway |
| Persistence | Rolling buffers, JSONL, UserDefaults |
| Simulation | Custom scenario engine with 1000+ message pools |

---

## 📄 License

MIT — built for the NVIDIA + SendChow Techathon.

---

*Made with 🧠, too much coffee, and an Apple Watch that definitely knows when I'm stressed.*