import Foundation
import IOBluetooth

/// Disconnects a Bluetooth accessory. macOS asks for Bluetooth access the first time this runs.
enum BluetoothDisconnector {
    static func disconnect(deviceNamed name: String) -> Bool {
        let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let matches = pairedDevices.filter { device in
            device.isConnected() && device.name == name
        }
        // No connected device has this name, or several do; refuse rather than guess.
        guard matches.count == 1 else { return false }
        return matches[0].closeConnection() == kIOReturnSuccess
    }
}
