# Native capabilities

Audit date: 2026-09-12. Expo source: `modula-mod/modula-latest@7876379948cb382aab5cf8692686354e7646a769`. Paths below are relative to that read-only checkout unless a separate repository is named. “Implemented” means present in source, not a fresh runtime pass.

Source dependency and adapter audit: expo-camera, image-picker, clipboard, haptics, secure-store, local-authentication, linking, network, video, web-browser, system-ui, glass-effect, @expo/ui and @callstack/liquid-glass; native adapters under src/platform/ui.

NATIVE_REWRITE Keychain credentials, OS permission broker, haptics, sharing, clipboard/files, deep links, app lifecycle and native materials. N1 bridge must default-deny unsupported capability families. Camera/microphone/photos/location/contacts/notifications/biometrics require host policy and user/system consent when introduced; bundled library availability is not module authorization. System accessibility and Dynamic Type are environment truth. Avoid adding unused entitlement/privacy usage keys just for future symmetry. No master session secret enters module props.

