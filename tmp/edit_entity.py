path = r'E:\Descon\descon\scripts\systems\EntityManager.gd'
with open(path, 'r') as f:
    content = f.read()

# Insert whip_summon dispatch before meteor check
insert_text = 'if action == "whip_summon_start" or action == "whip_summon_hit":\n\t\t_handle_whip_summon_action(data)\n\t\treturn\n\t'

marker = '# v411: Meteorito'
idx = content.find(marker)
if idx > 0:
    new_content = content[:idx] + insert_text + content[idx:]
    with open(path, 'w') as f:
        f.write(new_content)
    print('INSERTED whip_summon dispatch')
else:
    print('METEOR MARKER NOT FOUND')

# Also add the _handle_whip_summon_action function before _on_loot_despawned
# Actually, add it near _handle_meteor_action
print('DONE')
