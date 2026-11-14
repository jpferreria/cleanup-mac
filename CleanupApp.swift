import SwiftUI
import Foundation
import FoundationModels
import AppIntents

let APP_VERSION = "1.1.0"

struct CleanupCategory: Identifiable {
    let id: String
    let name: String
    let description: String
    let paths: [String]
    var sizeBytes: Int64 = 0
    var isSelected: Bool = true
    var isInstallersOnly: Bool = false
}

struct StorageAssessment: Codable {
    var needsCleaning: Bool
    var urgencyLevel: String
    var explanation: String
    var recommendedCategories: [String]
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
    
    // Disk Capacity Metrics
    @Published var totalDiskBytes: Int64 = 0
    @Published var availableDiskBytes: Int64 = 0
    
    // Apple Intelligence Advisor State
    @Published var isAnalyzingAI = false
    @Published var aiAssessment: StorageAssessment? = nil
    @Published var aiSourceLabel = "Apple Intelligence"
    @Published var showAbout = false
    
    private let installerExtensions = Set(["dmg", "pkg", "zip", "tar.gz", "tgz", "app"])
    
    func logMessage(_ message: String) {
        DispatchQueue.main.async {
            self.logs += message + "\n"
        }
    }
    
    func refreshDiskCapacity() {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? homeURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let avail = values.volumeAvailableCapacityForImportantUsage ?? 0
            DispatchQueue.main.async {
                self.totalDiskBytes = total
                self.availableDiskBytes = avail
            }
        }
    }
    
    func scan() {
        isScanning = true
        statusMessage = "Scanning disk..."
        logs = ""
        refreshDiskCapacity()
        
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
                self.analyzeWithAppleIntelligence()
            }
        }
    }
    
    func analyzeWithAppleIntelligence() {
        isAnalyzingAI = true
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        
        let totalStr = formatter.string(fromByteCount: totalDiskBytes)
        let availStr = formatter.string(fromByteCount: availableDiskBytes)
        let usedPct = totalDiskBytes > 0 ? Int(Double(totalDiskBytes - availableDiskBytes) / Double(totalDiskBytes) * 100.0) : 0
        
        let categorySummary = categories.map { cat in
            "- \(cat.id) (\(cat.name)): \(formatter.string(fromByteCount: cat.sizeBytes))"
        }.joined(separator: "\n")
        
        let totalReclaimable = categories.map { $0.sizeBytes }.reduce(0, +)
        let reclaimableStr = formatter.string(fromByteCount: totalReclaimable)
        
        Task {
            let model = SystemLanguageModel.default
            if case .available = model.availability {
                do {
                    let instructions = """
                    You are an intelligent macOS storage advisor. Given the user's disk capacity and scanned cache/installer categories, determine if the storage needs cleaning right now.
                    Respond ONLY with valid JSON matching this schema (no markdown code fences, no extra text):
                    {"needsCleaning": true/false, "urgencyLevel": "Low"|"Moderate"|"High", "explanation": "1-2 concise sentences explaining why and what stands out", "recommendedCategories": ["category_id1", "category_id2"]}
                    Only include category IDs in recommendedCategories that have significant size (> 10 MB) and are safe to clean.
                    """
                    let prompt = """
                    Disk Total: \(totalStr)
                    Disk Available: \(availStr) (\(usedPct)% used)
                    Total Reclaimable in Scan: \(reclaimableStr)
                    Categories:
                    \(categorySummary)
                    """
                    let session = LanguageModelSession(instructions: instructions)
                    let response = try await session.respond(to: prompt)
                    let parsed = self.parseAssessment(from: response.content, totalReclaimable: totalReclaimable, usedPct: usedPct)
                    
                    await MainActor.run {
                        self.aiAssessment = parsed
                        self.aiSourceLabel = "Apple Intelligence (On-Device)"
                        self.isAnalyzingAI = false
                        self.logMessage("Apple Intelligence assessment: \(parsed.needsCleaning ? "Cleanup Recommended" : "Storage Healthy") (\(parsed.urgencyLevel) urgency).")
                    }
                    return
                } catch {
                    self.logMessage("Apple Intelligence session fallback: \(error.localizedDescription)")
                }
            }
            
            // Fallback heuristic if Apple Intelligence is unavailable or failed
            let fallback = self.heuristicAssessment(totalReclaimable: totalReclaimable, usedPct: usedPct)
            await MainActor.run {
                self.aiAssessment = fallback
                self.aiSourceLabel = "Smart Storage Advisor"
                self.isAnalyzingAI = false
            }
        }
    }
    
    func parseAssessment(from raw: String, totalReclaimable: Int64, usedPct: Int) -> StorageAssessment {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstBrace = cleaned.firstIndex(of: "{"), let lastBrace = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[firstBrace...lastBrace])
        }
        if let data = cleaned.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(StorageAssessment.self, from: data) {
            return decoded
        }
        return heuristicAssessment(totalReclaimable: totalReclaimable, usedPct: usedPct)
    }
    
    func heuristicAssessment(totalReclaimable: Int64, usedPct: Int) -> StorageAssessment {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        let reclaimStr = formatter.string(fromByteCount: totalReclaimable)
        
        let significantIDs = categories.filter { $0.sizeBytes > 10 * 1024 * 1024 }.map { $0.id }
        let needsClean = usedPct >= 80 || totalReclaimable > 500 * 1024 * 1024
        let urgency: String
        if usedPct >= 85 || totalReclaimable > 5 * 1024 * 1024 * 1024 {
            urgency = "High"
        } else if needsClean {
            urgency = "Moderate"
        } else {
            urgency = "Low"
        }
        
        let explanation = needsClean
            ? "Your disk is \(usedPct)% full with \(reclaimStr) of reclaimable caches and temporary files ready to clean."
            : "Your storage is healthy (\(usedPct)% used) with only \(reclaimStr) in temporary caches."
        
        return StorageAssessment(
            needsCleaning: needsClean,
            urgencyLevel: urgency,
            explanation: explanation,
            recommendedCategories: significantIDs
        )
    }
    
    func applyAIRecommendations() {
        guard let rec = aiAssessment?.recommendedCategories else { return }
        let recSet = Set(rec)
        for index in categories.indices {
            categories[index].isSelected = recSet.contains(categories[index].id)
        }
        logMessage("Applied Apple Intelligence recommendations (\(rec.count) categories selected).")
    }
    
    private func calculateSize(of url: URL, isInstallersOnly: Bool, fm: FileManager) -> Int64 {
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
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: []) else {
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
                        self.cleanInstallers(in: url, fileManager: fm)
                    } else {
                        self.cleanDirectoryContents(at: url, fileManager: fm)
                    }
                }
                
                DispatchQueue.main.async {
                    self.categories[index].sizeBytes = 0
                }
            }
            
            DispatchQueue.main.async {
                self.isCleaning = false
                self.statusMessage = "Cleanup complete."
                self.logMessage("Finished cleanup of all selected categories.")
                self.refreshDiskCapacity()
                self.analyzeWithAppleIntelligence()
            }
        }
    }
    
    private func cleanInstallers(in url: URL, fileManager fm: FileManager) {
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []) else { return }
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
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []) else { return }
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

// MARK: - Siri & Shortcuts AppIntent
struct CheckStorageHealthIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Storage Health"
    static var description = IntentDescription("Uses Apple Intelligence to check if your Mac's storage needs cleaning.")
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? homeURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let avail = values?.volumeAvailableCapacityForImportantUsage ?? 0
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        let availStr = formatter.string(fromByteCount: avail)
        let totalStr = formatter.string(fromByteCount: total)
        
        if case .available = SystemLanguageModel.default.availability {
            let session = LanguageModelSession()
            let prompt = "The user's Mac has \(availStr) available out of \(totalStr). In one short sentence, tell them if they should run a disk cleanup."
            if let resp = try? await session.respond(to: prompt) {
                return .result(dialog: IntentDialog(stringLiteral: resp.content))
            }
        }
        return .result(dialog: "You have \(availStr) available out of \(totalStr) on your Mac.")
    }
}

struct ContentView: View {
    @StateObject private var viewModel = CleanupViewModel()
    
    var formattedSize: (Int64) -> String = { bytes in
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    var totalSelectedSize: Int64 {
        viewModel.categories.filter { $0.isSelected }.map { $0.sizeBytes }.reduce(0, +)
    }
    
    var diskUsedFraction: Double {
        guard viewModel.totalDiskBytes > 0 else { return 0 }
        let used = Double(viewModel.totalDiskBytes - viewModel.availableDiskBytes)
        return min(max(used / Double(viewModel.totalDiskBytes), 0), 1)
    }
    
    private func urgencyColor(_ urgency: String) -> Color {
        switch urgency.lowercased() {
        case "high": return .red
        case "moderate": return .orange
        default: return .green
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("macOS Disk Cleanup")
                            .font(.title)
                            .fontWeight(.bold)
                        Label("Apple Intelligence", systemImage: "apple.intelligence")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                    }
                    Text("Reclaim disk space by purging unnecessary installers, caches, and logs.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    viewModel.showAbout = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Disk Capacity + Apple Intelligence Advisor Banner
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.totalDiskBytes > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label("Macintosh HD", systemImage: "internaldrive")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(formattedSize(viewModel.availableDiskBytes)) available of \(formattedSize(viewModel.totalDiskBytes))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        ProgressView(value: diskUsedFraction)
                            .tint(diskUsedFraction > 0.85 ? .red : (diskUsedFraction > 0.70 ? .orange : .blue))
                    }
                }
                
                if viewModel.isAnalyzingAI {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Apple Intelligence is evaluating your storage health...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.purple.opacity(0.08))
                    .cornerRadius(8)
                } else if let assessment = viewModel.aiAssessment {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(assessment.needsCleaning ? "Cleanup Recommended" : "Storage Looks Healthy")
                                    .font(.headline)
                                Text("\(assessment.urgencyLevel) Urgency")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(urgencyColor(assessment.urgencyLevel).opacity(0.2))
                                    .foregroundColor(urgencyColor(assessment.urgencyLevel))
                                    .clipShape(Capsule())
                                Spacer()
                                Text(viewModel.aiSourceLabel)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(assessment.explanation)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            if !assessment.recommendedCategories.isEmpty {
                                HStack {
                                    Button(action: {
                                        viewModel.applyAIRecommendations()
                                    }) {
                                        Label("Select AI Recommended (\(assessment.recommendedCategories.count))", systemImage: "wand.and.stars")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.10), Color.blue.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.purple.opacity(0.25), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
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
                            HStack(spacing: 6) {
                                Text(cat.name)
                                    .font(.headline)
                                if viewModel.aiAssessment?.recommendedCategories.contains(cat.id) == true {
                                    Label("AI Pick", systemImage: "sparkles")
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.purple.opacity(0.15))
                                        .foregroundColor(.purple)
                                        .clipShape(Capsule())
                                }
                            }
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
                .frame(height: 90)
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
        .frame(minWidth: 680, minHeight: 580)
        .onAppear {
            viewModel.scan()
        }
        .sheet(isPresented: $viewModel.showAbout) {
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
            
            Text("A lightweight, high-performance macOS utility powered by Apple Intelligence to evaluate storage health and safely remove caches, temporary files, and logs.")
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

#if !TESTING
@main
#endif
struct CleanupApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
    }
}
