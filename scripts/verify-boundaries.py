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
assert json.loads((root/'runtime/package.json').read_text())['dependencies']['react-native'] == '0.87.1'
assert not (root/'android').exists()
assert not violations, '\n'.join(violations)
print('Native/runtime ownership boundaries passed')
