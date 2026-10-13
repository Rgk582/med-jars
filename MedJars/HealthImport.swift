import Foundation
import HealthKit

/// Reads the medication list from the Health app (iOS 26 and later) so jars can be prefilled.
/// Health only lets other apps read medications, never write doses back.
enum HealthImport {
    struct Found: Identifiable, Hashable {
        let id: String
        let name: String
        let nickname: String?
        let hasSchedule: Bool
    }

    enum Failure: Error {
        case unsupported
        case denied(String)
    }

    static var isSupported: Bool {
        if #available(iOS 26.0, *) { return HKHealthStore.isHealthDataAvailable() }
        return false
    }

    static func fetch() async -> Result<[Found], Failure> {
        guard #available(iOS 26.0, *), HKHealthStore.isHealthDataAvailable() else { return .failure(.unsupported) }
        let store = HKHealthStore()
        let type = HKObjectType.userAnnotatedMedicationType()
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                store.requestPerObjectReadAuthorization(for: type, predicate: nil) { _, error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
            let descriptor = HKUserAnnotatedMedicationQueryDescriptor(predicate: nil, limit: nil)
            let meds = try await descriptor.result(for: store)
            let found = meds.filter { !$0.isArchived }.map { med -> Found in
                let name = med.medication.displayText
                return Found(id: Format.slug(name).ifEmptyText(UUID().uuidString), name: name,
                             nickname: med.nickname, hasSchedule: med.hasSchedule)
            }
            return .success(found)
        } catch {
            let text = error.localizedDescription
            if text.localizedCaseInsensitiveContains("entitlement") {
                return .failure(.denied("Your signing certificate doesn't include HealthKit, so Med Jars can't read the Health app."))
            }
            return .failure(.denied("Couldn't read medications from Health: \(text)"))
        }
    }
}
