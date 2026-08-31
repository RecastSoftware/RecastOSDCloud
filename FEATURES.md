# OSDCloud Features

> **Boot into WinPE and deploy Windows — automatically, reliably, every time.**

**Platform:** Windows PE | PowerShell 7.6+ | amd64 & arm64

---

## WinPEStartup Orchestration

`Invoke-WinPEStartup` automates everything between power-on and deployment — loading drivers, connecting to the network, and auto-updating OSDCloud — in a single command. Drop a JSON profile on a USB drive for site-specific settings without touching the boot image. Extend the sequence with custom PowerShell or a HTTPS URL at any phase.

---

## OSDCloud Explorer

`Start-OSDCloudExplorer` is a Windows Forms file browser for WinPE and WinRE where Windows Explorer isn't available. Navigate folders, view file details, and copy paths to the clipboard with `Ctrl+C`. Runs as a non-blocking process so deployment scripts keep running in parallel.

---

## Built for WinPE Deployment Teams

- **Zero-touch boot** — full environment ready before the operator sees the screen
- **Flexible** — skip Wi-Fi, drivers, or IP config with simple flags; inject custom commands at any phase
- **Always current** — module auto-updates at startup
- **amd64 & arm64** — full dual-architecture support
