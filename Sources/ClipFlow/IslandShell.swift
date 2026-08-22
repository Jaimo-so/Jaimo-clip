import AppKit
import SwiftUI

enum ToolDestination: String, CaseIterable, Identifiable {
    case home
    case applications
    case prompts
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .applications: return "应用"
        case .prompts: return "提示词"
        case .clipboard: return "剪切板"
        }
    }

    var symbolName: String {
        switch self {
        case .home: return "house"
        case .applications: return "square.grid.2x2"
        case .prompts: return "sparkles"
        case .clipboard: return "doc.on.clipboard"
        }
    }
}

@MainActor
final class IslandShellModel: ObservableObject {
    @Published var destination: ToolDestination {
        didSet { defaults.set(destination.rawValue, forKey: Self.destinationKey) }
    }

    private static let destinationKey = "island.lastDestination"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        destination = ToolDestination(rawValue: defaults.string(forKey: Self.destinationKey) ?? "") ?? .home
    }
}

struct IslandRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shell: IslandShellModel
    @ObservedObject var homeModel: HomeDashboardModel
    @ObservedObject var applicationsModel: ApplicationsModel
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let theme = ClipFlowTheme(scheme: colorScheme)
        ZStack {
            VisualEffectBackground().ignoresSafeArea()
            theme.glass.opacity(colorScheme == .dark ? 0.92 : 0.96).ignoresSafeArea()

            expandedContent(theme)
                .disabled(model.settingsOpen)

            if model.settingsOpen {
                SettingsView(model: model)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.975)))
                    .zIndex(30)
            }

            if let message = model.toastMessage {
                IslandToast(message: message)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(40)
            }
        }
        .foregroundStyle(theme.foreground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke((colorScheme == .dark ? Color.white : Color.black).opacity(0.16), lineWidth: 0.5)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.settingsOpen)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.toastMessage)
    }

    private func expandedContent(_ theme: ClipFlowTheme) -> some View {
        VStack(spacing: 0) {
            topBar(theme)
            Divider().overlay(theme.hairline)
            destinationContent
        }
    }

    private func topBar(_ theme: ClipFlowTheme) -> some View {
        GeometryReader { proxy in
            HStack(spacing: proxy.size.width < 720 ? 8 : 18) {
                HStack(spacing: 9) {
                    IslandBrandMark(size: 30)
                    if proxy.size.width >= 720 {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Jaimo")
                                .font(.system(size: 13, weight: .semibold))
                            Text("个人工具站")
                                .font(.system(size: 9.5))
                                .foregroundStyle(theme.muted)
                        }
                    }
                }
                .padding(.leading, 2)

                HStack(spacing: 2) {
                    ForEach(ToolDestination.allCases) { destination in
                        Button {
                            selectDestination(destination)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: destination.symbolName)
                                    .font(.system(size: 14))
                                if proxy.size.width >= 650 {
                                    Text(destination.title)
                                        .font(.system(size: 12))
                                }
                            }
                            .foregroundStyle(shell.destination == destination ? theme.foreground : theme.muted)
                            .frame(minWidth: proxy.size.width >= 650 ? 70 : 42, maxHeight: .infinity)
                            .background(shell.destination == destination ? theme.chip : Color.clear)
                            .overlay(alignment: .bottom) {
                                if shell.destination == destination {
                                    Capsule()
                                        .fill(theme.accent)
                                        .frame(height: 2)
                                        .padding(.horizontal, 14)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(destination.title)
                        .accessibilityAddTraits(shell.destination == destination ? [.isSelected] : [])
                    }
                }
                .frame(maxHeight: .infinity)

                Spacer(minLength: 4)

                HStack(spacing: 3) {
                    Button {
                        model.settingsOpen = true
                    } label: {
                        Image(systemName: "gearshape")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(IslandIconButtonStyle())
                    .accessibilityLabel("打开设置")
                    .help("设置（⌘,）")

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(IslandIconButtonStyle())
                    .accessibilityLabel("关闭工具站")
                    .help("关闭工具站（Esc）")
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 61)
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch shell.destination {
        case .home:
            HomeDashboardView(
                model: homeModel,
                applicationsModel: applicationsModel,
                onOpenApplications: { selectDestination(.applications) }
            )
        case .applications:
            ApplicationsView(model: applicationsModel)
        case .prompts:
            ContentView(model: model, fixedMode: .prompts, embedded: true)
                .id("prompts-library")
        case .clipboard:
            ContentView(model: model, fixedMode: .history, embedded: true)
                .id("clipboard-library")
        }
    }

    private func selectDestination(_ destination: ToolDestination) {
        shell.destination = destination
        switch destination {
        case .prompts: model.setMode(.prompts)
        case .clipboard: model.setMode(.history)
        case .home, .applications: break
        }
    }
}

private struct IslandBrandMark: View {
    let size: CGFloat

    var body: some View {
        Text("J")
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.76))
            .frame(width: size, height: size)
            .background(ClipFlowTheme(scheme: .dark).accent)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

private struct IslandIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let theme = ClipFlowTheme(scheme: colorScheme)
        configuration.label
            .foregroundStyle(theme.foregroundSecondary)
            .background(configuration.isPressed ? theme.chipHigh : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct IslandToast: View {
    let message: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = ClipFlowTheme(scheme: colorScheme)
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.foreground)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .background(theme.glass.opacity(0.98))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.hairline, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: .black.opacity(0.34), radius: 16, y: 8)
                .padding(.bottom, shellToastBottomPadding)
                .accessibilityLabel(message)
                .accessibilityAddTraits(.updatesFrequently)
        }
        .allowsHitTesting(false)
    }

    private var shellToastBottomPadding: CGFloat { 24 }
}

extension Notification.Name {
    static let jaimoFocusQuickNote = Notification.Name("jaimo.focusQuickNote")
    static let jaimoStartCamera = Notification.Name("jaimo.startCamera")
    static let jaimoFocusApplicationSearch = Notification.Name("jaimo.focusApplicationSearch")
}
