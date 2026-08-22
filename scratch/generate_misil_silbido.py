import numpy as np, lameenc, os
SR=44100
OUT=r"E:\Descon\descon\assets\Sonidos"
os.makedirs(OUT, exist_ok=True)

def lowpass(x, cutoff):
    rc=1/(2*np.pi*cutoff)
    dt=1/SR
    a=dt/(rc+dt)
    y=np.zeros_like(x)
    y[0]=x[0]
    for i in range(1,len(x)):
        y[i]=y[i-1]+a*(x[i]-y[i-1])
    return y

def encode(pcm, path):
    enc=lameenc.Encoder()
    enc.set_bit_rate(128)
    enc.set_in_sample_rate(SR)
    enc.set_channels(1)
    enc.set_quality(2)
    d=enc.encode(pcm.tobytes())
    d+=enc.flush()
    open(path,"wb").write(d)
    return len(d)

# Nuevo misil silbido - cortito fluido sin terminacion
duration=0.26  # cortito como "salio algo"
N=int(SR*duration)
t=np.arange(N)/SR

# sweep agudo fluido 1900 -> 850 Hz exponencial suave
f_start, f_end = 1850, 820
k=18  # sweep lento fluido, no rebote
f = f_end + (f_start-f_end)*np.exp(-k*t)
phase = 2*np.pi*np.cumsum(f)/SR

# sine puro anime lindo
env = np.exp(-t*9)  # cola suave que se va sola, sin terminacion dura
# ataque ultra suave 5ms
attack=int(0.005*SR)
env_attack=np.ones(N)
env_attack[:attack]=0.5*(1-np.cos(np.pi*np.arange(attack)/attack))
env = env * env_attack

whistle = np.sin(phase) * env * 0.62
# vibrato super sutil para fluidez
whistle *= (1 + 0.015*np.sin(2*np.pi*11*t))

# segunda capa una octava abajo muy bajita para cuerpo sin lata
layer = np.sin(phase*0.51) * np.exp(-t*11) * 0.09
layer = lowpass(layer, 2000)

# aire soplido cortito inicial solo 0.04s muy suave
np.random.seed(121)
noise=np.random.uniform(-1,1,N)
air = lowpass(noise, 1400) * np.exp(-t*32) * 0.07
air[ t>0.06 ] *= np.exp(-(t[t>0.06]-0.06)*40)

mix = whistle + layer + air
# lowpass maestro para quitar lata 3500Hz
mix = lowpass(mix, 3200)
# fade out progresivo sin terminacion marcada 50ms final
fade_len=int(0.05*SR)
fade=np.ones(N)
fade[-fade_len:]=0.5*(1+np.cos(np.linspace(0,np.pi,fade_len)))
mix = mix * fade
# sin distorsion
mix = np.tanh(mix*1.04)/np.tanh(1.04)
peak=np.max(np.abs(mix))
mix=mix/peak*0.64

pcm=(mix*32767).astype(np.int16)
path=os.path.join(OUT,"disparo_misil_silbido.mp3")
sz=encode(pcm,path)
print(f"Generado: {path}")
print(f"260ms silbido 1850->820Hz fluido | {sz/1024:.1f}KB | peak {peak:.3f} | sine puro cute sin lata")
# tambien variante un pelin mas aguda por si quiere elegir
# variante 2: 2100->980
f_start2, f_end2 = 2100, 980
f2 = f_end2 + (f_start2-f_end2)*np.exp(-k*t)
phase2 = 2*np.pi*np.cumsum(f2)/SR
whistle2 = np.sin(phase2) * env * 0.62 * (1 + 0.015*np.sin(2*np.pi*11*t))
mix2 = whistle2 + layer + air
mix2 = lowpass(mix2, 3200)
mix2 = mix2 * fade
mix2 = np.tanh(mix2*1.04)/np.tanh(1.04)
mix2=mix2/np.max(np.abs(mix2))*0.64
pcm2=(mix2*32767).astype(np.int16)
path2=os.path.join(OUT,"disparo_misil_silbido_agudo.mp3")
sz2=encode(pcm2,path2)
print(f"Variante aguda: {path2} | 2100->980Hz | {sz2/1024:.1f}KB")
