# Changelog

All notable changes to **ollama-top** (`otop`) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [v1.1.0] - 2026-09-14

### Added
- **Server-Scale Headroom Alignment**: All metrics (Clocks, Temps, Power Draw, RAM/VRAM allocations, Sockets, Context lengths, Tokens/s, Memory MB, CPU seconds) are right-aligned with leading-space padding to maintain rigid column boundaries even on large multi-GPU enterprise servers (up to 1,000 W TDP, 4 TB RAM, 1M context windows).
- **Interactive Keyboard Controls**: Added `[Q]` and `[X]` keys for instant clean termination without breaking terminal scrollback, alongside `[R]` and `[Spacebar]` for live statistics reset.
- **Header & Footer Streamlining**: Embedded version indicator in the top header (`v1.1.0`) and organized author signature, links, and shortcuts cleanly in the footer.
- **Accurate Loopback TCP Deduplication**: Filtered OS-level loopback socket pairs (`127.0.0.1` / `::1`) and internal monitor polling calls to ensure reported service socket counts represent real active worker connections 1:1.
- **Enhanced Concurrency & Hardware Health Advisor**: Compact 2-line concurrency state reporting (`CONTINUOUS BATCHING OPTIMAL`, `DEDICATED INFERENCE`, etc.) with full-line color-coded alerts on bottlenecks or thermal warnings.

### Changed
- Compacted sensor layout: Integrated GPU Power Draw and GPU Temperature into Clock and Memory Bus lines, reducing vertical terminal footprint.
- Standardized cross-platform parity between PowerShell (`ollama-top.ps1`) and POSIX Bash (`ollama-top.sh`).

---

## [v1.0.0] - 2026-09-14

### Added
- **Initial Release of `ollama-top` (`otop`)**.
- Real-time Multi-Instance Ollama Inference monitoring (Prompt & Generation Tokens/s, Slots, Context, VRAM).
- Dynamic Ollama server log discovery and automatic slot capacity parsing (`OLLAMA_NUM_PARALLEL` / `-np`).
- NVIDIA GPU hardware acceleration monitoring via `nvidia-smi` (Core Load, Memory Bus, VRAM, Power, Temp).
- Intel NPU (Neural Processing Unit) & Intel Arc / Core Ultra iGPU (Vulkan) hardware load tracking.
- Universal database & enterprise service discovery across 18+ engines (PostgreSQL, MySQL, Oracle, DB2, Informix, HANA, SQL Server, Redis, ClickHouse, etc.).
- Network bandwidth monitoring with automatic scope classification (`Localhost IPC`, `Local LAN`, `Remote WAN / Cloud`).
- Active client process inspector (PID, Name, Memory, CPU time, connected endpoints).
- Pipeable Batch Job Progress Bar engine with throughput estimation and dynamic ETA calculation.
- One-command installers for Windows (`install.ps1`) and Linux/macOS (`install.sh`).
