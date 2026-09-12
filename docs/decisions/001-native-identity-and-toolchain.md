# ADR 001: native identity and supported runtime

Status: accepted for N1, 2026-09-12.

- Native SwiftUI entry point, development bundle ID `digital.modula.app.native`, coexistence with historical Expo `digital.modula.app`.
- React Native **0.87.1**: npm `latest` checked on 2026-09-12. `next` was 0.88.0-rc.0 and is explicitly excluded.
- Node **22.21.0** already installed on the Mac. Runtime engines require Node major 22; no system-wide upgrade.
- CocoaPods **1.16.2**, current installed tool, for RN. Ordinary native packages may use SPM when justified. RN SPM is experimental and excluded.
- Initial deployment target iOS **18.0**: supports Observation and modern SwiftUI navigation while retaining existing iOS 18 simulator coverage. New glass APIs require availability checks. Reassess only if installed RN podspecs demand a higher baseline.
- One lazy RN runtime; bundled module code only; no arbitrary package/framework downloads.

Sources: [RN stable channel](https://reactnative.dev/releases/), [0.87 release](https://reactnative.dev/blog/2026/08/11/react-native-0.87), [native integration](https://reactnative.dev/docs/integration-with-existing-apps), `npm view react-native dist-tags`, `npm view react-native@0.87.1 engines peerDependencies`.

The published engine range also accepts newer Node families; pinning 22 here is an intentional project choice. Shell Node 24.1.0 is below the permitted Node 24 minimum.
