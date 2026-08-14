import Foundation
import HealthKit
import RepsKit

/// The whole Apple Health surface: write a workout per session so push-ups count toward
/// the user's activity rings.
///
/// Writing only. Reading push-up workouts back would double-count anything Reps itself
/// wrote, and there is no other app writing "push-ups" in a form worth importing.
///
/// Shipping this needs more than the entitlement: the HealthKit capability has to be
/// enabled on the App ID in the developer portal, or signing fails.
@MainActor
enum HealthSync {
    private static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static var typesToShare: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        return types
    }

    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: typesToShare, read: [])
            return true
        } catch {
            return false
        }
    }

    /// Save a finished session. Silently does nothing when the user has not switched sync
    /// on — this is called unconditionally from the summary screen so the call site does
    /// not have to know the preference.
    static func save(workout: Workout, preferences: Preferences) {
        guard preferences.syncToHealth, isAvailable else { return }
        Task { await write(workout, preferences: preferences) }
    }

    private static func write(_ workout: Workout, preferences: Preferences) async {
        let start = workout.startedAt
        let duration = max(60, workout.duration)   // a floor, so a fast session still registers
        let end = start.addingTimeInterval(duration)

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)

            if let weight = preferences.bodyWeightKg,
               let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                let kcal = Format.activeEnergyKcal(seconds: duration, bodyWeightKg: weight)
                let sample = HKQuantitySample(
                    type: energyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                    start: start,
                    end: end
                )
                try await builder.addSamples([sample])
            }

            // The rep count rides along as metadata. HealthKit has no push-up quantity
            // type, so this is the only place the number survives outside Reps.
            try await builder.addMetadata([
                HKMetadataKeyExternalUUID: workout.id.uuidString,
                HKMetadataKeyWorkoutBrandName: "Reps",
                "TotalRepetitions": workout.totalReps
            ])

            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            // A Health write that fails is not worth interrupting the summary screen for.
            // The session is already saved locally, which is the system of record.
        }
    }
}
