// Captured IOPS power-source descriptions (macOS 27.0.1, MacBook Pro M4 Max in clamshell mode, 2026-10-14),
// as `IOPSGetPowerSourceDescription` returns them (CFNumber/CFBoolean values), through PropertyListSerialization.
// Device names, serials, power-source IDs and group identifiers are redacted. The "AC, not charging" battery and
// all accessory sources are verbatim captures; the other battery states keep the captured shape with the values
// of that state (charging, discharging, full, still estimating).
import Foundation
import Testing

enum Fixtures {
    static func dictionary(_ xml: String) throws -> [String: Any] {
        let data = Data("<plist version=\"1.0\">\(xml)</plist>".utf8)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private static func battery(capacity: Int, state: String, charging: Bool, charged: Bool,
                                toEmpty: Int, toFull: Int, lowPower: Bool = false) -> String {
        """
        <dict>
          <key>Battery Provides Time Remaining</key><true/>
          <key>Current</key><integer>0</integer>
          <key>Current Capacity</key><integer>\(capacity)</integer>
          <key>DesignCycleCount</key><integer>300</integer>
          <key>Is Charged</key>\(charged ? "<true/>" : "<false/>")
          <key>Is Charging</key>\(charging ? "<true/>" : "<false/>")
          <key>Is Present</key><true/>
          <key>LPM Active</key>\(lowPower ? "<true/>" : "<false/>")
          <key>Max Capacity</key><integer>100</integer>
          <key>Name</key><string>InternalBattery-0</string>
          <key>Power Source ID</key><integer>1</integer>
          <key>Power Source State</key><string>\(state)</string>
          <key>Time to Empty</key><integer>\(toEmpty)</integer>
          <key>Time to Full Charge</key><integer>\(toFull)</integer>
          <key>Transport Type</key><string>Internal</string>
          <key>Type</key><string>InternalBattery</string>
        </dict>
        """
    }

    /// Verbatim: 80 %, adapter attached, charge limit holding (`pmset`: "AC attached; not charging").
    static var pluggedInNotCharging: String { battery(capacity: 80, state: "AC Power", charging: false, charged: false, toEmpty: 0, toFull: 0) }
    static var charging: String { battery(capacity: 46, state: "AC Power", charging: true, charged: false, toEmpty: 0, toFull: 80) }
    static var chargingEstimating: String { battery(capacity: 46, state: "AC Power", charging: true, charged: false, toEmpty: 0, toFull: -1) }
    static var full: String { battery(capacity: 100, state: "AC Power", charging: false, charged: true, toEmpty: 0, toFull: 0) }
    static var discharging: String { battery(capacity: 64, state: "Battery Power", charging: false, charged: false, toEmpty: 250, toFull: 0) }
    static var dischargingEstimating: String { battery(capacity: 64, state: "Battery Power", charging: false, charged: false, toEmpty: -1, toFull: 0) }
    static var dischargingLowPower: String { battery(capacity: 9, state: "Battery Power", charging: false, charged: false, toEmpty: 31, toFull: 0, lowPower: true) }

    /// Verbatim: `IOPSCopyExternalPowerAdapterDetails` keys we read (the rest — serials, firmware — omitted).
    static let adapter = "<dict><key>Name</key><string>140W USB-C Power Adapter</string><key>Watts</key><integer>140</integer></dict>"

    // MARK: Accessories (private IOPSCopyPowerSourcesByType(4))

    /// Verbatim: a Magic Trackpad (USB-C), Bluetooth.
    static let trackpad = """
    <dict>
      <key>Accessory Category</key><string>Trackpad</string>
      <key>Current Capacity</key><integer>64</integer>
      <key>Is Charging</key><false/>
      <key>Is Present</key><true/>
      <key>Max Capacity</key><integer>100</integer>
      <key>Name</key><string>Magic Trackpad</string>
      <key>Power Source ID</key><integer>1</integer>
      <key>Power Source State</key><string>Battery Power</string>
      <key>Product ID</key><integer>804</integer>
      <key>Transport Type</key><string>Bluetooth</string>
      <key>Type</key><string>Accessory Source</string>
      <key>Vendor ID</key><integer>76</integer>
    </dict>
    """

    /// Verbatim: the charging case of AirPods 4 (product 0x201B). Its name differs from the buds' name.
    static let airPodsCase = """
    <dict>
      <key>Accessory Category</key><string>Audio Battery Case</string>
      <key>Current Capacity</key><integer>13</integer>
      <key>Dynamic End of Charging Engaged</key><false/>
      <key>Group Identifier</key><string>00000000-0000-4000-8000-000000000001</string>
      <key>Is Charged</key><integer>0</integer>
      <key>Is Charging</key><false/>
      <key>Is Present</key><true/>
      <key>Low Warn Level</key><integer>25</integer>
      <key>Max Capacity</key><integer>100</integer>
      <key>Name</key><string>AirPods Case</string>
      <key>Optimized Battery Charging Engaged</key><false/>
      <key>Part Identifier</key><string>Case</string>
      <key>Power Source ID</key><integer>1</integer>
      <key>Power Source State</key><string>Battery Power</string>
      <key>Product ID</key><integer>8219</integer>
      <key>Time to Full Charge</key><integer>0</integer>
      <key>Transport Type</key><string>Bluetooth LE</string>
      <key>Type</key><string>Accessory Source</string>
      <key>Vendor ID</key><integer>76</integer>
      <key>Vendor ID Source</key><integer>1</integer>
    </dict>
    """

    private static func bud(_ part: String, letter: String, capacity: Int) -> String {
        """
        <dict>
          <key>Accessory Category</key><string>Headset</string>
          <key>Current Capacity</key><integer>\(capacity)</integer>
          <key>Group Identifier</key><string>00000000-0000-4000-8000-000000000001</string>
          <key>Is Charged</key><integer>0</integer>
          <key>Is Charging</key><false/>
          <key>Is Present</key><true/>
          <key>Low Warn Level</key><integer>20</integer>
          <key>Max Capacity</key><integer>100</integer>
          <key>Name</key><string>AirPods</string>
          <key>Part Identifier</key><string>\(part)</string>
          <key>Part Name</key><string>AirPods \(letter)</string>
          <key>Power Source State</key><string>Battery Power</string>
          <key>Product ID</key><integer>8219</integer>
          <key>Transport Type</key><string>Bluetooth LE</string>
          <key>Type</key><string>Accessory Source</string>
          <key>Vendor ID</key><integer>76</integer>
          <key>Vendor ID Source</key><integer>1</integer>
        </dict>
        """
    }

    /// The buds as captured (a "Combined" source carrying "Combined Parts" left and right); levels edited so
    /// left and right differ.
    static let airPodsBuds = """
    <dict>
      <key>Accessory Category</key><string>Headset</string>
      <key>Combined Parts</key><array>\(bud("Left", letter: "🅛", capacity: 84))\(bud("Right", letter: "🅡", capacity: 81))</array>
      <key>Current Capacity</key><integer>81</integer>
      <key>Group Identifier</key><string>00000000-0000-4000-8000-000000000001</string>
      <key>Is Charged</key><integer>0</integer>
      <key>Is Charging</key><false/>
      <key>Is Present</key><true/>
      <key>Low Warn Level</key><integer>20</integer>
      <key>Max Capacity</key><integer>100</integer>
      <key>Name</key><string>AirPods</string>
      <key>Part Identifier</key><string>Combined</string>
      <key>Power Source ID</key><integer>1</integer>
      <key>Power Source State</key><string>Battery Power</string>
      <key>Product ID</key><integer>8219</integer>
      <key>Transport Type</key><string>Bluetooth LE</string>
      <key>Type</key><string>Accessory Source</string>
      <key>Vendor ID</key><integer>76</integer>
      <key>Vendor ID Source</key><integer>1</integer>
    </dict>
    """

    /// Verbatim registry properties of `AppleDeviceManagementHIDEventService` entries (the keys we read).
    static let hidTrackpad = """
    <dict>
      <key>Accessory Category</key><string>Trackpad</string>
      <key>BatteryPercent</key><integer>64</integer>
      <key>Built-In</key><integer>0</integer>
      <key>Product</key><string>Magic Trackpad  Office</string>
      <key>ProductID</key><integer>804</integer>
      <key>Transport</key><string>Bluetooth</string>
      <key>VendorID</key><integer>76</integer>
    </dict>
    """
    static let hidBuiltIn = """
    <dict>
      <key>Built-In</key><integer>1</integer>
      <key>Product</key><string>Apple Internal Keyboard / Trackpad</string>
      <key>ProductID</key><integer>858</integer>
      <key>Transport</key><string>FIFO</string>
      <key>VendorID</key><integer>0</integer>
    </dict>
    """
}
