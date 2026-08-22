import AppKit
import SwiftUI

struct LocalApplication: Identifiable {
    let id: String
    let bundleIdentifier: String
    let displayName: String
    let bundleURL: URL
    let icon: NSImage
    let version: String?
    var isFavorite: Bool
    var lastLaunchedAt: Date?
    var launchCount: Int

    var relativeLaunchTime: String {
        guard let lastLaunchedAt else { return "尚未启动" }
        let seconds = max(0, Date().timeIntervalSince(lastLaunchedAt))
        if seconds < 60 { return "刚刚" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) 小时前" }
        return lastLaunchedAt.formatted(.dateTime.month().day())
    }
}

@MainActor
final class ApplicationsModel: ObservableObject {
    @Published private(set) var applications: [LocalApplication] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var query = ""

    private enum Key {
        static let favorites = "applications.favorites"
        static let lastLaunch = "applications.lastLaunch"
        static let launchCount = "applications.launchCount"
    }

    private let defaults: UserDefaults
    private var favoriteIDs: Set<String>
    private var lastLaunchByID: [String: Double]
    private var launchCountByID: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favoriteIDs = Set(defaults.stringArray(forKey: Key.favorites) ?? [])
        lastLaunchByID = defaults.dictionary(forKey: Key.lastLaunch)?.reduce(into: [:]) { result, pair in
            if let value = pair.value as? Double { result[pair.key] = value }
            else if let value = pair.value as? NSNumber { result[pair.key] = value.doubleValue }
        } ?? [:]
        launchCountByID = defaults.dictionary(forKey: Key.launchCount)?.reduce(into: [:]) { result, pair in
            if let value = pair.value as? Int { result[pair.key] = value }
            else if let value = pair.value as? NSNumber { result[pair.key] = value.intValue }
        } ?? [:]
    }

    var filteredApplications: [LocalApplication] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return applications }
        return applications.filter {
            $0.displayName.localizedCaseInsensitiveContains(needle)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(needle)
        }
    }

    var favoriteApplications: [LocalApplication] {
        applications.filter(\.isFavorite)
    }

    var recentApplications: [LocalApplication] {
        applications
            .filter { $0.lastLaunchedAt != nil }
            .sorted { ($0.lastLaunchedAt ?? .distantPast) > ($1.lastLaunchedAt ?? .distantPast) }
    }

    func loadIfNeeded() {
        guard applications.isEmpty, !isLoading else { return }
        reload()
    }

    func reload() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let records = ApplicationCatalog.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.applications = records.map { record in
                    let lastLaunch = self.lastLaunchByID[record.id].map(Date.init(timeIntervalSince1970:))
                    return LocalApplication(
                        id: record.id,
                        bundleIdentifier: record.bundleIdentifier,
                        displayName: record.displayName,
                        bundleURL: record.url,
                        icon: NSWorkspace.shared.icon(forFile: record.url.path),
                        version: record.version,
                        isFavorite: self.favoriteIDs.contains(record.id),
                        lastLaunchedAt: lastLaunch,
                        launchCount: self.launchCountByID[record.id] ?? 0
                    )
                }
                self.isLoading = false
                if records.isEmpty {
                    self.errorMessage = "未在本机应用目录中找到可启动应用"
                }
            }
        }
    }

    func toggleFavorite(_ application: LocalApplication) {
        if favoriteIDs.contains(application.id) {
            favoriteIDs.remove(application.id)
        } else {
            favoriteIDs.insert(application.id)
        }
        defaults.set(favoriteIDs.sorted(), forKey: Key.favorites)
        updateApplication(id: application.id) { item in
            item.isFavorite = favoriteIDs.contains(application.id)
        }
    }

    func launch(_ application: LocalApplication) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: application.bundleURL, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.errorMessage = "无法启动 \(application.displayName)：\(error.localizedDescription)"
                    return
                }
                self.errorMessage = nil
                let timestamp = Date().timeIntervalSince1970
                self.lastLaunchByID[application.id] = timestamp
                self.launchCountByID[application.id, default: 0] += 1
                self.defaults.set(self.lastLaunchByID, forKey: Key.lastLaunch)
                self.defaults.set(self.launchCountByID, forKey: Key.launchCount)
                self.updateApplication(id: application.id) { item in
                    item.lastLaunchedAt = Date(timeIntervalSince1970: timestamp)
                    item.launchCount = self.launchCountByID[application.id] ?? item.launchCount
                }
            }
        }
    }

    private func updateApplication(id: String, mutate: (inout LocalApplication) -> Void) {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        mutate(&applications[index])
    }
}

private struct ApplicationRecord {
    let id: String
    let bundleIdentifier: String
    let displayName: String
    let url: URL
    let version: String?
}

private enum ApplicationCatalog {
    static func scan() -> [ApplicationRecord] {
        let manager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]
        var recordsByID: [String: ApplicationRecord] = [:]

        for root in roots where manager.fileExists(atPath: root.path) {
            let keys: [URLResourceKey] = [.isDirectoryKey, .isApplicationKey, .isPackageKey]
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                guard let record = makeRecord(url: url) else { continue }
                if recordsByID[record.id] == nil {
                    recordsByID[record.id] = record
                }
            }
        }

        return recordsByID.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private static func makeRecord(url: URL) -> ApplicationRecord? {
        guard let bundle = Bundle(url: url) else { return nil }
        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundleIdentifier = bundle.bundleIdentifier ?? url.standardizedFileURL.path
        let id = bundle.bundleIdentifier ?? "path:\(url.standardizedFileURL.path)"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return ApplicationRecord(
            id: id,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            url: url,
            version: version
        )
    }
}

struct ApplicationsView: View {
    @ObservedObject var model: ApplicationsModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool

    var body: some View {
        let theme = ClipFlowTheme(scheme: colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本机应用")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.muted)
                    Text("应用程序")
                        .font(.system(size: 18, weight: .semibold))
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.muted)
                    TextField("搜索应用…", text: $model.query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .accessibilityLabel("搜索应用")
                    if !model.query.isEmpty {
                        Button {
                            model.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(theme.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空应用搜索")
                    }
                }
                .padding(.horizontal, 11)
                .frame(width: 260, height: 34)
                .background(theme.chip)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.hairline, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 18)
            .frame(height: 72)

            Divider().overlay(theme.weakHairline)

            GeometryReader { proxy in
                HStack(spacing: 0) {
                    favoritesPane(theme)
                        .frame(width: proxy.size.width < 720 ? 168 : 220)
                    Divider().overlay(theme.hairline)
                    allApplicationsPane(theme)
                }
            }
        }
        .onAppear { model.loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .jaimoFocusApplicationSearch)) { _ in
            searchFocused = true
        }
    }

    private func favoritesPane(_ theme: ClipFlowTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("常用")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.muted)
                .padding(.horizontal, 7)
                .padding(.bottom, 8)

            if model.favoriteApplications.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "star")
                        .font(.system(size: 18))
                    Text("还没有常用应用")
                        .font(.system(size: 11.5))
                    Text("在右侧收藏后会显示在这里。")
                        .font(.system(size: 10.5))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(14)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 3) {
                        ForEach(model.favoriteApplications) { application in
                            Button {
                                model.launch(application)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(nsImage: application.icon)
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: 30, height: 30)
                                    Text(application.displayName)
                                        .font(.system(size: 11.5))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(7)
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(ApplicationRowButtonStyle())
                            .accessibilityLabel("启动 \(application.displayName)")
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(theme.glassSecondary.opacity(0.64))
    }

    private func allApplicationsPane(_ theme: ClipFlowTheme) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("全部应用")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("\(model.filteredApplications.count) 个应用")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.muted)
                    .monospacedDigit()
                Button(action: model.reload) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(ApplicationSmallButtonStyle())
                .accessibilityLabel("重新扫描应用")
                .help("重新扫描应用")
                .disabled(model.isLoading)
            }
            .padding(.bottom, 12)

            if let errorMessage = model.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(errorMessage)
                        .lineLimit(2)
                    Spacer()
                }
                .font(.system(size: 11))
                .foregroundStyle(theme.danger)
                .padding(10)
                .background(theme.danger.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 10)
            }

            if model.isLoading {
                applicationSkeleton(theme)
            } else if model.filteredApplications.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 22))
                    Text(model.query.isEmpty ? "没有可用的应用" : "没有匹配的应用")
                        .font(.system(size: 13))
                    if !model.query.isEmpty {
                        Button("清空搜索") { model.query = "" }
                            .buttonStyle(GlassButtonStyle(kind: .normal))
                            .fixedSize()
                    }
                }
                .foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 9)], spacing: 9) {
                        ForEach(model.filteredApplications) { application in
                            ApplicationTile(application: application, model: model)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(17)
    }

    private func applicationSkeleton(_ theme: ClipFlowTheme) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 9)], spacing: 9) {
            ForEach(0..<12, id: \.self) { _ in
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.skeleton)
                        .frame(width: 48, height: 48)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.skeleton)
                        .frame(width: 58, height: 8)
                }
                .frame(height: 88)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityLabel("正在扫描本机应用")
    }
}

private struct ApplicationTile: View {
    let application: LocalApplication
    @ObservedObject var model: ApplicationsModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        let theme = ClipFlowTheme(scheme: colorScheme)
        ZStack(alignment: .topTrailing) {
            Button {
                model.launch(application)
            } label: {
                VStack(spacing: 8) {
                    Image(nsImage: application.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                    Text(application.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.foregroundSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, minHeight: 88)
                .padding(.horizontal, 6)
                .padding(.vertical, 7)
                .contentShape(RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("启动 \(application.displayName)")

            if hovering || application.isFavorite {
                Button {
                    model.toggleFavorite(application)
                } label: {
                    Image(systemName: application.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(application.isFavorite ? theme.star : theme.muted)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(ApplicationSmallButtonStyle())
                .accessibilityLabel(application.isFavorite ? "取消收藏 \(application.displayName)" : "收藏 \(application.displayName)")
                .help(application.isFavorite ? "取消收藏" : "收藏")
                .padding(4)
            }
        }
        .background(hovering ? theme.chip : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(hovering ? theme.hairline : .clear, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .onHover { hovering = $0 }
    }
}

private struct ApplicationRowButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let theme = ClipFlowTheme(scheme: colorScheme)
        configuration.label
            .background(configuration.isPressed ? theme.chipHigh : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ApplicationSmallButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let theme = ClipFlowTheme(scheme: colorScheme)
        configuration.label
            .background(configuration.isPressed ? theme.chipHigh : theme.chip)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
