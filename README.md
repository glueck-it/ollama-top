# ollama-top (`otop`)

<p align="center">
  <img src="assets/ollama-top-icon.svg" width="96" height="96" alt="ollama-top Logo">
</p>

[![Release](https://img.shields.io/badge/Release-v1.1.0-blue.svg)](https://github.com/glueck-it/ollama-top/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-blue)](https://github.com/glueck-it/ollama-top)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell)](https://github.com/glueck-it/ollama-top)
[![Bash](https://img.shields.io/badge/Bash-POSIX-4EAA25?logo=gnu-bash)](https://github.com/glueck-it/ollama-top)
[![Zero Dependencies](https://img.shields.io/badge/Dependencies-Zero-brightgreen)](https://github.com/glueck-it/ollama-top)


**The `htop` / `nvtop` for Ollama, Local LLMs, GPUs and Enterprise Data Pipelines.**

`ollama-top` (`otop`) is an ultra-lightweight, **zero-dependency** terminal dashboard that monitors your entire local AI and batch stack in real-time:
* 🚀 **Multi-Instance Ollama Inference:** Live Prompt & Generation speeds (`Tokens/s In/Out`), Context window, VRAM allocation, and real-time statistics (Min / Max / Avg / Median).
* ⚡ **Full Hardware Acceleration:** NVIDIA RTX GPUs (CUDA, Core Load, Memory Bus, Temp, Power, VRAM), Intel Arc / Core Ultra iGPU (Vulkan load) and NPU Neural status.
* 🗄️ **Universal Database & Network Socket Discovery:** Auto-detects active client connections to PostgreSQL, MySQL/MariaDB, Oracle, IBM DB2, IBM Informix, SAP HANA, Microsoft SQL Server, Redis, MongoDB, ClickHouse, and more.
* 🌐 **Network Bandwidth & Traffic Scope:** Real-time download/upload throughput and intelligent scope classification (`Localhost IPC`, `Local LAN`, `Remote WAN / Cloud`).
* ⚙️ **Active Parallel Client Workers:** Tracks client runtimes (Python, Perl, PHP, Node.js, Go, Rust) with PID, memory consumption, CPU time, and remote endpoints.
* 💡 **System Health & Config Advisor:** Intelligent heuristic warnings for slot bottlenecks, VRAM saturation, context limits, and thermal throttling.
* 📊 **Batch Job Progress Bar:** Pipe any CLI script into `ollama-top` to render live progress bars, throughput rates (Items/s), and real-time ETAs.

---

## 📸 Live Terminal Preview

```text
═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
  OLLAMA-TOP v1.1.0: AI, DATABASE & HARDWARE MONITOR  |  11:06:18  |  Host: BLADE
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  NVIDIA GPU SENSORS (GeForce RTX 5070 Ti):
  GPU Core Load:   [████████████████  ]  91%  | Clock:  2122 MHz  | Temp:   81° C
  GPU Memory Bus:  [███████           ]  39%  | Clock: 11001 MHz  | Power:  114,0 W
  VRAM Belegung:   [█████████████████ ]   11,1 /   11,9 GB ( 93%)

  HOST CPU & SYSTEM (Intel Core Ultra 9 275HX - 24C/24T):
  CPU Auslastung:  [█████             ]  28%  | Clock:  2700 MHz  | Temp:   91° C
  System RAM:      [██████████        ]   51,5 /   95,5 GB ( 54%)

  INTEL NPU & iGPU SENSORS (Intel(R) AI Boost):
  NPU Neural Load: [                  ]   0%  | Engine: Neural (Standby / Ollama nutzt iGPU Vulkan)
  Intel iGPU Load: [██████████████████] 100%  | Device: Intel(R) Graphics

  NETWORK TRAFFIC & ADAPTER (Realtek USB GbE):
  Gesamt Live:     [In / Download] 48,2 KB/s   [Out / Upload] 12,4 KB/s   | Session: In 14,2 MB / Out 3,1 MB

  ACTIVE SERVICES & ENDPOINTS (Database, Cache & AI):
  PORT    SERVICE                 ENDPOINT / TARGET                    SOCKETS  SCOPE / NETWORK             
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   5432   PostgreSQL              192.168.1.150:5432                   4 aktiv  Local LAN / On-Premise      
  11435   Ollama (iGPU/Secondary) 127.0.0.1:11435 (iGPU Vulkan)        1 aktiv  Localhost IPC (Loopback)    
  11434   Ollama (NVIDIA/Primary) 127.0.0.1:11434 (RTX 5070 Ti)        1 aktiv  Localhost IPC (Loopback)    

  LLM ENGINES & INFERENCE SPEED:
  PORT   MODEL / ENGINE        SLOTS     CONTEXT     VRAM/RAM   TOKENS IN (INPUT)    TOKENS OUT (GEN)
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  11434  gemma4:e4b          3 slots      40.960       3,1 GB         3.415 Tok/s          61,9 Tok/s
  11435  gemma4:e4b           1 slot      40.960       3,6 GB           117 Tok/s           9,6 Tok/s

  Stats Port 11434 (gemma4:e4b):
    Tokens In:   Min:  2.375 | Max:  4.504 | Avg:  3.423 | Med:  3.505 Tok/s  (n=   26)
    Tokens Out:  Min:   12,9 | Max:   91,9 | Avg:   42,6 | Med:   50,2 Tok/s  (n=    7)

  ACTIVE CLIENTS & PARALLEL WORKERS: [4 parallel verbunden]
      PID  CLIENT        CONNECTED SERVICES / TARGETS                         MEMORY         CPU TIME
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
    35284  php           PostgreSQL (5432), Ollama (11435)                   37,4 MB           11,6 s
    41228  php           PostgreSQL (5432)                                   37,8 MB            6,5 s
    41880  php           Ollama (11434), PostgreSQL (5432)                   42,3 MB            6,6 s
    43160  php           PostgreSQL (5432)                                   39,9 MB            6,8 s

  SYSTEM HEALTH & CONFIG ADVISOR:
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  [*] CONTINUOUS BATCHING OPTIMAL (Port 11434): 2 workers multiplexing seamlessly across 3 GPU slots. Zero queue latency.
  [*] DEDICATED INFERENCE (Port 11435): 1 active worker running with full dedicated GPU throughput (1 slot configured).
═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
  Frank Glück (Glück IT)  |  https://dozent.net  |  GitHub: glueck-it/ollama-top  |  [R] Reset  |  [Q/X] Exit
```

---

## ⚡ Quickstart & Installation

### Windows (PowerShell)
Install via one-line PowerShell command:
```powershell
irm https://raw.githubusercontent.com/glueck-it/ollama-top/main/install.ps1 | iex
```
*Or run directly without installing:*
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\ollama-top.ps1
```

### Linux / macOS (Bash)
Install via one-line curl command:
```bash
curl -fsSL https://raw.githubusercontent.com/glueck-it/ollama-top/main/install.sh | bash
```
*Or execute directly:*
```bash
chmod +x ./ollama-top.sh
./ollama-top.sh
```

---

## 💡 Key Features

### 1. Multi-Instance Ollama Tracking
Running multiple Ollama daemons simultaneously (e.g. one on NVIDIA CUDA, another on an Intel iGPU via Vulkan)?  
`ollama-top` tracks each port individually:
* Independent prompt evaluation (`Tokens In / s`) and response generation (`Tokens Out / s`) rates.
* Rolling Min, Max, Average, and Median statistics. Press **`[Space]`** or **`[R]`** to reset anytime.

### 2. Universal Enterprise Database & Cache Catalog
Identifies active network sockets across all major databases without manual configuration:
* **Relational / Enterprise:** PostgreSQL, MySQL / MariaDB, Oracle Database, Microsoft SQL Server, IBM DB2, IBM Informix, SAP HANA, Sybase ASE, Teradata.
* **NoSQL, Cache & Message Queues:** MongoDB, Redis / Valkey, Apache Cassandra, ClickHouse, Elasticsearch / OpenSearch, Neo4j, Apache Kafka, RabbitMQ.
* **Network Scopes:** Classifies endpoints into `Localhost IPC (Loopback)`, `Local LAN / On-Premise`, or `Remote WAN / Cloud`.

### 3. Hardware Sensor Telemetry
* **NVIDIA GPUs:** Queries `nvidia-smi` directly for core utilization %, memory bus load %, VRAM usage, temperature, power draw (W), and clock speeds.
* **Intel iGPU & NPU:** Monitors Intel Graphics compute engine (Vulkan/DirectX) and Intel AI Boost NPU status via Windows Performance Counters.
* **CPU & RAM:** Multi-core utilization %, clock speed, system memory allocation, and package thermal status.

### 4. Batch Job & Pipeline Integration
Monitor any long-running ETL, AI, or database job by piping output:
```powershell
# Pipe any script with progress indicators into ollama-top:
python backfill.py | .\ollama-top.ps1 -Total 5000 -Title "Data Ingestion"
```

---

## 🔧 CLI Options

| Option | Windows (`.ps1`) | Linux (`.sh`) | Description |
| :--- | :--- | :--- | :--- |
| **Total Items** | `-Total 5000` | `-t 5000` | Expected item count for batch progress bar |
| **Title** | `-Title "ETL Job"` | `-j "ETL Job"` | Custom job name in header |
| **Refresh Interval** | `-RefreshMs 1200` | `-r 1.2` | Poll and refresh interval |
| **Custom Ports** | `-WatchPorts 1521,3306` | `-p 1521,3306` | Additional ports to monitor |
| **Ollama Ports** | `-OllamaPorts 11434,11435` | *(auto)* | Ports of active Ollama instances |
| **Width** | `-Width 108` | `-w 108` | Dashboard column width |

---

## 👨‍🏫 Author & Enterprise Trainings

Developed and maintained by **Frank Glück** ([Glück IT](https://glueck-it.de)).

Looking for in-depth, hands-on enterprise seminars on:
* **Local LLM Deployment & Integration (Ollama, vLLM, OpenVINO, HuggingFace)**
* **High-Performance PostgreSQL Tuning & Architecture**
* **Microsoft SQL Server & Oracle Database Optimization**
* **Data Engineering & Batch Pipeline Architecture**

👉 Visit **[dozent.net](https://dozent.net)** for hands-on, instructor-led technical trainings (Remote & On-Site across DACH).

---

## 📄 License

Licensed under the [MIT License](LICENSE). Free for personal and commercial use.
