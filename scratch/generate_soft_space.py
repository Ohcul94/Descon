import numpy as np
import lameenc
import os

SR = 44100
OUT_DIR = r"E:\Descon\descon\assets\Sonidos"
os.makedirs(OUT_DIR, exist_ok=True)

def lowpass_onepole(x, cutoff):
    rc = 1/(2*np.pi*cutoff)
    dt = 1/SR
    a = dt/(rc+dt)
    y = np.zeros_like(x)
    y[0]=x[0]
    for i in range(1,len(x)):
        y[i]=y[i-1]+a*(x[i]-y[i-1])
    return y

def highpass_onepole(x, cutoff):
    return x - lowpass_onepole(x, cutoff)

def encode_mp3(pcm, path):
    enc = lameenc.Encoder()
    enc.set_bit_rate(128)
    enc.set_in_sample_rate(SR)
    enc.set_channels(1)
    enc.set_quality(2)
    data = enc.encode(pcm.tobytes())
    data += enc.flush()
    with open(path,"wb") as f:
        f.write(data)
    return len(data)

# --- Generador suave espacial ---
def generate_soft(name, duration, variant=1):
    N = int(SR*duration)
    t = np.arange(N)/SR
    
    # Envolvente SUAVE: ataque 8ms fade in + decay largo y sin click
    attack = 0.008
    env_attack = np.clip(t/attack, 0, 1)
    # curva suave ataque
    env_attack = 0.5*(1 - np.cos(np.pi*env_attack))  # raised cosine
    
    # decays muy suaves, nada de pelotita
    env_main = np.exp(-t*9)      # cola larga y tranquila
    env_mid  = np.exp(-t*14)
    env_air  = np.exp(-t*11)
    
    # fade out muy suave 30ms
    fade_len = int(0.030*SR)
    fade = np.ones(N)
    fade[-fade_len:] = 0.5*(1+np.cos(np.linspace(0, np.pi, fade_len)))

    mix = np.zeros(N)

    if variant == 1:
        # Soft hit 1 - mas grave y esponjoso, ideal colision nave-nave tranquila
        # Sub 65->30 Hz triangle/sine muy suave
        f_sub = 30 + (65-30)*np.exp(-10*t)
        phase_sub = 2*np.pi*np.cumsum(f_sub)/SR
        sub = np.sin(phase_sub) * env_main * 0.58
        # suavizar
        sub = lowpass_onepole(sub, 250)

        # Cuerpo 110 Hz sine puro, sin harmonicos duros
        body = np.sin(2*np.pi*110*t) * env_mid * 0.30
        body2 = np.sin(2*np.pi*165*t) * env_mid * 0.14
        body = lowpass_onepole(body+body2, 600)

        # Aire espacial - 900 Hz muy suave, como brisa plasma
        air = np.sin(2*np.pi*900*t) * env_air * 0.08
        air += np.sin(2*np.pi*1400*t) * env_air * 0.04
        air = lowpass_onepole(air, 1800)

        # Ruido rosado muy filtrado, solo textura suave
        np.random.seed(10)
        noise = np.random.uniform(-1,1,N)
        # pink-ish: lowpass fuerte
        puff = lowpass_onepole(noise, 700)
        puff = puff * np.exp(-t*12) * 0.18
        puff = puff * env_attack

        mix = (sub + body + air + puff) * env_attack * 0.95

    elif variant == 2:
        # Soft hit 2 - mas espacial brillante pero tranquilo (escudo suave)
        f_sub = 32 + (55-32)*np.exp(-9*t)
        phase_sub = 2*np.pi*np.cumsum(f_sub)/SR
        sub = np.sin(phase_sub) * np.exp(-t*8) * 0.45
        sub = lowpass_onepole(sub, 220)

        # Tonos espaciales 280Hz + 420Hz beating lento muy suave
        tone1 = np.sin(2*np.pi*280*t) * np.exp(-t*13) * 0.28
        tone2 = np.sin(2*np.pi*418*t) * np.exp(-t*14) * 0.20
        tones = lowpass_onepole(tone1+tone2, 800)

        # Sheen 1800Hz ultra suave
        sheen = np.sin(2*np.pi*1850*t) * np.exp(-t*16) * 0.07

        np.random.seed(22)
        noise = np.random.uniform(-1,1,N)
        haze = lowpass_onepole(noise, 900) * np.exp(-t*14) * 0.14

        mix = (sub + tones + sheen + haze) * env_attack

    elif variant == 3:
        # Soft hit 3 - el mas cortito y apagado, para impactos leves
        f_sub = 28 + (70-28)*np.exp(-14*t)
        phase_sub = 2*np.pi*np.cumsum(f_sub)/SR
        sub = np.sin(phase_sub) * np.exp(-t*12) * 0.52
        sub = lowpass_onepole(sub, 280)

        body = np.sin(2*np.pi*140*t) * np.exp(-t*18) * 0.32
        body = lowpass_onepole(body, 500)

        # casi sin aire
        np.random.seed(33)
        noise = np.random.uniform(-1,1,N)
        soft = lowpass_onepole(noise, 500) * np.exp(-t*18) * 0.16

        mix = (sub + body + soft) * env_attack

    # Suavizado final - nada de clip duro
    # solo leve tanh muy suave drive 1.1
    mix = np.tanh(mix*1.15)/np.tanh(1.15)
    mix = mix * fade * 0.82

    # Normalizar suave a -2dB
    peak = np.max(np.abs(mix))
    if peak>0:
        mix = mix/peak * 0.72

    pcm = (mix*32767).astype(np.int16)
    path = os.path.join(OUT_DIR, name+".mp3")
    sz = encode_mp3(pcm, path)
    print(f"{name}.mp3 | {duration*1000:.0f}ms | {sz/1024:.1f}KB | peak {peak:.3f} | suave OK")
    return path

# Generar 3 hits suaves espaciales - SOLO MP3
generate_soft("impacto_suave_01", 0.38, variant=1)
generate_soft("impacto_suave_02", 0.42, variant=2)
generate_soft("impacto_suave_03", 0.28, variant=3)

print("\nGenerados solo MP3 en", OUT_DIR)
