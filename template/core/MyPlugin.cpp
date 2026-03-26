#include "MyPlugin.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

MyPlugin::MyPlugin(QObject* parent)
    : QObject(parent)
{
    qDebug() << "MyPlugin constructed";
}

MyPlugin::~MyPlugin()
{
    qDebug() << "MyPlugin destroyed";
}

void MyPlugin::initLogos(LogosAPI* api)
{
    // Use the base class member — do NOT declare your own LogosAPI* member.
    // The shell checks PluginInterface::logosAPI to verify initialization.
    // Declaring a private member shadows it and breaks initialization detection.
    logosAPI = api;
    qDebug() << "MyPlugin: Logos API initialized";
}

QString MyPlugin::initialize()
{
    qDebug() << "MyPlugin::initialize() called";
    m_initialized = true;

    // Always return JSON. Never return raw types (bool, int, etc.)
    // because they don't cross the callModule bridge reliably.
    QJsonObject result;
    result["initialized"] = true;
    result["version"] = version();
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString MyPlugin::getStatus()
{
    QJsonObject result;
    result["initialized"] = m_initialized;
    result["status"] = m_initialized ? "ready" : "not_initialized";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString MyPlugin::doWork(const QString& input)
{
    qDebug() << "MyPlugin::doWork() called with:" << input;

    if (!m_initialized) {
        QJsonObject result;
        result["error"] = "Module not initialized — call initialize() first";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // --- Your business logic here ---

    QJsonObject result;
    result["success"] = true;
    result["input"] = input;
    result["output"] = "Processed: " + input;
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}
