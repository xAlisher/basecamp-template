# Build, Install, and Test

## Prerequisites

- **Nix** with flakes enabled (for reproducible dev environment)
- **Logos AppImage** at `~/logos-app/logos-app.AppImage`
- **Ubuntu 24.04** (tested; other Linux distros may work)

## Development build

### Enter the Nix shell

```bash
cd your-module/template
nix develop
```

This gives you: CMake 3.28, Ninja, Qt 6.9.3, pkg-config, libsodium, and the Logos SDK. Everything pinned to compatible versions.

### Configure and build

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```

**If CMake can't find the Logos SDK:**
The `flake.nix` sets `LOGOS_CPP_SDK_ROOT` and `LOGOS_LIBLOGOS_HEADERS` environment variables. If you're building outside Nix, set these manually:

```bash
export LOGOS_CPP_SDK_ROOT=/path/to/logos-cpp-sdk
export LOGOS_LIBLOGOS_HEADERS=/path/to/logos-liblogos/include
cmake -B build -G Ninja
```

The CMakeLists.txt has hardcoded Nix store paths as fallback, but these are machine-specific. Update them for your system or use environment variables.

### Install

```bash
cmake --install build --prefix ~/.local
```

This installs to:
- `~/.local/share/Logos/LogosBasecamp/modules/<name>/` — your `.so` + `manifest.json`
- `~/.local/share/Logos/LogosBasecamp/plugins/<name>-ui/` — your QML + manifests

### Verify installation

```bash
# Check core module
ls -la ~/.local/share/Logos/LogosBasecamp/modules/mymodule/
# Expected: mymodule_plugin.so, manifest.json

# Check UI plugin
ls -la ~/.local/share/Logos/LogosBasecamp/plugins/my-module-ui/
# Expected: Main.qml, manifest.json, metadata.json

# Verify .so has execute permission (required for loading)
chmod +x ~/.local/share/Logos/LogosBasecamp/modules/mymodule/mymodule_plugin.so
```

**Execute permission is required.** CMake install sometimes strips it. If your module doesn't appear in Basecamp, this is the first thing to check.

## The kill-relaunch ritual

This is the most important workflow to get right. Stale processes holding old `.so` files cause more wasted debugging time than anything else.

### Kill ALL processes

```bash
pkill -9 -f "logos_host"
pkill -9 -f "LogosApp"
pkill -9 -f "logos_core"
sleep 2
```

### Verify they're dead

```bash
ps aux | grep -i logos | grep -v grep
# Must show NOTHING. If any process remains, kill it by PID:
# kill -9 <pid>
```

### Why `-f` flag?

The AppImage wraps executables through `ld-linux` dynamic linker. Process names become something like `/tmp/.mount_logosX/ld-linux-x86-64.so.2 /tmp/.mount_logosX/LogosApp.elf`. Plain `pkill logos_host` won't match. The `-f` flag matches against the full command line.

### Launch

```bash
~/logos-app/logos-app.AppImage &
```

**Do NOT use:**
- Any AppImage from `/nix/store/` — those are Nix build artifacts, not the installed app
- `--dev-mode` flag — dev mode freezes plugin discovery, new plugins won't appear

### The convenience script

Use `template/scripts/relaunch.sh`:

```bash
./scripts/relaunch.sh
```

It handles kill, verify, and relaunch in one command.

## Build-install-test cycle

The full cycle for testing a change:

```bash
# 1. Build
cmake --build build

# 2. Install
cmake --install build --prefix ~/.local

# 3. Fix permissions (if needed)
chmod +x ~/.local/share/Logos/LogosBasecamp/modules/mymodule/mymodule_plugin.so

# 4. Kill and relaunch
./scripts/relaunch.sh

# 5. Test in Basecamp UI
```

Or use the shortcut:

```bash
./scripts/install.sh  # Does steps 1-3
./scripts/relaunch.sh # Does step 4
```

## CMake structure explained

The template has a root `CMakeLists.txt` that includes both `core/` and `ui/`:

### Root CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.28)
project(mymodule-basecamp VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)          # Required — Qt MOC generates metadata code

find_package(Qt6 REQUIRED COMPONENTS Core)
find_package(PkgConfig REQUIRED)
pkg_check_modules(sodium REQUIRED IMPORTED_TARGET libsodium)

add_subdirectory(core)
add_subdirectory(ui)
```

### Core CMakeLists.txt

```cmake
add_library(mymodule_plugin MODULE ...)   # MODULE, not SHARED
set_target_properties(mymodule_plugin PROPERTIES
    PREFIX ""                              # No "lib" prefix
    INSTALL_RPATH "$ORIGIN"               # Find bundled .so deps
)
```

**`MODULE` vs `SHARED`:** Qt plugins must be `MODULE` libraries. `SHARED` libraries are for linking at build time. `MODULE` libraries are for `dlopen()` at runtime, which is what `QPluginLoader` does.

**`PREFIX ""`:** Without this, CMake outputs `libmymodule_plugin.so`. The manifest expects `mymodule_plugin.so`. The mismatch causes silent load failure.

### Logos SDK path resolution

The CMakeLists.txt resolves SDK paths in this priority:

1. Environment variable (set by `nix develop` or manually)
2. Hardcoded Nix store path (fallback for quick builds)

```cmake
if(DEFINED ENV{LOGOS_CPP_SDK_ROOT})
    set(LOGOS_CPP_SDK "$ENV{LOGOS_CPP_SDK_ROOT}")
else()
    set(LOGOS_CPP_SDK "/nix/store/XXXX-logos-cpp-sdk")  # Update for your system
endif()
```

**The Nix store paths are machine-specific.** After running `nix develop`, find your paths:

```bash
echo $LOGOS_CPP_SDK_ROOT
echo $LOGOS_LIBLOGOS_HEADERS
```

Update the fallback paths in `core/CMakeLists.txt`.

### Stale backup cleanup

Logos creates `.bak` copies of modules during updates. These accumulate and can cause conflicts:

```cmake
install(CODE "
    file(GLOB _old \"${INSTALL_DIR}/mymodule.*\")
    foreach(_dir \${_old})
        file(REMOVE_RECURSE \"\${_dir}\")
    endforeach()
")
```

## LGX packaging

LGX is the distribution format for Basecamp modules. It's a tar.gz with a specific structure:

```
mymodule-core.lgx
├── manifest.json
└── variants/
    └── linux-amd64/
        ├── mymodule_plugin.so
        ├── manifest.json
        ├── metadata.json
        └── (bundled .so dependencies)
```

### Building LGX packages

```bash
# Package core module
nix bundle --bundler github:logos-co/nix-bundle-lgx#portable .#lib

# Package UI plugin
nix bundle --bundler github:logos-co/nix-bundle-lgx#portable .#ui
```

### The libpcsclite trap

If your module depends on `libpcsclite` (for smartcard access), you **must** remove it from the LGX bundle after packaging:

```bash
# After bundling, extract, remove pcsclite, repack
tar -xzf mymodule-core.lgx -C temp/
find temp/ -name "libpcsclite.so*" -delete
(cd temp && tar -czf ../mymodule-core.lgx *)
```

**Why:** `libpcsclite` communicates with the system `pcscd` daemon via Unix socket. A bundled copy uses wrong socket paths and protocol versions. The system library must be used instead.

### LGX metadata vs manifest

The LGX bundler reads `metadata.json`, not `manifest.json`. The key difference:

```json
// metadata.json (for bundler) — main is a simple string
{"main": "mymodule_plugin"}

// manifest.json (for runtime) — main is a platform dict
{"main": {"linux-amd64": "mymodule_plugin.so"}}
```

Provide both files. The bundler appends `.so` automatically — don't include the extension in `metadata.json`.

## Troubleshooting

### Module doesn't appear in sidebar

1. **Check both JSON files exist** for the UI plugin:
   ```bash
   ls ~/.local/share/Logos/LogosBasecamp/plugins/my-module-ui/
   # Must have: manifest.json AND metadata.json AND Main.qml
   ```

2. **Check directory name matches `name` field:**
   ```bash
   grep '"name"' ~/.local/share/Logos/LogosBasecamp/plugins/my-module-ui/metadata.json
   # Must match the directory name exactly
   ```

3. **Check .so has execute permission:**
   ```bash
   ls -la ~/.local/share/Logos/LogosBasecamp/modules/mymodule/mymodule_plugin.so
   # Must have x permission
   ```

4. **Check for duplicate plugin directories:**
   ```bash
   find ~/.local/share/Logos/ -name "*mymodule*" -type d
   # Should show exactly 2 results (modules/ and plugins/)
   ```

5. **Kill and relaunch** — always the first thing to try.

### Method calls return empty

1. Verify the method is `Q_INVOKABLE`
2. Verify the method name matches exactly (case-sensitive)
3. Verify the method returns `QString`
4. Verify `plugin_metadata.json` isn't empty
5. Check `logos_host` stderr: `journalctl --user -f | grep logos_host`

### qDebug() output not visible

Your plugin runs in `logos_host.elf`, a separate process. `qDebug()` goes to that process's stderr, not the main app log.

**Solution:** Write to a debug log file:

```cpp
#include <QFile>
#include <QDateTime>

static void debugLog(const QString& msg) {
    QFile file("/tmp/mymodule-debug.log");
    if (file.open(QIODevice::Append)) {
        QTextStream out(&file);
        out << QDateTime::currentDateTime().toString("hh:mm:ss.zzz")
            << " " << msg << "\n";
    }
}
```

Then: `tail -f /tmp/mymodule-debug.log`

### Build works but plugin crashes on load

Usually a library version mismatch between Nix and AppImage Qt. The definitive test is always the AppImage, not the Nix shell. Build in Nix, test in AppImage.
