import json
path = r'E:\Descon\Server\config.json'
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
enemy8 = data['enemyModels']['8']
print('Enemy 8 mechanics:')
for m in enemy8['mechanics']:
    print('  - type:', m['type'])
has_whip = any(m['type'] == 'whip_summon' for m in enemy8['mechanics'])
print('Has whip_summon:', has_whip)
print('Config is valid JSON: True')
