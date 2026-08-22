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
def highpass(x,c): return x-lowpass(x,c)
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

# Bomba/Mina anime - totalmente distinta a laser/misil silbido
# Concepto: "pomu" esponjoso grave + wobble cute, como poner una mina flotante
duration=0.38
N=int(SR*duration)
t=np.arange(N)/SR

# ataque suave 8ms
attack=int(0.008*SR)
env_attack=np.ones(N)
env_attack[:attack]=0.5*(1-np.cos(np.pi*np.arange(attack)/attack))

# 1. Cuerpo principal bloop grave 140 -> 55 Hz (triangle-ish sine)
f_body = 55 + (140-55)*np.exp(-14*t)
phase = 2*np.pi*np.cumsum(f_body)/SR
body = np.sin(phase) * np.exp(-t*9) * 0.58
# triangle suavizado
body_tri = (2/np.pi)*np.arcsin(np.sin(phase))*0.12 * np.exp(-t*10)
body = lowpass(body+body_tri, 400)

# 2. Wobble anime 95Hz con modulacion lenta (mina flotando)
wobble = np.sin(2*np.pi*92*t + 0.6*np.sin(2*np.pi*5*t)) * np.exp(-t*7) * 0.18
wobble = lowpass(wobble, 600)

# 3. Pop cute 520Hz muy corto y bajo, para "colocar" sin lata
pop = np.sin(2*np.pi*520*t) * np.exp(-t*28) * 0.11
pop = lowpass(pop, 1200)
# pop solo primeros 60ms
pop[t>0.06] *= np.exp(-(t[t>0.06]-0.06)*50)

# 4. Puff aire esponjoso - ruido filtrado grave
np.random.seed(200)
noise=np.random.uniform(-1,1,N)
puff = lowpass(noise, 450) * np.exp(-t*11) * 0.20
puff = highpass(puff, 60) * env_attack

# 5. Burbuja 220Hz armonico suave para que no sea solo grave
bubble = np.sin(2*np.pi*220*t) * np.exp(-t*14) * 0.10
bubble = lowpass(bubble, 800)

mix = body + wobble + pop + puff + bubble
mix = lowpass(mix, 1800)  # muy oscuro vs laser agudo -> distinto total
# fade out largo fluido sin corte
fade_len=int(0.07*SR)
fade=np.ones(N)
fade[:attack]=env_attack[:attack]
fade[-fade_len:]=0.5*(1+np.cos(np.linspace(0,np.pi,fade_len)))
mix = mix * fade
mix = np.tanh(mix*1.05)/np.tanh(1.05)
peak=np.max(np.abs(mix))
mix=mix/peak*0.62

pcm=(mix*32767).astype(np.int16)
path=os.path.join(OUT,"disparo_bomba_mina.mp3")
sz=encode(pcm,path)
print(f"Generado: {path}")
print(f"380ms bomba/mina esponjosa 140->55Hz bloop | {sz/1024:.1f}KB | peak {peak:.3f}")
print("Caracter: grave pomu wobble, pop 520Hz suave, puff 450Hz, lowpass 1.8k - totalmente distinto a silbido laser/misil")

# Variante ligeramente mas cute corta
duration2=0.30
N2=int(SR*duration2)
t2=np.arange(N2)/SR
attack2=int(0.007*SR)
env2=np.ones(N2)
env2[:attack2]=0.5*(1-np.cos(np.pi*np.arange(attack2)/attack2))
f2 = 60 + (155-60)*np.exp(-16*t2)
phase2=2*np.pi*np.cumsum(f2)/SR
body2=np.sin(phase2)*np.exp(-t2*11)*0.60
body2=lowpass(body2,380)
pop2=np.sin(2*np.pi*620*t2)*np.exp(-t2*32)*0.10
puff2=lowpass(np.random.uniform(-1,1,N2),500)*np.exp(-t2*13)*0.18
mix2=body2+pop2+puff2
mix2=lowpass(mix2,1900)
fade2=np.ones(N2)
fade2[:attack2]=env2[:attack2]
fade2[-int(0.06*SR):]=0.5*(1+np.cos(np.linspace(0,np.pi,int(0.06*SR))))
mix2=mix2*fade2
mix2=np.tanh(mix2*1.05)/np.tanh(1.05)
mix2=mix2/np.max(np.abs(mix2))*0.62
pcm2=(mix2*32767).astype(np.int16)
path2=os.path.join(OUT,"mina_suave_cute.mp3")
sz2=encode(pcm2,path2)
print(f"Variante mina cute: {path2} | 300ms 155->60Hz | {sz2/1024:.1f}KB")
