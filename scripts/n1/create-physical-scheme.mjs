// Generates an ignored, mode-0600 UI-test scheme. Secret values are never logged.
import {readFileSync, writeFileSync} from 'node:fs';

const fixture = JSON.parse(readFileSync('.env.n1.local', 'utf8'));
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const path = 'ios/Modula.xcodeproj/xcshareddata/xcschemes/ModulaPhysicalAcceptance.local.xcscheme';
const scheme = `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="96CA5FDC02302F64CB91380C" BuildableName="Modula.app" BlueprintName="Modula" ReferencedContainer="container:Modula.xcodeproj"/></BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="NO">
    <MacroExpansion><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="96CA5FDC02302F64CB91380C" BuildableName="Modula.app" BlueprintName="Modula" ReferencedContainer="container:Modula.xcodeproj"/></MacroExpansion>
    <Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="6123FAD15A8BE142791092D0" BuildableName="ModulaUITests.xctest" BlueprintName="ModulaUITests" ReferencedContainer="container:Modula.xcodeproj"/></TestableReference></Testables>
    <EnvironmentVariables>
      <EnvironmentVariable key="N1_PHYSICAL_EMAIL" value="${escape(fixture.email)}" isEnabled="YES"/>
      <EnvironmentVariable key="N1_PHYSICAL_PASSWORD" value="${escape(fixture.password)}" isEnabled="YES"/>
    </EnvironmentVariables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="96CA5FDC02302F64CB91380C" BuildableName="Modula.app" BlueprintName="Modula" ReferencedContainer="container:Modula.xcodeproj"/></BuildableProductRunnable></LaunchAction>
</Scheme>
`;
writeFileSync(path, scheme, {mode: 0o600});
console.log('Ignored physical acceptance scheme generated.');
