path = r'E:\Descon\descon\scripts\systems\EntityManager.gd'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Insert whip_summon dispatch before meteor check
insert = 'if action == "whip_summon_start" or action == "whip_summon_hit":\t\t_handle_whip_summon_action(data)\t\treturn\t'
marker = '# v411: Meteorito'
idx = content.find(marker)
if idx > 0:
    new_content = content[:idx] + insert + content[idx:]
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print('INSERTED whip_summon dispatch before meteor')
else:
    print('METEOR MARKER NOT FOUND')
