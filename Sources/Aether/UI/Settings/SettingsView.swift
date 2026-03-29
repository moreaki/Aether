import SwiftUI
import Security

struct DecompilerSettingsTab: View {
    @AppStorage(SyntaxHighlightEngine.userDefaultsKey) private var syntaxEngine = SyntaxHighlightEngine.internalEngine.rawValue
    @AppStorage(DecompilerLineNumberingMode.userDefaultsKey) private var lineNumberingMode = DecompilerLineNumberingMode.allOutput.rawValue
    @AppStorage(BinaryDecompilerBackend.userDefaultsKey) private var binaryBackend = BinaryDecompilerBackend.native.rawValue
    @State private var radare2Path: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "highlighter")
                    .font(.title2)
                    .foregroundColor(.blue)
                VStack(alignment: .leading) {
                    Text(translate("settings.decompiler.title"))
                        .font(.headline)
                    Text(translate("settings.decompiler.subtitle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(translate("settings.decompiler.syntaxEngine"))
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("", selection: $syntaxEngine) {
                    Text(translate("settings.decompiler.syntax.internal"))
                        .tag(SyntaxHighlightEngine.internalEngine.rawValue)
                    Text(translate("settings.decompiler.syntax.highlightswift"))
                        .tag(SyntaxHighlightEngine.highlightSwift.rawValue)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Binary Decompiler Backend")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("", selection: $binaryBackend) {
                    Text("Native")
                        .tag(BinaryDecompilerBackend.native.rawValue)
                    if radare2Path != nil {
                        Text("radare2")
                            .tag(BinaryDecompilerBackend.radare2.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("radare2 Status")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Button("Refresh") {
                        refreshRadare2Status()
                    }
                }

                if let radare2Path {
                    Label("radare2 available", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text(radare2Path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                } else {
                    Label("radare2 not found", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("Native remains the default when the external backend is unavailable.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(translate("settings.decompiler.lineNumbers"))
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("", selection: $lineNumberingMode) {
                    Text(translate("settings.decompiler.lineNumbers.allOutput"))
                        .tag(DecompilerLineNumberingMode.allOutput.rawValue)
                    Text(translate("settings.decompiler.lineNumbers.functionOnly"))
                        .tag(DecompilerLineNumberingMode.functionOnly.rawValue)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label(translate("settings.decompiler.info.internal"), systemImage: "hammer")
                    .font(.caption)
                Label("radare2 can provide alternate DOS pseudocode when available.", systemImage: "terminal")
                    .font(.caption)
                Label(translate("settings.decompiler.info.highlightswift"), systemImage: "paintbrush.pointed")
                    .font(.caption)
                Label(translate("settings.decompiler.info.lineNumbers"), systemImage: "list.number")
                    .font(.caption)
                Label(translate("settings.decompiler.info.headerToggle"), systemImage: "arrow.left.arrow.right")
                    .font(.caption)
            }
            .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .onAppear {
            refreshRadare2Status()
        }
    }

    private func refreshRadare2Status() {
        radare2Path = Radare2Decompiler.findExecutablePath()
        if radare2Path == nil && binaryBackend == BinaryDecompilerBackend.radare2.rawValue {
            binaryBackend = BinaryDecompilerBackend.native.rawValue
        }
    }
}

struct JavaDecompilerSettingsTab: View {
    @AppStorage(JavaDecompilerBackend.userDefaultsKey) private var selectedBackend = JavaDecompilerBackend.internalEngine.rawValue
    @State private var vineflowerPath: String?

    private var resolvedBackend: JavaDecompilerBackend {
        JavaDecompilerBackend(rawValue: selectedBackend) ?? .internalEngine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                VStack(alignment: .leading) {
                    Text(translate("settings.java.title"))
                        .font(.headline)
                    Text(translate("settings.java.subtitle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(translate("settings.java.backend"))
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("", selection: $selectedBackend) {
                    Text(translate("settings.java.backend.internal"))
                        .tag(JavaDecompilerBackend.internalEngine.rawValue)

                    if vineflowerPath != nil {
                        Text(translate("settings.java.backend.vineflower"))
                            .tag(JavaDecompilerBackend.vineflower.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(translate("settings.java.vineflowerStatus"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Button(translate("settings.java.refresh")) {
                        refreshVineflowerStatus()
                    }
                }

                if let vineflowerPath {
                    Label(translate("settings.java.vineflowerFound"), systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text(vineflowerPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                } else {
                    Label(translate("settings.java.vineflowerMissing"), systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text(translate("settings.java.vineflowerHint"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label(translate("settings.java.info.internal"), systemImage: "swift")
                    .font(.caption)
                Label(translate("settings.java.info.vineflower"), systemImage: "terminal")
                    .font(.caption)
                if resolvedBackend == .vineflower && vineflowerPath == nil {
                    Label(translate("settings.java.info.fallback"), systemImage: "arrow.uturn.backward.circle")
                        .font(.caption)
                }
            }
            .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .onAppear {
            refreshVineflowerStatus()
        }
    }

    private func refreshVineflowerStatus() {
        vineflowerPath = VineflowerDecompiler.findExecutablePath()
        if vineflowerPath == nil && resolvedBackend == .vineflower {
            selectedBackend = JavaDecompilerBackend.internalEngine.rawValue
        }
    }
}

struct AISettingsTab: View {
    @AppStorage("aiAPIKeyConfigured") private var apiKeyConfigured = false
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var saveStatus: SaveStatus = .none
    @State private var isValidating = false

    enum SaveStatus {
        case none
        case success
        case error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "brain")
                    .font(.title2)
                    .foregroundColor(.purple)
                VStack(alignment: .leading) {
                    Text(translate("settings.ai.title"))
                        .font(.headline)
                    Text(translate("settings.ai.subtitle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if apiKeyConfigured {
                    Label(translate("settings.ai.active"), systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }

            Divider()

            // API Key Section
            VStack(alignment: .leading, spacing: 8) {
                Text(translate("settings.ai.apiKey"))
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    if showAPIKey {
                        TextField(translate("settings.ai.apiKeyPlaceholder"), text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField(translate("settings.ai.apiKeyPlaceholder"), text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }

                Text(translate("settings.ai.apiKeyHelp"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Actions
            HStack {
                Button(translate("settings.ai.saveKey")) {
                    saveAPIKey()
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty || isValidating)

                if apiKeyConfigured {
                    Button(translate("settings.ai.remove")) {
                        removeAPIKey()
                    }
                    .foregroundColor(.red)
                }

                if isValidating {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                Spacer()

                switch saveStatus {
                case .success:
                    Label(translate("settings.ai.saved"), systemImage: "checkmark.circle")
                        .foregroundColor(.green)
                        .font(.caption)
                case .error(let message):
                    Label(message, systemImage: "xmark.circle")
                        .foregroundColor(.red)
                        .font(.caption)
                case .none:
                    EmptyView()
                }
            }

            Divider()

            // Info
            VStack(alignment: .leading, spacing: 6) {
                Label(translate("settings.ai.info.analyzes"), systemImage: "shield.lefthalf.filled")
                    .font(.caption)
                Label(translate("settings.ai.info.keychain"), systemImage: "lock.shield")
                    .font(.caption)
                Label(translate("settings.ai.info.credits"), systemImage: "dollarsign.circle")
                    .font(.caption)
            }
            .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .onAppear {
            loadAPIKey()
        }
    }

    private func saveAPIKey() {
        guard !apiKey.isEmpty else { return }

        isValidating = true
        saveStatus = .none

        // Validate API key format
        guard apiKey.hasPrefix("sk-ant-") else {
            saveStatus = .error(translate("settings.ai.error.invalidFormat"))
            isValidating = false
            return
        }

        // Save to Keychain
        let result = KeychainHelper.save(key: "AIAPIKey", value: apiKey)

        isValidating = false

        if result {
            apiKeyConfigured = true
            saveStatus = .success
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                apiKey = String(repeating: "*", count: 20)
            }
        } else {
            saveStatus = .error(translate("settings.ai.error.saveFailed"))
        }
    }

    private func loadAPIKey() {
        if let savedKey = KeychainHelper.load(key: "AIAPIKey") {
            apiKey = String(repeating: "*", count: min(savedKey.count, 20))
            apiKeyConfigured = true
        }
    }

    private func removeAPIKey() {
        KeychainHelper.delete(key: "AIAPIKey")
        apiKey = ""
        apiKeyConfigured = false
        saveStatus = .none
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.aether.disassembler",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.aether.disassembler",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.aether.disassembler"
        ]

        SecItemDelete(query as CFDictionary)
    }
}
