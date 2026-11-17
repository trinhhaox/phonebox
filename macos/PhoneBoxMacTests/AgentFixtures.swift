import Foundation

/// Responses captured from a running agent 0.9.18 (paths and device serial anonymised; /api/pair is not used by the app).
enum AgentFixtures {
    static let info = Data("""
    {"version":"0.9.18","os":"macos","configPath":"/Users/me/Library/Application Support/PhoneBox/config.json","logPath":"/Users/me/Library/Application Support/PhoneBox/agent.log","adb":"/opt/homebrew/bin/adb","connected":true,"via":"USB","devices":["adb-SERIAL._adb-tls-connect._tcp"],"appMissing":[],"usbProblem":null,"webviewProblem":null}
    """.utf8)

    static let infoDisconnected = Data("""
    {"version":"0.9.18","os":"macos","connected":false,"via":null,"devices":[],"appMissing":["adb-SERIAL"],"usbProblem":{"x":1},"webviewProblem":null}
    """.utf8)

    static let phones = Data("""
    [{"id":"dd6b9591ef32","model":"Jambo Technology JP1","lastSeen":1794933607169,"via":"USB","webView":"com.google.android.webview/157.0.8103.38","webviewProblem":null,"name":null,"pages":null},{"id":"d1da8796b824","model":"Apple iPhone15,3","lastSeen":1794933607169,"via":"Wi-Fi","webView":null,"webviewProblem":null,"name":"iPhone của tôi","pages":null}]
    """.utf8)
}
