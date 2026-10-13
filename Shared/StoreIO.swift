import Foundation

/// Reads and writes the single JSON file that holds jars, the dose log and settings.
/// The app and the widget share it through an App Group when the signing certificate allows one;
/// otherwise the app keeps it in its own Documents folder and the widget shows a setup note.
enum StoreIO {
    static let appGroup = "group.com.medjars.app"
    static let fileName = "medjars.json"

    /// The App Group folder, only if it exists and can be written to.
    static var sharedFolder: URL? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let probe = url.appendingPathComponent(".probe")
            try Data("ok".utf8).write(to: probe, options: .atomic)
            try? FileManager.default.removeItem(at: probe)
            return url
        } catch {
            return nil
        }
    }

    static var isShared: Bool { sharedFolder != nil }

    static var localURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    static var url: URL {
        if let folder = sharedFolder { return folder.appendingPathComponent(fileName) }
        return localURL
    }

    static func load() -> StoreFile {
        let target = url
        // Move data into the shared folder if it was saved locally under an earlier signature.
        if target != localURL,
           !FileManager.default.fileExists(atPath: target.path),
           FileManager.default.fileExists(atPath: localURL.path) {
            try? FileManager.default.copyItem(at: localURL, to: target)
        }
        guard let data = try? Data(contentsOf: target) else { return StoreFile() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode(StoreFile.self, from: data)) ?? StoreFile()
    }

    static func save(_ file: StoreFile) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
