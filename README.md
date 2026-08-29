# macOS Disk Cleanup Utility

A simple Python utility to scan, estimate, and safely clean up temporary files, installer archives, application logs, and developer caches on macOS.

## Features

- **Safe Scan (Dry-Run)**: Calculates potential reclaimed space and prints path details without modifying/deleting any files.
- **Categorized Purging**: Select specific categories to clean (e.g., package manager caches, user logs, temp directories).
- **macOS Permissions Aware**: Gracefully logs and skips protected directories (e.g., SIP/TCC restricted system caches) instead of crashing.

## Monitored Categories

| Category | Key Paths Scanned | File Types / Purpose |
| :--- | :--- | :--- |
| **Downloads & Installers** | `~/Downloads` | `.dmg`, `.pkg`, `.zip`, `.tar.gz`, `.tgz`, `.app` files |
| **User Caches** | `~/Library/Caches` | General application cache files |
| **Package Manager Caches**| Homebrew, pip, npm, cargo caches | Downloaded package archives and registries |
| **User Logs** | `~/Library/Logs` | Application logs and diagnostics |
| **Xcode Derived Data** | `~/Library/Developer/Xcode/DerivedData` | Build artifacts and project index cache |
| **System Caches** | `/Library/Caches` | System-wide cache directories |
| **System Temp** | `/tmp` (or `/private/tmp`) | Temporary files |

## Usage

### 1. Scan (Dry Run / Inspect Space)
Run the script with the `scan` argument to analyze files and output a size breakdown:
```bash
python3 cleanup.py scan
```

### 2. Clean Specific Category
Run the script with `clean` followed by the category identifier to delete the scanned files/folders under that category:
```bash
python3 cleanup.py clean <category_id>
```
*Example (cleaning package manager caches):*
```bash
python3 cleanup.py clean package_manager_caches
```

## Security & Safety

- The script **does not delete directories recursively** unless they explicitly match an installer directory format (e.g. `.app` inside Downloads) or are contents within cache/temp directories.
- Always review the output of `scan` before running any cleanup commands.
