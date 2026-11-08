// The network extension. iOS starts this process, hands it the wg-quick text
// the app saved, and WireGuardKit (the official engine) drives the tunnel.
// It also holds the auto-close deadline: the door shuts itself at `closeAt`
// even when the app is not running.

import NetworkExtension
import WireGuardKit
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {
    private lazy var adapter = WireGuardAdapter(with: self) { level, message in
        os_log("%{public}@", log: .default, type: level == .error ? .error : .debug, message)
    }
    private var closeAt: TimeInterval = 0          // unix seconds; 0 = stays open
    private var timer: DispatchSourceTimer?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let text = proto.providerConfiguration?["wgQuickConfig"] as? String,
              let config = try? TunnelConfiguration(fromWgQuickConfig: text, called: "serdab") else {
            completionHandler(NSError(domain: "serdab", code: 1, userInfo: [NSLocalizedDescriptionKey: "The saved config is not valid."]))
            return
        }
        closeAt = (proto.providerConfiguration?["closeAt"] as? NSNumber)?.doubleValue ?? 0
        adapter.start(tunnelConfiguration: config) { [weak self] error in
            if let error { os_log("serdab: start failed: %{public}@", type: .error, String(describing: error)) }
            if error == nil { self?.watchDeadline() }
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        timer?.cancel()
        adapter.stop { _ in completionHandler() }
    }

    /// Checked against the wall clock every 20 s, so a phone that slept through
    /// the deadline still closes the moment it wakes.
    private func watchDeadline() {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 20, repeating: 20, leeway: .seconds(5))
        t.setEventHandler { [weak self] in
            guard let self, self.closeAt > 0, Date().timeIntervalSince1970 >= self.closeAt else { return }
            os_log("serdab: auto-close deadline reached", type: .info)
            self.timer?.cancel()
            self.cancelTunnelWithError(nil)
        }
        t.resume()
        timer = t
    }

    /// Messages from the app: [0] = send the runtime stats;
    /// [1] + 8-byte little-endian Double = the new close deadline (0 = stay open).
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        if messageData.count == 1 && messageData[0] == 0 {
            guard let completionHandler else { return }
            adapter.getRuntimeConfiguration { completionHandler($0?.data(using: .utf8)) }
        } else if messageData.count == 9 && messageData[0] == 1 {
            var bits: UInt64 = 0
            for (i, b) in messageData.dropFirst().enumerated() { bits |= UInt64(b) << (8 * UInt64(i)) }
            closeAt = Double(bitPattern: bits)
            completionHandler?(Data([1]))
        } else {
            completionHandler?(nil)
        }
    }
}
