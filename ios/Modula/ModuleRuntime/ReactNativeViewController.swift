import UIKit
import React

final class ReactNativeViewController: UIViewController {
    let session: ModuleSession
    let runtime: ModuleRuntimeController
    init(session: ModuleSession, runtime: ModuleRuntimeController) {
        self.session = session
        self.runtime = runtime
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() { view = runtime.makeSurface(session) ?? UIView() }
    /// Called only on real dismantle (host removed), not on tab switches.
    func stop() {
        if let hosting = view as? RCTSurfaceHostingProxyRootView { hosting.surface.stop() }
        view?.removeFromSuperview()
        runtime.unmount(session)
    }
}
