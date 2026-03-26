# Lessons Learned

Hard-won rules from building [keycard-basecamp](https://github.com/xAlisher/keycard-basecamp) and [logos-notes](https://github.com/xAlisher/logos-notes). Each lesson cost at least 30 minutes of debugging. Some cost hours.

---

## Plugin loading

### Empty `plugin_metadata.json` = invisible plugin

If `plugin_metadata.json` is `{}` or has missing fields, the Logos shell silently ignores your plugin. No error message, no log line, no indication anything went wrong. Your plugin just doesn't exist.

**Required fields:** `name`, `version`, `type`, `author`, `description`, `main`, `category`, `dependencies`.

**How we found this:** Spent 2 hours checking build output, manifest files, and directory permissions before realizing the metadata file was the problem.

### IID must be globally unique

`Q_PLUGIN_METADATA(IID "org.logos.MyModuleInterface" ...)` — if two plugins share the same IID, Qt loads one and ignores the other. Use your module name in the IID string.

### `initLogos` must NOT use `override`

The shell calls `initLogos` via `QMetaObject::invokeMethod` (reflection), not through the virtual table. Adding `override` can break method resolution. Declare it as a plain `Q_INVOKABLE` method.

### Don't redeclare `logosAPI`

`PluginInterface` has a public `LogosAPI* logosAPI` member. If you declare `private: LogosAPI* logosAPI = nullptr;` in your plugin class, it shadows the base member. The shell checks the base class member to verify initialization — your plugin appears uninitialized.

### `eventResponse` signal is mandatory

The shell's `ModuleProxy` calls `QObject::connect` on your `eventResponse(QString, QVariantList)` signal during loading. If the signal doesn't exist, the connect fails silently. Always include it even if you don't use it.

### Plugin `.so` needs execute permission

CMake install sometimes strips the execute bit. Without it, `QPluginLoader` silently fails. Always `chmod +x` after install.

---

## UI plugin registration

### UI plugins need BOTH manifest.json AND metadata.json

Missing either file causes the plugin to not appear in the sidebar. No error. We initially shipped with only `metadata.json` and spent an hour wondering why it was invisible.

### Directory name must match `name` field exactly

`plugins/my-module-ui/metadata.json` must contain `"name": "my-module-ui"`. A mismatch between directory name and the JSON `name` field (e.g., underscore vs hyphen: `my_module_ui` vs `my-module-ui`) makes the plugin invisible.

### Only include tested platforms in manifest `main`

If `manifest.json` has `"main": {"linux-amd64": "...", "darwin-arm64": "..."}` but you've only built for Linux, the extra platform entry can prevent loading. Only list platforms you've actually tested.

### Icon must be PNG, not SVG

The shell doesn't render SVG icons for plugins. Must be 28x28 PNG. Also: the shell desaturates inactive icons to grayscale, so light/white icons become invisible in the sidebar. Use saturated colors with good contrast.

---

## `callModule` behavior

### Missing methods return empty, not error

If you call `logos.callModule("name", "nonexistent", [])`, you get `""` (empty string). No error object, no exception, no log. This is the #1 debugging time sink for new developers.

**Fix:** Always check for empty returns before `JSON.parse()`.

### Must `JSON.parse()` every return value

`callModule` returns a JSON *string*. `result.success` on a string is `undefined`. You must parse first: `JSON.parse(result).success`.

### Raw return types don't cross the bridge

`Q_INVOKABLE bool isReady()` returning `true` — QML receives... something unreliable. The `callModule` bridge serializes through strings. Always return `QString` containing JSON.

---

## QML sandbox

### No `Logos.Theme`, no `Logos.Controls`

These imports are shell-internal. Your plugin QML can't use them. Hardcode hex colors and use standard `QtQuick.Controls 2.15`.

### No `FileDialog`

`FileDialog` fails silently in the plugin sandbox. All file I/O must go through C++ `Q_INVOKABLE` methods.

### `Text` is not selectable

Use `TextEdit` with `readOnly: true`, `selectByMouse: true`, `selectByKeyboard: true` for any text users might want to copy.

### QML signals don't return values

If you define `signal execute()` on a component and call `var result = row.execute()`, result is `undefined`. Signals are fire-and-forget. For callbacks that return values, use `property var executeFunc: function() { return ... }`.

---

## State management

### Screen state dies on navigation

When the user clicks another plugin in the sidebar, the Loader destroys your QML tree. All properties reset. Persist anything important to C++ via `callModule` before it's too late. Restore in `Component.onCompleted`.

### Use state-based UI, not flags

Don't maintain separate boolean flags (`readerFound`, `cardFound`) alongside a polled state. The flags go stale. Instead, derive everything from a single `currentState` property that's updated by a Timer.

```javascript
// WRONG — flags go stale
property bool cardFound: false
text: root.cardFound ? "Card found" : "No card"

// RIGHT — derived from polled state
property string currentState: "INITIAL"  // Updated by Timer
text: root.currentState !== "CARD_NOT_PRESENT" ? "Card found" : "No card"
```

### Session state is logical, not physical

If your module has sessions: session state (active, closed) is a user-intent concept. Card/device presence is a physical concept. Don't auto-clear session state when a device is rediscovered — that defeats the purpose of explicit session management. Only clear on actual device removal.

---

## Build and install

### Nix store paths are machine-specific

`/nix/store/047dm...-logos-cpp-sdk` is different on every machine. Hardcode them as fallback for your own dev box, but always support the environment variable override:

```cmake
if(DEFINED ENV{LOGOS_CPP_SDK_ROOT})
    set(LOGOS_CPP_SDK "$ENV{LOGOS_CPP_SDK_ROOT}")
else()
    set(LOGOS_CPP_SDK "/nix/store/YOUR-HASH-HERE-logos-cpp-sdk")
endif()
```

### AppImage is the truth, not Nix

A module can build and run perfectly in `nix develop` but crash inside the AppImage due to Qt version differences or missing symbols. Always do final testing inside the AppImage.

### `MODULE` not `SHARED`

Qt plugins must be `add_library(name MODULE ...)`. `SHARED` is for build-time linking. `MODULE` is for runtime `dlopen()`, which is what `QPluginLoader` uses.

### Set `PREFIX ""` on the library target

Without it, CMake produces `libmymodule_plugin.so`. Your manifest says `mymodule_plugin.so`. The shell can't find it.

### `configure_file` for metadata

`Q_PLUGIN_METADATA(... FILE "plugin_metadata.json")` resolves relative to the **build** directory (because of MOC). Copy the source file to the build directory:

```cmake
configure_file(plugin_metadata.json ${CMAKE_CURRENT_BINARY_DIR}/plugin_metadata.json COPYONLY)
```

---

## Process management

### Kill ALL Logos processes

Logos runs 3+ processes. Killing just the main one leaves `logos_host` running with your old `.so` loaded. You must kill all:

```bash
pkill -9 -f "logos_host"; pkill -9 -f "LogosApp"; pkill -9 -f "logos_core"
```

### Use `-f` for pkill

AppImage wraps executables via `ld-linux`. Process names become long paths like `/tmp/.mount_logosX/ld-linux-x86-64.so.2 .../logos_host.elf`. Plain `pkill logos_host` doesn't match. Use `pkill -f` to match against the full command line.

### Module qDebug() goes to a different process

Your plugin runs in `logos_host.elf`, not the main app. `qDebug()` output goes to `logos_host`'s stderr, which may go to journal or nowhere visible. For reliable debugging, write to `/tmp/mymodule-debug.log`.

---

## Packaging (LGX)

### Never bundle `libpcsclite`

If your module uses PC/SC (smartcard access), the LGX bundler will automatically include `libpcsclite.so`. You must remove it. The bundled version can't communicate with the system `pcscd` daemon — wrong socket paths, protocol version mismatch.

### `metadata.json` vs `manifest.json` for bundler

The LGX bundler reads `metadata.json` with `"main": "plugin_name"` (string, no `.so`). The runtime reads `manifest.json` with `"main": {"linux-amd64": "plugin_name.so"}` (dict with platform). Provide both.

### Relative paths break in subshells

If your packaging script does `(cd $TEMP && tar -czf $OUTPUT_DIR/file.lgx *)` and `OUTPUT_DIR` is relative (`.`), after `cd` it points to the wrong place. Convert to absolute first: `OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)`.

### Git submodules don't survive archives

`git archive` and GitHub release tarballs don't include submodule contents. If you depend on external repos, use CMake `FetchContent` as a fallback:

```cmake
if(EXISTS "${CMAKE_SOURCE_DIR}/external/dep/CMakeLists.txt")
    add_subdirectory(external/dep)
else()
    FetchContent_Declare(dep GIT_REPOSITORY ... GIT_TAG ...)
    FetchContent_MakeAvailable(dep)
endif()
```

---

## Don't fix what works

The single most expensive lesson: **when adding a feature, only modify what the feature needs.** Don't "improve" plugin naming, switch install paths, or change the AppImage while you're trying to add a new QML screen. Every infrastructure change you make while debugging a feature creates a new variable to debug.

**Before changing any configuration:**
1. Verify master branch works (build, install, launch, test)
2. Make your feature change and ONLY your feature change
3. If it breaks, you know it's your feature, not infrastructure

**Red flags that you're about to waste time:**
- "Let me fix the naming to match conventions" — Is the current naming broken? No? Don't touch it.
- "The docs say use a different path" — Does the current path work? Yes? Keep it.
- "Maybe it's the AppImage version" — Did it work yesterday? Yes? It's not the AppImage.
