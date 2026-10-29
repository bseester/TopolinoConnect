import Foundation
import WatchConnectivity

final class WatchSnapshotBridge: NSObject, WCSessionDelegate {
    static let shared = WatchSnapshotBridge()

    private var pendingSnapshot: WatchVehicleSnapshot?
    private var didActivate = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(_ snapshot: WatchVehicleSnapshot) {
        guard WCSession.isSupported() else { return }
        pendingSnapshot = snapshot
        guard didActivate, WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        send(snapshot)
    }

    private func send(_ snapshot: WatchVehicleSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let context = ["vehicleSnapshot": data]
        do {
            try WCSession.default.updateApplicationContext(context)
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(context, replyHandler: nil)
            }
        } catch {
            // The latest context is resent after activation; no vehicle control is sent.
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        didActivate = activationState == .activated
        if didActivate, let pendingSnapshot { send(pendingSnapshot) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
