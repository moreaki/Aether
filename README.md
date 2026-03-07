# Aether

<p align="center">
  <img src="img/5.png" alt="Aether - Welcome Screen" width="700">
</p>

<p align="center">
  <a href="https://github.com/Pinperepette/Aether/releases/download/v2.0.0/Aether.dmg">
    <img src="https://img.shields.io/badge/Download-v2.0.0-blue?style=for-the-badge&logo=apple" alt="Download">
  </a>
  <img src="https://img.shields.io/badge/macOS-14.0+-black?style=for-the-badge&logo=apple" alt="macOS 14.0+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=for-the-badge&logo=swift" alt="Swift 5.9">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="MIT License">
  </a>
</p>

**Aether** is a native macOS disassembler built with Swift and SwiftUI. It breaks down binaries into their purest essence — just like the ancient Greek element that permeated the cosmos.

> *"Beyond the binary, into the essence."*

## Download

**[Download Aether v2.0.0](https://github.com/Pinperepette/Aether/releases/download/v2.0.0/Aether.dmg)** — macOS 14.0 (Sonoma) or later

If the application appears corrupted or macOS displays a message stating the app is damaged, open Terminal and run the following command:

  xattr -cr /path/to/Application.app

  Replace /path/to/Application.app with the actual path to the application. This command removes extended attributes, including the quarantine flag, that may prevent the app from launching.

## What's New in v2.0.0

### Malware Analysis Dashboard
- **Threat Scoring**: Automated threat level assessment (Clean/Low/Medium/High/Critical) with 0-100 scoring
- **Malware Dashboard**: Unified view combining all analysis results in a single panel
- **Comprehensive Reports**: Detailed findings with severity levels and actionable insights

### Entropy Analysis
- **Shannon Entropy**: Calculate entropy for the entire binary and individual sections
- **Section Assessment**: Automatically flag sections as packed, encrypted, or normal
- **Entropy Heatmap**: Block-level entropy visualization to identify suspicious regions

### Indicators of Compromise (IoC) Extraction
- **URL Detection**: Extract embedded URLs from binary strings
- **IP Addresses**: Find hardcoded IPv4 addresses
- **Domains & Emails**: Identify network indicators
- **File Paths & Registry Keys**: Detect filesystem and registry artifacts
- **Crypto Wallets**: Find cryptocurrency wallet addresses
- **Mutex Names**: Extract synchronization object names

### PE Anomaly Detection
- **Section Analysis**: Detect suspicious section names (UPX, VMProtect, Themida, etc.)
- **Entropy Anomalies**: Flag sections with abnormally high entropy
- **Severity Classification**: Anomalies rated as Low/Medium/High/Critical

### Packer Detection
- **Signature Matching**: Detect UPX, VMProtect, Themida, ASPack, and more
- **Section Name Analysis**: Match against known packer section patterns
- **Import Fingerprinting**: Identify packers by their import patterns
- **Confidence Scoring**: Each detection includes a confidence level

### Enhanced PE Loader
- **Import/Export Browser**: Browse PE imports and exports with full detail
- **Imphash Calculation**: Compute import hash for malware classification
- **Improved Parsing**: More robust PE format handling

### Import/Export Browser View
- **Visual Browser**: Navigate PE imports and exports in a dedicated view
- **DLL Grouping**: Imports organized by source DLL
- **Export Details**: View exported symbols with ordinals and addresses

---

## What's New in v1.2.0

### AI-Powered Interactive Features
Three new AI features that you can use on-demand when analyzing binaries:

#### AI Chat
- **Interactive Conversation**: Chat with AI about your binary in real-time
- **Context-Aware**: AI knows the loaded binary, selected function, and decompiled code
- **Follow-up Questions**: Ask clarifying questions and get detailed explanations
- **Quick Suggestions**: Pre-built prompts to get started quickly

#### Explain Function
- **Natural Language Explanation**: Understand what any function does in plain English
- **Complexity Rating**: See if a function is simple, medium, or high complexity
- **Pattern Recognition**: Automatically identifies patterns like crypto, networking, file I/O
- **Detailed Analysis**: Multi-paragraph explanation of function behavior and purpose

#### AI Variable Renaming
- **Smart Suggestions**: AI analyzes code and suggests meaningful variable names
- **Selective Application**: Choose which renames to accept with checkboxes
- **Preview Changes**: See how the code will look before applying
- **Batch Operations**: Select All / Deselect All for quick decisions
- **Reasoning Provided**: Each suggestion includes why that name was chosen

### How to Use AI Features
1. Go to **Settings** (gear icon) → **AI** tab
2. Enter your AI API key
3. Click the **AI** menu in the toolbar:
   - **Chat with AI...** — Open interactive chat panel
   - **Explain Function** — Get explanation of selected function
   - **Rename Variables** — Get AI suggestions for variable names
4. AI features only appear when API key is configured

---

## What's New in v1.1.7

### Frida Script Generator
- **Dynamic Instrumentation**: Generate ready-to-use Frida scripts for iOS and macOS
- **6 Hook Types**: Trace, Bypass, Intercept, Memory Dump, String Patch, Anti-Debug
- **Platform Support**: iOS and macOS with platform-specific optimizations
- **AI-Enhanced Scripts**: Optional AI-powered script generation
- **Export Options**: Copy to clipboard or save as .js file

---

## Features

### Core Features
- **Multi-Architecture Support**: ARM64 and x86_64
- **Multiple Binary Formats**: Mach-O, ELF, PE/COFF, JAR/Java Class
- **Modern UI**: Native SwiftUI interface with dark mode
- **Disassembly View**: Syntax-highlighted assembly with address navigation
- **Hex View**: Synchronized hex dump viewer
- **Control Flow Graph (CFG)**: Visual representation of code flow
- **Decompiler**: Pseudo-C code generation
- **Function Analysis**: Automatic function detection and naming
- **String Analysis**: Extract and navigate to strings
- **Cross-References**: Track code and data references
- **Symbol Support**: Full symbol table parsing
- **Project System**: Save and restore analysis sessions

### Analysis Menu
| Feature | Shortcut | Description |
|---------|----------|-------------|
| Analyze All | ⇧⌘A | Run full binary analysis |
| Find Functions | ⇧⌘F | Detect and list all functions |
| Show CFG | ⌘G | Display control flow graph |
| Decompile | ⇧⌘D | Generate decompiled code |
| Generate Pseudo-Code | ⇧⌘P | Generate structured pseudo-code |
| Call Graph | ⌘K | Show interactive call graph |
| Frida Script | - | Generate Frida hooking scripts |
| Malware Analysis | - | Full malware threat assessment |
| Crypto Detection | - | Detect cryptographic algorithms |
| Deobfuscation Analysis | - | Analyze obfuscation techniques |
| Type Recovery | - | Recover data types |
| Idiom Recognition | - | Recognize code patterns |
| Show Jump Table | ⇧⌘J | View all branches and jumps |

### AI Menu (requires API key)
| Feature | Description |
|---------|-------------|
| Chat with AI | Interactive chat about the binary |
| Explain Function | Natural language explanation of selected function |
| Rename Variables | AI-suggested meaningful variable names |
| Security Analysis | Identify vulnerabilities and bypass techniques |
| Analyze Binary | Full binary security assessment |

### Export Menu
| Format | Description |
|--------|-------------|
| IDA Python | Script for IDA Pro |
| Ghidra XML | Project file for Ghidra |
| Radare2 | r2 command script |
| Binary Ninja | Python script for BN |
| JSON | Structured data export |
| CSV | Spreadsheet-compatible |
| HTML | Web report with styling |
| Markdown | Documentation format |
| C Header | Function declarations |

## Screenshots

<p align="center">
  <img src="img/6.png" alt="Aether - Disassembly View" width="700">
</p>

<p align="center">
  <img src="img/7.png" alt="Aether - Analysis View" width="700">
</p>

<p align="center">
  <img src="img/3.png" alt="Aether - Analysis View" width="700">
</p>

<p align="center">
  <img src="img/1.png" alt="Aether - Disassembly View" width="700">
</p>
<p align="center">
  <img src="img/2.png" alt="Aether - Disassembly View" width="700">
</p>

## Installation

### Download DMG (Recommended)

1. Download [Aether.dmg](https://github.com/Pinperepette/Aether/releases/download/v2.0.0/Aether.dmg)
2. Open the DMG and drag Aether to Applications
3. Launch Aether from Applications

### Build from Source

```bash
git clone https://github.com/Pinperepette/Aether.git
cd Aether
swift build -c release
```

The built application will be available at `.build/release/Aether`.

## Usage

1. **Open a binary**: Drag and drop a file onto the window, or use `File → Open Binary` (⌘O)
2. **Navigate**: Click on functions in the sidebar to jump to their code
3. **Analyze**: Use `Analysis → Analyze All` (⇧⌘A) for full analysis
4. **View CFG**: Select a function and press ⌘G to see the control flow graph
5. **Decompile**: Press ⇧⌘D to generate pseudo-C code
6. **Pseudo-Code**: Press ⇧⌘P to generate structured pseudo-code
7. **Call Graph**: Press ⌘K to view function call relationships
8. **Malware Analysis**: Use Analysis → Malware Analysis for threat assessment
9. **Export**: Use the Export menu to save analysis in various formats

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open Binary | ⌘O |
| Close | ⌘W |
| Go to Address | ⇧⌘G |
| Search | ⌘F |
| Analyze All | ⇧⌘A |
| Find Functions | ⇧⌘F |
| Show CFG | ⌘G |
| Decompile | ⇧⌘D |
| Pseudo-Code | ⇧⌘P |
| Call Graph | ⌘K |
| Jump Table | ⇧⌘J |

## Supported Formats

| Format | Extensions | Architectures |
|--------|------------|---------------|
| Mach-O | (various) | ARM64, x86_64 |
| ELF | .so, .elf, (none) | ARM64, x86_64 |
| PE/COFF | .exe, .dll | x86, x86_64 |
| Java | .jar, .class | JVM Bytecode |

## Architecture

```
Aether/
├── App/           # Application entry point and state management
├── Core/
│   ├── Binary/    # Binary format loaders (Mach-O, ELF, PE, JAR)
│   ├── Disassembler/  # Disassembly engine
│   ├── Analysis/  # Function, string, xref, crypto, malware, entropy analysis
│   ├── Decompiler/    # Pseudo-code generation
│   └── Emulation/     # Lightweight CPU emulator
├── UI/            # SwiftUI views and components
│   ├── GraphView/     # CFG and Call Graph visualization
│   └── AnalysisViews/ # Analysis result views (including Malware Dashboard)
├── Models/        # Data models
└── Services/      # Export manager, Frida generator, AI client, Plugin system
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  <b>Aether</b> — Peel back the layers. See the code beneath.
</p>
