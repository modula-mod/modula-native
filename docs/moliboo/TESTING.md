# Testing
Unit (ModulaTests/MOL01Tests.swift; see WARDROBE_3D.md for the cosmetic cases): flag default off · manifest + anchors + hat→real wardrobe item · schema rejection · load, all anchors, hat equip upright/remove, sync ignores unsupported, expression state.
Run: `xcodebuild … -only-testing:ModulaTests/MOL01Tests test` then full suite. Result: PENDING (needs Mac/Xcode/simulator).
Simulator evidence (8 PNGs, scripts/mol01_screenshots.sh): 01 front · 02 three-quarter · 03 back · 04 happy · 05 surprised · 06 Signature Cap equipped · 07 Signature Cap removed · 08 saved outfit reopened. Status: PENDING (needs Mac/Xcode/simulator).
Manual regression (2D mascot, composer, wardrobe, flag off = no entry): PENDING (needs Mac/Xcode/simulator).
