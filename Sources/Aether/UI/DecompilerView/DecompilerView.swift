import SwiftUI
import HighlightSwift

struct DecompilerView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("fontName") private var fontName = "SF Mono"
    @AppStorage(SyntaxHighlightEngine.userDefaultsKey) private var syntaxHighlightEngine = SyntaxHighlightEngine.internalEngine.rawValue
    @AppStorage(DecompilerLineNumberingMode.userDefaultsKey) private var lineNumberingMode = DecompilerLineNumberingMode.allOutput.rawValue
    @State private var showEngineErrorDetails = false

    private var selectedSyntaxHighlightEngine: SyntaxHighlightEngine {
        SyntaxHighlightEngine(rawValue: syntaxHighlightEngine) ?? .internalEngine
    }

    private var selectedLineNumberingMode: DecompilerLineNumberingMode {
        DecompilerLineNumberingMode(rawValue: lineNumberingMode) ?? .allOutput
    }

    private var nextSyntaxHighlightEngine: SyntaxHighlightEngine {
        selectedSyntaxHighlightEngine == .internalEngine ? .highlightSwift : .internalEngine
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.plaintext")
                    .foregroundColor(.accent)
                Text("Decompiler")
                    .font(.headline)
                Text("Backend: \(appState.activeDecompilerBackendName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if hasFunctionReferences(appState.decompilerOutput, appState: appState) {
                    Text("Use Jump on call lines")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                if appState.canNavigateDecompilerBack {
                    Menu {
                        ForEach(appState.decompilerJumpHistoryItems, id: \.startAddress) { function in
                            Button(function.displayName) {
                                appState.navigateDecompilerHistory(to: function.startAddress)
                            }
                        }
                    } label: {
                        Label("Back", systemImage: "arrow.uturn.backward")
                    }
                    primaryAction: {
                        appState.navigateDecompilerBack()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Click to jump back to the previous decompiler function, or open the menu for older history")
                }

                if appState.isCurrentFileJava {
                    Button("Switch to \(appState.nextJavaDecompilerBackendName)") {
                        appState.switchToNextJavaDecompilerBackend()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!appState.canSwitchToNextJavaDecompilerBackend)
                    .help(appState.canSwitchToNextJavaDecompilerBackend ? "Switch Java decompiler backend" : "Alternative backend is unavailable")
                } else {
                    Button("Switch to \(appState.nextBinaryDecompilerBackendName)") {
                        appState.switchToNextBinaryDecompilerBackend()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!appState.canSwitchToNextBinaryDecompilerBackend)
                    .help(appState.canSwitchToNextBinaryDecompilerBackend ? "Switch native/external binary decompiler backend" : "Alternative backend is unavailable")
                }

                Button("Syntax: \(selectedSyntaxHighlightEngine.displayName)") {
                    syntaxHighlightEngine = nextSyntaxHighlightEngine.rawValue
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Switch syntax highlighter to \(nextSyntaxHighlightEngine.displayName)")

                if appState.decompilerEngineError != nil {
                    Button {
                        showEngineErrorDetails = true
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Show decompiler engine error")
                }
                if appState.selectedFunction != nil {
                    Button {
                        copyToClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.sidebar)

            Divider()

            // Content
            if appState.selectedFunction == nil {
                EmptyStateView(
                    icon: "doc.plaintext",
                    title: "No Function Selected",
                    message: "Select a function to see pseudo-code"
                )
            } else if appState.decompilerOutput.isEmpty {
                VStack {
                    ProgressView()
                    Text("Decompiling...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        Group {
                            if selectedSyntaxHighlightEngine == .highlightSwift {
                                HighlightSwiftCodeView(
                                    code: appState.decompilerOutput,
                                    fontSize: fontSize,
                                    language: appState.isCurrentFileJava ? "java" : nil,
                                    lineNumberingMode: selectedLineNumberingMode
                                )
                            } else {
                                SyntaxHighlightedCode(
                                    code: appState.decompilerOutput,
                                    fontSize: fontSize,
                                    fontName: fontName,
                                    isJavaStyle: appState.isCurrentFileJava,
                                    lineNumberingMode: selectedLineNumberingMode
                                )
                            }
                        }
                        .padding(12)
                        .frame(
                            minWidth: proxy.size.width,
                            minHeight: proxy.size.height,
                            alignment: .topLeading
                        )
                    }
                }
            }
        }
        .background(Color.background)
        .sheet(isPresented: $showEngineErrorDetails) {
            DecompilerEngineErrorView(
                errorText: appState.decompilerEngineError ?? "No decompiler engine error available."
            )
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.decompilerOutput, forType: .string)
    }
}

struct HighlightSwiftCodeView: View {
    let code: String
    let fontSize: Double
    let language: String?
    let lineNumberingMode: DecompilerLineNumberingMode
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var highlightedLines: [AttributedString] = []

    private var plainLines: [String] {
        normalizedLines(from: code)
    }

    private var displayLines: [AttributedString] {
        if highlightedLines.isEmpty {
            return plainLines.map(AttributedString.init)
        }
        return highlightedLines
    }

    private var displayPlainLines: [String] {
        displayLines.map { String($0.characters) }
    }

    private var firstCodeLineIndex: Int? {
        firstFunctionContentLineIndex(in: displayPlainLines)
    }

    private var numberedLineCount: Int {
        switch lineNumberingMode {
        case .allOutput:
            return displayLines.count
        case .functionOnly:
            guard let firstCodeLineIndex else { return 0 }
            return max(displayLines.count - firstCodeLineIndex, 0)
        }
    }

    private var lineNumberColumnWidth: CGFloat {
        let count = max(numberedLineCount, 1)
        let digits = max(String(count).count, 2)
        return CGFloat(digits) * (fontSize * 0.65) + 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                let plainLine = displayPlainLines[index]
                let targetFunction = referencedFunction(in: plainLine, appState: appState)
                let semanticHelp = semanticHelperDescription(in: plainLine)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(displayLineNumber(index: index))
                        .font(.system(size: fontSize, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: lineNumberColumnWidth, alignment: .trailing)
                        .padding(.trailing, 12)
                        .textSelection(.disabled)

                    Text(line)
                        .font(.system(size: fontSize, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                        .textSelection(.enabled)
                        .modifier(OptionalHelpModifier(helpText: semanticHelp))

                    if let targetFunction {
                        JumpToFunctionButton(function: targetFunction)
                            .environmentObject(appState)
                    }

                    if let semanticHelp {
                        SemanticHelpBadge(text: semanticHelp)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: highlightTaskID) {
            await highlightCode()
        }
    }

    private var highlightTaskID: String {
        "\(code)|\(language ?? "auto")|\(colorScheme == .dark ? "dark" : "light")"
    }

    @MainActor
    private func highlightCode() async {
        guard !code.isEmpty else {
            highlightedLines = [AttributedString("")]
            return
        }

        do {
            let style = HighlightStyle(name: .xcode, colorScheme: colorScheme)
            let result = try await Highlight.text(
                code,
                language: language,
                style: style
            )
            highlightedLines = splitAttributedLines(result.attributed)
        } catch {
            highlightedLines = plainLines.map(AttributedString.init)
        }
    }

    private func splitAttributedLines(_ attributed: AttributedString) -> [AttributedString] {
        let nsAttributed = NSAttributedString(attributed)
        let text = nsAttributed.string as NSString

        if text.length == 0 {
            return [AttributedString("")]
        }

        var lines: [AttributedString] = []
        var lineStart = 0

        for index in 0..<text.length where text.character(at: index) == 10 {
            let range = NSRange(location: lineStart, length: index - lineStart)
            lines.append(AttributedString(nsAttributed.attributedSubstring(from: range)))
            lineStart = index + 1
        }

        if lineStart <= text.length {
            let range = NSRange(location: lineStart, length: text.length - lineStart)
            lines.append(AttributedString(nsAttributed.attributedSubstring(from: range)))
        }

        if lines.last == AttributedString(""), text.hasSuffix("\n") {
            lines.removeLast()
        }

        return lines.isEmpty ? [AttributedString("")] : lines
    }

    private func displayLineNumber(index: Int) -> String {
        lineNumberString(
            for: index,
            mode: lineNumberingMode,
            firstContentLine: firstCodeLineIndex
        )
    }
}

struct DecompilerEngineErrorView: View {
    let errorText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Decompiler Engine Error", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
            }

            ScrollView {
                Text(errorText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.sidebar)
            )

            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(errorText, forType: .string)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 380)
    }
}

// MARK: - Syntax Highlighted Code

struct SyntaxHighlightedCode: View {
    let code: String
    let fontSize: Double
    let fontName: String
    let isJavaStyle: Bool
    let lineNumberingMode: DecompilerLineNumberingMode
    @EnvironmentObject var appState: AppState

    private var lines: [String] {
        normalizedLines(from: code)
    }

    private var firstCodeLineIndex: Int? {
        firstFunctionContentLineIndex(in: lines)
    }

    private var numberedLineCount: Int {
        switch lineNumberingMode {
        case .allOutput:
            return lines.count
        case .functionOnly:
            guard let firstCodeLineIndex else { return 0 }
            return max(lines.count - firstCodeLineIndex, 0)
        }
    }

    private var lineNumberColumnWidth: CGFloat {
        let count = max(numberedLineCount, 1)
        let digits = max(String(count).count, 2)
        return CGFloat(digits) * (fontSize * 0.65) + 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let targetFunction = referencedFunction(in: line, appState: appState)
                let semanticHelp = semanticHelperDescription(in: line)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    // Line number
                    Text(displayLineNumber(index: index))
                        .font(.system(size: fontSize, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: lineNumberColumnWidth, alignment: .trailing)
                        .padding(.trailing, 12)

                    // Code line
                    highlightedLine(String(line))
                        .modifier(OptionalHelpModifier(helpText: semanticHelp))

                    if let targetFunction {
                        JumpToFunctionButton(function: targetFunction)
                            .environmentObject(appState)
                    }

                    if let semanticHelp {
                        SemanticHelpBadge(text: semanticHelp)
                    }
                }
            }
        }
    }

    private func highlightedLine(_ line: String) -> some View {
        var attributedParts: [(String, Color)] = []

        // Simple tokenizer for C-like and Java-like syntax
        let baseKeywords = Set([
            "if", "else", "while", "for", "return", "break", "continue", "switch", "case", "default"
        ])
        let cKeywords = Set([
            "void", "int", "char", "long", "short", "unsigned", "signed", "const",
            "static", "struct", "enum", "typedef", "goto"
        ])
        let javaKeywords = Set([
            "package", "import", "class", "interface", "enum", "extends", "implements",
            "public", "private", "protected", "static", "final", "abstract", "native",
            "synchronized", "transient", "volatile", "strictfp", "new", "this", "super",
            "throws", "throw", "try", "catch", "finally", "instanceof", "assert",
            "record", "sealed", "permits", "var", "true", "false", "null"
        ])

        let cTypes = Set([
            "int", "void", "char", "long", "short", "unsigned", "signed",
            "uint8_t", "uint16_t", "uint32_t", "uint64_t",
            "int8_t", "int16_t", "int32_t", "int64_t"
        ])
        let javaTypes = Set([
            "boolean", "byte", "short", "int", "long", "float", "double", "char", "void",
            "String", "Object", "Integer", "Long", "Double", "Boolean", "Character",
            "List", "Set", "Map", "Optional", "Class"
        ])

        let keywords = isJavaStyle ? baseKeywords.union(javaKeywords) : baseKeywords.union(cKeywords)
        let types = isJavaStyle ? javaTypes : cTypes

        var remaining = line[...]

        while !remaining.isEmpty {
            // Skip whitespace
            if remaining.first?.isWhitespace == true {
                var ws = ""
                while let char = remaining.first, char.isWhitespace {
                    ws.append(char)
                    remaining = remaining.dropFirst()
                }
                attributedParts.append((ws, .primary))
                continue
            }

            // Comment
            if remaining.hasPrefix("//") {
                attributedParts.append((String(remaining), .commentColor))
                break
            }

            // Java annotation
            if remaining.hasPrefix("@") {
                var annotation = "@"
                remaining = remaining.dropFirst()
                while let char = remaining.first, char.isLetter || char.isNumber || char == "_" || char == "." {
                    annotation.append(char)
                    remaining = remaining.dropFirst()
                }
                attributedParts.append((annotation, .accent))
                continue
            }

            // String literal
            if remaining.hasPrefix("\"") {
                var str = "\""
                remaining = remaining.dropFirst()
                while let char = remaining.first {
                    str.append(char)
                    remaining = remaining.dropFirst()
                    if char == "\"" && !str.hasSuffix("\\\"") {
                        break
                    }
                }
                attributedParts.append((str, .stringColor))
                continue
            }

            // Number (hex or decimal)
            if remaining.first?.isNumber == true || (remaining.hasPrefix("0x")) {
                var num = ""
                if remaining.hasPrefix("0x") {
                    num = "0x"
                    remaining = remaining.dropFirst(2)
                    while let char = remaining.first, char.isHexDigit {
                        num.append(char)
                        remaining = remaining.dropFirst()
                    }
                } else {
                    while let char = remaining.first, char.isNumber {
                        num.append(char)
                        remaining = remaining.dropFirst()
                    }
                }
                attributedParts.append((num, .immediateColor))
                continue
            }

            // Identifier or keyword
            if remaining.first?.isLetter == true || remaining.first == "_" {
                var ident = ""
                while let char = remaining.first, char.isLetter || char.isNumber || char == "_" {
                    ident.append(char)
                    remaining = remaining.dropFirst()
                }

                if keywords.contains(ident) {
                    attributedParts.append((ident, .keywordColor))
                } else if types.contains(ident) {
                    attributedParts.append((ident, .typeColor))
                } else if ident.hasPrefix("arg") || ident.hasPrefix("var_") || ident.hasPrefix("result") {
                    attributedParts.append((ident, .registerColor))
                } else if ident.hasPrefix("sub_") || ident.hasPrefix("loc_") {
                    attributedParts.append((ident, .accent))
                } else {
                    attributedParts.append((ident, .primary))
                }
                continue
            }

            // Operators and punctuation
            let char = remaining.first!
            attributedParts.append((String(char), .operatorColor))
            remaining = remaining.dropFirst()
        }

        return HStack(spacing: 0) {
            ForEach(Array(attributedParts.enumerated()), id: \.offset) { _, part in
                Text(part.0)
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundColor(part.1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func displayLineNumber(index: Int) -> String {
        lineNumberString(
            for: index,
            mode: lineNumberingMode,
            firstContentLine: firstCodeLineIndex
        )
    }
}

private struct JumpToFunctionButton: View {
    let function: Function
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            appState.jumpToFunction(function)
        } label: {
            Label("Jump", systemImage: "arrow.up.forward.square")
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .padding(.leading, 8)
        .help("Jump to \(function.displayName)")
    }
}

private func normalizedLines(from code: String) -> [String] {
    let splitLines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard !splitLines.isEmpty else {
        return [""]
    }

    if splitLines.last == "", code.hasSuffix("\n") {
        return Array(splitLines.dropLast())
    }

    return splitLines
}

private func firstFunctionContentLineIndex(in lines: [String]) -> Int? {
    for (index, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("//") {
            continue
        }
        return index
    }
    return nil
}

private func lineNumberString(
    for index: Int,
    mode: DecompilerLineNumberingMode,
    firstContentLine: Int?
) -> String {
    switch mode {
    case .allOutput:
        return "\(index + 1)"
    case .functionOnly:
        guard let firstContentLine, index >= firstContentLine else {
            return ""
        }
        return "\(index - firstContentLine + 1)"
    }
}

@MainActor
private func referencedFunction(in line: String, appState: AppState) -> Function? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else {
        return nil
    }

    let pattern = #"\b([A-Za-z_][A-Za-z0-9_]*)\s*\("#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }

    let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
    let keywords: Set<String> = ["if", "while", "for", "switch", "return", "sizeof"]

    for match in matches {
        guard match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: line) else {
            continue
        }

        let candidate = String(line[range])
        if keywords.contains(candidate) {
            continue
        }

        if let function = appState.resolveFunctionReference(named: candidate) {
            if function.startAddress == appState.selectedFunction?.startAddress {
                continue
            }
            return function
        }
    }

    return nil
}

@MainActor
private func hasFunctionReferences(_ code: String, appState: AppState) -> Bool {
    normalizedLines(from: code).contains { referencedFunction(in: $0, appState: appState) != nil }
}

private struct OptionalHelpModifier: ViewModifier {
    let helpText: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let helpText {
            content.help(helpText)
        } else {
            content
        }
    }
}

private struct SemanticHelpBadge: View {
    let text: String
    @State private var showPopover = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.leading, 8)
            .onHover { hovering in
                showPopover = hovering
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                Text(text)
                    .font(.system(.body))
                    .frame(maxWidth: 320, alignment: .leading)
                    .padding(12)
            }
            .help("Show helper explanation")
    }
}

private func semanticHelperDescription(in line: String) -> String? {
    let helperDescriptions: [(String, String)] = [
        ("clear_direction_flag(", "Clears the CPU direction flag so string instructions advance forward."),
        ("set_direction_flag(", "Sets the CPU direction flag so string instructions run backward."),
        ("disable_interrupts(", "Clears the interrupt-enable flag so maskable hardware interrupts are temporarily blocked."),
        ("enable_interrupts(", "Sets the interrupt-enable flag so maskable hardware interrupts are accepted again."),
        ("bios_get_video_state(", "BIOS INT 10h AH=0Fh: reads the current video mode, text columns, and active page."),
        ("bios_set_video_mode(", "BIOS INT 10h AH=00h: switches the display adapter into the requested video mode."),
        ("bios_set_cursor_shape(", "BIOS INT 10h AH=01h: changes the text-mode cursor start and end scanlines."),
        ("bios_set_cursor_position(", "BIOS INT 10h AH=02h: moves the text cursor to the given page, row, and column."),
        ("bios_scroll_up_window(", "BIOS INT 10h AH=06h: scrolls or clears a rectangular text window."),
        ("bios_write_char_attr(", "BIOS INT 10h AH=09h: writes a character with a text attribute at the cursor."),
        ("bios_teletype_output(", "BIOS INT 10h AH=0Eh: prints one character and advances the cursor."),
        ("bios_read_key(", "BIOS INT 16h AH=00h: waits for a keypress and returns ASCII in AL and scan code in AH."),
        ("dos_exit(", "DOS INT 21h AH=4Ch: terminates the program and returns the given exit code."),
        ("dos_print_string(", "DOS INT 21h AH=09h: prints a '$'-terminated string from DS:DX."),
        ("port_out8(", "Writes one byte to an I/O port, typically to program hardware registers directly."),
        ("port_out16(", "Writes one 16-bit word to an I/O port, typically to program hardware registers directly."),
        ("fill_words(", "Stores the same 16-bit value repeatedly, like a `rep stosw` memory fill."),
        ("load_word_and_advance(", "Loads a 16-bit word from DS:SI and advances SI, matching `lodsw`."),
        ("load_byte_and_advance(", "Loads a byte from DS:SI and advances SI, matching `lodsb`."),
        ("MK_FP(", "Builds a real-mode far pointer from a segment and offset pair.")
    ]

    for (marker, description) in helperDescriptions where line.contains(marker) {
        return description
    }

    return nil
}

// MARK: - Character Extensions

extension Character {
    var isHexDigit: Bool {
        isNumber || ("a"..."f").contains(lowercased().first!) || ("A"..."F").contains(self)
    }
}
