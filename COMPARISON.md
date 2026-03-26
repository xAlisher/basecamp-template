# Comparison: basecamp-template vs logos-tutorial

A side-by-side comparison of [xAlisher/basecamp-template](https://github.com/xAlisher/basecamp-template) and the official [logos-co/logos-tutorial](https://github.com/logos-co/logos-tutorial) from the Logos Core team.

Both repos help developers build Basecamp modules. They come at the problem from different angles and are complementary, not competing.

---

## At a glance

| | **basecamp-template** | **logos-tutorial** |
|---|---|---|
| **Approach** | Fork-and-rename scaffold + battle-tested docs | Step-by-step tutorial series with example code |
| **Source** | Extracted from 2 production modules (keycard-basecamp, logos-notes) | Written by Logos Core team as educational material |
| **Status** | Verified: builds, installs, loads in AppImage, LGX packages | WIP — 9 open issues, actively being developed |
| **Build system** | Raw CMake + Nix flake (manual SDK path resolution) | `logos-module-builder` helpers (`mkLogosModule`, `mkLogosQmlModule`) |
| **Scope** | Core + QML UI pair | Core + QML UI + C++ Widget UI + C library wrapping |
| **Docs style** | "Here's what broke and why" (lessons-learned) | "Here's how to build it" (tutorial) |

---

## What logos-tutorial has that we don't

### 1. `logos-module-builder` integration

The tutorial uses standardized build helpers from [logos-module-builder](https://github.com/logos-co/logos-module-builder):

```nix
# Their flake.nix — clean, minimal
logos-module-builder.lib.mkLogosModule {
  src = ./.;
  configFile = ./metadata.json;
  flakeInputs = inputs;
};
```

```cmake
# Their CMakeLists.txt — one function call
logos_module(
  NAME calc_module
  SOURCES src/calc_module_plugin.h src/calc_module_plugin.cpp
  EXTERNAL_LIBS calc
)
```

**vs. our approach** — raw CMake with manual SDK path resolution, manual install targets, manual backup cleanup. More verbose but more transparent about what's happening.

**Verdict:** Their approach is cleaner for new projects. Ours shows the internals, which helps when `logos_module()` does something unexpected.

### 2. Type-safe C++ UI path

The tutorial shows a C++ widget UI plugin using generated SDK headers (`logos_sdk.h` via `logos-cpp-generator`):

```cpp
// Type-safe module calls — no string coercion
int result = m_logos->calc_module->add(3, 5);  // Returns int, not QString JSON
```

Our template only covers the QML path where everything goes through `callModule` as JSON strings. The C++ UI path preserves types end-to-end.

### 3. C library wrapping tutorial

Part 1 walks through wrapping a plain C library (`libcalc`) as a Basecamp module — useful for integrating existing C/C++ code.

### 4. CLI tooling documentation

The tutorial documents several CLI tools we don't mention:

| Tool | Purpose |
|------|---------|
| `lm` | Inspect module metadata and method signatures |
| `logoscore` | Run modules headless (`logoscore call calc_module add 3 5`) |
| `lgpm` | Package manager CLI for installing `.lgx` files |
| `logos-cpp-generator` | Generate typed SDK headers from `metadata.json` |

### 5. `metadata.json` as single source of truth

Their `metadata.json` includes a `nix_config` section that drives the entire build:

```json
{
  "name": "calc_module",
  "type": "core",
  "main_entry_point": "calc_module_plugin",
  "nix_config": {
    "external_libs": [{"name": "calc", "vendor_path": "lib"}],
    "cmake_config": {
      "extra_include_dirs": ["lib"],
      "find_packages": [],
      "extra_sources": []
    }
  }
}
```

We use separate `metadata.json`, `manifest.json`, and `plugin_metadata.json` with different `main` formats — more files, but matches what the runtime actually reads.

### 6. Standalone app testing

```nix
# Test UI in isolation without full Basecamp
logos-standalone-app.url = "github:logos-co/logos-standalone-app";
```

We don't have this — our testing requires the full AppImage.

### 7. QML hot-reloading via `QML_PATH`

The tutorial documents dev-mode QML reloading without rebuilding:

```bash
QML_PATH=/path/to/your/qml logos-basecamp
```

We don't cover this — our workflow is always build → install → kill → relaunch.

### 8. `Logos.Theme` and `Logos.Controls` imports

The tutorial uses themed components:

```qml
import Logos.Theme
import Logos.Controls

LogosButton { text: "Add" }
LogosTextField { placeholderText: "Enter a" }
```

**Important caveat:** In our production experience, these imports don't work reliably in the plugin sandbox (see "What we have that they don't" #3 below). The tutorial may be using them in standalone mode or a newer Basecamp version where this is fixed.

---

## What we have that they don't

### 1. Production-tested gotchas (30+ rules)

Every rule in our docs came from a real failure. The tutorial teaches the happy path; we document the sad path:

- `callModule` silently returns empty string on missing methods (no error)
- `plugin_metadata.json` must never be `{}` — silent load failure
- Plugin `.so` needs execute permission or `QPluginLoader` silently fails
- `initLogos()` must NOT use `override` keyword — called via reflection
- Don't redeclare `logosAPI` — shadows base class member, breaks initialization detection
- `eventResponse` signal is mandatory — `ModuleProxy` connect fails silently without it
- UI plugins need BOTH `manifest.json` AND `metadata.json` or they're invisible

The tutorial mentions some of these (like the global `logosAPI` pattern) but doesn't document the failure modes.

### 2. The kill-relaunch ritual

We document the multi-process kill workflow that every Basecamp developer hits:

```bash
pkill -9 -f "logos_host"; pkill -9 -f "LogosApp"; pkill -9 -f "logos_core"
```

Including why `-f` is needed (AppImage wraps via `ld-linux`), why all three processes must die (stale `.so` locks), and a convenience script. The tutorial doesn't cover this.

### 3. QML sandbox restrictions with workarounds

From real AppImage testing, we document what doesn't work in the plugin sandbox:

| Blocked | Workaround |
|---------|-----------|
| `Logos.Theme` | Hardcode hex colors |
| `FileDialog` | Move to C++ `Q_INVOKABLE` |
| File I/O from QML | All I/O through C++ plugin |
| `Logos.Controls` | Use `QtQuick.Controls 2.15` |

The tutorial shows `Logos.Theme` and `Logos.Controls` working — this may be version-dependent or standalone-mode-only. Our workarounds are safe regardless.

### 4. JSON.parse() requirement

We explicitly document that `callModule` returns a JSON *string*, not an object:

```javascript
// WRONG — result is a string, .success is undefined
var result = logos.callModule("mymodule", "getStatus", [])
if (result.success) { ... }

// RIGHT
var obj = JSON.parse(result)
if (obj.success) { ... }
```

The tutorial passes arguments as strings but doesn't document the return value parsing requirement.

### 5. State persistence across screen switches

We document that the Logos Loader destroys your QML tree on navigation:

> When the user navigates away, all QML properties are lost. Persist to C++ before the switch, restore in `Component.onCompleted`.

The tutorial doesn't mention this — it's only visible when you have real multi-screen UIs.

### 6. Process model and debug logging

We document that your plugin runs in `logos_host.elf` (separate process), so `qDebug()` goes to a different stderr. Solution: write to `/tmp/mymodule-debug.log`.

### 7. Three JSON files explained

We document why you need three different JSON files with different `main` field formats:

| File | `main` format | Used by |
|------|--------------|---------|
| `metadata.json` | `"mymodule_plugin"` (string) | LGX bundler |
| `manifest.json` | `{"linux-amd64": "mymodule_plugin.so"}` (dict) | Basecamp runtime |
| `plugin_metadata.json` | `"mymodule_plugin"` (string) | Qt MOC (embedded in .so) |

The tutorial uses a single `metadata.json` with `logos-module-builder` handling the rest. Cleaner, but if the builder breaks, you need to understand the underlying files.

### 8. libpcsclite bundling trap

Critical for hardware-dependent modules: never bundle `libpcsclite.so` in LGX packages. Breaks `pcscd` daemon communication. We document the removal step.

### 9. Test checklist

`CHECKLIST.md` — a pre-release checklist covering build, plugin loading, callModule round-trip, QML behavior, state persistence, and LGX packaging.

### 10. The "don't fix what works" lesson

Our most expensive lesson: when adding a feature, only modify what the feature needs. Don't "improve" naming, paths, or infrastructure while debugging something else.

---

## What's shared

Both repos cover these fundamentals:

| Topic | basecamp-template | logos-tutorial |
|-------|------------------|---------------|
| Core + UI plugin pair architecture | Yes | Yes |
| `Q_INVOKABLE` methods | Yes | Yes |
| `PluginInterface` base class | Yes | Yes |
| `logos.callModule()` bridge | Yes | Yes |
| LGX packaging | Yes (tested) | Yes (documented) |
| Nix flake builds | Yes (raw) | Yes (via module-builder) |
| `metadata.json` config | Yes | Yes |
| Plugin icons (PNG) | Documented | Included |
| `eventResponse` signal | Yes | Yes |
| `initLogos()` pattern | Yes | Yes |

---

## Which should you use?

**Start with logos-tutorial if:**
- You're new to Basecamp development
- You want a guided learning path (Parts 1 → 2 → 3)
- You want to use `logos-module-builder` (less boilerplate)
- You need C++ widget UI (not just QML)
- You want type-safe inter-module calls via generated SDK

**Start with basecamp-template if:**
- You want to fork something that builds and loads today
- You want to understand what's happening under the hood (raw CMake, manual SDK paths)
- You need to know what goes wrong and why (sandbox limits, silent failures, process model)
- You're building a production module and want a pre-flight checklist
- You hit a problem the tutorial doesn't cover

**Best approach:** Read the tutorial to understand the concepts, then fork the template to start building. Keep our `docs/lessons-learned.md` open while you work — it'll save you hours.

---

## Version note

This comparison was made on March 26, 2026 against:
- **basecamp-template** — verified against Logos Basecamp 1.0.0 (`pre-release-7b87ce2`)
- **logos-tutorial** — commit history up to March 26, 2026 (28 commits, WIP status)

The logos-tutorial is actively being developed. Some gaps noted here may be filled by the time you read this.
