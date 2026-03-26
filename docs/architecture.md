# Architecture: Logos Basecamp Plugin System

## How Basecamp discovers and loads your module

When the Logos AppImage launches, it scans two directories under `~/.local/share/Logos/LogosBasecamp/`:

```
modules/           ← core C++ plugins (.so files)
  └── mymodule/
      ├── mymodule_plugin.so
      └── manifest.json

plugins/            ← UI plugins (QML entry points)
  └── my-module-ui/
      ├── Main.qml
      ├── manifest.json
      └── metadata.json
```

The loading sequence:

1. **Scan `modules/`** — for each subdirectory, read `manifest.json`. If `type` is `"core"` and `main` maps to a `.so` file for the current platform, load it via `QPluginLoader`.
2. **Verify plugin metadata** — the `.so` must contain Qt plugin metadata (embedded via `Q_PLUGIN_METADATA`). If the `IID` doesn't match the expected interface pattern, the plugin is rejected silently.
3. **Connect signals** — the shell connects to the plugin's `eventResponse` signal. If this signal is missing, the plugin loads but can't communicate events back to the shell.
4. **Call `initLogos()`** — the shell passes its API object to the plugin via `QMetaObject::invokeMethod`. This is reflective, not virtual — do NOT use `override` on this method.
5. **Scan `plugins/`** — for each subdirectory, read both `manifest.json` and `metadata.json`. If `type` is `"ui_qml"`, register the QML entry point. The plugin appears in the sidebar.
6. **Lazy-load QML** — when the user clicks your plugin in the sidebar, the shell creates a `Loader` component pointing to your `Main.qml`. The QML now has access to `logos.callModule()`.

## The two-plugin architecture

Every Basecamp feature is a pair:

```
┌─────────────────────────────────────────────────────┐
│                   Logos Shell                         │
│                                                       │
│   ┌──────────────┐         ┌──────────────────┐     │
│   │  Core Module  │◄───────│   QML UI Plugin   │     │
│   │  (C++ .so)    │        │   (Main.qml)      │     │
│   │               │        │                    │     │
│   │  Q_INVOKABLE  │  JSON  │  logos.callModule  │     │
│   │  methods      │◄──────►│  ("name","method") │     │
│   │               │        │                    │     │
│   └──────────────┘         └──────────────────┘     │
│         │                           │                 │
│    modules/name/            plugins/name-ui/          │
└─────────────────────────────────────────────────────┘
```

**Why two plugins instead of one?**

- **Separation of concerns.** The C++ module handles system access (files, network, hardware, crypto). The QML handles layout and user interaction. Neither knows about the other's internals.
- **The shell is the router.** All calls go through `logos.callModule()`, which the shell intercepts. This lets the shell enforce sandboxing, logging, and access control.
- **QML is disposable.** When the user navigates away, the shell destroys the QML component tree. The C++ module stays loaded and retains state. When the user comes back, QML reloads and queries C++ for current state.

## Plugin class anatomy

```cpp
#include <QObject>
#include <QVariantList>
#include <core/interface.h>  // From Logos SDK — provides PluginInterface

class MyPlugin : public QObject, public PluginInterface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.logos.MyModuleInterface" FILE "plugin_metadata.json")
    Q_INTERFACES(PluginInterface)

public:
    // Required by PluginInterface
    QString name()    const override { return QStringLiteral("mymodule"); }
    QString version() const override { return QStringLiteral("1.0.0"); }

    // Called by shell via reflection — do NOT use override
    Q_INVOKABLE void initLogos(LogosAPI* api) {
        logosAPI = api;  // Use base class member, don't declare your own
    }

    // Your methods — each must be Q_INVOKABLE and return JSON QString
    Q_INVOKABLE QString doSomething(const QString& input);

signals:
    // Required — shell connects to this for event communication
    void eventResponse(const QString& eventName, const QVariantList& data);
};
```

### Critical details

**`Q_PLUGIN_METADATA` IID must be unique.** Two plugins with the same IID will collide. Convention: `org.logos.<YourModule>ModuleInterface`.

**`FILE "plugin_metadata.json"` path is relative to the build directory.** CMake must copy it there:
```cmake
configure_file(
    plugin_metadata.json
    ${CMAKE_CURRENT_BINARY_DIR}/plugin_metadata.json
    COPYONLY
)
```

**`logosAPI` is inherited from `PluginInterface`.** Do not declare a private `LogosAPI* logosAPI` member — it shadows the base class member and the shell checks the base class one, so your plugin appears uninitialized.

**`eventResponse` signal is mandatory.** The shell's `ModuleProxy` calls `QObject::connect` on this signal during loading. If the signal doesn't exist, the connect fails silently and your plugin can't emit events.

## Manifest and metadata files

You need **three** JSON files total. Getting any of them wrong causes silent failures.

### Core module: `modules/<name>/manifest.json`

```json
{
  "name": "mymodule",
  "version": "1.0.0",
  "type": "core",
  "author": "yourname",
  "description": "What this module does",
  "category": "general",
  "dependencies": [],
  "icon": "",
  "main": {
    "linux-amd64": "mymodule_plugin.so"
  },
  "manifestVersion": "0.1.0"
}
```

**Rules:**
- `name` must match the string returned by your plugin's `name()` method
- `main` is a dict keyed by platform — only include platforms you've tested
- `type` must be `"core"` for C++ modules

### Core module: `plugin_metadata.json` (embedded in .so)

```json
{
  "name": "mymodule",
  "version": "1.0.0",
  "type": "core",
  "author": "yourname",
  "description": "What this module does",
  "category": "general",
  "dependencies": [],
  "main": "mymodule_plugin"
}
```

**Rules:**
- `main` is a simple string (no `.so` extension, no platform dict)
- Must not be empty `{}` — empty metadata causes silent load failure
- Fields must be consistent with `manifest.json`

### UI plugin: `plugins/<name>-ui/manifest.json`

```json
{
  "name": "my-module-ui",
  "version": "1.0.0",
  "type": "ui_qml",
  "author": "yourname",
  "description": "UI for my module",
  "category": "general",
  "dependencies": ["mymodule"],
  "icon": "",
  "main": {
    "linux-amd64": "Main.qml"
  },
  "manifestVersion": "0.1.0"
}
```

### UI plugin: `plugins/<name>-ui/metadata.json`

```json
{
  "name": "my-module-ui",
  "version": "1.0.0",
  "type": "ui_qml",
  "pluginType": "qml",
  "author": "yourname",
  "description": "UI for my module",
  "category": "general",
  "dependencies": ["mymodule"],
  "main": "Main.qml",
  "capabilities": [],
  "icon": ""
}
```

**Rules:**
- UI plugins need BOTH `manifest.json` AND `metadata.json` — missing either causes the plugin to not appear in the sidebar
- `name` must match the directory name exactly (including hyphens vs underscores)
- `dependencies` must list the core module name — this tells the shell to load the core first
- `main` in metadata.json is a simple string (`"Main.qml"`)

## Module vs plugin naming

This causes more bugs than almost anything else:

| Entity | Name format | Example |
|--------|------------|---------|
| Core module directory | lowercase, no hyphens | `modules/mymodule/` |
| Core module `name` field | same as directory | `"mymodule"` |
| Core `.so` file | `<name>_plugin.so` | `mymodule_plugin.so` |
| UI plugin directory | with hyphen `-ui` | `plugins/my-module-ui/` |
| UI plugin `name` field | must match directory | `"my-module-ui"` |
| `callModule` first arg | core module name | `logos.callModule("mymodule", ...)` |

**The directory name must exactly match the `name` field in the JSON files.** A mismatch between `plugins/my_module_ui/` and `{"name": "my-module-ui"}` will cause the plugin to not load, with zero error messages.

## How the shell routes `callModule`

```
QML: logos.callModule("mymodule", "doSomething", ["hello"])
  │
  ▼
Shell looks up "mymodule" in loaded modules registry
  │
  ▼
Found: QObject* plugin (your MyPlugin instance)
  │
  ▼
QMetaObject::invokeMethod(plugin, "doSomething", Q_ARG(QString, "hello"))
  │
  ▼
Your Q_INVOKABLE method runs, returns QString (JSON)
  │
  ▼
Shell returns the string to QML
```

If "mymodule" isn't found → returns empty string.
If "doSomething" isn't a Q_INVOKABLE method → returns empty string.
If the method signature doesn't match the arguments → returns empty string.

No exceptions. No errors. Just empty strings. This is by design (the shell can't know if a missing method is a bug or an optional feature), but it makes debugging painful. Always check for empty returns in your QML code.

## Process model

Logos runs as multiple processes:

```
logos-app.AppImage
  └── LogosApp.elf        (main shell process)
      ├── logos_host.elf   (module host — loads your .so)
      └── logos_core.elf   (core services)
```

Your C++ plugin runs inside `logos_host.elf`, not in the main process. This means:
- `qDebug()` output goes to `logos_host`'s stderr, not the main app log
- If you need visible logging, write to a file (e.g., `/tmp/mymodule-debug.log`)
- Killing only `LogosApp` doesn't kill `logos_host` — your stale .so stays loaded
- You must kill ALL processes before relaunching (see [build-and-test.md](build-and-test.md))

## Icon requirements

If you want a sidebar icon:

- **Format:** 28x28 PNG, 8-bit RGBA
- **No SVG** — the shell doesn't render SVGs for plugin icons
- **Contrast matters** — the shell desaturates inactive icons to grayscale. Light/white icons become invisible. Use saturated colors.
- Reference the icon in both `manifest.json` (`"icon": "myicon.png"`) and `metadata.json` (`"icon": "icons/myicon.png"`)
