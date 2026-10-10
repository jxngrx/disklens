import SwiftUI

/// Trial + license. ponytail: local stub only; Paddle / Lemon Squeezy verification replaces `isValid` later.
enum License {
    static let trialDays = 14
    private static let startKey = "trialStart", keyKey = "licenseKey"

    static var trialStart: Date {
        if let d = UserDefaults.standard.object(forKey: startKey) as? Date { return d }
        UserDefaults.standard.set(Date(), forKey: startKey)
        return Date()
    }

    static var trialDaysLeft: Int {
        max(0, trialDays - (Calendar.current.dateComponents([.day], from: trialStart, to: Date()).day ?? 0))
    }

    static var key: String? { UserDefaults.standard.string(forKey: keyKey) }
    static var isLicensed: Bool { key.map(isValid) ?? false }
    /// Pro features (restore buttons, mobile pack, daemon) are on while licensed or in trial.
    static var proEnabled: Bool { isLicensed || trialDaysLeft > 0 }

    /// Stub format: `DL-XXXX-XXXX-XXXX` where the last group is a checksum of the first two.
    static func isValid(_ key: String) -> Bool {
        let parts = key.uppercased().split(separator: "-").map(String.init)
        guard parts.count == 4, parts[0] == "DL", parts.dropFirst().allSatisfy({ $0.count == 4 }) else { return false }
        let sum = (parts[1] + parts[2]).unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 65_536 }
        return String(format: "%04X", sum) == parts[3]
    }

    static func activate(_ key: String) -> Bool {
        guard isValid(key) else { return false }
        UserDefaults.standard.set(key, forKey: keyKey)
        return true
    }
}

struct LicenseSettings: View {
    @State private var key = License.key ?? ""
    @State private var status = ""

    var body: some View {
        Form {
            if License.isLicensed {
                Text("DiskLens Pro is active.")
            } else {
                Text(License.trialDaysLeft > 0 ? "Trial: \(License.trialDaysLeft) days left." : "Trial ended. Pro features are off.")
            }
            TextField("License key", text: $key)
            HStack {
                Button("Activate") { status = License.activate(key) ? "Activated." : "That key is not valid." }
                Text(status).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
