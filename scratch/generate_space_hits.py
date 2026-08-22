import numpy as np
import lameenc
import os
import wave

SR = 44100

OUT_DIR = r"E:\Descon\descon\assets\Sonidos\Impactos"
os.makedirs(OUT_DIR, exist_ok=True)

def soft_clip(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)

def bit_crush(x, bits=12):
    # simple bit reduction effect
    levels = 2**bits
    return np.round(x * levels) / levels

def lowpass_onepole(x, cutoff_hz):
    # simple one-pole lowpass
    rc = 1.0 / (2 * np.pi * cutoff_hz)
    dt = 1.0 / SR
    alpha = dt / (rc + dt)
    y = np.zeros_like(x)
    y[0] = x[0]
    for i in range(1, len(x)):
        y[i] = y[i-1] + alpha * (x[i] - y[i-1])
    return y

def highpass_onepole(x, cutoff_hz):
    # simple one-pole highpass = x - lowpass(x)
    return x - lowpass_onepole(x, cutoff_hz)

def add_spatial_tail(signal, delay_ms=35, decay=0.22, mix=0.18):
    # mini slap delay for sensacion espacial
    delay = int(SR * delay_ms / 1000)
    out = signal.copy()
    if delay < len(signal):
        echo = np.zeros_like(signal)
        echo[delay:] = signal[:-delay] * decay
        # highpass echo para que no embarre graves
        echo = highpass_onepole(echo, 800)
        out = out + echo * mix * 4
    return out

def encode_mp3(pcm_int16, path, bitrate=192):
    encoder = lameenc.Encoder()
    encoder.set_bit_rate(bitrate)
    encoder.set_in_sample_rate(SR)
    encoder.set_channels(1)
    encoder.set_quality(2)
    mp3_data = encoder.encode(pcm_int16.tobytes())
    mp3_data += encoder.flush()
    with open(path, "wb") as f:
        f.write(mp3_data)
    return len(mp3_data)

def save_wav(pcm_int16, path):
    with wave.open(path, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm_int16.tobytes())

def normalize_and_fade(mix, fade_ms=12):
    peak = np.max(np.abs(mix))
    if peak > 0:
        mix = mix / peak * 0.88
    fade_len = int(fade_ms/1000 * SR)
    fade = np.ones(len(mix))
    fade[-fade_len:] = np.linspace(1, 0, fade_len)
    return mix * fade

def generate_space_hit(name, duration, desc):
    N = int(SR * duration)
    t = np.arange(N) / SR
    print(f"\nGenerando {name} - {desc}")

    mix = np.zeros(N)

    if name == "impact_laser_hit":
        # Hit standard nave vs nave - plastico/energia, moderno
        # 1) Zap descendente FM 1200 -> 180Hz
        f_start, f_end = 1200, 160
        k = 38
        freq_zap = f_end + (f_start - f_end) * np.exp(-k * t)
        # FM: carrier modulated por modulator
        mod_freq = 110
        mod_index = 45 * np.exp(-t*60)
        phase_zap = 2*np.pi*np.cumsum(freq_zap)/SR + mod_index*np.sin(2*np.pi*mod_freq*t)
        zap = np.sin(phase_zap) * np.exp(-t*28) * 0.65
        zap[t>0.11] *= np.exp(-(t[t>0.11]-0.11)*60)

        # 2) Cuerpo plasma - square-ish + sine, 260Hz
        body = np.sin(2*np.pi*260*t) * np.exp(-t*32) * 0.45
        # square harmonic
        body_sq = np.sign(np.sin(2*np.pi*260*t)) * 0.15 * np.exp(-t*45)
        # filtrar un poco para no rasposo extremo
        body_sq = lowpass_onepole(body_sq, 2800)

        # 3) Sub electronico (triangle) 90 -> 35Hz
        f_sub = 35 + (90-35)*np.exp(-22*t)
        phase_sub = 2*np.pi*np.cumsum(f_sub)/SR
        # triangle approx via asin(sin)
        tri = (2/np.pi)*np.arcsin(np.sin(phase_sub)) * np.exp(-t*20) * 0.5

        # 4) Shimmer shield - high 3500Hz + ring mod
        shimmer = np.sin(2*np.pi*3800*t) * np.sin(2*np.pi*120*t) * np.exp(-t*90) * 0.22
        shimmer += np.sin(2*np.pi*5200*t) * np.exp(-t*120) * 0.12

        # 5) Noise burst filtrado (choque de energia)
        np.random.seed(42)
        noise = np.random.uniform(-1,1,N)
        # bandpass simple: highpass 1k + lowpass 4k
        noise_bp = highpass_onepole(noise, 1200)
        noise_bp = lowpass_onepole(noise_bp, 4200)
        noise_burst = noise_bp * np.exp(-t*90) * 0.35
        # solo los primeros 18ms fuerte
        env_noise = np.exp(-t*110)
        noise_burst = noise_burst * env_noise

        mix = zap + body + body_sq + tri + shimmer + noise_burst
        mix = soft_clip(mix, drive=1.9)
        mix = add_spatial_tail(mix, delay_ms=28, decay=0.18, mix=0.16)
        mix = highpass_onepole(mix, 40)  # limpiar DC

    elif name == "impact_shield":
        # Impacto contra escudo energia - mas brillante, resonante, bubble
        # 1) Shield wobble - sine 700Hz con pitch bend up/down + resonancia
        # frequency wobble: 700 -> 450 -> 680
        f_shield = 550 + 180*np.sin(2*np.pi*18*t)*np.exp(-t*25) + 120*np.exp(-t*40)
        phase_shield = 2*np.pi*np.cumsum(f_shield)/SR
        shield = np.sin(phase_shield) * np.exp(-t*22) * 0.62
        # add quint
        shield_harm = np.sin(phase_shield*1.5) * np.exp(-t*30) * 0.22

        # 2) Cristal shimmer 4200Hz + 7200Hz decaying lento (escudo vibrando)
        shimmer = np.sin(2*np.pi*4200*t) * np.exp(-t*55) * 0.28
        shimmer += np.sin(2*np.pi*7200*t) * np.exp(-t*75) * 0.14
        shimmer += np.sin(2*np.pi*10800*t) * np.exp(-t*90) * 0.06

        # 3) Plasma burst corto FM
        f_zap = 900 + 600*np.exp(-t*50)
        zap = np.sin(2*np.pi*np.cumsum(f_zap)/SR) * np.exp(-t*70) * 0.38
        # ringmod
        zap_rm = zap * np.sin(2*np.pi*180*t)

        # 4) Bubble low 80Hz short
        bubble = np.sin(2*np.pi*75*t) * np.exp(-t*18) * 0.45

        # 5) Noise chispa
        np.random.seed(7)
        noise = np.random.uniform(-1,1,N)
        noise_hp = highpass_onepole(noise, 3000)
        spark = noise_hp * np.exp(-t*150) * 0.25

        mix = shield + shield_harm + shimmer + zap_rm + bubble + spark
        mix = soft_clip(mix, drive=1.7)
        mix = add_spatial_tail(mix, delay_ms=42, decay=0.30, mix=0.22)

    elif name == "impact_hull":
        # Impacto casco metalico - mas contundente, mecanico pero sci-fi
        # 1) Metal clang - inharmonic : 220, 340, 510 Hz
        clang = (np.sin(2*np.pi*220*t)*0.5 + np.sin(2*np.pi*347*t)*0.32 + np.sin(2*np.pi*512*t)*0.18) * np.exp(-t*28) * 0.6
        # add detuned doubling for chorus metal
        clang2 = (np.sin(2*np.pi*223*t)*0.5 + np.sin(2*np.pi*351*t)*0.32) * np.exp(-t*30) * 0.28

        # 2) Low thump electronico 100 -> 30Hz
        f_sub = 30 + (105-30)*np.exp(-28*t)
        phase_sub = 2*np.pi*np.cumsum(f_sub)/SR
        sub = np.sin(phase_sub) * np.exp(-t*16) * 0.78

        # 3) Distorted square body 180Hz
        sq = np.sign(np.sin(2*np.pi*185*t)) * np.exp(-t*35) * 0.22
        sq = lowpass_onepole(sq, 2200)

        # 4) Debris noise - mid band 800-2500
        np.random.seed(99)
        noise = np.random.uniform(-1,1,N)
        debris = highpass_onepole(noise, 700)
        debris = lowpass_onepole(debris, 2600)
        debris = debris * np.exp(-t*45) * 0.33

        # 5) High tick 2500Hz ultra corto para definir impacto
        tick = np.sin(2*np.pi*2600*t) * np.exp(-t*200) * 0.30

        mix = sub + clang + clang2 + sq + debris + tick
        mix = soft_clip(mix, drive=2.4)
        mix = add_spatial_tail(mix, delay_ms=22, decay=0.14, mix=0.12)

    elif name == "impact_plasma_heavy":
        # Boss / heavy plasma cannon - largo, epico
        # 1) Charge down-sweep 600 -> 45Hz largo
        f_sweep = 45 + (650-45)*np.exp(-14*t)
        phase_sweep = 2*np.pi*np.cumsum(f_sweep)/SR
        sweep = np.sin(phase_sweep) * np.exp(-t*12) * 0.70
        # FM on sweep
        fm = 60*np.sin(2*np.pi*35*t) * np.exp(-t*15)
        sweep_fm = np.sin(phase_sweep + fm) * np.exp(-t*12) * 0.15

        # 2) Body plasma detuned 150Hz + 151.5Hz (beating)
        body = np.sin(2*np.pi*150*t)*np.exp(-t*14)*0.45 + np.sin(2*np.pi*151.8*t)*np.exp(-t*14)*0.45
        body_harm = np.sin(2*np.pi*300*t)*np.exp(-t*18)*0.18

        # 3) Resonance shimmer largo
        shimmer = np.sin(2*np.pi*3200*t)*np.exp(-t*35)*0.18 + np.sin(2*np.pi*4800*t)*np.exp(-t*40)*0.11

        # 4) Rumble noise low
        np.random.seed(2026)
        noise = np.random.uniform(-1,1,N)
        rumble = lowpass_onepole(noise, 400)
        rumble = rumble * np.exp(-t*18) * 0.32

        # 5) Impact click
        click = np.sin(2*np.pi*2000*t)*np.exp(-t*180)*0.22

        mix = sweep + sweep_fm + body + body_harm + shimmer + rumble + click
        mix = soft_clip(mix, drive=2.1)
        mix = add_spatial_tail(mix, delay_ms=55, decay=0.25, mix=0.20)

    # normalize
    mix = normalize_and_fade(mix, fade_ms=14)
    pcm = (mix * 32767).astype(np.int16)

    mp3_path = os.path.join(OUT_DIR, name + ".mp3")
    wav_path = os.path.join(OUT_DIR, name + ".wav")
    mp3_size = encode_mp3(pcm, mp3_path)
    save_wav(pcm, wav_path)
    print(f" -> {mp3_path} | {duration*1000:.0f}ms | {mp3_size/1024:.1f}KB | WAV {len(pcm)/SR*1000:.0f}ms")
    return mp3_path

# Generar packs espaciales
generate_space_hit("impact_laser_hit", 0.22, "Hit estandar nave - laser/plasma moderno")
generate_space_hit("impact_shield", 0.32, "Hit escudo energia - brillante/resonante")
generate_space_hit("impact_hull", 0.26, "Hit casco metalico - contundente sci-fi")
generate_space_hit("impact_plasma_heavy", 0.45, "Hit boss / canon pesado - epico grave")

print("\nTodos generados en", OUT_DIR)
