# Module Test Checklist

Use this checklist before every release or PR. Test inside the AppImage, not just the Nix shell.

## Build verification

- [ ] `cmake --build build` succeeds with no warnings
- [ ] `cmake --install build --prefix ~/.local` completes
- [ ] `.so` file exists in `~/.local/share/Logos/LogosBasecamp/modules/<name>/`
- [ ] `.so` file has execute permission (`ls -la` shows `x`)
- [ ] `manifest.json` exists alongside `.so`
- [ ] `Main.qml` exists in `~/.local/share/Logos/LogosBasecamp/plugins/<name>-ui/`
- [ ] Both `manifest.json` AND `metadata.json` exist in UI plugin directory
- [ ] No duplicate plugin directories under `~/.local/share/Logos/`

## Plugin loading

- [ ] Module appears in Basecamp sidebar after relaunch
- [ ] Clicking module opens the QML UI (no blank screen)
- [ ] `Component.onCompleted` fires (check via initial state)
- [ ] No crash on load (check `journalctl --user -f` for segfaults)

## callModule round-trip

- [ ] Each `Q_INVOKABLE` method is callable from QML
- [ ] Each method returns valid JSON (verify with `JSON.parse`)
- [ ] Missing/misspelled method names return empty gracefully (no crash)
- [ ] Error responses contain `"error"` field with human-readable message

## QML behavior

- [ ] All text that users might copy uses `TextEdit` (not `Text`)
- [ ] No references to `Logos.Theme` or `Logos.Controls`
- [ ] No `FileDialog` usage (all file I/O through C++ plugin)
- [ ] Colors are hardcoded hex values
- [ ] UI remains responsive (no methods taking >100ms)
- [ ] Timer polling works (state updates without user interaction)

## State persistence

- [ ] Navigate away from module, navigate back
- [ ] State is restored from C++ (not lost on QML reload)
- [ ] `Component.onCompleted` re-initializes correctly on return

## Process management

- [ ] All Logos processes killed before testing (`ps aux | grep -i logos` shows nothing)
- [ ] Fresh launch after install (not reusing stale process)
- [ ] Debug logging visible (if using file logging to `/tmp/`)

## Packaging (before distribution)

- [ ] `plugin_metadata.json` has all required fields (not `{}`)
- [ ] `plugin_metadata.json` fields match `manifest.json`
- [ ] `metadata.json` `name` field matches directory name exactly
- [ ] IID in `Q_PLUGIN_METADATA` is unique to this module
- [ ] No sensitive data in committed files (.env, keys, credentials)

## LGX packaging (if distributing)

- [ ] `nix run .#package-lgx` produces both `.lgx` files
- [ ] Core LGX does NOT contain `libpcsclite.so` (if applicable)
- [ ] LGX installs correctly via Basecamp package manager
- [ ] Module works from LGX install (not just dev install)
