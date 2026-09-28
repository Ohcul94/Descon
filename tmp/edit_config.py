import json

path = r'E:\Descon\Server\config.json'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Find enemy 8 mechanics section - add whip_summon after laser entry
# Look for the specific pattern in enemy 8
marker = '"type": "laser"\n                }\n            ],\n            "movementPhases": [\n                {\n                    "amplitude": 200'
replacement = '"type": "laser"\n                },\n                {\n                    "activationIntervalMs": 10000,\n                    "activationMode": "time",\n                    "castInterruptible": true,\n                    "castTimeMs": 500,\n                    "cooldown": 15000,\n                    "hits": 3,\n                    "cadence": 300,\n                    "damage": 60,\n                    "range": 500,\n                    "targetCount": 1,\n                    "targetMode": "nearest",\n                    "bulletSpeed": 1500,\n                    "radius": 50,\n                    "warnTimeMs": 500,\n                    "type": "whip_summon"\n                }\n            ],\n            "movementPhases": [\n                {\n                    "amplitude": 200'

if marker in content:
    new_content = content.replace(marker, replacement, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print('ADDED whip_summon to enemy 8')
else:
    # Try alternative: look for the laser entry in enemy 8
    print('MARKER NOT FOUND - trying alternative')
    # Search for the exact laser type in enemy 8 area
    idx = content.find('"type": "laser"')
    if idx > 0:
        print(f'Found laser at index {idx}')
        # Show surrounding context
        print(content[idx:idx+100])
    else:
        print('laser type not found')
