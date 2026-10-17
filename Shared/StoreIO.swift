import Foundation

/// Reads and writes the single JSON file that holds jars, the dose log and settings.
/// The app and the widget share it through an App Group when the signing certificate allows one;
/// otherwise the app keeps it in its own Documents folder and the widget shows a setup note.
enum StoreIO {
    static let appGroup = "group.com.medjars.app"
    static let fileName = "medjars.json"

    /// App Groups this copy of the app was signed with, read from its provisioning profile.
    /// A signing service gives its own group names (like group.9abf2a6b9fb214b6.1) instead of Med Jars' one,
    /// so the app and the widget both pick the same one from this list.
    static let profileGroups: [String] = {
        let main = Bundle.main.bundleURL
        let candidates = [
            main.appendingPathComponent("embedded.mobileprovision"),
            // Inside the widget extension, the app's profile sits two folders up (MedJars.app/PlugIns/MedJarsWidget.appex).
            main.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("embedded.mobileprovision")
        ]
        for url in candidates {
            if let groups = groups(inProfile: url), !groups.isEmpty { return groups.sorted() }
        }
        return []
    }()

    private static func groups(inProfile url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else { return nil }
        return (entitlements["com.apple.security.application-groups"] as? [String])?.filter { !$0.contains("*") }
    }

    /// The App Group folder, checked once per launch. Nil when the certificate doesn't allow one.
    static let sharedFolder: URL? = {
        for id in [appGroup] + profileGroups.filter({ $0 != appGroup }) {
            guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { continue }
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                let probe = url.appendingPathComponent(".probe")
                try Data("ok".utf8).write(to: probe, options: .atomic)
                try? FileManager.default.removeItem(at: probe)
                return url
            } catch {
                continue
            }
        }
        return nil
    }()

    static var isShared: Bool { sharedFolder != nil }

    static var localURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    static var url: URL {
        if let folder = sharedFolder { return folder.appendingPathComponent(fileName) }
        return localURL
    }

    /// Set when the saved file existed but couldn't be read. A copy is kept next to it.
    private(set) static var unreadableCopy: URL?

    static func load() -> StoreFile {
        let target = url
        // Move data into the shared folder if it was saved locally under an earlier signature.
        if target != localURL,
           !FileManager.default.fileExists(atPath: target.path),
           FileManager.default.fileExists(atPath: localURL.path) {
            try? FileManager.default.copyItem(at: localURL, to: target)
        }
        guard let data = try? Data(contentsOf: target), !data.isEmpty else { return StoreFile() }
        for strategy in [JSONDecoder.DateDecodingStrategy.secondsSince1970, .iso8601] {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = strategy
            if let file = try? decoder.decode(StoreFile.self, from: data) {
                file.applyContext()
                return file
            }
        }
        // Never let an unreadable file be overwritten: keep a copy first.
        if unreadableCopy != nil { return StoreFile() }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"
        let copy = target.deletingLastPathComponent().appendingPathComponent("medjars-unreadable-\(f.string(from: Date())).json")
        if (try? data.write(to: copy, options: .atomic)) != nil { unreadableCopy = copy }
        return StoreFile()
    }

    static func save(_ file: StoreFile) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
