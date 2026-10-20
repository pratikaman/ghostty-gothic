import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) var openURL

    private let githubURL = URL(string: "https://github.com/ghostty-org/ghostty")
    private let docsURL = URL(string: "https://ghostty.org/docs")

    /// Read the commit from the bundle.
    private var build: String? { Bundle.main.infoDictionary?["CFBundleVersion"] as? String }
    private var commit: String? { Bundle.main.infoDictionary?["GhosttyCommit"] as? String }
    private var version: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }

    private enum VersionConfig {
        case stable(version: String)
        case tip(commit: String?)
        case other(String)
        case none

        init(version: String?) {
            guard let version else { self = .none; return }
            if version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil {
                self = .stable(version: version)
                return
            }
            if version.range(of: #"^[0-9a-f]{7,40}$"#, options: .regularExpression) != nil {
                self = .tip(commit: version)
                return
            }
            self = .other(version)
        }

        var url: URL? {
            switch self {
            case .stable(let version):
                let slug = version.replacingOccurrences(of: ".", with: "-")
                return URL(string: "https://ghostty.org/docs/install/release-notes/\(slug)")
            default:
                return nil
            }
        }
    }

    private var versionConfig: VersionConfig { VersionConfig(version: version) }

    private var copyright: String? { Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String }

    // Ghostty Gothic: the About window is an illuminated manuscript page.
    private let forkURL = URL(string: "https://github.com/pratikaman/ghostty-gothic")
    private static let ink = Color(nsColor: Gothic.ink)
    private static let rubric = Color(nsColor: Gothic.ruby).opacity(0.95)
    private static let gilt = Color(nsColor: Gothic.gilt)

    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(height: 112)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                .accessibilityLabel("Ghostty Gothic Application Icon")

            // An illuminated initial opening the title, as on a folio.
            HStack(alignment: .bottom, spacing: 2) {
                if let initial = Gothic.image("initial-G") {
                    Image(nsImage: initial)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                } else {
                    Text("G").font(.custom("GrenzeGotisch-Medium", size: 46)).foregroundStyle(Self.rubric)
                }
                Text("hostty Gothic")
                    .font(.custom("GrenzeGotisch-Medium", size: 38))
                    .foregroundStyle(Self.ink)
                    .padding(.bottom, -4)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ghostty Gothic")

            Text("A fast, native terminal emulator,\nwrought in stone and stained glass.")
                .font(.system(size: 12, design: .serif).italic())
                .foregroundStyle(Self.ink.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Text("✠").font(.system(size: 13)).foregroundStyle(Self.rubric)

            VStack(spacing: 3) {
                switch versionConfig {
                case .stable(let version):
                    PropertyRow(label: "Version", text: version, url: versionConfig.url)
                case .tip:
                    PropertyRow(label: "Version", text: "Tip Release")
                case .other(let v):
                    PropertyRow(label: "Version", text: v)
                case .none:
                    EmptyView()
                }
                if let build {
                    PropertyRow(label: "Build", text: build)
                }
                if let commit, commit != "",
                   let url = githubURL?.appendingPathComponent("/commits/\(commit)") {
                    PropertyRow(label: "Commit", text: commit, url: url)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                link("Docs", docsURL)
                Text("·").foregroundStyle(Self.rubric)
                link("Ghostty", githubURL)
                Text("·").foregroundStyle(Self.rubric)
                link("This Fork", forkURL)
            }

            if let copy = self.copyright {
                Text(copy)
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(Self.ink.opacity(0.65))
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 44)
        .padding(.bottom, 34)
        .frame(minWidth: 340)
        .background(page.ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }

    private func link(_ title: String, _ url: URL?) -> some View {
        Button(title) { if let url { openURL(url) } }
            .buttonStyle(.plain)
            .font(.custom("GrenzeGotisch-Medium", size: 17))
            .foregroundStyle(Self.rubric)
    }

    /// Vellum with a ruled border: a gilt rule inside a rubric one.
    private var page: some View {
        ZStack {
            if let vellum = Gothic.image("parchment") {
                Image(nsImage: vellum).resizable().scaledToFill()
            } else {
                Color(nsColor: Gothic.parchment)
            }
            Rectangle()
                .strokeBorder(Self.rubric.opacity(0.7), lineWidth: 1.5)
                .padding(12)
            Rectangle()
                .strokeBorder(Self.gilt.opacity(0.8), lineWidth: 1)
                .padding(16)
        }
    }

    private struct PropertyRow: View {
        private let label: String
        private let text: String
        private let url: URL?

        init(label: String, text: String, url: URL? = nil) {
            self.label = label
            self.text = text
            self.url = url
        }

        @ViewBuilder private var textView: some View {
            Text(text)
                .frame(width: 125, alignment: .leading)
                .padding(.leading, 2)
                .foregroundStyle(AboutView.ink.opacity(0.85))
                .font(.system(size: 12, design: .serif))
        }

        var body: some View {
            HStack(spacing: 4) {
                // Rubricated labels, as in a manuscript.
                Text(label)
                    .font(.custom("GrenzeGotisch-Medium", size: 15))
                    .foregroundStyle(AboutView.rubric)
                    .frame(width: 126, alignment: .trailing)
                    .padding(.trailing, 2)
                if let url {
                    Link(destination: url) {
                        textView
                    }
                } else {
                    textView
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
        }
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
