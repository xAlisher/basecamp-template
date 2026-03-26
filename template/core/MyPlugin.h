#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <core/interface.h>

class MyPlugin : public QObject, public PluginInterface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.logos.MyModuleInterface" FILE "plugin_metadata.json")
    Q_INTERFACES(PluginInterface)

public:
    explicit MyPlugin(QObject* parent = nullptr);
    ~MyPlugin() override;

    // Required by PluginInterface
    QString name()    const override { return QStringLiteral("mymodule"); }
    QString version() const override { return QStringLiteral("1.0.0"); }

    // Called by shell via reflection — do NOT use override
    Q_INVOKABLE void initLogos(LogosAPI* api);

    // --- Your Q_INVOKABLE methods go here ---
    // Every method QML needs must be Q_INVOKABLE and return QString (JSON).
    // Missing Q_INVOKABLE = callModule silently returns empty string.

    Q_INVOKABLE QString initialize();
    Q_INVOKABLE QString getStatus();
    Q_INVOKABLE QString doWork(const QString& input);

signals:
    // Required — shell connects to this for event communication.
    // Without this signal, ModuleProxy can't connect and your plugin
    // won't communicate events. Include it even if you don't use it.
    void eventResponse(const QString& eventName, const QVariantList& data);

private:
    bool m_initialized = false;
};
