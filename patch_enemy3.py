import pathlib
p = pathlib.Path(r"E:\Descon\AdminDash\js\renderers.js")
txt = p.read_text(encoding="utf-8")

# The mechanics card ends with two closes then join. Inject before join.
# Original tail for mechanics: 
#                             </div>
#                         </div>
#                     `).join('')}
#                 </div>
#             </div>
old_tail = """                             </div>
                         </div>
                     `).join('')}
                 </div>
             </div>
             <div class="col">"""

# We will insert sound override before that
new_tail = """                             </div>
                             ${mechanicSoundOverrideHtml(selectedEnemyId, 'mechanics', idx, m)}
                         </div>
                     `).join('')}
                 </div>
             </div>
             <div class="col">"""

if old_tail in txt:
    txt = txt.replace(old_tail, new_tail, 1)
    print("patched mechanics enemy override")
else:
    print("not found tail")
    # debug find
    print(txt.find("` ).join('')}"))

p.write_text(txt, encoding="utf-8")
