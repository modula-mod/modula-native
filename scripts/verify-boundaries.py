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
assert not violations, '\n'.join(violations)
print('Native/runtime ownership boundaries passed')
