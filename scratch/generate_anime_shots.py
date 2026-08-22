import numpy as np
import lameenc
import os

SR = 44100
OUT_DIR = r"E:\Descon\descon\assets\Sonidos"
os.makedirs(OUT_DIR, exist_ok=True)

def lowpass(x, cutoff):
    rc = 1/(2*np.pi*cutoff)
    dt = 1/SR
    a = dt/(rc+dt)
    y = np.zeros_like(x)
    y[0]=x[0]
    for i in range(1,len(x)):
        y[i]=y[i-1]+a*(x[i]-y[i-1])
    return y

def highpass(x, cutoff):
    return x - lowpass(x, cutoff)

def encode_mp3(pcm, path, bitrate=128):
    enc = lameenc.Encoder()
    enc.set_bit_rate(bitrate)
    enc.set_in_sample_rate(SR)
    enc.set_channels(1)
    enc.set_quality(2)
    data = enc.encode(pcm.tobytes())
    data += enc.flush()
    with open(path,"wb") as f:
        f.write(data)
    return len(data)

def soft_fade(mix, fade_ms=28):
    fade_len = int(fade_ms/1000*SR)
    fade = np.ones(len(mix))
    # fade in 6ms + fade out
    attack = int(0.006*SR)
    fade[:attack] = 0.5*(1 - np.cos(np.pi*np.arange(attack)/attack))
    fade[-fade_len:] = 0.5*(1 + np.cos(np.linspace(0, np.pi, fade_len)))
    return mix * fade

def normalize(mix, target=0.68):
    p = np.max(np.abs(mix))
    if p>0:
        mix = mix/p*target
    return mix, p

def generate_laser(name, duration, f_start, f_end, bright=0.5):
    N = int(SR*duration)
    t = np.arange(N)/SR
    # envolventes suaves - nada de pelotita
    env_main = np.exp(-t*16)
    env_harm = np.exp(-t*22)
    # sweep exponencial suave
    k = 42
    f = f_end + (f_start - f_end)*np.exp(-k*t)
    phase = 2*np.pi*np.cumsum(f)/SR
    # carrier puro anime - sine limpio
    pew = np.sin(phase) * env_main * 0.55
    # leve armonico octave muy bajo para brillo anime sin cansar
    harm = np.sin(phase*2) * env_harm * (0.07*bright)
    harm = lowpass(harm, 3200)
    # vibrato sutil anime 18Hz
    vib = 1 + 0.015*np.sin(2*np.pi*18*t)
    pew = pew * vib
    # puff aire muy suave filtrado
    np.random.seed(101 if "01" in name else 102)
    noise = np.random.uniform(-1,1,N)
    puff = lowpass(noise, 1100) * np.exp(-t*28) * 0.10
    puff = highpass(puff, 280)
    # sub soplido muy leve 90hz
    sub = np.sin(2*np.pi*85*t) * np.exp(-t*20) * 0.14
    sub = lowpass(sub, 180)
    mix = pew + harm + puff + sub
    mix = lowpass(mix, 4200)  # nunca brillante agresivo
    mix = soft_fade(mix, fade_ms=22)
    mix = np.tanh(mix*1.08)/np.tanh(1.08)  # drive minimo
    mix, pk = normalize(mix, 0.68)
    pcm = (mix*32767).astype(np.int16)
    path = os.path.join(OUT_DIR, name+".mp3")
    sz = encode_mp3(pcm, path)
    print(f"{name}.mp3 | {duration*1000:.0f}ms | sweep {f_start}->{f_end}Hz | {sz/1024:.1f}KB | pk {pk:.2f}")
    return path

def generate_misil(name, duration=0.62):
    N = int(SR*duration)
    t = np.arange(N)/SR
    # misil anime: salida soplada + silbido cute, no explosion real
    # 1. thump inicial muy suave
    thump = np.sin(2*np.pi*72*t) * np.exp(-t*22) * 0.38
    thump = lowpass(thump, 220)
    # 2. swoosh ruido filtrado barrido
    np.random.seed(77)
    noise = np.random.uniform(-1,1,N)
    # cutoff baja con el tiempo 1800->400
    # aproximamos modulando con lowpass variable simple: mezcla de dos lowpass
    swoosh_a = lowpass(noise, 1600) * np.exp(-t*9) * 0.22
    swoosh_b = lowpass(noise, 600) * np.exp(-t*7) * 0.14
    swoosh = (swoosh_a* np.exp(-t*8) + swoosh_b*(1-np.exp(-t*8))) * 0.9
    swoosh = highpass(swoosh, 320) * np.exp(-t*10)
    # envolvente ataque suave
    swoosh *= (1 - np.exp(-t*18))
    # 3. silbido anime 680Hz con caida a 420
    f_whistle = 420 + (680-420)*np.exp(-12*t)
    whistle = np.sin(2*np.pi*np.cumsum(f_whistle)/SR) * np.exp(-t*10) * 0.24
    # vibrato suave
    whistle *= (1 + 0.04*np.sin(2*np.pi*9*t))
    whistle = lowpass(whistle, 2500)
    # 4. brillo corto inicial
    tick = np.sin(2*np.pi*1400*t) * np.exp(-t*65) * 0.09
    mix = thump + swoosh + whistle + tick
    mix = lowpass(mix, 3600)
    mix = soft_fade(mix, fade_ms=35)
    mix = np.tanh(mix*1.12)/np.tanh(1.12)
    mix, pk = normalize(mix, 0.66)
    pcm = (mix*32767).astype(np.int16)
    path = os.path.join(OUT_DIR, name+".mp3")
    sz = encode_mp3(pcm, path)
    print(f"{name}.mp3 | {duration*1000:.0f}ms | misil anime soplado | {sz/1024:.1f}KB | pk {pk:.2f}")
    return path

def generate_bomba(name, duration=0.75):
    N = int(SR*duration)
    t = np.arange(N)/SR
    # bomba anime: lanzamiento pesadito pero cute, caida con silbido, nada realista
    # 1. drop grave suave 90->38
    f_drop = 38 + (95-38)*np.exp(-8*t)
    phase_drop = 2*np.pi*np.cumsum(f_drop)/SR
    drop = np.sin(phase_drop) * np.exp(-t*7) * 0.52
    drop = lowpass(drop, 260)
    # 2. cuerpo 140Hz
    body = np.sin(2*np.pi*138*t) * np.exp(-t*9) * 0.24
    body = lowpass(body, 500)
    # 3. silbido de caida 850->280 largo y cute
    f_fall = 280 + (820-280)*np.exp(-4*t)
    fall = np.sin(2*np.pi*np.cumsum(f_fall)/SR) * np.exp(-t*5.5) * 0.20
    fall = lowpass(fall, 2200)
    # leve wow anime
    fall *= (1 + 0.03*np.sin(2*np.pi*6*t))
    # 4. puff de lanzamiento
    np.random.seed(55)
    noise = np.random.uniform(-1,1,N)
    puff = lowpass(noise, 550) * np.exp(-t*8) * 0.18
    puff = highpass(puff, 180)
    # ataque puff 12ms
    puff *= (1 - np.exp(-t*24))
    # 5. pop cute final muy suave 1600Hz blip
    pop = np.sin(2*np.pi*1650*t) * np.exp(-((t-0.12)**2)*180) * 0.10
    pop[t<0.08] = 0
    mix = drop + body + fall + puff + pop
    mix = lowpass(mix, 3200)
    mix = soft_fade(mix, fade_ms=40)
    mix = np.tanh(mix*1.10)/np.tanh(1.10)
    mix, pk = normalize(mix, 0.65)
    pcm = (mix*32767).astype(np.int16)
    path = os.path.join(OUT_DIR, name+".mp3")
    sz = encode_mp3(pcm, path)
    print(f"{name}.mp3 | {duration*1000:.0f}ms | bomba anime caida cute | {sz/1024:.1f}KB | pk {pk:.2f}")
    return path

# 4 variantes pedidas
generate_laser("disparo_laser_suave_01", 0.34, 880, 520, bright=0.7)
generate_laser("disparo_laser_suave_02", 0.28, 1120, 680, bright=0.5)
generate_misil("disparo_misil_suave", 0.62)
generate_bomba("disparo_bomba_suave", 0.75)

print("\nTodos en", OUT_DIR, "- solo MP3, anime suave, no cansan")
