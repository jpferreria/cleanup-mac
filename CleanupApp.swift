import SwiftUI
import Foundation

let APP_VERSION = "1.0.0"

struct CleanupCategory: Identifiable {
    let id: String
    let name: String
    let description: String
    let paths: [String]
    var sizeBytes: Int64 = 0
    var isSelected: Bool = true
    var isInstallersOnly: Bool = false
}

class CleanupViewModel: ObservableObject {
    @Published var categories: [CleanupCategory] = [
        CleanupCategory(
            id: "downloads_installers",
            name: "Downloads & Installers",
            description: "Installer files (.dmg, .pkg, .zip, etc.) in ~/Downloads",
            paths: ["~/Downloads"],
            isInstallersOnly: true
        ),
        CleanupCategory(
            id: "user_caches",
            name: "User Caches",
            description: "General application caches in ~/Library/Caches",
            paths: ["~/Library/Caches"]
        ),
        CleanupCategory(
            id: "system_caches",
            name: "System Caches",
            description: "System-wide application caches in /Library/Caches",
            paths: ["/Library/Caches"]
        ),
        CleanupCategory(
            id: "user_logs",
            name: "User Logs",
            description: "Application and system logs in ~/Library/Logs",
            paths: ["~/Library/Logs"]
        ),
        CleanupCategory(
            id: "package_manager_caches",
            name: "Package Manager Caches",
            description: "Caches for npm, pip, Homebrew, cargo",
            paths: [
                "~/Library/Caches/Homebrew",
                "~/Library/Caches/pip",
                "~/.cache/pip",
                "~/.npm/_cacache",
                "~/.cargo/registry/cache"
            ]
        ),
        CleanupCategory(
            id: "xcode_derived_data",
            name: "Xcode Derived Data",
            description: "Build artifacts and indexes for Xcode projects",
            paths: ["~/Library/Developer/Xcode/DerivedData"]
        ),
        CleanupCategory(
            id: "system_tmp",
            name: "System Temp Directory",
            description: "Files in /tmp",
            paths: ["/tmp"]
        )
    ]
    
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var statusMessage = "Ready to scan."
    @Published var logs = ""
    
    private let installerExtensions = Set(["dmg", "pkg", "zip", "tar.gz", "tgz", "app"])
    
    func logMessage(_ message: String) {
        DispatchQueue.main.async {
            self.logs += message + "\n"
        }
    }
    
    func scan() {
        isScanning = true
        statusMessage = "Scanning disk..."
        logs = ""
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            for index in self.categories.indices {
                let cat = self.categories[index]
                var catSize: Int64 = 0
                
                for pathStr in cat.paths {
                    let expanded = NSString(string: pathStr).expandingTildeInPath
                    let url = URL(fileURLWithPath: expanded)
                    catSize += self.calculateSize(of: url, isInstallersOnly: cat.isInstallersOnly, fm: fm)
                }
                
                DispatchQueue.main.async {
                    self.categories[index].sizeBytes = catSize
                }
            }
            
            DispatchQueue.main.async {
                self.isScanning = false
                self.statusMessage = "Scan complete."
                self.logMessage("Scan finished. Ready to clean selected items.")
            }
        }
    }
    
    private func calculateSize(of url: URL, isInstallersOnly: Bool, fm: FileManager) -> Int64 {
        // Renamed variable fileManager to fm to avoid duplicate identifier issues
        var total: Int64 = 0
        var isDir: ObjCBool = false
        
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        
        if !isDir.boolValue {
            if isInstallersOnly {
                let ext = url.pathExtension.lowercased()
                if installerExtensions.contains(ext) {
                    let attrs = try? fm.attributesOfItem(atPath: url.path)
                    return (attrs?[.size] as? Int64) ?? 0
                }
                return 0
            } else {
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                return (attrs?[.size] as? Int64) ?? 0
            }
        }
        
        // It's a directory
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            if isInstallersOnly {
                let ext = fileURL.pathExtension.lowercased()
                if installerExtensions.contains(ext) {
                    let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
                    total += (attrs?[.size] as? Int64) ?? 0
                }
            } else {
                let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
                total += (attrs?[.size] as? Int64) ?? 0
            }
        }
        return total
    }
    
    func cleanSelected() {
        isCleaning = true
        statusMessage = "Cleaning selected items..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            
            for index in self.categories.indices {
                let cat = self.categories[index]
                if !cat.isSelected { continue }
                
                self.logMessage("Cleaning category: \(cat.name)...")
                
                for pathStr in cat.paths {
                    let expanded = NSString(string: pathStr).expandingTildeInPath
                    let url = URL(fileURLWithPath: expanded)
                    
                    if cat.isInstallersOnly {
                        // Deleting specific files inside ~/Downloads
                        self.cleanInstallers(in: url, fileManager: fm)
                    } else {
                        // Deleting contents of the directory
                        self.cleanDirectoryContents(at: url, fileManager: fm)
                    }
                }
                
                // Reset size to 0
                DispatchQueue.main.async {
                    self.categories[index].sizeBytes = 0
                }
            }
            
            DispatchQueue.main.async {
                self.isCleaning = false
                self.statusMessage = "Cleanup complete."
                self.logMessage("Finished cleanup of all selected categories.")
            }
        }
    }
    
    private func cleanInstallers(in url: URL, fileManager fm: FileManager) {
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        for item in contents {
            let ext = item.pathExtension.lowercased()
            if installerExtensions.contains(ext) {
                do {
                    self.logMessage("Deleting installer: \(item.lastPathComponent)")
                    try fm.removeItem(at: item)
                } catch {
                    self.logMessage("Error deleting \(item.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func cleanDirectoryContents(at url: URL, fileManager fm: FileManager) {
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        for item in contents {
            do {
                self.logMessage("Deleting: \(item.path)")
                try fm.removeItem(at: item)
            } catch {
                self.logMessage("Error deleting \(item.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = CleanupViewModel()
    @State private var showAbout = false
    
    var formattedSize: (Int64) -> String = { bytes in
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    var totalSelectedSize: Int64 {
        viewModel.categories.filter { $0.isSelected }.map { $0.sizeBytes }.reduce(0, +)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("macOS Disk Cleanup")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Reclaim disk space by purging unnecessary installers, caches, and logs.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    showAbout = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Categories List
            List {
                ForEach($viewModel.categories) { $cat in
                    HStack(alignment: .center, spacing: 12) {
                        Toggle("", isOn: $cat.isSelected)
                            .labelsHidden()
                            .disabled(viewModel.isScanning || viewModel.isCleaning)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cat.name)
                                .font(.headline)
                            Text(cat.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(formattedSize(cat.sizeBytes))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(cat.sizeBytes > 0 && cat.isSelected ? .primary : .secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Divider()
            
            // Console / Logging Output
            VStack(alignment: .leading, spacing: 4) {
                Text("Log Output:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ScrollView {
                    Text(viewModel.logs.isEmpty ? "No active logs." : viewModel.logs)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
                .frame(height: 100)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
            }
            .padding()
            
            Divider()
            
            // Footer Controls
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.statusMessage)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Total Selected for Cleanup: \(formattedSize(totalSelectedSize))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.scan()
                }) {
                    Text("Scan Disk")
                }
                .disabled(viewModel.isScanning || viewModel.isCleaning)
                
                Button(action: {
                    viewModel.cleanSelected()
                }) {
                    Text("Clean Selected")
                        .foregroundColor(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(viewModel.isScanning || viewModel.isCleaning || totalSelectedSize == 0)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 650, minHeight: 500)
        .onAppear {
            viewModel.scan()
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 80, height: 80)
            
            VStack(spacing: 4) {
                Text("macOS Disk Cleanup")
                    .font(.headline)
                Text("Version \(APP_VERSION)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text("A lightweight, high-performance macOS utility to reclaim disk space by safely removing caches, temporary files, and log files.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            VStack(spacing: 2) {
                Text("Developer: jpferreria")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Link("GitHub Repository", destination: URL(string: "https://github.com/jpferreria/cleanup-mac")!)
                    .font(.caption)
            }
            
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(width: 320, height: 320)
    }
}

@main
struct CleanupApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
    }
}
