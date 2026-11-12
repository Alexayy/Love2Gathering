#!/usr/bin/env python3
"""Map the engine's actual set definitions to its concrete card classes."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
cards = {}
for path in sorted((root / 'engine/mage/Mage.Sets/src/mage/sets').glob('*.java')):
    source = path.read_text()
    code = re.search(r'super\("(?:[^"\\]|\\.)*",\s*"([^"]+)"', source)
    for match in re.finditer(r'new SetCardInfo\("((?:[^"\\]|\\.)*)",\s*("(?:[^"\\]|\\.)*"|\d+),\s*Rarity\.([A-Z_]+),\s*([\w.]+)\.class', source):
        name, number, rarity, clazz = match.groups()
        name = json.loads('"' + name + '"')
        number = number.strip('"')
        info = cards.setdefault(name.casefold(), {'name': name, 'class': clazz, 'set': code.group(1) if code else 'L2G', 'number': number, 'rarity': rarity, 'printings': {}})
        if code:
            info['printings'].setdefault(code.group(1), {'number': number, 'rarity': rarity})
output = root / 'bridge/card-map.json'
output.write_text(json.dumps(cards, ensure_ascii=False, separators=(',', ':')))
print(f'Indexed {len(cards)} implemented XMage card names')
