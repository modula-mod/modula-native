import SwiftUI
import RealityKit
import UIKit
import Combine

/// One long-lived RealityKit view for the whole app session (MOL-02 stability track).
///
/// The simulator crashes cluster around creating and destroying a `RealityView` (and with it a RealityKit scene,
/// renderer and Metal state) on every Studio open. The stage keeps a single non-AR `ARView` alive and only swaps
/// what it shows. SwiftUI screens embed it with `MolibooStageView(controller:)`.
///
/// API (kept deliberately small, also intended as the renderer of MolibooLivingStage):
/// - `MolibooStage.shared.show(_:)`: make a controller's `root` + `cameraEntity` the stage content (replaces the previous).
/// - `MolibooStage.shared.clear(_:)`: remove that controller's content if it is still shown (call from `onDisappear`).
/// - `MolibooStageView(controller:)`: SwiftUI host. Gestures/overlays go on this view as with RealityView.
@MainActor
final class MolibooStage {
    static let shared = MolibooStage()

    let view: ARView
    private let anchor = AnchorEntity(world: .zero)
    private weak var current: MolibooSceneController?
    private var frameSubscription: (any Cancellable)?

    private init() {
        view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.backgroundColor = .clear
        view.environment.background = .color(.clear)
        view.renderOptions.insert(.disableGroundingShadows)
        view.scene.addAnchor(anchor)
        frameSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] ev in
            MainActor.assumeIsolated { self?.current?.recordFrame(ev.deltaTime) }
        }
    }

    func show(_ controller: MolibooSceneController) {
        guard current !== controller else { return }
        if let old = current { detach(old) }
        current = controller
        anchor.addChild(controller.root)
        anchor.addChild(controller.cameraEntity)
    }

    func clear(_ controller: MolibooSceneController) {
        guard current === controller else { return }
        detach(controller)
        current = nil
    }

    private func detach(_ c: MolibooSceneController) {
        c.root.removeFromParent()
        c.cameraEntity.removeFromParent()
    }
}

/// SwiftUI host for the shared stage view. Re-parents the single ARView into whichever screen is showing it.
struct MolibooStageView: UIViewRepresentable {
    let controller: MolibooSceneController

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .clear
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {
        let v = MolibooStage.shared.view
        if v.superview !== host {
            v.removeFromSuperview()
            v.frame = host.bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.addSubview(v)
        }
        MolibooStage.shared.show(controller)
    }

    static func dismantleUIView(_ host: UIView, coordinator: ()) {
        // Keep the ARView alive; just take it out of this host if it is still here.
        if MolibooStage.shared.view.superview === host { MolibooStage.shared.view.removeFromSuperview() }
    }
}
