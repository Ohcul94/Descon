import pathlib, re
p = pathlib.Path(r"E:\Descon\AdminDash\js\renderers.js")
txt = p.read_text(encoding="utf-8", errors="ignore")

# Find mechanics card block: en.mechanics.map((m, idx) => ` ... </div>\n                         </div>\n                     `).join
# We'll use a simple approach: find index of 'en.mechanics.map' and then find next occurrence of "                         </div>\n                     `).join"
idx = txt.find("en.mechanics.map")
if idx != -1:
    # find the next occurrence of that closing pattern
    pattern = "                         </div>\n                     `).join"
    j = txt.find(pattern, idx)
    if j != -1:
        insert = "                             ${mechanicSoundOverrideHtml(selectedEnemyId, 'mechanics', idx, m)}\n                         </div>\n                     `).join"
        # Check if already patched
        if "mechanicSoundOverrideHtml(selectedEnemyId, 'mechanics'" not in txt[idx: j+500]:
            txt = txt[:j] + insert[len(pattern):]  # we replace tail with insert? Actually we need to replace pattern with injection
            # The pattern we found is "                         </div>\n                     `).join" -> we want to keep first </div> and inject before second?
            # Simpler: replace pattern with insert
            # need reconstruct: we consumed pattern partially
            # Let's do direct replace for this occurrence only
            txt2 = p.read_text(encoding="utf-8", errors="ignore")
            txt2 = txt2.replace(pattern, "                             ${mechanicSoundOverrideHtml(selectedEnemyId, 'mechanics', idx, m)}\n                         </div>\n                     `).join", 1)
            # That replacement actually inserts before final join, but we want injection before that final div
            # Let's instead do: txt2 = txt2.replace(pattern, insert) -> but insert already contains join prefix
            # Do it correctly
            p.write_text(txt2, encoding="utf-8")
            print("patched mechanics via simple replace")
        else:
            print("already patched mechanics")
    else:
        print("pattern not found")
        # try alternative: search for two closes
        print(repr(txt[idx: idx+5000][-2000:]))
else:
    print("en.mechanics.map not found")
