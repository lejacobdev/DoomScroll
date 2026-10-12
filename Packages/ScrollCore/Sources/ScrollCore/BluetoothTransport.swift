#if canImport(CoreBluetooth)
import CoreBluetooth
import Foundation
import os

/// Backup transport: the Mac advertises one writable Bluetooth LE characteristic and the
/// iPhone/Watch writes the same signed, newline-delimited messages to it that they
/// would otherwise send over TCP. Authentication and replay protection are identical.
public enum BluetoothTransport {
    public static let service = CBUUID(string: "7B3D8E10-5C1A-4F7B-9A52-D005C011A001")
    public static let characteristic = CBUUID(string: "7B3D8E10-5C1A-4F7B-9A52-D005C011A002")
    /// Advertisements carry a short name; both sides compare this form.
    public static func advertisedName(for macName: String) -> String { String(macName.prefix(20)) }
}

// MARK: - Mac side (peripheral)

public final class BLEScrollServer: NSObject, CBPeripheralManagerDelegate, @unchecked Sendable {
    private struct Peer {
        var framer = LineFramer()
        var replay = ReplayGuard()
        var lastSeen = Date()
    }

    private let queue = DispatchQueue(label: "dev.doomscroll.ble.server")
    private let log = Logger(subsystem: "dev.doomscroll", category: "ble-server")
    private let localName: String
    private let callbacks: ScrollServer.Callbacks
    private var authenticator: MessageAuthenticator
    private var manager: CBPeripheralManager?
    private var peers: [UUID: Peer] = [:]
    private var pruneTimer: DispatchSourceTimer?

    public init(key: Data, macName: String, callbacks: ScrollServer.Callbacks) {
        self.authenticator = MessageAuthenticator(key: key)
        self.localName = BluetoothTransport.advertisedName(for: macName)
        self.callbacks = callbacks
    }

    public func start() {
        queue.async {
            guard self.manager == nil else { return }
            self.manager = CBPeripheralManager(delegate: self, queue: self.queue)
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + 2, repeating: 2)
            t.setEventHandler { [weak self] in self?.prune() }
            self.pruneTimer = t
            t.resume()
        }
    }

    public func stop() {
        queue.async {
            self.manager?.stopAdvertising()
            self.manager = nil
            self.pruneTimer?.cancel(); self.pruneTimer = nil
            self.peers.removeAll()
            self.callbacks.onClientCountChanged(0)
        }
    }

    public func updateKey(_ key: Data) {
        queue.async {
            self.authenticator = MessageAuthenticator(key: key)
            self.peers.removeAll()
            self.callbacks.onClientCountChanged(0)
        }
    }

    // MARK: CBPeripheralManagerDelegate

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            callbacks.onListenerState("bluetooth unavailable (\(peripheral.state.rawValue))")
            return
        }
        let characteristic = CBMutableCharacteristic(type: BluetoothTransport.characteristic,
                                                     properties: [.write, .writeWithoutResponse],
                                                     value: nil, permissions: [.writeable])
        let service = CBMutableService(type: BluetoothTransport.service, primary: true)
        service.characteristics = [characteristic]
        peripheral.add(service)
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            log.error("add service failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BluetoothTransport.service],
            CBAdvertisementDataLocalNameKey: localName,
        ])
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let data = request.value { ingest(data, from: request.central.identifier) }
        }
        if let first = requests.first { peripheral.respond(to: first, withResult: .success) }
    }

    // MARK: Messages

    private func ingest(_ data: Data, from id: UUID) {
        var peer = peers[id] ?? Peer()
        let isNew = peers[id] == nil
        peer.lastSeen = Date()
        do {
            for line in try peer.framer.push(data) {
                do {
                    let env = try JSONDecoder().decode(Envelope.self, from: line)
                    let message = try authenticator.open(env)
                    try peer.replay.check(env, nowMs: Int64(Date().timeIntervalSince1970 * 1000))
                    callbacks.onMessage(message)
                } catch {
                    log.debug("Dropped BLE message: \(String(describing: error), privacy: .public)")
                }
            }
        } catch {
            log.error("BLE framing error: \(String(describing: error), privacy: .public)")
            peer.framer = LineFramer()
        }
        peers[id] = peer
        if isNew { callbacks.onClientCountChanged(peers.count) }
    }

    private func prune() {
        let before = peers.count
        peers = peers.filter { Date().timeIntervalSince($0.value.lastSeen) < 6 }
        if peers.count != before { callbacks.onClientCountChanged(peers.count) }
    }
}

// MARK: - iPhone / Watch side (central)

public final class BLEScrollClient: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    public enum State: Equatable, Sendable { case idle, scanning, connecting, ready }

    private let queue = DispatchQueue(label: "dev.doomscroll.ble.client")
    private let log = Logger(subsystem: "dev.doomscroll", category: "ble-client")
    private let expectedName: String
    private let onStateChange: @Sendable (State) -> Void
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var wanted = false
    private var backoff: TimeInterval = 0.5
    private var state = State.idle { didSet { if state != oldValue { onStateChange(state) } } }

    public init(macName: String, onStateChange: @escaping @Sendable (State) -> Void) {
        self.expectedName = BluetoothTransport.advertisedName(for: macName)
        self.onStateChange = onStateChange
    }

    public var isReady: Bool { queue.sync { state == .ready } }

    public func start() {
        queue.async {
            self.wanted = true
            if self.central == nil {
                self.central = CBCentralManager(delegate: self, queue: self.queue)
            } else if self.central?.state == .poweredOn, self.peripheral == nil {
                self.beginScan()
            }
        }
    }

    public func stop() {
        queue.async {
            self.wanted = false
            self.central?.stopScan()
            if let p = self.peripheral { self.central?.cancelPeripheralConnection(p) }
            self.peripheral = nil
            self.characteristic = nil
            self.state = .idle
        }
    }

    /// Writes one already-encoded line. Continuous updates are dropped if the radio is
    /// busy; the next one supersedes them.
    public func send(_ line: Data) {
        queue.async {
            guard self.state == .ready, let p = self.peripheral, let c = self.characteristic,
                  p.canSendWriteWithoutResponse else { return }
            let size = max(20, p.maximumWriteValueLength(for: .withoutResponse))
            var offset = 0
            while offset < line.count {
                let end = min(line.count, offset + size)
                p.writeValue(line.subdata(in: offset..<end), for: c, type: .withoutResponse)
                offset = end
            }
        }
    }

    // MARK: CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if wanted, peripheral == nil { beginScan() }
        } else {
            peripheral = nil
            characteristic = nil
            state = .idle
        }
    }

    private func beginScan() {
        guard wanted, let central, central.state == .poweredOn else { return }
        state = .scanning
        central.scanForPeripherals(withServices: [BluetoothTransport.service], options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard wanted, self.peripheral == nil else { return }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        // If the Mac advertised a name, it must be the paired one. No name: try it, the
        // signature check rejects anything that is not our Mac.
        if let name, name != expectedName { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([BluetoothTransport.service])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        dropAndRetry()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        dropAndRetry()
    }

    private func dropAndRetry() {
        peripheral = nil
        characteristic = nil
        state = .idle
        guard wanted else { return }
        let delay = backoff
        backoff = min(5, backoff * 2)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.beginScan() }
    }

    // MARK: CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == BluetoothTransport.service })
        else { return dropAndRetry() }
        peripheral.discoverCharacteristics([BluetoothTransport.characteristic], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil,
              let c = service.characteristics?.first(where: { $0.uuid == BluetoothTransport.characteristic })
        else { return dropAndRetry() }
        characteristic = c
        backoff = 0.5
        state = .ready
    }
}
#endif
