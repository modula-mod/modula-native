import XCTest
import SwiftUI
import UIKit
@testable import Modula

/// MOL-03F diagnostics: Studio open/close memory, frame delivery for the one active preview, catalogue cost, and
/// Nodus coexistence (rendering and packages never need or load a language model).
@MainActor
final class MOL03PerformanceTests: XCTestCase {
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    private func report(_ name: String, _ value: String) {
        print("MOL03-METRIC \(name)=\(value)")
        let a = XCTAttachment(string: "\(name)=\(value)"); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func pump(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func host<V: View>(_ view: V) -> (UIWindow, UIHostingController<V>) {
        let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let vc = UIHostingController(rootView: view)
        w.rootViewController = vc
        w.isHidden = false
        return (w, vc)
    }

    func testStudioOpenClose20CyclesHasNoSustainedGrowth() {
        let kinds: [ModulaMascotKind] = [.pip, .aura, .nyx, .bramble, .vesper, .somna, .kringle, .bolt, .rolo, .lochie]
        var samples: [Double] = []
        for cycle in 0..<20 {
            autoreleasepool {
                let (w, _) = host(NavigationStack { MolibooLivingStudioView(characterID: kinds[cycle % kinds.count].rawValue) })
                pump(0.6)
                w.isHidden = true
                w.rootViewController = nil
            }
            pump(0.2)
            samples.append(Self.footprintMB())
        }
        let early = samples[4], late = samples[19]
        report("studio.footprintMB.cycle5", String(format: "%.1f", early))
        report("studio.footprintMB.cycle20", String(format: "%.1f", late))
        report("studio.footprintMB.series", samples.map { String(format: "%.0f", $0) }.joined(separator: ","))
        XCTAssertLessThan(late - early, 25, "sustained growth across Studio open/close cycles suggests a leak")
    }

    func testActivePreviewFrameDelivery() {
        final class Counter: NSObject { var frames = 0; var worst: CFTimeInterval = 0; var last: CFTimeInterval = 0
            @objc func tick(_ l: CADisplayLink) { if last > 0 { worst = max(worst, l.timestamp - last) }; last = l.timestamp; frames += 1 } }
        let (w, _) = host(NavigationStack { MolibooLivingStudioView(characterID: "somna") })
        pump(1.0)
        let c = Counter()
        let link = CADisplayLink(target: c, selector: #selector(Counter.tick(_:)))
        link.add(to: .main, forMode: .common)
        let start = CACurrentMediaTime()
        pump(3.0)
        link.invalidate()
        let fps = Double(c.frames) / (CACurrentMediaTime() - start)
        report("studio.fps.simulator", String(format: "%.1f", fps))
        report("studio.worstFrameMs.simulator", String(format: "%.1f", c.worst * 1000))
        w.isHidden = true
        XCTAssertGreaterThan(fps, 30, "main-thread frame delivery collapsed while the Studio preview animates")
    }

    func testCatalogueThumbnailCost() {
        let before = Self.footprintMB()
        let t0 = CACurrentMediaTime()
        for kind in ModulaMascotKind.allCases {
            let r = ImageRenderer(content: ModulaMascotFigure(kind: kind, pose: .still(), size: 32))
            r.scale = 3
            _ = r.cgImage
        }
        let ms = (CACurrentMediaTime() - t0) * 1000
        let after = Self.footprintMB()
        report("catalogue.thumbs115.ms", String(format: "%.0f", ms))
        report("catalogue.thumbs115.perThumbMs", String(format: "%.1f", ms / Double(ModulaMascotKind.allCases.count)))
        report("catalogue.thumbs115.footprintDeltaMB", String(format: "%.1f", after - before))
        XCTAssertLessThan(after - before, 40)
    }

    /// Moliboo rendering, registry, fits and packages never load a language model.
    func testNodusCoexistence() async {
        XCTAssertNil(Bundle.main.resourceURL.map { $0.appending(path: "Nodus/R7") }.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil },
                     "optional Nodus weights must not be bundled")
        let before = Self.footprintMB()
        _ = MolibooRegistryStore.bundled
        _ = MolibooFitProfiles.bundled
        _ = MolibooPackageRuntime.shared.active()
        for kind in ModulaMascotKind.allCases {
            _ = ImageRenderer(content: ModulaMascotFigure(kind: kind, pose: MascotPose(t: 1, mood: .happy, amp: 1), size: 64)).cgImage
        }
        let after = Self.footprintMB()
        report("nodus.coexistence.footprintDeltaMB", String(format: "%.1f", after - before))
        // A Nodus model load is hundreds of MB; Moliboo work must stay far below that.
        XCTAssertLessThan(after - before, 60)
        let loaded = Bundle.allFrameworks.contains { ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains("nodus.model") }
        XCTAssertFalse(loaded)
    }
}
