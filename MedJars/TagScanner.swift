import Foundation
import CoreNFC

struct ScannedTag: Equatable {
    /// Hardware ID of the tag as hex, used for pairing.
    let uid: String
    /// A link written on the tag, if any.
    let url: URL?
}

enum ScanFailure: Error, Equatable {
    case unsupported
    case notAllowed
    case cancelled
    case failed(String)

    var message: String? {
        switch self {
        case .unsupported: return "This iPhone can't scan NFC tags."
        case .notAllowed: return "Your signing certificate doesn't include NFC tag reading, so the app can't scan. Use the Shortcuts automation in Settings to open jars by tag instead."
        case .cancelled: return nil
        case .failed(let m): return m
        }
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

/// Reads one NFC tag: its hardware ID plus any link stored on it.
final class TagScanner: NSObject, NFCTagReaderSessionDelegate {
    static let shared = TagScanner()

    private var session: NFCTagReaderSession?
    private var completion: ((Result<ScannedTag, ScanFailure>) -> Void)?

    static var isSupported: Bool { NFCTagReaderSession.readingAvailable }

    func scan(prompt: String, completion: @escaping (Result<ScannedTag, ScanFailure>) -> Void) {
        guard NFCTagReaderSession.readingAvailable else {
            completion(.failure(.unsupported))
            return
        }
        self.completion = completion
        guard let session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: nil) else {
            finish(.failure(.notAllowed))
            return
        }
        session.alertMessage = prompt
        self.session = session
        session.begin()
    }

    // MARK: NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        self.session = nil
        guard let nfc = error as? NFCReaderError else {
            finish(.failure(.failed(error.localizedDescription)))
            return
        }
        switch nfc.code {
        case .readerSessionInvalidationErrorUserCanceled,
             .readerSessionInvalidationErrorFirstNDEFTagRead,
             .readerSessionInvalidationErrorSessionTimeout:
            finish(.failure(.cancelled))
        case .readerErrorSecurityViolation, .readerErrorUnsupportedFeature:
            finish(.failure(.notAllowed))
        default:
            finish(.failure(.failed(nfc.localizedDescription)))
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if error != nil {
                session.invalidate(errorMessage: "Couldn't read that tag. Hold still and try again.")
                return
            }
            let uid: String
            let ndef: NFCNDEFTag?
            switch tag {
            case .miFare(let t): uid = t.identifier.hexString; ndef = t
            case .iso15693(let t): uid = t.identifier.hexString; ndef = t
            case .iso7816(let t): uid = t.identifier.hexString; ndef = t
            case .feliCa(let t): uid = t.currentIDm.hexString; ndef = t
            @unknown default:
                session.invalidate(errorMessage: "That kind of tag isn't supported.")
                return
            }
            guard let ndef else {
                self.complete(session, ScannedTag(uid: uid, url: nil))
                return
            }
            ndef.readNDEF { message, _ in
                let url = message?.records.lazy.compactMap { $0.wellKnownTypeURIPayload() }.first
                self.complete(session, ScannedTag(uid: uid, url: url))
            }
        }
    }

    private func complete(_ session: NFCTagReaderSession, _ tag: ScannedTag) {
        finish(.success(tag))
        session.alertMessage = "Got it"
        session.invalidate()
    }

    private func finish(_ result: Result<ScannedTag, ScanFailure>) {
        DispatchQueue.main.async {
            let c = self.completion
            self.completion = nil
            c?(result)
        }
    }
}
