import SwiftUI

/// Which illustration a page shows.
enum OnboardingArt {
    case welcome, hotkey, shortcuts, editor
}

/// A single onboarding card.
struct OnboardingPage: Identifiable {
    let id = UUID()
    let art: OnboardingArt
    let title: String
    let description: String
}

/// First-launch feature tour, shown as a paged sheet over the main window.
@available(macOS 14.0, *)
struct OnboardingView: View {
    let onDismiss: () -> Void

    @State private var index = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            art: .welcome,
            title: "Welcome to Peelr",
            description: "Peelr strips the background from lecture slides and photos, leaving a clean transparent PNG. Slides use fast color-keying; photos use an AI matting model."
        ),
        OnboardingPage(
            art: .hotkey,
            title: "One keystroke from anywhere",
            description: "Copy an image, press the global hotkey, then paste the transparent result into any app. The scissors icon in your menu bar does the same thing."
        ),
        OnboardingPage(
            art: .shortcuts,
            title: "Shortcuts & Quick Actions",
            description: "Automate Peelr with the “Remove Background” actions in the Shortcuts app, or right-click an image in Finder and pick Peelr from Quick Actions / Services."
        ),
        OnboardingPage(
            art: .editor,
            title: "Fine-tune in the editor",
            description: "Drag in an image, pick Auto / Slide / Photo mode, and adjust tolerance, feather, and interior protection. Compare before and after side-by-side or with hover reveal."
        ),
    ]

    private var isLastPage: Bool { index == pages.count - 1 }

    var body: some View {
        VStack(spacing: 20) {
            card(pages[index])
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { i in
                    Circle()
                        .fill(i == index ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            HStack {
                Button("Back") { index -= 1 }
                    .opacity(index == 0 ? 0 : 1)
                    .disabled(index == 0)

                Spacer()

                Button(isLastPage ? "Get Started" : "Next") {
                    if isLastPage { onDismiss() } else { index += 1 }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 520)
    }

    private func card(_ page: OnboardingPage) -> some View {
        VStack(spacing: 20) {
            illustration(page.art)
                .frame(height: 168)
                .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                Text(page.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func illustration(_ art: OnboardingArt) -> some View {
        switch art {
        case .welcome:   WelcomeArt()
        case .hotkey:    HotkeyArt(display: HotKeyStore.shared.config.display)
        case .shortcuts: QuickActionsArt()
        case .editor:    EditorArt()
        }
    }
}

// MARK: - Illustrations

/// Before → after: a slide with a solid background becomes a transparent cutout.
@available(macOS 14.0, *)
private struct WelcomeArt: View {
    var body: some View {
        HStack(spacing: 16) {
            miniCard(transparent: false)
            Image(systemName: "arrow.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            miniCard(transparent: true)
        }
    }

    private func miniCard(transparent: Bool) -> some View {
        ZStack {
            if transparent {
                Checkerboard(square: 7)
                    .fill(Color(white: 0.85))
                    .background(Color.white)
            } else {
                LinearGradient(colors: [.blue, .indigo],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 34))
                .foregroundStyle(transparent ? Color.indigo : .white)
        }
        .frame(width: 108, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }
}

/// Keycap chips for the hotkey, plus a mock menu bar highlighting the scissors icon.
@available(macOS 14.0, *)
private struct HotkeyArt: View {
    let display: String

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(Array(display.enumerated()), id: \.offset) { _, ch in
                    Keycap(String(ch))
                }
            }
            FakeMenuBar()
        }
    }
}

/// A rounded strip resembling the top-right of the macOS menu bar.
@available(macOS 14.0, *)
private struct FakeMenuBar: View {
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 14) {
                Spacer()
                Image(systemName: "scissors")
                    .foregroundStyle(.tint)
                    .padding(5)
                    .background(Circle().fill(Color.accentColor.opacity(0.18)))
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
                Text("9:41").monospacedDigit()
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))

            Text("Look for ✂ in your menu bar")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

/// A single keyboard-key chip.
@available(macOS 14.0, *)
private struct Keycap: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .frame(minWidth: 34, minHeight: 38)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
    }
}

/// A mock Finder right-click menu with Peelr's Quick Action highlighted.
@available(macOS 14.0, *)
private struct QuickActionsArt: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(label: "Open", trailing: nil, highlighted: false)
            row(label: "Get Info", trailing: nil, highlighted: false)
            Divider().padding(.vertical, 3)
            row(label: "Quick Actions", trailing: "chevron.right", highlighted: false)
            row(label: "Remove Background (Peelr)", trailing: "scissors", highlighted: true)
        }
        .padding(6)
        .frame(width: 262)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    private func row(label: String, trailing: String?, highlighted: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let trailing {
                Image(systemName: trailing).font(.system(size: 11, weight: .semibold))
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(highlighted ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(highlighted ? Color.accentColor : Color.clear)
        )
    }
}

/// Mock mode picker + slider that mirror the editor's controls.
@available(macOS 14.0, *)
private struct EditorArt: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                segment("Auto", selected: true)
                segment("Slide", selected: false)
                segment("Photo", selected: false)
            }
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary))

            VStack(alignment: .leading, spacing: 6) {
                Text("Tolerance").font(.caption).foregroundStyle(.secondary)
                fakeSlider
            }
            .frame(width: 220)
        }
        .frame(width: 240)
    }

    private func segment(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                    .padding(2)
            )
    }

    private var fakeSlider: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 4)
            Capsule().fill(Color.accentColor).frame(width: 132, height: 4)
            Circle()
                .fill(.white)
                .frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                .overlay(Circle().stroke(.quaternary))
                .offset(x: 124)
        }
    }
}
