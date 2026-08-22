import numpy as np
import lameenc
import os

SR = 44100

def soft_clip(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)

def generate_hit(
    duration=0.22,
    sub_freq_start=140,
    sub_freq_end=35,
    body_freq=220,
    filename="impact_hit.mp3",
    style="punch"
):
    N = int(SR * duration)
    t = np.arange(N) / SR

    # --- envelopes
    # transient very fast
    env_transient = np.exp(-t * 180)  # 5ms decay
    env_body = np.exp(-t * 35)       # ~30ms
    env_sub = np.exp(-t * 18)        # ~55ms tail
    # overall amplitude shaping
    env_overall = np.exp(-t * 22)
    # slight fade out last 20ms to avoid click
    fade_len = int(0.015 * SR)
    fade = np.ones(N)
    fade[-fade_len:] = np.linspace(1, 0, fade_len)

    # --- 1) SUB THUMP with pitch drop
    # exponential pitch drop
    k = 25  # drop speed
    # freq(t) = end + (start-end)*exp(-k*t)
    freq_sub = sub_freq_end + (sub_freq_start - sub_freq_end) * np.exp(-k * t)
    phase_sub = 2 * np.pi * np.cumsum(freq_sub) / SR
    sub = np.sin(phase_sub) * env_sub * 0.9

    # --- 2) BODY PUNCH (mid)
    body = np.sin(2 * np.pi * body_freq * t) * env_body * 0.55
    # add a slightly detuned layer for thickness
    body2 = np.sin(2 * np.pi * (body_freq * 1.52) * t) * np.exp(-t * 50) * 0.25

    # --- 3) TRANSIENT CLICK / IMPACT NOISE
    # white noise -> highpass via simple difference, burst only at start
    np.random.seed(0 if style=="punch" else 123)
    noise = np.random.uniform(-1, 1, N)
    # simple highpass: y[n] = x[n] - x[n-1]
    noise_hp = np.zeros_like(noise)
    noise_hp[1:] = noise[1:] - 0.92 * noise[:-1]
    # band burst: window it very short
    transient = noise_hp * env_transient * 0.6
    # add a very short sine click 1.8kHz for "hit" clarity
    click_freq = 1800 if style=="punch" else 2800
    click = np.sin(2 * np.pi * click_freq * t) * np.exp(-t * 280) * 0.35
    # only first 12ms
    click[t > 0.012] *= np.exp(-(t[t>0.012]-0.012)*200)

    # --- 4) MIX
    mix = sub + body + body2 + transient + click

    # apply overall envelope and soft clip for punch
    mix = mix * env_overall
    # distortion drive depends on style
    drive = 2.2 if style=="punch" else 2.8
    mix = soft_clip(mix, drive=drive) * 0.85

    # slight pitch wobble for boss hits? not for regular

    # normalize to -1dB
    peak = np.max(np.abs(mix))
    if peak > 0:
        mix = mix / peak * 0.89

    mix *= fade

    # convert to 16-bit PCM
    pcm = (mix * 32767).astype(np.int16)

    # --- Encode MP3 with lameenc
    encoder = lameenc.Encoder()
    encoder.set_bit_rate(192)
    encoder.set_in_sample_rate(SR)
    encoder.set_channels(1)
    encoder.set_quality(2)  # 2 = high quality

    mp3_data = encoder.encode(pcm.tobytes())
    mp3_data += encoder.flush()

    out_path = os.path.join(r"E:\Descon", filename)
    # ensure directory exists
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(mp3_data)

    # also save wav for debug
    import wave
    wav_path = out_path.replace(".mp3", ".wav")
    with wave.open(wav_path, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())

    dur_ms = duration*1000
    size_kb = len(mp3_data)/1024
    print(f"Generado: {out_path} | {dur_ms:.0f}ms | {size_kb:.1f}KB | peak {peak:.2f}")
    return out_path

# Generate 3 variants:
# 1) Hit standard - equilibrado para player/enemigo
# 2) Hit heavy - mas grave para boss
# 3) Hit sharp - mas click para espada/golpe rapido
generate_hit(duration=0.20, sub_freq_start=150, sub_freq_end=40, body_freq=230, filename="impact_hit.mp3", style="punch")
generate_hit(duration=0.28, sub_freq_start=110, sub_freq_end=28, body_freq=180, filename="impact_hit_heavy.mp3", style="heavy")
generate_hit(duration=0.15, sub_freq_start=180, sub_freq_end=50, body_freq=320, filename="impact_hit_sharp.mp3", style="punch")

print("Listo - 3 sonidos generados en E:\\Descon\\")
