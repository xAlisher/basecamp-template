# QML Bridge: `callModule` Contract and QML Sandbox

## The `callModule` function

`logos.callModule` is the only way your QML UI communicates with your C++ core module. It's injected into the QML context by the Logos shell — you don't import it.

### Signature

```javascript
var result = logos.callModule(moduleName, methodName, paramsArray)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `moduleName` | string | The `name` field from your core module's `manifest.json` |
| `methodName` | string | Exact name of a `Q_INVOKABLE` method on your plugin class |
| `paramsArray` | array | Arguments in order — `["arg1", "arg2"]` or `[]` for no args |
| **return** | string | JSON string, or empty string on failure |

### Example: full round-trip

```cpp
// C++ — MyPlugin.h
Q_INVOKABLE QString greet(const QString& name) {
    QJsonObject result;
    result["message"] = "Hello, " + name;
    result["timestamp"] = QDateTime::currentSecsSinceEpoch();
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}
```

```javascript
// QML — Main.qml
function callBackend(method, params) {
    var raw = logos.callModule("mymodule", method, params)
    if (!raw || raw === "") {
        console.log("callModule returned empty for:", method)
        return null
    }
    try {
        return JSON.parse(raw)
    } catch (e) {
        console.log("JSON parse failed for:", method, "raw:", raw)
        return null
    }
}

// Usage
var result = callBackend("greet", ["Alice"])
if (result) {
    label.text = result.message  // "Hello, Alice"
}
```

### The wrapper pattern

Every production module uses a wrapper function like `callBackend` above. This gives you:
- Centralized error handling
- Consistent JSON parsing
- A single place to add logging during development
- Protection against empty/malformed returns

**Recommended:** Define this wrapper at the top of your `Main.qml` and never call `logos.callModule` directly.

## Return value rules

### Rule 1: Always return JSON strings from C++

```cpp
// CORRECT — returns JSON string
Q_INVOKABLE QString getCount() {
    QJsonObject result;
    result["count"] = 42;
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

// WRONG — returns raw int, QML can't use this reliably
Q_INVOKABLE int getCount() {
    return 42;
}
```

Raw return types (`bool`, `int`, `double`) don't cross the `callModule` boundary reliably. The shell serializes everything as strings. Always wrap in JSON.

### Rule 2: Always `JSON.parse()` in QML

```javascript
// CORRECT
var result = logos.callModule("mymodule", "getCount", [])
var obj = JSON.parse(result)
console.log(obj.count)  // 42 (number)

// WRONG — comparing string to number
var result = logos.callModule("mymodule", "getCount", [])
console.log(result.count)  // undefined (result is a string, not an object)
```

### Rule 3: Handle empty returns

```javascript
var result = logos.callModule("mymodule", "missingMethod", [])
// result === "" (empty string, not null, not undefined)

// This crashes:
var obj = JSON.parse(result)  // SyntaxError: unexpected end of input

// This is safe:
if (!result || result === "") {
    console.log("Method not found or returned empty")
    return
}
var obj = JSON.parse(result)
```

Empty returns happen when:
- The method name is misspelled
- The method exists but isn't marked `Q_INVOKABLE`
- The module name is wrong
- The core module failed to load

**There is no way to distinguish these cases from QML.** If you get empty returns, check the C++ side.

## Consistent response patterns

Adopt a convention for success and error responses. Both production modules use this pattern:

```cpp
// Success
QJsonObject result;
result["success"] = true;
result["data"] = someValue;
return QJsonDocument(result).toJson(QJsonDocument::Compact);

// Error
QJsonObject result;
result["error"] = "Human-readable error message";
return QJsonDocument(result).toJson(QJsonDocument::Compact);
```

```javascript
// QML
var obj = callBackend("someMethod", [])
if (obj && obj.error) {
    showError(obj.error)
} else if (obj && obj.success) {
    // Use obj.data
}
```

## Synchronous execution model

`callModule` blocks the QML thread until the C++ method returns. This has consequences:

### Keep methods fast

If a C++ method takes 500ms, the UI freezes for 500ms. Users will think the app crashed.

**Guideline:** Methods should return in <100ms. If you need to do something slow:

```cpp
// Start a long operation, return immediately
Q_INVOKABLE QString startExport() {
    // Kick off work in background (QThread, QFuture, etc.)
    m_exporter->startAsync();

    QJsonObject result;
    result["status"] = "started";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

// Check progress — called from QML Timer
Q_INVOKABLE QString checkExportStatus() {
    QJsonObject result;
    result["status"] = m_exporter->isRunning() ? "running" : "complete";
    result["progress"] = m_exporter->progress();
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}
```

```javascript
// QML — poll for completion
Timer {
    id: exportPoller
    interval: 500
    running: false
    repeat: true
    onTriggered: {
        var status = callBackend("checkExportStatus", [])
        if (status && status.status === "complete") {
            exportPoller.running = false
            showDone()
        }
    }
}

Button {
    text: "Export"
    onClicked: {
        callBackend("startExport", [])
        exportPoller.running = true
    }
}
```

### Polling is the standard pattern

Both keycard-basecamp and logos-notes use QML `Timer` components polling C++ state:

```javascript
Timer {
    interval: 500
    running: true
    repeat: true
    onTriggered: {
        var state = callBackend("getState", [])
        if (state) {
            root.currentState = state.state
        }
    }
}
```

This is the correct pattern for Basecamp modules. Don't try to use signals or callbacks from C++ to QML — the `callModule` bridge doesn't support them. Use polling.

## QML sandbox restrictions

Your QML runs inside the Logos shell's sandboxed environment. Several things that work in standalone Qt apps don't work here.

### What's blocked and why

| Feature | Status | Why | Workaround |
|---------|--------|-----|-----------|
| `import Logos.Theme` | Blocked | Not available in plugin sandbox | Hardcode hex colors |
| `import Logos.Controls` | Blocked | Shell-internal components | Use `QtQuick.Controls 2.15` |
| `FileDialog` | Blocked | Fails silently in plugin context | Move to C++ via `Q_INVOKABLE`, use `QFileDialog` or direct file I/O |
| File read/write | Blocked | QML has no filesystem access | All I/O through C++ plugin methods |
| `import QtQuick.Dialogs` | Unreliable | Some dialogs work, some don't | Test each individually; prefer C++ |
| Dynamic `Qt.createComponent()` | Limited | Can't load components from other plugins | Keep all QML in your plugin directory |
| Network requests from QML | Blocked | `XMLHttpRequest` not available | Use C++ `QNetworkAccessManager` |

### Hardcoded color palette

Since you can't use Logos.Theme, hardcode a dark palette that matches the Basecamp shell:

```javascript
// Standard Basecamp-compatible palette
readonly property color bgPrimary:   "#2b2b2b"   // Main background
readonly property color bgSecondary: "#1a1a1a"   // Cards, panels
readonly property color bgTertiary:  "#333333"   // Input fields
readonly property color textPrimary: "#ffffff"   // Main text
readonly property color textMuted:   "#888888"   // Secondary text
readonly property color border:      "#555555"   // Borders
readonly property color accent:      "#4a9eff"   // Links, active elements
readonly property color success:     "#00cc66"   // Success states
readonly property color error:       "#ff4444"   // Error states
readonly property color warning:     "#ffaa00"   // Warnings
```

### File I/O pattern

```cpp
// C++ — expose file operations as Q_INVOKABLE methods
Q_INVOKABLE QString saveToFile(const QString& filename, const QString& content) {
    QString path = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                   + "/" + filename;

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        return R"({"error": "Cannot open file"})";
    }
    file.write(content.toUtf8());
    file.close();

    QJsonObject result;
    result["success"] = true;
    result["path"] = path;
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}
```

```javascript
// QML — call C++ for all file operations
Button {
    text: "Save"
    onClicked: {
        var result = callBackend("saveToFile", ["notes.json", contentArea.text])
        if (result && result.error) {
            showError(result.error)
        }
    }
}
```

### Well-known paths

Use fixed paths that work inside the AppImage environment:

```cpp
// Data directory for your module
QString dataDir = QDir::homePath() + "/.local/share/Logos/LogosBasecamp/data/mymodule";
QDir().mkpath(dataDir);

// Temporary files
QString tempDir = "/tmp/mymodule";
QDir().mkpath(tempDir);
```

Don't rely on `QStandardPaths` returning the same path inside and outside the AppImage — test with the actual AppImage.

## State persistence across screen switches

When the user navigates away from your plugin in the sidebar, the Logos shell **destroys** your QML component tree. All QML property values are lost.

When the user navigates back, `Component.onCompleted` runs again from scratch.

### The pattern

```javascript
// On screen load — restore state from C++
Component.onCompleted: {
    var state = callBackend("getState", [])
    if (state) {
        root.currentScreen = state.screen
        root.userData = state.data
    }
}

// Before doing anything that might cause a screen switch — save state to C++
function saveState() {
    callBackend("saveState", [root.currentScreen, JSON.stringify(root.userData)])
}
```

**Key insight:** Your C++ module stays alive when QML is destroyed. Use it as your state store.

## QML text display

Use `TextEdit` instead of `Text` if users need to copy content:

```javascript
// WRONG — Text can't be selected or copied
Text {
    text: resultJson
    wrapMode: Text.Wrap
}

// CORRECT — TextEdit with read-only for copyable text
TextEdit {
    text: resultJson
    readOnly: true
    selectByMouse: true
    selectByKeyboard: true
    wrapMode: TextEdit.Wrap
    color: "#ffffff"
    font.family: "monospace"
}
```

## Imports that work

These imports are safe to use in plugin QML:

```javascript
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
```

Stick to these three unless you've tested a specific import inside the AppImage.
