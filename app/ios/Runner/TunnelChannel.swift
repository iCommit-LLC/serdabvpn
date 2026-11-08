// The iOS half of the `serdab/tunnel` channel: one NETunnelProviderManager that
// hands the wg-quick text to the SerdabTunnel network extension and relays the
// system's VPN status back to Dart.

import Flutter
import NetworkExtension

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
            connect(config, alwaysOn: (args["alwaysOn"] as? Bool) ?? true, result)
        case "disconnect":
            disconnect(result)
        case "setAlwaysOn":
            let enabled = ((call.arguments as? [String: Any])?["enabled"] as? Bool) ?? true
            setAlwaysOn(enabled, result)
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
    private func connect(_ config: String, alwaysOn: Bool, _ result: @escaping FlutterResult) {
        load { [weak self] existing in
            guard let self else { return }
            let manager = existing ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = TunnelChannel.providerBundleId
            proto.providerConfiguration = ["wgQuickConfig": config]
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

    @objc private func statusChanged(_ note: Notification) {
        guard let connection = note.object as? NEVPNConnection else { return }
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
