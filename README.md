# Modula Native

Native Modula clients and shared module runtime. SwiftUI first, Jetpack Compose later, React Native modules.

> Modula is a native application.
> Modules are hosted applications.
> The shell owns the platform.
> The runtime owns module rendering.
> The Greenfield backend owns product truth.
> A module may request platform behaviour.
> A module may never silently take ownership
> of the platform application.

Phase N1 is frozen on `phase-n1-ios-native-foundation`. The native, bridge, Vault, simulator, failure-containment, and Metro-free Release gates pass. Physical-device interaction remains explicitly open because the paired iPhone runs iOS 27.0 while this Mac's Xcode 26.6 provides iOS 26.5 device support; signing, build, installation, and launch have been proven. See `docs/environment/n1-acceptance.md` for exact evidence.

This repository is canonical at `/Users/msjoy/Developer/modula-native`. The separate Expo reference checkout is read-only and is never a build dependency. Android, web, and N2 shell work are outside this phase.
