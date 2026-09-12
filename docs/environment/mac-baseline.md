# Mac baseline

Captured 2026-09-12 from `/Users/msjoy/Developer` before implementation. Mac is authoritative; no VPS app development. No system tooling was upgraded.

## `xcodebuild -version`

Exit status: 0

```text
Xcode 26.6
Build version 17F113
```

## `xcodebuild -showsdks`

Exit status: 0

```text
DriverKit SDKs:
	DriverKit 25.5                	-sdk driverkit25.5

iOS SDKs:
	iOS 26.5                      	-sdk iphoneos26.5

iOS Simulator SDKs:
	Simulator - iOS 26.5          	-sdk iphonesimulator26.5

macOS SDKs:
	macOS 26.5                    	-sdk macosx26.5
	macOS 26.5                    	-sdk macosx26.5

tvOS SDKs:
	tvOS 26.5                     	-sdk appletvos26.5

tvOS Simulator SDKs:
	Simulator - tvOS 26.5         	-sdk appletvsimulator26.5

visionOS SDKs:
	visionOS 26.5                 	-sdk xros26.5

visionOS Simulator SDKs:
	Simulator - visionOS 26.5     	-sdk xrsimulator26.5

watchOS SDKs:
	watchOS 26.5                  	-sdk watchos26.5

watchOS Simulator SDKs:
	Simulator - watchOS 26.5      	-sdk watchsimulator26.5

```

## `swift --version`

Exit status: 0

```text
swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
Target: arm64-apple-macosx28.0
```

## `xcrun simctl list devices available`

Exit status: 0

```text
== Devices ==
-- iOS 18.2 --
    iPhone 16 Pro (8AAF71C9-8250-4E76-8C5B-1AC35A275F2D) (Shutdown) 
    iPhone 16 Pro Max (F135986B-CF76-4BCD-ADDE-62EA6DAFBA10) (Shutdown) 
    iPhone 16 (EE2E6E1F-8357-4471-8425-FDD9A4DD8C5F) (Shutdown) 
    iPhone 16 Plus (1724B8C2-B6B4-4F26-AC7F-971B7490B5A0) (Shutdown) 
    iPhone SE (3rd generation) (B2AD2B01-052A-4FB8-9323-75F0EBA6CEAE) (Shutdown) 
    iPad Pro 11-inch (M4) (35C1507B-5962-4D4D-BBFC-FF293865D0EC) (Shutdown) 
    iPad Pro 13-inch (M4) (33E19B10-B372-4DDF-B60D-910FEC0667B5) (Shutdown) 
    iPad Air 11-inch (M2) (A378511D-B2AC-4C6E-8925-EBF5A24FCF8C) (Shutdown) 
    iPad Air 13-inch (M2) (9988776A-781D-4AC3-8A85-4EA73B674E21) (Shutdown) 
    iPad mini (A17 Pro) (6F993BE3-01C4-4F07-B0C5-653110BD98FF) (Shutdown) 
    iPad (10th generation) (2E1AE09A-3317-40FA-B541-E8595CBCB0BF) (Shutdown) 
-- iOS 18.4 --
    iPhone 16 Pro (FB1A881F-3409-42BC-9750-817EC93352A3) (Shutdown) 
    iPhone 16 Pro Max (51A45189-E626-4225-9C00-6BAB98EE04A5) (Shutdown) 
    iPhone 16e (D2F7E67E-DE8A-4531-B901-33DE0F51546E) (Shutdown) 
    iPhone 16 (44237EF8-B744-4739-88A5-5060574D1C5C) (Shutdown) 
    iPhone 16 Plus (29C00CF9-133F-4A70-9D41-E5850DE5099B) (Shutdown) 
    iPad Pro 11-inch (M4) (8E0695A0-51FE-4362-8C8E-3AE7E187B494) (Shutdown) 
    iPad Pro 13-inch (M4) (97058646-1383-4E7A-AB29-A237629A907F) (Shutdown) 
    iPad mini (A17 Pro) (20BA93CD-7C97-4708-8A89-1AE35E851653) (Shutdown) 
    iPad (A16) (1503EE49-335B-45A3-A9F4-9159F4E206ED) (Shutdown) 
    iPad Air 13-inch (M3) (A1F6426F-D3D6-4C91-A8FD-AA919CBE3604) (Shutdown) 
    iPad Air 11-inch (M3) (ECC76BEE-45F0-4E4B-903F-AFD477A6C015) (Shutdown) 
-- iOS 26.3 --
    iPhone 17 Pro (1F8BD84E-2432-45A0-B93A-36D7D745860D) (Shutdown) 
    iPhone 17 Pro Max (452EBDDB-B567-46C4-A9F4-A567BA349FD5) (Shutdown) 
    iPhone 17e (F9C4FDBF-8FE1-4F74-A82A-21E6F683CFD7) (Shutdown) 
    iPhone Air (CA8B367B-3C48-47DA-8D52-2EDE37F13E4F) (Shutdown) 
    iPhone 17 (AF57F67B-E8FD-4ED4-A508-63A17DFD6B48) (Shutdown) 
    iPhone 16e (97F37F6B-6286-41BE-8C4F-99FBDF324D4C) (Shutdown) 
    iPad Pro 13-inch (M5) (1AFCDF48-A0E6-4120-B983-C31078D8EB43) (Shutdown) 
    iPad Pro 11-inch (M5) (8F7E55A9-1DAC-4DF7-A54C-8BD88623728C) (Shutdown) 
    iPad mini (A17 Pro) (545F0170-7483-42BD-A55F-D383310A8D75) (Shutdown) 
    iPad Air 13-inch (M4) (9D20309B-CAD8-487F-9585-CF2540B36A74) (Shutdown) 
    iPad Air 11-inch (M4) (ED3AE2B9-90E7-47F7-ADE3-3A48057AF9AE) (Shutdown) 
    iPad (A16) (B9A341F7-93BD-4216-8594-7E1916DFA60C) (Shutdown) 
    iPad Air 13-inch (M3) (7BA97C1A-D353-43DB-94EF-FABBE520F0D9) (Shutdown) 
    iPad Air 11-inch (M3) (CA2B787C-6474-42F4-9409-648783A66C11) (Shutdown) 
-- iOS 26.5 --
    iPhone 17 Pro (439E8DF1-EA4F-4028-98A0-32CA9469EAE0) (Booted) 
    iPhone 17 Pro (9C3D4616-8EA0-4F27-9450-D5AFDAC5570B) (Shutdown) 
    iPhone 17 Pro Max (8D09BEB9-E178-4FA9-938C-BEBE56496506) (Shutdown) 
    iPhone 17e (913CD66D-7ADB-4A42-B265-B533466C3BE0) (Shutdown) 
    iPhone Air (423C39D1-C86F-4A03-AF1B-4936DB6C0C2D) (Shutdown) 
    iPhone 17 (9FB71D91-82D3-4D7F-A481-DD1922D31A2B) (Shutdown) 
    iPad Pro 13-inch (M5) (224C01C7-9AB2-4E16-B42B-F005926C0C9D) (Shutdown) 
    iPad Pro 11-inch (M5) (5DB232E5-AF91-4A78-B6D7-EC89C91F0A6B) (Shutdown) 
    iPad mini (A17 Pro) (F5EE53D5-E056-439C-BE42-60721C2C5EF4) (Shutdown) 
    iPad Air 13-inch (M4) (338D7749-A762-45EE-9095-C816A0FFDB56) (Shutdown) 
    iPad Air 11-inch (M4) (FCA2B46F-7116-4A55-8FD8-36FA6D81119D) (Shutdown) 
    iPad (A16) (BEAA43BB-75B1-41D2-A0FA-26ECBB652768) (Shutdown) 
-- iOS 27.0 --
    iPhone 17 Pro (0727E2F0-8528-44DA-9F4C-7B5F7394096B) (Shutdown) 
    iPhone 17 Pro Max (D2F9AB8C-FD6C-4DEE-AF0D-C14B694CBECB) (Shutdown) 
    iPhone 17e (2F5F5718-4297-4519-9061-65671511F65B) (Shutdown) 
    iPhone Air (63CB3517-CD4E-4B7E-8E1B-FD1A52A9F0C3) (Shutdown) 
    iPhone 17 (6A726C21-D5B2-47CA-B3D5-255AD763F83A) (Shutdown) 
    iPad Pro 13-inch (M5) (6AFD35DD-90A9-4CC6-8CDF-D840A0D9FD07) (Shutdown) 
    iPad Pro 11-inch (M5) (2EFB70C5-BC6C-4901-B556-5B000450C869) (Shutdown) 
    iPad mini (A17 Pro) (B3370FAB-CBFA-45EF-A39A-48E3A7A95AB3) (Shutdown) 
    iPad Air 13-inch (M4) (5EDCFD69-9336-4737-8230-C9CCCB5773C7) (Shutdown) 
    iPad Air 11-inch (M4) (8DC74331-F9D2-4352-9AF7-F6FC130960C1) (Shutdown) 
    iPad (A16) (A93F5EBC-E87B-4FC6-8BC3-4838E229A82A) (Shutdown) 
```

## `git --version`

Exit status: 0

```text
git version 2.50.1 (Apple Git-155)
```

## `gh --version`

Exit status: 0

```text
gh version 2.96.0 (2026-07-02)
https://github.com/cli/cli/releases/tag/v2.96.0
```

## `gh auth status`

Exit status: 0

```text
github.com
  ✓ Logged in to github.com account modula-mod (keyring)
  - Active account: true
  - Git operations protocol: https
```

## `node --version`

Exit status: 0

```text
v24.1.0
```

## `corepack --version`

Exit status: 0

```text
0.32.0
```

## `ruby --version`

Exit status: 0

```text
ruby 2.6.10p210 (2022-04-12 revision 67958) [universal.arm64e-darwin26]
```

## `pod --version`

Exit status: 0

```text
1.16.2
```

## Selected runtime tools

Use existing `~/.nvm/versions/node/v22.21.0/bin` for runtime commands. Default shell Node 24.1.0 does not satisfy RN 0.87.1 engines. CocoaPods 1.16.2 is installed through Homebrew and uses its own Ruby; shell Ruby is 2.6.10. iPhone 17 Pro on iOS 26.5 is available. Physical iPhone 17 Pro Max is paired but unavailable at baseline.
