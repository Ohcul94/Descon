import pathlib
p = pathlib.Path(r"E:\Descon\AdminDash\js\app.js")
txt = p.read_text(encoding="utf-8")

old = """    libsMap.forEach(item => {
        if (!config[item.configKey]) {
            config[item.configKey] = JSON.parse(JSON.stringify(item.base));
        } else {
            for (let type in item.base) {
                if (!config[item.configKey][type]) {
                    config[item.configKey][type] = JSON.parse(JSON.stringify(item.base[type]));
                } else {
                    // v268.620: Forzar sincronización de la estructura de campos
                    config[item.configKey][type].fields = [...item.base[type].fields];
                    if (config[item.configKey][type].label === undefined) {
                        config[item.configKey][type].label = item.base[type].label;
                    }
                    if (config[item.configKey][type].icon === undefined) {
                        config[item.configKey][type].icon = item.base[type].icon;
                    }
                }
            }
        }
    });"""

new = """    libsMap.forEach(item => {
        if (!config[item.configKey]) {
            config[item.configKey] = JSON.parse(JSON.stringify(item.base));
        } else {
            for (let type in item.base) {
                if (!config[item.configKey][type]) {
                    config[item.configKey][type] = JSON.parse(JSON.stringify(item.base[type]));
                } else {
                    // v268.620: Forzar sincronización de la estructura de campos
                    config[item.configKey][type].fields = [...item.base[type].fields];
                    if (config[item.configKey][type].label === undefined) {
                        config[item.configKey][type].label = item.base[type].label;
                    }
                    if (config[item.configKey][type].icon === undefined) {
                        config[item.configKey][type].icon = item.base[type].icon;
                    }
                    // v900.0: migrar sonido (hybrid: default de libreria)
                    if (config[item.configKey][type].sound === undefined) config[item.configKey][type].sound = item.base[type].sound || "";
                    if (config[item.configKey][type].soundVolumeDb === undefined) config[item.configKey][type].soundVolumeDb = item.base[type].soundVolumeDb || 0;
                    if (config[item.configKey][type].soundMaxDist === undefined) config[item.configKey][type].soundMaxDist = item.base[type].soundMaxDist || 1200;
                }
            }
        }
    });
    // v900.0: migrar sonido de skills
    if (config.skillsData) {
        for (let sn in config.skillsData) {
            const sd = config.skillsData[sn];
            if (sd.sound === undefined) sd.sound = "";
            if (sd.soundVolumeDb === undefined) sd.soundVolumeDb = sd.soundVolume !== undefined ? sd.soundVolume : 0;
            if (sd.soundMaxDist === undefined) sd.soundMaxDist = 1400;
        }
    }"""

if old in txt:
    txt = txt.replace(old, new)
    print("patched libsMap")
else:
    print("libsMap not found")

# also need to patch addMechanic etc to include sound fields - not strictly needed since instance will override separately, but ensure default instance has sound empty
p.write_text(txt, encoding="utf-8")
