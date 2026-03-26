# Basecamp Module Template

A developer starter kit for building [Logos Basecamp](https://logos.co) modules. Fork this repo, rename the placeholders, and you'll have a working module pair (C++ core + QML UI) ready to build and test inside the Logos AppImage.

This template is extracted from two production modules:
- [keycard-basecamp](https://github.com/xAlisher/keycard-basecamp) — smartcard authentication
- [logos-notes](https://github.com/xAlisher/logos-notes) — encrypted local-first notes

Every pattern here has been validated against real AppImage builds. If something isn't in this template, it's because it caused problems.

---

## What is a Basecamp module?

A Basecamp module is a pair of plugins that work together:

| Part | Type | Language | Lives in | Purpose |
|------|------|----------|----------|---------|
| **Core module** | `core` | C++17 | `modules/<name>/` | Business logic, I/O, crypto — anything that needs system access |
| **UI plugin** | `ui_qml` | QML (Qt 6) | `plugins/<name>-ui/` | User interface — calls core via `logos.callModule()` |

The core module exposes `Q_INVOKABLE` methods on a class that implements `PluginInterface`. The UI plugin is a QML file that calls those methods through a bridge function provided by the Logos shell. They never communicate directly — the shell routes all calls.

---

## Folder layout

```
basecamp-template/
├── README.md                  ← you are here
├── docs/
│   ├── architecture.md        ← plugin system deep dive
│   ├── qml-bridge.md          ← callModule contract, JSON rules, QML sandbox
│   ├── build-and-test.md      ← CMake, install, AppImage, process kill
│   └── lessons-learned.md     ← hard-won rules from real modules
├── template/
│   ├── CMakeLists.txt         ← working CMake for core + ui plugins
│   ├── flake.nix              ← Nix flake for reproducible builds
│   ├── core/
│   │   ├── MyPlugin.h         ← PluginInterface implementation skeleton
│   │   ├── MyPlugin.cpp       ← Q_INVOKABLE methods returning JSON
│   │   ├── plugin_metadata.json
│   │   └── manifest.json      ← type: "core"
│   ├── ui/
│   │   ├── Main.qml           ← minimal QML screen with callModule example
│   │   └── manifest.json      ← type: "ui_qml"
│   └── scripts/
│       ├── install.sh         ← cmake --build + --install shortcut
│       └── relaunch.sh        ← kill all Logos processes + relaunch AppImage
└── CHECKLIST.md               ← UI/UX test checklist template
```

**Why this structure?**
- `core/` and `ui/` mirror how Basecamp discovers modules at runtime — it scans `modules/` for `.so` files and `plugins/` for QML entry points. Keeping them separate during development matches the install layout.
- `scripts/` exists because the build-install-kill-relaunch cycle is the most common workflow and getting any step wrong wastes 5+ minutes of debugging.
- `docs/` is split by concern so you can hand a single file to a teammate who only needs to understand one part.

---

## Quick start

### 1. Fork and rename

```bash
git clone https://github.com/xAlisher/basecamp-template.git my-module
cd my-module
```

Then find-and-replace these placeholders throughout `template/`:

| Placeholder | Replace with | Example |
|-------------|-------------|---------|
| `mymodule` | your module name (lowercase, no hyphens in C++) | `notes` |
| `MyPlugin` | your plugin class name | `NotesPlugin` |
| `my-module-ui` | your UI plugin directory name | `notes-ui` |
| `org.logos.MyModuleInterface` | your IID string | `org.logos.NotesModuleInterface` |
| `My Module` | human-readable name | `Encrypted Notes` |
| `yourname` | your author name | `alisher` |

### 2. Enter Nix shell and build

```bash
nix develop
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```

### 3. Install

```bash
cmake --install build --prefix ~/.local
```

This installs:
- Core `.so` + `manifest.json` → `~/.local/share/Logos/LogosBasecamp/modules/<name>/`
- QML + `manifest.json` + `metadata.json` → `~/.local/share/Logos/LogosBasecamp/plugins/<name>-ui/`

### 4. Kill, relaunch, test

```bash
# Kill ALL Logos processes (critical — stale .so files block new loads)
pkill -9 -f "logos_host"; pkill -9 -f "LogosApp"; pkill -9 -f "logos_core"
sleep 2

# Launch
~/logos-app/logos-app.AppImage &
```

Your module should appear in the Basecamp sidebar. Click it to load your QML UI.

---

## How `logos.callModule` works

This is the only way QML talks to C++. Understanding it prevents 90% of debugging time.

```javascript
// QML side
var result = logos.callModule("mymodule", "someMethod", ["param1", "param2"])
var parsed = JSON.parse(result)
```

```cpp
// C++ side — must be Q_INVOKABLE, must return QString (JSON)
Q_INVOKABLE QString someMethod(const QString& param1, const QString& param2) {
    QJsonObject result;
    result["success"] = true;
    result["data"] = "hello";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}
```

**Three rules:**

1. **Always `JSON.parse()` the result.** `callModule` returns a JSON *string*, never a parsed object. If you forget to parse, you'll be comparing a string `"true"` to boolean `true` and wondering why nothing works.

2. **Missing methods return nothing silently.** If the method name doesn't match a `Q_INVOKABLE` method on your plugin class, `callModule` returns an empty string. No error, no warning, no exception. Check spelling and ensure `Q_INVOKABLE` is present.

3. **It's synchronous.** The call blocks the QML thread until C++ returns. Keep methods fast (<100ms) or the UI freezes. For long operations, return immediately with a status and poll from a QML Timer.

See [docs/qml-bridge.md](docs/qml-bridge.md) for the full contract.

---

## Hard rules

These are extracted from real build failures across two production modules. Every rule has a story behind it.

### 1. Every backend method QML needs must be `Q_INVOKABLE`

`callModule` uses Qt's reflection system to find methods. If `Q_INVOKABLE` is missing, the method is invisible to QML. The call returns empty — no error, no log, nothing. This is the #1 cause of "my method doesn't work" bugs.

### 2. Always `JSON.parse()` callModule results

The return value is a JSON string, not a JavaScript object. `result.success` on an unparsed string is `undefined`. Always: `var obj = JSON.parse(result)`.

### 3. Screen state doesn't survive Qt Loader destruction

When the Logos shell switches away from your plugin's screen, the QML Loader destroys your component tree. All property values are lost. If you need state to persist across screen switches, pass it to C++ before the switch happens, and reload it on `Component.onCompleted`.

### 4. `plugin_metadata.json` must be fully populated

An empty `{}` or missing fields causes the Logos shell to silently skip your plugin. Every field must be present and the `IID` in `Q_PLUGIN_METADATA` must match exactly. There is no error message — the plugin simply doesn't appear.

### 5. Always test with AppImage build

`nix develop` + `cmake` builds against Nix store libraries. The AppImage bundles its own Qt and dependencies. A module that builds and runs in Nix can fail inside the AppImage due to library version mismatches, missing symbols, or path differences. The AppImage is the truth.

### 6. Kill ALL Logos processes before relaunch

Logos runs multiple processes (`logos_host`, `LogosApp`, `logos_core`). If you only kill one, the others hold file locks on your old `.so`. Your new build won't load. Always:

```bash
pkill -9 -f "logos_host"; pkill -9 -f "LogosApp"; pkill -9 -f "logos_core"
```

Use `-f` because AppImage wraps processes via `ld-linux`, so process names don't match what you expect.

### 7. QML sandbox restrictions

Your QML runs inside the Logos shell's sandbox. These things don't work:

| Blocked | Workaround |
|---------|-----------|
| `import Logos.Theme` | Hardcode hex color values (`#2b2b2b`, `#ffffff`) |
| `FileDialog` | Move file I/O to C++ plugin, expose via `Q_INVOKABLE` |
| File read/write from QML | All file I/O must go through C++ plugin methods |
| `import Logos.Controls` | Use standard `QtQuick.Controls 2.15` |
| Dynamic plugin loading | Not supported — one QML entry point per plugin |

---

## Docs

- [Architecture deep dive](docs/architecture.md) — how the plugin system loads and routes calls
- [QML bridge contract](docs/qml-bridge.md) — `callModule` semantics, JSON rules, sandbox limits
- [Build and test](docs/build-and-test.md) — CMake config, install paths, AppImage workflow
- [Lessons learned](docs/lessons-learned.md) — every mistake we made so you don't have to

---

## Tested against

This template was built and validated against:

| Component | Version | Notes |
|-----------|---------|-------|
| **Logos Basecamp** | **1.0.0** (`pre-release-7b87ce2`) | [logos-co/logos-basecamp](https://github.com/logos-co/logos-basecamp) — the host app |
| C++ | 17 | Required by Logos SDK |
| Qt | 6.9.3 | QML + Core modules |
| CMake | 3.28+ | Module library builds |
| Nix | flake-based | Reproducible dev environment |
| Ubuntu | 24.04 | Primary dev/test platform |
| libsodium | 1.0.18 | Optional — for crypto operations |

If you're using a different Basecamp version, the plugin loading contract and `callModule` interface may differ. The patterns here are known to work with Basecamp 1.0.0.

---

## License

MIT — use this template however you want.
