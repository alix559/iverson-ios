import CoreBluetooth
import Foundation
import Observation
import os

/// BLE GATT peripheral that advertises as `iverson-XXXX` so a computer running
/// `iverson-receive --code XXXX` can subscribe and receive Unicode text.
///
/// `CBPeripheralManager` is created lazily on first Link/advertise so SwiftUI
/// view rebuilds never spin up (and tear down) CoreBluetooth XPC connections.
@Observable
@MainActor
final class BluetoothKeyboardPeripheral: NSObject {
    // Must match iverson.bt (SERVICE / CHAR) — computer scans by service UUID + link code.
    static let serviceUUID = CBUUID(string: "6e616461-6b69-7400-4b42-000000000001")
    static let characteristicUUID = CBUUID(string: "6e616461-6b69-7400-4b42-000000000002")
    static let localNameBase = "iverson"
    private static let maxChunkBytes = 160
    private static let logger = Logger(subsystem: "io.iverson", category: "bt")

    /// CoreBluetooth may outlive this object briefly; `nonisolated(unsafe)` lets `deinit` stop advertising.
    nonisolated(unsafe) private var manager: CBPeripheralManager?
    private var characteristic: CBMutableCharacteristic?
    private var pendingChunks: [Data] = []
    private var wantsAdvertising = false

    /// Four-digit code shown in the UI and embedded in the BLE local name (`iverson-4821`).
    var linkCode: String?
    var isPoweredOn = false
    var isAdvertising = false
    var serviceReady = false
    var subscriberCount = 0
    var statusText = "Link off"
    var sentCount = 0
    var droppedCount = 0
    var notifyFailCount = 0
    var logLines: [String] = []

    var isConnectedToPC: Bool { subscriberCount > 0 }

    var advertisedLocalName: String {
        guard let linkCode else { return Self.localNameBase }
        return "\(Self.localNameBase)-\(linkCode)"
    }

    override init() {
        super.init()
        // Do not create CBPeripheralManager here — SwiftUI may construct this
        // object during view setup; creating the manager immediately causes
        // init/deinit thrashing and "XPC connection invalid" storms.
    }

    /// Ensure a single long-lived peripheral manager exists.
    private func ensureManager() -> CBPeripheralManager {
        if let manager { return manager }
        log("init peripheral manager (lazy)")
        let created = CBPeripheralManager(delegate: self, queue: nil)
        manager = created
        return created
    }

    func startAdvertising() {
        wantsAdvertising = true
        linkCode = Self.makeLinkCode()
        let mgr = ensureManager()
        log("startAdvertising requested code=\(linkCode ?? "?") state=\(stateName(mgr.state))")
        statusText = "Starting Bluetooth…"
        guard mgr.state == .poweredOn else {
            statusText = "Waiting for Bluetooth…"
            return
        }
        rebuildService()
    }

    func stopAdvertising() {
        wantsAdvertising = false
        isAdvertising = false
        serviceReady = false
        subscriberCount = 0
        linkCode = nil
        pendingChunks.removeAll()
        guard let manager else {
            statusText = "Link off"
            return
        }
        if manager.isAdvertising {
            manager.stopAdvertising()
        }
        manager.removeAllServices()
        characteristic = nil
        statusText = "Link off"
        log("stopAdvertising")
    }

    /// Re-advertise after returning to foreground if Link was left on.
    func resumeIfNeeded() {
        guard wantsAdvertising else { return }
        let mgr = ensureManager()
        guard mgr.state == .poweredOn else { return }
        if !serviceReady {
            rebuildService()
        } else if !mgr.isAdvertising {
            beginAdvertisingNow()
        }
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let manager, let characteristic, isAdvertising, subscriberCount > 0 else {
            statusText = wantsAdvertising
                ? "Waiting for computer…"
                : "Turn on Link first."
            droppedCount += 1
            log("send DROPPED text=\(preview(trimmed)) wantsAdv=\(wantsAdvertising) advertising=\(isAdvertising) subscribers=\(subscriberCount) droppedTotal=\(droppedCount)")
            return
        }

        let chunks = Self.utf8Chunks(trimmed, maxBytes: Self.maxChunkBytes)
        log("send enqueue text=\(preview(trimmed)) bytes=\(trimmed.utf8.count) chunks=\(chunks.count) pendingBefore=\(pendingChunks.count)")
        for chunk in chunks {
            pendingChunks.append(chunk)
        }
        flushPending(using: characteristic, manager: manager)
    }

    private func rebuildService() {
        guard let manager else { return }
        log("rebuildService: removeAllServices then add \(Self.serviceUUID.uuidString)")
        serviceReady = false
        manager.removeAllServices()
        characteristic = nil
        let props: CBCharacteristicProperties = [.read, .notify]
        let perms: CBAttributePermissions = [.readable]
        let char = CBMutableCharacteristic(
            type: Self.characteristicUUID,
            properties: props,
            value: nil,
            permissions: perms
        )
        characteristic = char
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [char]
        manager.add(service)
    }

    private func beginAdvertisingNow() {
        guard let manager else { return }
        let name = advertisedLocalName
        var payload: [String: Any] = [
            CBAdvertisementDataLocalNameKey: name,
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]
        ]
        // iOS often surfaces the phone GAP name to scanners instead of our local
        // name — also put the link code in manufacturer data so receive can match.
        if let linkCode, let codeData = linkCode.data(using: .utf8) {
            var mfg = Data([0xFF, 0xFF]) // little-endian company id 0xFFFF (dev/testing)
            mfg.append(codeData)
            payload[CBAdvertisementDataManufacturerDataKey] = mfg
        }
        log("calling startAdvertising name=\(name) service=\(Self.serviceUUID.uuidString) code=\(linkCode ?? "-")")
        manager.startAdvertising(payload)
    }

    deinit {
        // `deinit` is nonisolated — only touch `nonisolated(unsafe)` storage here.
        if let manager {
            if manager.isAdvertising {
                manager.stopAdvertising()
            }
            manager.removeAllServices()
        }
        print("[iverson-bt] deinit: stopped advertising and removed services")
    }

    private func flushPending(using characteristic: CBMutableCharacteristic, manager: CBPeripheralManager) {
        var flushed = 0
        while !pendingChunks.isEmpty {
            let chunk = pendingChunks[0]
            characteristic.value = chunk
            let ok = manager.updateValue(chunk, for: characteristic, onSubscribedCentrals: nil)
            if ok {
                pendingChunks.removeFirst()
                sentCount += 1
                flushed += 1
                log("notify OK #\(sentCount) bytes=\(chunk.count) text=\(preview(String(data: chunk, encoding: .utf8) ?? "")) pendingLeft=\(pendingChunks.count)")
            } else {
                notifyFailCount += 1
                statusText = "Computer buffer full — waiting…"
                log("notify BUSY/FAIL #\(notifyFailCount) bytes=\(chunk.count) pending=\(pendingChunks.count) (will retry when ready)")
                return
            }
        }
        if flushed > 0 {
            statusText = "Sent"
            log("flush complete flushed=\(flushed) sentTotal=\(sentCount)")
        }
    }

    static func makeLinkCode() -> String {
        String(Int.random(in: 1000...9999))
    }

    static func utf8Chunks(_ text: String, maxBytes: Int) -> [Data] {
        var chunks: [Data] = []
        var current = Data()
        for ch in text {
            var piece = Data()
            for unit in String(ch).utf8 {
                piece.append(unit)
            }
            if current.count + piece.count > maxBytes, !current.isEmpty {
                chunks.append(current)
                current = Data()
            }
            current.append(piece)
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private func preview(_ text: String, limit: Int = 80) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: "\\n")
        if oneLine.count <= limit { return "\"\(oneLine)\"" }
        let idx = oneLine.index(oneLine.startIndex, offsetBy: limit)
        return "\"\(oneLine[..<idx])…\"(+\(oneLine.count - limit))"
    }

    private func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)"
        Self.logger.log("\(message, privacy: .public)")
        print("[iverson-bt] \(line)")
        logLines.append(line)
        if logLines.count > 200 {
            logLines.removeFirst(logLines.count - 200)
        }
    }

    private func stateName(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "other(\(state.rawValue))"
        }
    }
}

extension BluetoothKeyboardPeripheral: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor in
            self.handleDidUpdateState(peripheral)
        }
    }

    private func handleDidUpdateState(_ peripheral: CBPeripheralManager) {
        isPoweredOn = peripheral.state == .poweredOn
        log("manager state → \(stateName(peripheral.state)) wantsAdvertising=\(wantsAdvertising)")
        switch peripheral.state {
        case .poweredOn:
            statusText = isAdvertising ? statusText : "Bluetooth ready"
            if wantsAdvertising {
                serviceReady = false
                rebuildService()
            }
        case .poweredOff:
            isAdvertising = false
            serviceReady = false
            statusText = "Bluetooth is off"
        case .unauthorized:
            statusText = "Allow Bluetooth for this app in Settings"
        case .unsupported:
            statusText = "Bluetooth LE unsupported on this device"
        case .resetting:
            isAdvertising = false
            serviceReady = false
            subscriberCount = 0
            statusText = "Bluetooth resetting…"
        default:
            statusText = "Bluetooth unavailable"
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        Task { @MainActor in
            self.handleDidStartAdvertising(peripheral, error: error)
        }
    }

    private func handleDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if let error {
            isAdvertising = false
            statusText = "Advertise failed: \(error.localizedDescription)"
            log("advertise FAILED: \(error.localizedDescription)")
            return
        }
        isAdvertising = true
        statusText = "Waiting for computer…"
        log("advertise OK as \(advertisedLocalName) isAdvertising=\(peripheral.isAdvertising)")
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        Task { @MainActor in
            self.handleDidAdd(service, peripheral: peripheral, error: error)
        }
    }

    private func handleDidAdd(_ service: CBService, peripheral: CBPeripheralManager, error: (any Error)?) {
        if let error {
            serviceReady = false
            statusText = "Service error: \(error.localizedDescription)"
            log("addService FAILED \(service.uuid.uuidString): \(error.localizedDescription)")
            return
        }
        serviceReady = true
        log("addService OK \(service.uuid.uuidString) chars=\(service.characteristics?.count ?? 0) wantsAdvertising=\(wantsAdvertising)")
        if wantsAdvertising, !peripheral.isAdvertising {
            beginAdvertisingNow()
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        Task { @MainActor in
            self.handleSubscribe(central: central, characteristic: characteristic)
        }
    }

    private func handleSubscribe(central: CBCentral, characteristic: CBCharacteristic) {
        subscriberCount += 1
        statusText = "Linked — speak to type"
        log("SUBSCRIBE central=\(central.identifier.uuidString) mtu=\(central.maximumUpdateValueLength) subscribers=\(subscriberCount) char=\(characteristic.uuid.uuidString)")
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        Task { @MainActor in
            self.handleUnsubscribe(central: central)
        }
    }

    private func handleUnsubscribe(central: CBCentral) {
        subscriberCount = max(0, subscriberCount - 1)
        statusText = subscriberCount == 0
            ? "Waiting for computer…"
            : "Linked — speak to type"
        log("UNSUBSCRIBE central=\(central.identifier.uuidString) subscribers=\(subscriberCount) pending=\(pendingChunks.count)")
    }

    nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Task { @MainActor in
            self.handleReadyToUpdate()
        }
    }

    private func handleReadyToUpdate() {
        log("readyToUpdateSubscribers pending=\(pendingChunks.count)")
        guard let manager, let characteristic else { return }
        flushPending(using: characteristic, manager: manager)
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        Task { @MainActor in
            self.handleRead(request, peripheral: peripheral)
        }
    }

    private func handleRead(_ request: CBATTRequest, peripheral: CBPeripheralManager) {
        let value = characteristic?.value ?? Data()
        log("READ request central=\(request.central.identifier.uuidString) offset=\(request.offset) bytes=\(value.count)")
        request.value = value
        peripheral.respond(to: request, withResult: .success)
    }
}
