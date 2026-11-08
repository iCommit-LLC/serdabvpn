// The iOS half of the `serdab/tunnel` channel: one NETunnelProviderManager that
// hands the wg-quick text to the SerdabTunnel network extension and relays the
// system's VPN status back to Dart.

import Flutter
import NetworkExtension
import UserNotifications

final class TunnelChannel: NSObject, FlutterStreamHandler {
    static let providerBundleId = "app.serdabvpn.tunnel"

    private var manager: NETunnelProviderManager?
    private var sink: FlutterEventSink?

    init(messenger: FlutterBinaryMessenger) {
        super.init()
        let methods = FlutterMethodChannel(name: "serdab/tunnel", binaryMessenger: messenger)
        methods.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
        FlutterEventChannel(name: "serdab/tunnel/state", binaryMessenger: messenger).setStreamHandler(self)
        NotificationCenter.default.addObserver(self, selector: #selector(statusChanged), name: .NEVPNStatusDidChange, object: nil)
        load { _ in }
    }

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case "prepare":
            result(true) // iOS asks the user itself the first time the profile is saved
        case "connect":
            guard let args = call.arguments as? [String: Any], let config = args["config"] as? String else {
                result(FlutterError(code: "bad_config", message: "no config", details: nil))
                return
            }
            connect(config, alwaysOn: (args["alwaysOn"] as? Bool) ?? false,
                    closeAfterMinutes: (args["closeAfterMinutes"] as? Int) ?? 0, result)
        case "disconnect":
            disconnect(result)
        case "setAlwaysOn":
            let enabled = ((call.arguments as? [String: Any])?["enabled"] as? Bool) ?? true
            setAlwaysOn(enabled, result)
        case "extend":
            let minutes = ((call.arguments as? [String: Any])?["minutes"] as? Int) ?? 60
            TunnelChannel.extend(minutes: minutes) { at in result(at.map { Int($0 * 1000) }) }
        case "closeAt":
            let at = AutoClose.closeAt
            result(at > 0 ? Int(at * 1000) : nil)
        case "requestNotifications":
            AutoClose.requestPermission()
            result(nil)
        case "state":
            result(Self.word(for: manager?.connection.status ?? .invalid))
        case "stats":
            stats(result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func load(_ done: @escaping (NETunnelProviderManager?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            let mine = managers?.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == TunnelChannel.providerBundleId
            }
            self?.manager = mine
            done(mine)
        }
    }

    /// "Stay underground" on iOS is the system's own on-demand rule: whenever
    /// the phone has any network, iOS raises the tunnel itself, after a reboot
    /// too. No background process of ours is involved.
    private func connect(_ config: String, alwaysOn: Bool, closeAfterMinutes: Int, _ result: @escaping FlutterResult) {
        let closeAt = !alwaysOn && closeAfterMinutes > 0 ? Date().timeIntervalSince1970 + Double(closeAfterMinutes * 60) : 0
        load { [weak self] existing in
            guard let self else { return }
            let manager = existing ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = TunnelChannel.providerBundleId
            proto.providerConfiguration = ["wgQuickConfig": config, "closeAt": NSNumber(value: closeAt)]
            proto.serverAddress = Self.endpointHost(in: config) ?? "serdab"
            manager.protocolConfiguration = proto
            manager.localizedDescription = "Serdab"
            manager.isEnabled = true
            manager.onDemandRules = [NEOnDemandRuleConnect()]
            manager.isOnDemandEnabled = alwaysOn
            manager.saveToPreferences { error in
                if let error {
                    result(FlutterError(code: "save", message: error.localizedDescription, details: nil))
                    return
                }
                manager.loadFromPreferences { error in
                    if let error {
                        result(FlutterError(code: "load", message: error.localizedDescription, details: nil))
                        return
                    }
                    self.manager = manager
                    do {
                        try manager.connection.startVPNTunnel(options: ["activationAttemptId": UUID().uuidString as NSString])
                        AutoClose.set(closeAt)
                        result(nil)
                    } catch {
                        result(FlutterError(code: "start", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }

    /// A deliberate disconnect must also switch on-demand off, or iOS would
    /// reopen the door the moment it shut. The next connect arms it again.
    private func disconnect(_ result: @escaping FlutterResult) {
        AutoClose.set(0)
        guard let manager else { result(nil); return }
        if manager.isOnDemandEnabled {
            manager.isOnDemandEnabled = false
            manager.saveToPreferences { _ in
                manager.connection.stopVPNTunnel()
                result(nil)
            }
        } else {
            manager.connection.stopVPNTunnel()
            result(nil)
        }
    }

    private func setAlwaysOn(_ enabled: Bool, _ result: @escaping FlutterResult) {
        load { manager in
            guard let manager else { result(nil); return } // nothing saved yet; connect will arm it
            manager.onDemandRules = [NEOnDemandRuleConnect()]
            manager.isOnDemandEnabled = enabled
            if enabled { TunnelChannel.setDeadline(0, on: manager) }
            manager.saveToPreferences { error in
                if let error { result(FlutterError(code: "save", message: error.localizedDescription, details: nil)) } else { result(nil) }
            }
        }
    }

    /// Asks the extension for WireGuard's runtime config and sums the peer counters.
    private func stats(_ result: @escaping FlutterResult) {
        guard let session = manager?.connection as? NETunnelProviderSession, session.status == .connected else {
            result(nil)
            return
        }
        do {
            try session.sendProviderMessage(Data([0])) { data in
                guard let data, let text = String(data: data, encoding: .utf8) else {
                    result(nil)
                    return
                }
                var rx = 0, tx = 0, handshake = 0
                for line in text.split(separator: "\n") {
                    let parts = line.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2, let value = Int(parts[1]) else { continue }
                    switch parts[0] {
                    case "rx_bytes": rx += value
                    case "tx_bytes": tx += value
                    case "last_handshake_time_sec": handshake = max(handshake, value)
                    default: break
                    }
                }
                result(["rxBytes": rx, "txBytes": tx, "lastHandshake": handshake])
            }
        } catch {
            result(nil)
        }
    }

    /// Renews for [minutes] from now, only within the last ten minutes before
    /// the deadline (otherwise the deadline stays): hours never stack.
    /// Static and Flutter-free: the "+1 hour" notification button runs it with
    /// the app in the background, before any Flutter engine exists.
    static func extend(minutes: Int, _ done: @escaping (TimeInterval?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            guard let manager = managers?.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerBundleId
            }), manager.connection.status == .connected || manager.connection.status == .connecting else {
                done(nil); return
            }
            let now = Date().timeIntervalSince1970
            guard AutoClose.closeAt > 0, AutoClose.closeAt - now <= AutoClose.renewWindow + 30 else {
                done(AutoClose.closeAt > 0 ? AutoClose.closeAt : nil); return
            }
            let at = now + Double(minutes * 60)
            setDeadline(at, on: manager)
            manager.saveToPreferences { _ in
                AutoClose.set(at)
                done(at)
            }
        }
    }

    /// Tells the running extension, and the saved profile for its next start.
    static func setDeadline(_ at: TimeInterval, on manager: NETunnelProviderManager) {
        if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol {
            var pc = proto.providerConfiguration ?? [:]
            pc["closeAt"] = NSNumber(value: at)
            proto.providerConfiguration = pc
        }
        var bits = at.bitPattern
        let msg = Data([1]) + withUnsafeBytes(of: &bits) { Data($0) }
        try? (manager.connection as? NETunnelProviderSession)?.sendProviderMessage(msg) { _ in }
        if at == 0 { AutoClose.set(0) }
    }

    @objc private func statusChanged(_ note: Notification) {
        guard let connection = note.object as? NEVPNConnection else { return }
        // Closed early (by hand, or from Settings): drop the pending warnings.
        if connection.status == .disconnected, AutoClose.closeAt > Date().timeIntervalSince1970 + 60 { AutoClose.set(0) }
        sink?(Self.word(for: connection.status))
    }

    private static func word(for status: NEVPNStatus) -> String {
        switch status {
        case .connected: return "connected"
        case .connecting, .reasserting: return "connecting"
        case .disconnecting: return "disconnecting"
        default: return "disconnected"
        }
    }

    static func endpointHost(in config: String) -> String? {
        for line in config.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.lowercased().hasPrefix("endpoint"), let eq = t.firstIndex(of: "=") else { continue }
            let value = t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let colon = value.lastIndex(of: ":") { return String(value[..<colon]) }
            return value
        }
        return nil
    }

    // MARK: FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        events(Self.word(for: manager?.connection.status ?? .invalid))
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
}

/// The deadline as the app knows it, and the two local notifications around it:
/// a warning five minutes before (with "+1 hour"), and "closed" at the deadline.
enum AutoClose {
    static let category = "serdab.close"
    static let extendAction = "serdab.extend"
    static let renewWindow: TimeInterval = 600     // renewing is only possible in the last 10 minutes
    private static let key = "serdab.closeAt"

    static var closeAt: TimeInterval { UserDefaults.standard.double(forKey: key) }

    static func requestPermission() {
        let c = UNUserNotificationCenter.current()
        c.setNotificationCategories([UNNotificationCategory(
            identifier: category,
            actions: [UNNotificationAction(identifier: extendAction, title: Words.extend, options: [])],
            intentIdentifiers: [], options: [])])
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func set(_ at: TimeInterval) {
        UserDefaults.standard.set(at, forKey: key)
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ["serdab.warn", "serdab.closed"])
        c.removeDeliveredNotifications(withIdentifiers: ["serdab.warn"])
        let now = Date().timeIntervalSince1970
        guard at > now else { return }
        let time = DateFormatter.localizedString(from: Date(timeIntervalSince1970: at), dateStyle: .none, timeStyle: .short)
        if at - renewWindow > now + 1 {
            let warn = UNMutableNotificationContent()
            warn.title = Words.warnTitle
            warn.body = Words.warnBody(time)
            warn.categoryIdentifier = category
            warn.sound = .default
            c.add(UNNotificationRequest(identifier: "serdab.warn", content: warn,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: at - renewWindow - now, repeats: false)))
        }
        let closed = UNMutableNotificationContent()
        closed.title = Words.closedTitle
        closed.body = Words.closedBody
        c.add(UNNotificationRequest(identifier: "serdab.closed", content: closed,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, at - now + 25), repeats: false)))
    }
}

/// The words the native side shows, in the phone's language (en, fr, ar).
enum Words {
    private static func t(_ en: String, _ fr: String, _ ar: String) -> String {
        switch Locale.preferredLanguages.first?.prefix(2) {
        case "fr": return fr
        case "ar": return ar
        default: return en
        }
    }
    static var warnTitle: String { t("Serdab closes in 10 minutes", "Serdab se ferme dans 10 minutes", "سيُغلق سرداب خلال 10 دقائق") }
    static func warnBody(_ time: String) -> String {
        t("At \(time). Still on a call? Renew for one hour.", "À \(time). Toujours en appel ? Renouvelez pour une heure.", "عند \(time). ما زلت في مكالمة؟ جدّد لساعة.")
    }
    static var extend: String { t("Renew 1 hour", "Renouveler 1 h", "جدّد ساعة") }
    static var closedTitle: String { t("Serdab closed", "Serdab est fermé", "أُغلق سرداب") }
    static var closedBody: String { t("Open the app when you need it again.", "Ouvrez l'app quand vous en avez besoin.", "افتح التطبيق عندما تحتاجه مجددًا.") }
}
