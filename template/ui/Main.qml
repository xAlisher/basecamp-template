import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    width: 800
    height: 600
    color: "#2b2b2b"

    // --- State ---
    property string moduleStatus: "unknown"
    property string lastResult: ""
    property string lastError: ""

    // --- callModule wrapper ---
    // Use this for ALL backend calls. Never call logos.callModule directly.
    // Handles empty returns and JSON parsing in one place.
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

    // --- Initialize on load ---
    // Component.onCompleted fires every time the user navigates to this plugin.
    // QML state is destroyed on navigation away, so reload everything here.
    Component.onCompleted: {
        var result = callBackend("initialize", [])
        if (result && result.initialized) {
            root.moduleStatus = "ready"
        } else {
            root.moduleStatus = "init_failed"
        }
    }

    // --- Poll for status updates (standard Basecamp pattern) ---
    // Use Timer + polling instead of signals/callbacks.
    // callModule is synchronous, so keep poll handlers fast (<100ms).
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            var status = callBackend("getStatus", [])
            if (status) {
                root.moduleStatus = status.status
            }
        }
    }

    // --- UI Layout ---
    ScrollView {
        anchors.fill: parent
        anchors.margins: 20
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 16

            // Header
            Text {
                text: "My Module"
                font.pixelSize: 24
                font.bold: true
                color: "#ffffff"
                Layout.alignment: Qt.AlignHCenter
            }

            // Status indicator
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                color: "#1a1a1a"
                border.color: "#555555"
                border.width: 1
                radius: 4

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 10

                    Text {
                        text: "Status:"
                        color: "#888888"
                        font.pixelSize: 14
                    }

                    Text {
                        text: root.moduleStatus
                        font.pixelSize: 18
                        font.bold: true
                        color: root.moduleStatus === "ready" ? "#00cc66" : "#ff4444"
                    }
                }
            }

            // Input section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: inputColumn.implicitHeight + 32
                color: "#1a1a1a"
                border.color: "#555555"
                border.width: 1
                radius: 4

                ColumnLayout {
                    id: inputColumn
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Text {
                        text: "Do Work"
                        color: "#ffffff"
                        font.pixelSize: 16
                        font.bold: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        TextField {
                            id: inputField
                            Layout.fillWidth: true
                            placeholderText: "Enter input..."
                            color: "#ffffff"
                            font.pixelSize: 14
                            background: Rectangle {
                                color: "#333333"
                                border.color: inputField.activeFocus ? "#4a9eff" : "#555555"
                                radius: 4
                            }
                        }

                        Button {
                            text: "Execute"
                            onClicked: {
                                root.lastError = ""
                                var result = callBackend("doWork", [inputField.text])
                                if (!result) {
                                    root.lastError = "No response from backend"
                                    root.lastResult = ""
                                } else if (result.error) {
                                    root.lastError = result.error
                                    root.lastResult = ""
                                } else {
                                    root.lastResult = JSON.stringify(result, null, 2)
                                    root.lastError = ""
                                }
                            }
                        }
                    }

                    // Error display
                    Text {
                        visible: root.lastError !== ""
                        text: root.lastError
                        color: "#ff4444"
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    // Result display — TextEdit for copy/paste support
                    // NEVER use Text for results — users can't select or copy from Text.
                    TextEdit {
                        visible: root.lastResult !== ""
                        text: root.lastResult
                        readOnly: true
                        selectByMouse: true
                        selectByKeyboard: true
                        wrapMode: TextEdit.Wrap
                        color: "#00cc66"
                        font.pixelSize: 13
                        font.family: "monospace"
                        Layout.fillWidth: true
                    }
                }
            }

            // Instructions
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: helpText.implicitHeight + 32
                color: "#1a1a1a"
                border.color: "#555555"
                border.width: 1
                radius: 4

                Text {
                    id: helpText
                    anchors.fill: parent
                    anchors.margins: 16
                    text: "This is a template module. Replace the doWork method with your logic.\n\n" +
                          "Key patterns demonstrated:\n" +
                          "• callBackend() wrapper for all logos.callModule calls\n" +
                          "• Component.onCompleted for initialization\n" +
                          "• Timer polling for state updates\n" +
                          "• Error handling for empty/failed responses\n" +
                          "• TextEdit for copyable result display"
                    color: "#888888"
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                    lineHeight: 1.4
                }
            }
        }
    }
}
