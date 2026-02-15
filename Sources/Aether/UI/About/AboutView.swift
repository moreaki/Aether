import SwiftUI
import CryptoKit
import AppKit

struct AboutView: View {
    @State private var executableSHA256 = "Calculating..."
    @State private var isHashing = false
    @State private var showLicenseSheet = false
    @State private var licenseText = "License text is unavailable in this build."
    @State private var didLoad = false

    private let buildInfo = BuildInfo.current
    private let primaryText = Color(red: 0.95, green: 0.97, blue: 1.00)
    private let secondaryText = Color(red: 0.76, green: 0.82, blue: 0.92)
    private let accentText = Color(red: 0.66, green: 0.78, blue: 0.98)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.16),
                    Color(red: 0.04, green: 0.05, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    buildDetailsCard
                    integrityCard
                    licenseCard
                    verificationNote
                }
                .padding(20)
                .foregroundStyle(primaryText)
            }
        }
        .frame(width: 620, height: 620)
        .preferredColorScheme(.dark)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            loadLicenseText()
            refreshExecutableHash()
        }
        .sheet(isPresented: $showLicenseSheet) {
            LicenseTextView(licenseName: buildInfo.license, licenseText: licenseText)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Group {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                } else {
                    Image(systemName: "cpu.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.blue)
                        .padding(20)
                }
            }
            .frame(width: 80, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 5) {
                Text("Aether")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Beyond the binary, into the essence.")
                    .font(.subheadline)
                    .foregroundStyle(secondaryText)
                Text("Version \(buildInfo.version) (\(buildInfo.build))")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(accentText)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var buildDetailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Build Details", systemImage: "wrench.and.screwdriver")
                .font(.headline)

            AboutRow(label: "Built", value: buildInfo.timestampDisplay)
            AboutRow(label: "Source", value: buildInfo.commit)
            AboutRow(label: "Target Architecture", value: buildInfo.targetArchitecture)
            AboutRow(label: "Running Architecture", value: buildInfo.runningArchitecture)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var integrityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Integrity Fingerprint", systemImage: "checkmark.shield")
                .font(.headline)

            Text(executableSHA256)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                )

            HStack(spacing: 10) {
                Button("Copy SHA-256") {
                    copyToClipboard(executableSHA256)
                }
                .disabled(isHashing)
                .buttonStyle(.bordered)

                Button("Copy Build Report") {
                    copyToClipboard(buildReport)
                }
                .disabled(isHashing)
                .buttonStyle(.bordered)
            }

            if isHashing {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var licenseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("License", systemImage: "doc.text")
                    .font(.headline)
                Spacer(minLength: 0)
                Button("View License Text") {
                    showLicenseSheet = true
                }
                .buttonStyle(.bordered)
            }

            Text(buildInfo.license)
                .font(.callout)
                .foregroundStyle(secondaryText)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var verificationNote: some View {
        Text("Compare the SHA-256 value above with checksums published by the authoritative release source to verify this executable.")
            .font(.footnote)
            .foregroundStyle(secondaryText)
            .padding(.horizontal, 4)
    }

    private var buildReport: String {
        """
        Aether Build Report
        Version: \(buildInfo.version)
        Build: \(buildInfo.build)
        Built: \(buildInfo.timestampRaw)
        Source: \(buildInfo.commit)
        Target Architecture: \(buildInfo.targetArchitecture)
        Running Architecture: \(buildInfo.runningArchitecture)
        License: \(buildInfo.license)
        Executable SHA-256: \(executableSHA256)
        """
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.09))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }

    private func refreshExecutableHash() {
        guard !isHashing else { return }
        isHashing = true

        DispatchQueue.global(qos: .utility).async {
            let hash = Self.computeExecutableSHA256() ?? "Unavailable"
            DispatchQueue.main.async {
                executableSHA256 = hash
                isHashing = false
            }
        }
    }

    private func loadLicenseText() {
        guard let licenseURL = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: licenseURL, encoding: .utf8) else {
            return
        }
        licenseText = text
    }

    private static func computeExecutableSHA256() -> String? {
        guard let executableURL = Bundle.main.executableURL,
              let data = try? Data(contentsOf: executableURL, options: .mappedIfSafe) else {
            return nil
        }

        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct AboutRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.76, green: 0.82, blue: 0.92))
                .frame(width: 150, alignment: .leading)

            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LicenseTextView: View {
    let licenseName: String
    let licenseText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(licenseName)
                    .font(.title3.bold())
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }

            ScrollView {
                Text(licenseText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.20))
            )
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 520)
        .background(Color(red: 0.09, green: 0.10, blue: 0.14))
        .preferredColorScheme(.dark)
    }
}

private struct BuildInfo {
    let version: String
    let build: String
    let commit: String
    let timestampRaw: String
    let targetArchitecture: String
    let runningArchitecture: String
    let license: String

    var timestampDisplay: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: timestampRaw) else {
            return timestampRaw
        }

        let localFormatter = DateFormatter()
        localFormatter.dateStyle = .medium
        localFormatter.timeStyle = .medium
        localFormatter.timeZone = .current
        return "\(localFormatter.string(from: date)) (\(timestampRaw))"
    }

    static var current: BuildInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        return BuildInfo(
            version: info["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info["CFBundleVersion"] as? String ?? "unknown",
            commit: info["AetherBuildCommit"] as? String ?? "unknown",
            timestampRaw: info["AetherBuildTimestamp"] as? String ?? "unknown",
            targetArchitecture: info["AetherBuildTargetArch"] as? String ?? "unknown",
            runningArchitecture: runtimeArchitecture,
            license: info["AetherLicense"] as? String ?? "MIT License"
        )
    }

    private static var runtimeArchitecture: String {
#if arch(arm64)
        "arm64"
#elseif arch(x86_64)
        "x86_64"
#else
        "unknown"
#endif
    }
}
