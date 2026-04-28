<div align="center">
  <h1>Anteater</h1>
  <p><em>Deep clean your *nix system, based on <a href="https://github.com/tw93/mole">Mole</a> from <a href="https://github.com/tw93">tw93</a>.</em></p>
</div>

<p align="center">
  <a href="https://github.com/cloudwithax/anteater/stargazers"><img src="https://img.shields.io/github/stars/cloudwithax/anteater?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/cloudwithax/anteater/releases"><img src="https://img.shields.io/github/v/tag/cloudwithax/anteater?label=version&style=flat-square" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/cloudwithax/anteater/commits"><img src="https://img.shields.io/github/commit-activity/m/cloudwithax/anteater?style=flat-square" alt="Commits"></a>
</p>

## Features

- **Deep cache cleanup**: Removes user, browser, developer, and app caches to reclaim gigabytes of space.
- **Project artifact purge**: Sweeps `node_modules`, `target`, `build`, `dist`, `.venv` and friends across your project directories.
- **Disk analyzer**: Interactive TUI (`aa-analyze`) for browsing disk usage and finding large files.
- **System status**: Snapshot of CPU load, memory, mounted disks, and Anteater's own footprint, parsed from `/proc` and `/sys`.
- **System maintenance**: Opt-in tasks for package-manager cache cleanup, journal vacuuming, failed unit reset, and `fstrim`.
- **Linux + OpenBSD**: Pure bash + a single static Go binary for the analyzer. No daemons, no Homebrew.

## Quick Start

**Install via script**

```bash
# Optional args: -s latest for main branch, -s 1.0.0 for a tagged release.
curl -fsSL https://raw.githubusercontent.com/cloudwithax/anteater/main/install.sh | bash
```

> Anteater targets Linux and OpenBSD. macOS users should use the upstream [Mole](https://github.com/tw93/mole) project.

**Run**

```bash
aa                           # Interactive menu
aa clean                     # Deep cleanup of caches and leftover app data
aa purge                     # Sweep project build artifacts (node_modules, target, ...)
aa analyze                   # Visual disk explorer (or 'aa analyse')
aa status                    # System health snapshot
aa optimize                  # Run package-manager and system maintenance tasks
aa completion                # Set up shell tab completion
aa update                    # Update Anteater
aa update --nightly          # Update to latest unreleased main build (script install only)
aa remove                    # Remove Anteater from the system
aa --help                    # Show help
aa --version                 # Show installed version
```

**Preview safely**

```bash
aa clean --dry-run
aa purge --dry-run
aa optimize --dry-run

aa clean --dry-run --debug   # Preview + detailed logs
aa clean --whitelist         # Manage protected caches
aa purge --paths             # Configure project scan directories
aa analyze /mnt              # Analyze a specific mount or directory
```

## Security & Safety Design

Anteater is a local system maintenance tool, and some commands perform destructive local operations.

It uses safety-first defaults: path validation, protected-directory rules, conservative cleanup boundaries, and explicit confirmation for higher-risk actions. When risk or uncertainty is high, Anteater skips, refuses, or requires stronger confirmation rather than broadening deletion scope.

`aa optimize` requires sudo and only runs the maintenance tasks you explicitly check. All checkboxes default to off so nothing happens by accident.

Review [SECURITY.md](SECURITY.md) for reporting guidance, safety boundaries, and current limitations.

## Tips

- **Safety and logs**: `clean`, `purge`, `optimize`, and `remove` are destructive. Review with `--dry-run` first, and add `--debug` when needed. File operations are logged to `~/.local/state/anteater/operations.log`. Disable with `AA_NO_OPLOG=1`.
- **Navigation**: Anteater supports arrow keys and Vim bindings `h/j/k/l`. Space toggles selection in pickers, Enter confirms.
- **OpenBSD**: Most commands work, but `optimize`'s package-cleanup tasks fall back to `pkg_delete -a` semantics. Linux-only tasks (`journalctl --vacuum-size`, `systemctl reset-failed`, `fstrim`) are hidden when the underlying tool is missing.

## Features in Detail

### Deep System Cleanup

```bash
$ aa clean

Scanning cache directories...

  ✓ User app cache (~/.cache)                                  4.2GB
  ✓ Browser cache (Chromium, Firefox)                          1.5GB
  ✓ Developer tools (Go, npm, pip, cargo)                      3.3GB
  ✓ System logs and temp files                                 0.8GB
  ✓ Trash (~/.local/share/Trash)                               1.3GB

====================================================================
Space freed: 11.1GB | Free space now: 223.5GB
====================================================================
```

### System Maintenance

```bash
$ aa optimize

System: 5/32 GB RAM | 333/460 GB Disk (72%) | Uptime 6d

  ☐ Clean pacman cache (paccache -rk1)
  ☐ Vacuum systemd journal (>200M)
  ☐ Reset failed systemd units
  ☐ Trim mounted filesystems (fstrim -av)

[Space] toggle | [Enter] confirm | [q] cancel
```

Tasks default to off. Selected tasks run sequentially under `sudo`; failures are reported but do not abort the rest of the run.

### Disk Space Analyzer

```bash
$ aa analyze ~

Analyze Disk  /home/you  |  Total: 156.8GB

 ▶  1. ███████████████████  48.2%  |  📁 .cache                       75.4GB  >6mo
    2. ██████████░░░░░░░░░  22.1%  |  📁 Downloads                    34.6GB
    3. ████░░░░░░░░░░░░░░░  14.3%  |  📁 go                           22.4GB
    4. ███░░░░░░░░░░░░░░░░  10.8%  |  📁 Documents                    16.9GB
    5. ██░░░░░░░░░░░░░░░░░   5.2%  |  📄 backup_2023.zip               8.2GB

  ↑↓←→ Navigate  |  O Open  |  L Large files  |  Q Quit
```

### System Status

```bash
$ aa status

Anteater Status — host  · Linux 6.7.0 · 2026-04-27

System
  Hostname        host
  Kernel          Linux 6.7.0
  Uptime          6d 4h
  Load            0.82, 1.05, 1.23

Memory
  Total           24.0 GB
  Used            ████████████░░░░░░░  58%   14.0 GB
  Available       9.8 GB

Disks
  /               ████████████░░░░░░░  62%   192G / 305G
  /home           █████░░░░░░░░░░░░░░  27%   135G / 500G

Anteater
  Cache           24 MB
  Logs            1.4 MB
  Last operation  2026-04-26 18:30 — clean
```

#### Machine-Readable Output

`aa analyze` supports `--json` for scripting and automation.

```bash
# Disk analysis as JSON
$ aa analyze --json ~/Documents
{
  "path": "/home/you/Documents",
  "overview": false,
  "entries": [
    { "name": "Library", "path": "...", "size": 80939438080, "is_dir": true }
  ],
  "large_files": [
    { "name": "backup.zip", "path": "...", "size": 8796093022 }
  ],
  "total_size": 168393441280,
  "total_files": 42187
}
```

### Project Artifact Purge

Clean old build artifacts such as `node_modules`, `target`, `.venv`, `build`, and `dist` to free up disk space.

```bash
aa purge

Select Categories to Clean - 18.5GB (8 selected)

➤ ● my-react-app       3.2GB | node_modules
  ● old-project        2.8GB | node_modules
  ● rust-app           4.1GB | target
  ● next-blog          1.9GB | node_modules
  ○ current-work       856MB | node_modules  | Recent
  ● django-api         2.3GB | venv
  ● vue-dashboard      1.7GB | node_modules
  ● backend-service    2.5GB | node_modules
```

> Tip: Install `fd` for faster scans. `pacman -S fd`, `apt install fd-find`, or `pkg_add fd`.

> Safety: This permanently deletes selected artifacts. Review carefully before confirming. Projects newer than 7 days are marked and unselected by default.

<details>
<summary><strong>Custom Scan Paths</strong></summary>

Run `aa purge --paths` to configure scan directories, or edit `~/.config/anteater/purge_paths` directly:

```shell
~/Documents/MyProjects
~/Work/ClientA
~/Work/ClientB
```

When custom paths are configured, Anteater scans only those directories. Otherwise, it uses defaults like `~/Projects`, `~/GitHub`, and `~/dev`.

</details>

## Community Love

Thanks to everyone who helped build Anteater and the upstream Mole project. ❤️

<a href="https://github.com/cloudwithax/anteater/graphs/contributors">
  <img src="./CONTRIBUTORS.svg?v=2" width="1000" />
</a>

## Support

- If Anteater helped you, [share it](https://twitter.com/intent/tweet?url=https://github.com/cloudwithax/anteater&text=Anteater%20-%20Deep%20clean%20your%20%2Anix%20system.) or give it a star.
- Got ideas or bugs? Open an issue or PR.

## License

MIT License. Feel free to use Anteater and contribute.
