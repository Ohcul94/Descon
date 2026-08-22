import numpy as np, lameenc, os
SR=44100
OUT_DIR=r"E:\Descon\descon\assets\Sonidos"
os.makedirs(OUT_DIR, exist_ok=True)

def lowpass(x, cutoff):
    rc=1/(2*np.pi*cutoff)
    dt=1/SR
    a=dt/(rc+dt)
    y=np.zeros_like(x)
    y[0]=x[0]
    for i in range(1,len(x)):
        y[i]=y[i-1]+a*(x[i]-y[i-1])
    return y
def highpass(x, cutoff):
    return x-lowpass(x,cutoff)
def encode(pcm,path):
    enc=lameenc.Encoder()
    enc.set_bit_rate(128)
    enc.set_in_sample_rate(SR)
    enc.set_channels(1)
    enc.set_quality(2)
    d=enc.encode(pcm.tobytes())
    d+=enc.flush()
    open(path,"wb").write(d)
    return len(d)

# Misil anime largo y suave - sin metal
duration=0.95
N=int(SR*duration)
t=np.arange(N)/SR

# envolventes suaves
attack=int(0.010*SR)
fade_in=np.ones(N)
fade_in[:attack]=0.5*(1-np.cos(np.pi*np.arange(attack)/attack))
env_main=np.exp(-t*6.5)  # cola muy larga y tranquila
env_swoosh=np.exp(-t*5.2)

# 1. thump inicial ultra suave 58Hz
thump=np.sin(2*np.pi*58*t)*np.exp(-t*18)*0.30
thump=lowpass(thump,180)

# 2. swoosh aire largo anime - ruido rosado filtrado
np.random.seed(88)
noise=np.random.uniform(-1,1,N)
# dos etapas para sensacion de movimiento sin metal
swoosh = lowpass(noise, 1100) * 0.20
# filtrar dejando solo aire suave 500-1100
swoosh = highpass(swoosh, 380)
swoosh = swoosh * env_swoosh * 0.85
# darle forma de "shuuu" largo: attack lento 60ms
swoosh *= (1 - np.exp(-t*14))
# lowpass final para quitar metal
swoosh = lowpass(swoosh, 1800)

# 3. silbido principal anime cute - sweep lento 620->340 Hz  (corazon del sonido)
f_whistle = 340 + (620-340)*np.exp(-3.2*t)
phase_whistle = 2*np.pi*np.cumsum(f_whistle)/SR
whistle = np.sin(phase_whistle)*np.exp(-t*4.8)*0.26
# vibrato anime muy suave 7Hz +- 15 cents
whistle *= (1 + 0.035*np.sin(2*np.pi*7*t + 0.5))
whistle = lowpass(whistle, 2400)

# 4. capa celestial 1400Hz muy baja para brillo anime sin metal
celeste = np.sin(2*np.pi*1380*t)*np.exp(-t*7)*0.055
celeste += np.sin(2*np.pi*1850*t)*np.exp(-t*8)*0.030
celeste = lowpass(celeste, 2400)

# 5. sub grave continuo de vuelo 45Hz
hum = np.sin(2*np.pi*44*t)*np.exp(-t*5)*0.16
hum = lowpass(hum, 120)

# mezcla suave
mix = thump*0.9 + swoosh*1.0 + whistle*1.0 + celeste*0.9 + hum*0.8
# filtro maestro suave
mix = lowpass(mix, 2800)
# fade in/out suaves
fade_out_len=int(0.045*SR)
fade=np.ones(N)
fade[:attack]=fade_in[:attack]
fade[-fade_out_len:] = 0.5*(1+np.cos(np.linspace(0,np.pi,fade_out_len)))
mix = mix * fade
# drive minimo nada de metal
mix = np.tanh(mix*1.06)/np.tanh(1.06)
# normalizar suave -3.5dB para no cansar
peak=np.max(np.abs(mix))
mix=mix/peak*0.66

pcm=(mix*32767).astype(np.int16)
path=os.path.join(OUT_DIR,"disparo_misil_suave_largo.mp3")
sz=encode(pcm,path)
print(f"Generado: {path}")
print(f"Duracion {duration*1000:.0f}ms | {sz/1024:.1f}KB | peak {peak:.3f}")
print(f"Caracter: anime largo, swoosh 1100Hz-> aire + silbido 620->340Hz, 0 metal, lowpass 2.8k")
