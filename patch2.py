import pathlib, re
p = pathlib.Path(r"E:\Descon\AdminDash\js\renderers.js")
txt = p.read_text(encoding="utf-8")
pattern = r"\${requirementsSectionHtml\('req_skill_' \+ reqSectionIdSanitize\(name\), `config\.skillsData\[\"\${name\.replace"
if re.search(pattern, txt):
    print("found pattern regex skill")
else:
    print("not found regex")
# do direct string find
needle = "${requirementsSectionHtml('req_skill_"
print("needle idx", txt.find(needle))
# try replace using split
if needle in txt:
    replacement = """<div style="margin-top:1rem; padding:1rem; background:rgba(168,85,247,0.06); border:1px solid rgba(168,85,247,0.2); border-radius:8px;">
                <label style="color:#a855f7; font-size:0.65rem; font-weight:bold; letter-spacing:1px; display:flex; align-items:center; gap:6px;">SONIDO DE HABILIDAD (assets/Sonidos/Habilidades/)</label>
                <div style="display:flex; gap:8px; align-items:center; margin-top:0.6rem; flex-wrap:wrap;">
                    <input type="text" placeholder="res://assets/Sonidos/Habilidades/ej.ogg" value="${s.sound || ''}" style="flex:1; min-width:200px; font-size:0.7rem;" onchange="config.skillsData['${name}'].sound = this.value; renderSkills();">
                    <button class="btn" style="padding:6px 10px; font-size:0.65rem; background:rgba(168,85,247,0.12); border:1px solid rgba(168,85,247,0.3); color:#a855f7;" onclick="triggerAssetUpload('${name}', 'skill_sound')">SONIDO</button>
                    ${s.sound ? `<button class="btn" style="padding:2px 6px; font-size:0.58rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060;" onclick="config.skillsData['${name}'].sound=''; renderSkills();">Quitar</button><audio controls preload="none" src="${resolveAssetWebUrl(s.sound)}" style="height:28px; width:140px;"></audio>` : ''}
                </div>
                <div style="display:grid; grid-template-columns:1fr 1fr; gap:8px; margin-top:0.6rem;">
                    <div class="field"><label>Volumen (dB)</label><input type="number" step="1" value="${s.soundVolumeDb !== undefined ? s.soundVolumeDb : (s.soundVolume || 0)}" onchange="config.skillsData['${name}'].soundVolumeDb = parseFloat(this.value) || 0"></div>
                    <div class="field"><label>Distancia Max (px)</label><input type="number" step="50" value="${s.soundMaxDist || 1400}" onchange="config.skillsData['${name}'].soundMaxDist = parseInt(this.value) || 1400"></div>
                </div>
            </div>
            """ + needle
    txt2 = txt.replace(needle, replacement, 1)
    if txt2 != txt:
        p.write_text(txt2, encoding="utf-8")
        print("patched ok")
    else:
        print("no change")
