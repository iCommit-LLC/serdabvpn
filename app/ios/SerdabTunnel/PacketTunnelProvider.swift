// The network extension. iOS starts this process, hands it the wg-quick text
// the app saved, and WireGuardKit (the official engine) drives the tunnel.

import NetworkExtension
import WireGuardKit
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {
    private lazy var adapter = WireGuardAdapter(with: self) { level, message in
        os_log("%{public}@", log: .default, type: level == .error ? .error : .debug, message)
    }

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let text = proto.providerConfiguration?["wgQuickConfig"] as? String,
              let config = try? TunnelConfiguration(fromWgQuickConfig: text, called: "serdab") else {
            completionHandler(NSError(domain: "serdab", code: 1, userInfo: [NSLocalizedDescriptionKey: "The saved config is not valid."]))
            return
        }
        adapter.start(tunnelConfiguration: config) { error in
            if let error { os_log("serdab: start failed: %{public}@", type: .error, String(describing: error)) }
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        adapter.stop { _ in completionHandler() }
    }

    /// One byte 0 from the app means "send me the runtime stats".
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        guard let completionHandler else { return }
        if messageData.count == 1 && messageData[0] == 0 {
            adapter.getRuntimeConfiguration { completionHandler($0?.data(using: .utf8)) }
        } else {
            completionHandler(nil)
        }
    }
}
