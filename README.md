# ollama-top (`otop`)

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
* 📊 **Batch Job Progress Bar:** Pipe any CLI script into `ollama-top` to render live progress bars, throughput rates (Items/s), and real-time ETAs.

---

## 📸 Live Terminal Preview

```text
════════════════════════════════════════════════════════════════════════════════════════════════════════════
  OLLAMA-TOP: AI, DATABASE & HARDWARE MONITOR  |  09:30:00  |  Host: BLADE
  Author: Frank Glück (Glück IT)  |  Web: https://dozent.net  |  GitHub: https://github.com/glueck-it/ollama-top
────────────────────────────────────────────────────────────────────────────────────────────────────────────
  NVIDIA GPU SENSORS (GeForce RTX 5070 Ti):
  GPU Core Load:   [████████████████  ]  90%  | Clock: 2160 MHz
  GPU Memory Bus:  [████████████      ]  65%  | Clock: 11001 MHz
  VRAM Belegung:   [███████           ]  4.9 / 11.9 GB (41%)
  GPU Power/Temp:  114.3 W Power Draw  |  GPU Temp: 78° C

  HOST CPU & SYSTEM (Intel Core Ultra 9 275HX - 24C/24T):
  CPU Auslastung:  [████              ]  23%  | Clock: 2700 MHz
  System RAM:      [████████          ] 44.9 / 95.5 GB (47%)
  CPU Status/Temp: Package Thermal: 91° C   |  Architecture: x64 (24C/24T)

  INTEL NPU & iGPU SENSORS (Intel(R) AI Boost):
  NPU Neural Load: [                  ]   0%  | Engine: Neural (Standby / Ollama nutzt iGPU Vulkan)
  Intel iGPU Load: [██████████████████] 100%  | Device: Intel(R) Graphics

  NETWORK TRAFFIC & ADAPTER (Realtek USB GbE):
  Gesamt Live:     [In / Download] 48.2 KB/s   [Out / Upload] 12.4 KB/s   | Session: In 14.2 MB / Out 3.1 MB

  ACTIVE SERVICES & ENDPOINTS (Database, Cache & AI):
  PORT    SERVICE                 ENDPOINT / TARGET               SOCKETS       SCOPE / NETWORK             
────────────────────────────────────────────────────────────────────────────────────────────────────────────
  11434   Ollama (NVIDIA/Primary) 127.0.0.1:11434 (RTX 5070 Ti)   12 aktiv      Localhost IPC (Loopback)    
  11435   Ollama (iGPU/Secondary) 127.0.0.1:11435 (iGPU Vulkan)   6 aktiv       Localhost IPC (Loopback)    
  5432    PostgreSQL              192.168.1.150:5432              4 aktiv       Local LAN / On-Premise      

  LLM ENGINES & INFERENCE SPEED:
  PORT    MODEL / ENGINE          CONTEXT     VRAM/RAM    TOKENS IN (INPUT)         TOKENS OUT (GEN)        
────────────────────────────────────────────────────────────────────────────────────────────────────────────
  11434   gemma4:e4b              40960       3.04 GB     5.012 Tok/s               91.3 Tok/s              
  11435   gemma4:e4b              40960       3.60 GB     109 Tok/s                 9.8 Tok/s               

  Stats Port 11434 (gemma4:e4b):
    Tokens In:   Min: 5.012 | Max: 5.012 | Avg: 5.012 | Med: 5.012 Tok/s  (n=12)
    Tokens Out:  Min:  88.5 | Max:  94.2 | Avg:  91.3 | Med:  91.3 Tok/s  (n=12)

  Stats Port 11435 (gemma4:e4b):
    Tokens In:   Min:    97 | Max:   112 | Avg:   104 | Med:   104 Tok/s  (n=8)
    Tokens Out:  Min:   9.5 | Max:  10.2 | Avg:   9.8 | Med:   9.8 Tok/s  (n=8)

  ACTIVE CLIENTS & PARALLEL WORKERS: [4 parallel verbunden]
  PID      CLIENT          TARGET ENDPOINT                 LOCAL PORT    MEMORY            CPU TIME         
────────────────────────────────────────────────────────────────────────────────────────────────────────────
  18504    php             127.0.0.1:11434                 64297         41.4 MB           4.9 s            
  20380    php             127.0.0.1:11434                 58296         41.3 MB           5.1 s            
  35284    php             127.0.0.1:11435                 61306         47.1 MB           3.8 s            
  39824    php             192.168.1.150:5432              58189         41.7 MB           4.7 s            
════════════════════════════════════════════════════════════════════════════════════════════════════════════
  Refresh: 1.2s  |  [Leertaste]/[R]: Reset  |  https://dozent.net  |  https://github.com/glueck-it/ollama-top
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
