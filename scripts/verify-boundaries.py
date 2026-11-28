from pathlib import Path
import json,re
root = Path(__file__).resolve().parent.parent
violations = []
for p in (root / 'ios/Modula').rglob('*'):
    if p.suffix not in {'.swift', '.h', '.m', '.mm'}: continue
    source = p.read_text()
    if 'ModuleRuntime' not in p.parts and re.search(r'(?:import React|#import.*React)', source):
        violations.append(f'RN import outside ModuleRuntime: {p}')
for p in [root/'package.json', root/'runtime/package.json']:
    data=json.loads(p.read_text())
    for name in data.get('dependencies', {}):
        if name.startswith('expo') or name.startswith('@react-navigation'):
            violations.append(f'Forbidden application host dependency: {name}')
project = (root/'ios/Modula.xcodeproj/project.pbxproj').read_text()
if re.search(r'MODULA_INCLUDE_EXPERIMENTAL_NODUS\s*=\s*1\s*;', project):
    violations.append('Experimental Nodus model is forced into an Xcode build')
for p in (root/'ios/Modula').rglob('*'):
    if p.name in {'model.safetensors', 'game.tgz'}:
        violations.append(f'Optional package is bundled in Native source: {p}')
assert json.loads((root/'runtime/package.json').read_text())['dependencies']['react-native'] == '0.87.1'
assert not (root/'android').exists()
# t169u component unification: one segmented control, one sheet style, no accent action buttons.
SEGMENTED_HOME = 'ModulaTabsAndSpaces.swift'
SHEET_HOMES = {'ModulaGlass.swift', 'ModulaSheet.swift'}
unification_rules = [
    (r'\.pickerStyle\(\.segmented\)', 'system segmented Picker (use ModulaSegmentedControl)', set()),
    (r'\b(?:ModulaTabStrip|ModulaTabIndicator|ModulaEffectTabs|DiscoverScopeGlass|MessagesGlassScopeControl|ModulaMetricPicker)\b', 'removed bespoke segmented variant', set()),
    (r'matchedGeometryEffect\(id:\s*"[^"]*(?:pill|tab|segment|chip|scope|filter|thumb|mode)', 'bespoke sliding selection indicator', {SEGMENTED_HOME}),
    (r'modulaAccentCTA|\.borderedProminent\b', 'accent-filled action button (use .modulaPrimary / modulaPrimaryCTA)', set()),
    (r'\.tint\((?:app|environment)\.appearance\.liveAccent\)', 'accent-tinted control', set()),
    (r'modulaGlass\([^\n]*tint:\s*(?:app\.appearance\.liveAccent|accent)\b[^\n]*prominent:\s*true', 'accent-filled glass button', set()),
    (r'\.presentationCornerRadius\(', 'bespoke sheet corner radius (use modulaSheetStyle)', set()),
    (r'\.presentationDragIndicator\(', 'bespoke sheet grabber (use modulaSheetStyle)', SHEET_HOMES),
]
for p in (root / 'ios/Modula').rglob('*.swift'):
    code = '\n'.join('' if line.lstrip().startswith('//') else line for line in p.read_text().split('\n'))
    for pattern, label, allowed in unification_rules:
        if p.name in allowed: continue
        for m in re.finditer(pattern, code):
            line = code.count('\n', 0, m.start()) + 1
            violations.append(f'Component unification: {label}: {p.relative_to(root)}:{line}')
assert not violations, '\n'.join(violations)
print('Native/runtime ownership boundaries passed')
