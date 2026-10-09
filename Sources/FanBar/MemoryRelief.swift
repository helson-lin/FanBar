import Darwin
import Dispatch

/// malloc keeps pages freed by a released view tree resident until the system
/// is under memory pressure, so a long-running menu bar app would keep its
/// peak footprint. Called right after a large teardown to hand them back.
enum MemoryRelief {
    static func returnFreedPages() {
        // A deferred hop lets autoreleased objects from the teardown drain first.
        DispatchQueue.main.async {
            malloc_zone_pressure_relief(nil, 0)
        }
    }
}
