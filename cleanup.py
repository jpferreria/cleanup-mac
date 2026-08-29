#!/usr/bin/env python3
import os
import sys
import shutil
import json
from pathlib import Path

CATEGORIES = {
    "downloads_installers": {
        "name": "Downloads & Installers",
        "description": "Installer files (.dmg, .pkg, .zip, etc.) in ~/Downloads",
        "paths": ["~/Downloads"]
    },
    "user_caches": {
        "name": "User Caches",
        "description": "General application caches in ~/Library/Caches",
        "paths": ["~/Library/Caches"]
    },
    "system_caches": {
        "name": "System Caches",
        "description": "System-wide application caches in /Library/Caches",
        "paths": ["/Library/Caches"]
    },
    "user_logs": {
        "name": "User Logs",
        "description": "Application and system logs in ~/Library/Logs",
        "paths": ["~/Library/Logs"]
    },
    "package_manager_caches": {
        "name": "Package Manager Caches",
        "description": "Caches for npm, pip, Homebrew, cargo",
        "paths": [
            "~/Library/Caches/Homebrew",
            "~/Library/Caches/pip",
            "~/.cache/pip",
            "~/.npm/_cacache",
            "~/.cargo/registry/cache"
        ]
    },
    "xcode_derived_data": {
        "name": "Xcode Derived Data",
        "description": "Build artifacts and indexes for Xcode projects",
        "paths": ["~/Library/Developer/Xcode/DerivedData"]
    },
    "system_tmp": {
        "name": "System Temp Directory",
        "description": "Files in /tmp",
        "paths": ["/tmp"]
    }
}

INSTALLER_EXTENSIONS = {'.dmg', '.pkg', '.zip', '.tar.gz', '.tgz', '.app'}

def get_dir_size(path: Path, scan_installers_only: bool = False) -> int:
    total_size = 0
    if not path.exists():
        return 0
    
    if path.is_file():
        if not scan_installers_only or path.suffix.lower() in INSTALLER_EXTENSIONS:
            try:
                return path.stat().st_size
            except Exception:
                return 0
        return 0

    try:
        for entry in os.scandir(path):
            try:
                if entry.is_file(follow_symlinks=False):
                    if not scan_installers_only or Path(entry.name).suffix.lower() in INSTALLER_EXTENSIONS:
                        total_size += entry.stat().st_size
                elif entry.is_dir(follow_symlinks=False):
                    total_size += get_dir_size(Path(entry.path), scan_installers_only)
            except Exception:
                continue
    except Exception:
        pass
    return total_size

def scan():
    results = {}
    for cat_id, info in CATEGORIES.items():
        total_size = 0
        expanded_paths = []
        for p in info["paths"]:
            expanded = Path(os.path.expanduser(p)).resolve()
            if expanded.exists():
                expanded_paths.append(str(expanded))
                installers_only = (cat_id == "downloads_installers")
                total_size += get_dir_size(expanded, installers_only)
        
        results[cat_id] = {
            "name": info["name"],
            "description": info["description"],
            "size_bytes": total_size,
            "paths": expanded_paths
        }
    print(json.dumps(results, indent=2))

def delete_category(cat_id: str):
    if cat_id not in CATEGORIES:
        print(f"Unknown category: {cat_id}", file=sys.stderr)
        sys.exit(1)
        
    info = CATEGORIES[cat_id]
    installers_only = (cat_id == "downloads_installers")
    
    print(f"Cleaning category: {info['name']}")
    for p in info["paths"]:
        expanded = Path(os.path.expanduser(p)).resolve()
        if not expanded.exists():
            continue
            
        if installers_only:
            # Only delete installer files in Downloads
            for entry in os.scandir(expanded):
                try:
                    p_entry = Path(entry.path)
                    if p_entry.is_file(follow_symlinks=False) and p_entry.suffix.lower() in INSTALLER_EXTENSIONS:
                        print(f"Deleting file: {p_entry}")
                        p_entry.unlink()
                    elif p_entry.is_dir(follow_symlinks=False) and p_entry.suffix.lower() in INSTALLER_EXTENSIONS:
                        print(f"Deleting directory: {p_entry}")
                        shutil.rmtree(p_entry)
                except Exception as e:
                    print(f"Error deleting {entry.path}: {e}", file=sys.stderr)
        else:
            # Delete everything inside the directory or the directory itself and recreate it
            if expanded.is_file():
                try:
                    print(f"Deleting file: {expanded}")
                    expanded.unlink()
                except Exception as e:
                    print(f"Error deleting {expanded}: {e}", file=sys.stderr)
            else:
                for entry in os.scandir(expanded):
                    try:
                        p_entry = Path(entry.path)
                        if p_entry.is_file(follow_symlinks=False):
                            p_entry.unlink()
                        elif p_entry.is_dir(follow_symlinks=False):
                            shutil.rmtree(p_entry)
                    except Exception as e:
                        print(f"Error deleting {entry.path}: {e}", file=sys.stderr)
    print(f"Finished cleaning {info['name']}.")

def main():
    if len(sys.argv) < 2:
        print("Usage: cleanup.py <scan|clean> [category_id]")
        sys.exit(1)
        
    mode = sys.argv[1]
    if mode == "scan":
        scan()
    elif mode == "clean":
        if len(sys.argv) < 3:
            print("Please specify a category_id to clean.")
            sys.exit(1)
        delete_category(sys.argv[2])
    else:
        print(f"Unknown mode: {mode}")
        sys.exit(1)

if __name__ == "__main__":
    main()
