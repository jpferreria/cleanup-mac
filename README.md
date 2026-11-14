# macOS Disk Cleanup Utility & GUI App

A native macOS application and command-line utility powered by **Apple Intelligence** to scan, evaluate storage health, and safely clean up temporary files, installer archives, application logs, and developer caches on macOS.

![App Screenshot](screenshot.png)

## Features

- **Native macOS GUI App**: Built with SwiftUI, offering a clean user interface with live Macintosh HD disk capacity bar, checkboxes, real-time logging, and dynamic space calculation.
- **Apple Intelligence Storage Advisor (`FoundationModels`)**: Uses Apple's on-device `SystemLanguageModel` (`LanguageModelSession`) to evaluate your disk usage and scanned cache sizes. It determines whether cleanup is needed, assigns an urgency rating (`Low`, `Moderate`, or `High`), explains why in plain language, and tags recommended categories with an **AI Pick** badge.
- **Siri & Shortcuts Integration (`AppIntents`)**: Includes `CheckStorageHealthIntent` so Siri and the macOS Shortcuts app can check your storage health directly.
- **Lightweight & Dependency-free**: Written in native Swift (App) and Python (CLI) with no external third-party packages required.
- **Safe Scan (Dry-Run)**: Analyzes disk space and prints path details/sizes before performing any deletion.
- **Categorized Purging**: Selectively clear categories such as package manager caches, user logs, Xcode derived data, or temporary directories.
- **macOS Permissions Aware**: Gracefully logs and skips protected directories (e.g., SIP/TCC restricted system caches) instead of crashing.

---

## Apple Intelligence Integration (`v1.1.0`)

After each disk scan, `Cleanup.app` automatically runs an on-device Apple Intelligence assessment:

1. **Disk & Category Analysis**: Collects total disk capacity, available space, and byte counts across all 7 monitored categories.
2. **On-Device LLM Evaluation**: Passes the structured summary to `LanguageModelSession` (`FoundationModels`), running 100% locally on your Mac without sending any data off-device.
3. **Smart Recommendations**:
   - Displays a status banner (**Cleanup Recommended** or **Storage Looks Healthy**) with a color-coded urgency badge (`Low`, `Moderate`, `High`).
   - Marks high-impact categories with an **AI Pick** badge.
   - Provides a **Select AI Recommended** button to one-click select only the categories recommended by Apple Intelligence.
4. **Automatic Fallback**: If Apple Intelligence is disabled or unavailable on the system, the app seamlessly falls back to a built-in smart heuristic advisor.

---

## Monitored Categories

| Category ID | Category Name | Key Paths Scanned | File Types / Purpose |
| :--- | :--- | :--- | :--- |
| `downloads_installers` | **Downloads & Installers** | `~/Downloads` | `.dmg`, `.pkg`, `.zip`, `.tar.gz`, `.tgz`, `.app` files |
| `user_caches` | **User Caches** | `~/Library/Caches` | General application cache files |
| `package_manager_caches` | **Package Manager Caches**| Homebrew, pip, npm, cargo caches | Downloaded package archives and registries |
| `user_logs` | **User Logs** | `~/Library/Logs` | Application logs and diagnostics |
| `xcode_derived_data` | **Xcode Derived Data** | `~/Library/Developer/Xcode/DerivedData` | Build artifacts and project index cache |
| `system_caches` | **System Caches** | `/Library/Caches` | System-wide cache directories |
| `system_tmp` | **System Temp** | `/tmp` (or `/private/tmp`) | Temporary files |

---

## Getting Started: SwiftUI App

### How to Run the App
To open the compiled native application bundle:
```bash
open Cleanup.app
```
*(Or locate `Cleanup.app` in Finder and double-click to open it).*

### How to Build the App from Source
If you make changes to `CleanupApp.swift`, you can recompile and bundle the app using the provided script:
```bash
./build.sh
```

---

## Command Line Interface (Python)

### 1. Scan (Dry Run / Inspect Space)
Run the script with the `scan` argument to analyze files and output a size breakdown:
```bash
python3 cleanup.py scan
```

### 2. Clean Specific Category
Run the script with `clean` followed by the category identifier to delete files/folders under that category:
```bash
python3 cleanup.py clean <category_id>
```
*Example (cleaning package manager caches):*
```bash
python3 cleanup.py clean package_manager_caches
```

### 3. Check Version
```bash
python3 cleanup.py --version
```

---

## Running Unit Tests

Both the Python CLI and the SwiftUI App include unit test suites:

- **Python Unit Tests**:
  ```bash
  python3 test_cleanup.py
  ```
- **Swift Unit Tests**:
  ```bash
  SDK_PATH=$(xcrun --show-sdk-path)
  swiftc -D TESTING -sdk "$SDK_PATH" -parse-as-library CleanupApp.swift CleanupTests.swift -o run_swift_tests
  ./run_swift_tests && rm -f run_swift_tests
  ```

---

## Security & Safety

- The utility **does not delete directories recursively** unless they explicitly match an installer directory format (e.g. `.app` inside Downloads) or are contents within cache/temp directories.
- Always review the scan results before executing any deletion commands.
