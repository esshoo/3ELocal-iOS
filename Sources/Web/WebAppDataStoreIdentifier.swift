import Foundation
import WebKit

/// Builds a deterministic UUID so each remote app reuses its own persistent WebKit profile.
enum WebAppDataStoreIdentifier {
    static func uuid(for identifier: String) -> UUID {
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 1_099_511_628_211
        for byte in identifier.utf8 {
            first ^= UInt64(byte)
            first &*= 1_099_511_628_211
            second &+= UInt64(byte)
            second ^= second << 13
            second ^= second >> 7
            second ^= second << 17
        }

        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8((first >> UInt64((7 - index) * 8)) & 0xff)
            bytes[index + 8] = UInt8((second >> UInt64((7 - index) * 8)) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    @MainActor
    static func persistentStore(for identifier: String) -> WKWebsiteDataStore {
        if #available(iOS 17.0, *) {
            return WKWebsiteDataStore(forIdentifier: uuid(for: identifier))
        }
        return .default()
    }

    static func removePersistentStore(for identifier: String) {
        guard #available(iOS 17.0, *) else { return }
        let uuid = uuid(for: identifier)
        Task { @MainActor in
            WKWebsiteDataStore.remove(forIdentifier: uuid) { _ in }
        }
    }
}
