# HPL — High Performance Linpack sobre un portátil

Workshop final del semillero **Scar (HPC)** — EAFIT, 2026-2
Juan José Díaz Rodríguez · primera medición 2026-08-30 · **segunda ronda 2026-09-07**

Medición del rendimiento real (**RMAX**) de una máquina con HPL 2.3, y comparación
contra su rendimiento teórico (**RPEAK**).

> **Sobre las dos rondas.** La primera versión reportaba 106,24 GFLOPS y una eficiencia
> del 30,2 %. La segunda ronda encontró que **la forma de medir tenía sesgos** —las
> primeras corridas de cada sesión salen bajas, y el orden dentro de un barrido se
> confundía con el parámetro barrido— y que **el denominador estaba mal elegido**: se
> usaba una frecuencia de catálogo en vez de la que el procesador sostiene de verdad.
> Corregido todo, el resultado es **132,5 GFLOPS y 47,7 % de eficiencia**. Los números
> de la primera ronda se conservan al final, porque el contraste entre las dos es buena
> parte de lo que este trabajo enseña.
>
> Los experimentos 7 a 9 son del cierre de esa misma jornada y **no mueven el resultado**:
> son tres limitaciones que la propia segunda ronda había declarado y que resultaron
> verificables en una tarde —el binding, el techo de N y la causa del castigo en frío—.
> Las tres salieron en contra de lo que el informe suponía.

## Resultado

| | |
|---|---|
| **RMAX medido** | **132,5 GFLOPS** |
| RPEAK a frecuencia sostenida **medida** | 277,5 GFLOPS |
| **Eficiencia (RMAX ÷ RPEAK medido)** | **47,7 %** |
| Frecuencia sostenida durante el cálculo | P-cores 2,29 GHz · E-cores 3,19 GHz |
| Configuración | N = 30.000 · NB = 192 · grilla 3×4 · 12 procesos · Intel MKL |
| Tiempo | 143,8 s |
| Validación | `PASSED` |

Contra los otros dos denominadores posibles, la misma corrida da 37,6 % (frecuencia
turbo de catálogo) y 133,5 % (frecuencia base). Por qué el correcto es el medido está
explicado en [El problema del RPEAK](#el-problema-del-rpeak-en-una-cpu-híbrida).

La eficiencia se descompone en dos factores, los dos medidos en la misma sesión:

```
dgemm alcanza el 80 % del RPEAK   ×   HPL alcanza el 59 % de dgemm   =   47,7 %
```

Salida completa en [`resultados/frecuencia/ab_nb192_par1/corrida.txt`](resultados/frecuencia/ab_nb192_par1/corrida.txt)
y muestreo de frecuencia segundo a segundo en [`muestras.csv`](resultados/frecuencia/ab_nb192_par1/muestras.csv).

## Cómo se mide, y por qué la primera ronda medía mal

Antes de comparar nada hay que saber cuánto vale una medición. La primera ronda no lo
verificó, y eso contaminó dos de sus cuatro conclusiones.

**Las dos primeras corridas de cada sesión salen bajas.** Ocho corridas idénticas, mismo
binario y misma configuración:

| corrida | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| GFLOPS | 102,2 | 118,0 | 116,4 | 116,2 | 118,3 | 115,2 | 118,4 | 119,6 |

Descartando la primera, las siete restantes dan **117,5 ± 1,5 GFLOPS**, o sea ±1,3 %.
Incluyéndola, la dispersión se dispara al 14,6 %. La rampa es de tres corridas —85,5 →
102,2 → 117— y va **hacia arriba**, que es lo contrario del *throttling*: es la máquina
saliendo de reposo y WSL2 tocando por primera vez las páginas de la matriz.

**Entre sesiones la variación es enorme y no está explicada.** El mismo binario, la
misma configuración (N = 16.000, NB = 192) y el portátil enchufado las dos veces:
**82,5 GFLOPS en una sesión y 129,1 en otra, un 56 % de diferencia.** Se verificó
leyendo los encabezados que el propio HPL imprime que las configuraciones eran
idénticas hasta el último parámetro, y se descartó presión de memoria del sistema
anfitrión. La sospecha inicial fue saturación térmica del disipador —la sesión lenta
arrancó inmediatamente después del banco de `dgemm`, la rápida tras un rato de reposo—,
pero el [experimento 9](#9-qué-explica-el-reloj-y-qué-no) la debilita: en el caso análogo
medido dentro de una sesión, la corrida castigada sostuvo **más** frecuencia que la buena.
El fenómeno existe y está cuantificado; su causa sigue abierta.

De ahí salen las tres reglas que sigue esta segunda ronda:

1. **Descartar dos corridas de calentamiento** y repetir al menos tres.
2. **Comparar solo dentro de la misma sesión**, alternando las configuraciones en vez
   de correr todas las de A y después todas las de B. Cuando son dos, el orden va
   A-B-B-A y no A-B-A-B, para que cada una corra una vez temprano y una vez tarde.
3. **Rotar el orden** cuando se barre un parámetro, para que la posición dentro de la
   tanda no quede correlacionada con el valor probado.

La tercera nació de un error cometido en esta misma ronda, documentado en el
[experimento 4](#4-nb-sí-importa-pero-un-14--y-el-óptimo-depende-de-n).

## Entorno

**Hardware.** Intel Core i5-1235U (12ª gen, Alder Lake), **arquitectura híbrida**:
2 P-cores (Golden Cove) + 8 E-cores (Gracemont), 10 cores y 12 hilos, TDP 15 W.
Soporta AVX2 y FMA; **no soporta AVX-512** (Intel lo deshabilitó en esta generación
porque los E-cores no lo implementan). 15,6 GiB de RAM.

**Windows ve la topología real —10 cores, 12 hilos— y WSL2 no.** Adentro de Linux,
`lscpu` reporta 6 cores uniformes de 2 hilos cada uno, que es falso: los E-cores no
tienen *hyperthreading*. Es una topología sintética que arma Hyper-V, y tiene una
consecuencia práctica: **desde WSL2 no se puede fijar un proceso a un core físico**,
porque los números de CPU que ve Linux no corresponden a nada estable.

**Software.**

| Componente | Versión |
|---|---|
| Sistema | Windows 11 + WSL2 (Ubuntu 24.04.3), 12 GB asignados vía `.wslconfig` |
| Compilador | gcc 13.3.0, con `-O3 -march=native` |
| Librería matemática | OpenBLAS 0.3.26 **y** Intel oneAPI MKL 2026.1 |
| MPI | OpenMPI 4.1.6 |
| Benchmark | HPL 2.3 (netlib, 2 dic. 2018) |

La memoria de WSL2 se subió de los 7,8 GB por defecto (la mitad del equipo) a 12 GB, con
`swap=0` para que una corrida que no quepa falle en vez de arrastrarse usando disco. Eso
permite pasar de N ≈ 26.000 a N = 30.000. En HPL el N grande importa porque el trabajo
útil crece como N³ mientras el sobrecosto —factorizar el panel, pivotear, comunicar—
crece como N²·NB: cuanto mayor es N, menor es la fracción desperdiciada.

## Reproducir

```bash
# 1. Dependencias
sudo apt update && sudo apt install -y build-essential gfortran \
     libopenmpi-dev openmpi-bin libopenblas-dev

# 2. Intel MKL
wget -qO- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
  | gpg --dearmor | sudo tee /usr/share/keyrings/oneapi-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
  | sudo tee /etc/apt/sources.list.d/oneAPI.list
sudo apt update && sudo apt install -y intel-oneapi-mkl-devel

# 3. Fuente de HPL (no versionada en este repo)
wget https://www.netlib.org/benchmark/hpl/hpl-2.3.tar.gz && tar -xzf hpl-2.3.tar.gz

# 4. Build contra OpenBLAS
cd hpl-2.3 && ./configure CC=mpicc CFLAGS="-O3 -march=native" LIBS="-lopenblas" && make -j$(nproc)

# 5. Build contra MKL (crea hpl-mkl/ aparte, sin tocar el anterior)
./scripts/03_compilar_con_mkl.sh
```

**El `configure` de HPL no sirve para escoger la librería.** Su detección de BLAS está
fija en el código, encuentra OpenBLAS y descarta cualquier `LIBS` que uno le pase — el
log lo dice literal: `checking for dgemm_ in OpenBLAS... yes`. Por eso el build de MKL
usa la vía clásica de HPL, un `Make.mkl` que declara la librería a mano. Y por eso el
script **verifica el binario después de compilar**: `ldd` no debe mostrar OpenBLAS y
`nm` debe encontrar símbolos de MKL. Sin esa verificación, el primer intento produjo un
binario que decía ser de MKL, estaba enlazado contra OpenBLAS, y midió durante ocho
corridas sin que nada lo delatara.

La corrida definitiva, con muestreo de frecuencia (desde **PowerShell**, no desde WSL2):

```powershell
.\scripts\05_medir_frecuencia.ps1 -N 30000 -NB 192 -Build hpl-mkl -Etiqueta definitiva
```

## El problema del RPEAK en una CPU híbrida

La fórmula del curso es `nodos × sockets × cores × frecuencia × FLOP/ciclo`, y **asume
que todos los cores son idénticos**. Este procesador rompe ese supuesto, así que hay que
calcular dos poblaciones y sumarlas.

El `FLOP/ciclo` tampoco es solo el ancho del vector. Son tres factores: el vector AVX2 de
256 bits carga 4 números de doble precisión (×4), la instrucción FMA hace multiplicación
y suma en una sola operación (×2), y cada core tiene varias unidades FMA (×2). Los
E-cores dan la mitad porque sus unidades son de 128 bits.

| | Cores | FLOP/ciclo | Base | Turbo | **Sostenida (medida)** |
|---|---|---|---|---|---|
| P-cores | 2 | 4 × 2 × 2 = 16 | 1,3 GHz | 4,4 GHz | **2,29 GHz** |
| E-cores | 8 | 2 × 2 × 2 = 8 | 0,9 GHz | 3,3 GHz | **3,19 GHz** |

```
A frecuencia base:       2×16×1,3  + 8×8×0,9   =  99,2 GFLOPS
A turbo máximo:          2×16×4,4  + 8×8×3,3   = 352,0 GFLOPS
A frecuencia sostenida:  2×16×2,29 + 8×8×3,19  = 277,5 GFLOPS
```

### La frecuencia sostenida hay que medirla, no inferirla

La primera ronda **dedujo** una frecuencia efectiva de ~1,4 GHz invirtiendo la fórmula
desde los GFLOPS medidos. Esa inversión supone que HPL rinde a cierto porcentaje del
techo, que es justo lo que el experimento debería averiguar: usarla es circular.

Medida de verdad, la frecuencia es más del doble de esa estimación. Se muestrea desde
Windows mientras HPL corre dentro de WSL2, porque **adentro de WSL2 no hay acceso a los
contadores del procesador** —no hay MSR y `turbostat` no funciona—. Se usa la clase WMI
`Win32_PerfFormattedData_Counters_ProcessorInformation`, que reporta por hilo lógico el
porcentaje sobre la frecuencia nominal de 1,3 GHz.

**Hallazgo inesperado: los E-cores sostienen más frecuencia que los P-cores** — 3,19
contra 2,29 GHz. Ninguna hoja de datos lo dice y es al revés de lo que sugieren sus
turbos nominales (3,3 contra 4,4 GHz). La explicación es de presupuesto de potencia:
bajo carga vectorial continua un P-core consume mucho más que un E-core, así que cuando
los diez calculan a la vez, el chip le recorta la frecuencia sobre todo al que más gasta.

### Por qué este es el denominador correcto

| Denominador | RPEAK | Eficiencia | Veredicto |
|---|---|---|---|
| Frecuencia base | 99,2 | 133,5 % | Inválido: es imposible superar el techo teórico |
| Frecuencia turbo | 352,0 | 37,6 % | Inalcanzable: el chip nunca sostiene el turbo en 10 cores |
| **Frecuencia medida** | **277,5** | **47,7 %** | El único físicamente alcanzable |

El 133,5 % no es una eficiencia: es la prueba de que ese denominador está mal. Y el turbo
tampoco sirve, por la razón simétrica — un techo que el hardware no puede tocar no mide
qué tan bien se aprovechó el hardware, mide qué tan optimista era el catálogo. La
validación de que 277,5 sí es alcanzable está en el
[experimento 3](#3-el-techo-real-de-la-máquina-son-223-gflops).

## Experimentos

### 1. La librería no es el cuello de botella

HPL se pasa el ~90 % del tiempo dentro de `dgemm`, que no la trae HPL sino la librería
BLAS. Comparar OpenBLAS contra Intel MKL —escrita por Intel para este mismo procesador—
debería ser la palanca grande. Seis pares alternados dentro de la misma sesión,
N = 10.000:

| par | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| OpenBLAS | 116,7 | 117,3 | 117,9 | 87,5 | 109,0 | 110,2 |
| MKL | 120,8 | 122,5 | 101,0 | 106,0 | 110,8 | 116,8 |

Diferencia media **+3,2 ± 4,7 GFLOPS: empate estadístico.** Los pares 3 y 4 son derrumbes
de una sola corrida, uno de cada lado; quitándolos MKL ganaría +4,4 ± 1,0, que sí sería
significativo — pero descartar los datos que estorban después de verlos no es un método
válido, así que lo que se reporta es el empate. En `dgemm` puro, con menos ruido
alrededor, MKL gana un 2 % consistente, y por eso se usa en la corrida definitiva.

Lo importante no es ese 2 %, es lo que implica: **cuando dos implementaciones tan
distintas de `dgemm` aterrizan en el mismo número, el límite no está en la librería.**

### 2. Cuánto se pierde por repartir mal el trabajo

Los 12 hilos se pueden repartir entre procesos MPI (que se comunican por mensajes) e
hilos de BLAS (que comparten memoria). La hipótesis original era que en una sola máquina
la memoria compartida ganaría. Salió al revés:

| ranks × hilos | 12 × 1 | 6 × 2 | 4 × 3 | 2 × 6 | 1 × 12 |
|---|---|---|---|---|---|
| GFLOPS | 116,8 | 119,7 | 91,1 | 68,8 | 51,6 |

La primera ronda lo explicó por la ley de Amdahl: con un solo proceso, lo único paralelo
son las llamadas a `dgemm` y el resto de HPL —factorización del panel, pivoteo,
difusión— queda en un hilo. **Esa explicación es correcta pero incompleta**, y el
experimento 3 lo demuestra: la misma caída aparece en `dgemm` puro, que no tiene ninguna
parte serial. La causa adicional es que **el BLAS con hilos no reparte bien entre cores
heterogéneos**: parte el trabajo en pedazos iguales entre cores que no rinden igual, y
cada ronda termina cuando acaba el más lento.

### 3. El techo real de la máquina son 223 GFLOPS

Para saber si los 277,5 GFLOPS de RPEAK son alcanzables se mide `dgemm` solo, sin HPL
alrededor: sin MPI, sin factorización, sin comunicación. Es el techo práctico.

| librería | reparto | GFLOPS | % del RPEAK |
|---|---|---|---|
| OpenBLAS | 1 proceso × 12 hilos | 161,8 | 58,3 % |
| OpenBLAS | 12 procesos × 1 hilo | 218,3 | 78,7 % |
| MKL | 1 proceso × 12 hilos | 122,1 | 44,0 % |
| **MKL** | **12 procesos × 1 hilo** | **222,9** | **80,3 %** |

Tres lecturas. **El RPEAK medido es real**: `dgemm` alcanza el 80 % de él, que es lo
normal para una multiplicación de matrices bien hecha; si esos 277,5 fueran un número
inventado por los contadores, no habría podido acercarse tanto. **MKL con hilos es un
25 % peor que OpenBLAS**, lo que confirma que su repartidor asume cores homogéneos. Y **el
reparto en procesos le gana al reparto en hilos incluso sin parte serial de por medio**,
que es la corrección al experimento 2.

Lo decisivo es el contraste: la máquina entrega 223 GFLOPS multiplicando matrices y HPL
saca 132,5. **HPL captura el 59 % de lo que su propia librería puede dar.** Lo que se
pierde no es silicio, es estructura: paneles de 192 columnas en vez de matrices grandes
y cuadradas, factorización que no se paraleliza, y comunicación entre doce procesos que
comparten un bus de memoria de portátil.

Este banco se corrió dos veces, en sesiones distintas, y dio 210,9 y 222,9 GFLOPS: un
6 % de diferencia. En esas mismas dos sesiones HPL varió un 27 %. **Lo que degrada una
sesión mala no toca el cálculo puro**, sino todo lo que HPL hace alrededor.

### 4. NB sí importa, pero un 14 %, y el óptimo depende de N

La primera ronda reportó que elegir mal el NB cuesta un **56 % de rendimiento**:

| NB | 128 | 160 | 192 | 224 | 256 |
|---|---|---|---|---|---|
| GFLOPS | 92,2 | 121,4 | 100,0 | 83,1 | 77,9 |

**Ese 56 % era un artefacto**, porque aquel barrido corría un NB tras otro, una sola vez
cada uno y sin calentamiento: el primero se midió en frío y los últimos en caliente.

El barrido nuevo lo confirmó de la peor manera posible: **reprodujo el artefacto**. Se
midió por rondas, pero dejando el mismo orden dentro de cada una, con lo cual la posición
volvió a quedar correlacionada con el valor probado. La ronda 1, con la máquina todavía
subiendo de temperatura, produjo otra curva descendente perfecta (110,4 → 69,9) que
desapareció por completo en las rondas 2 y 3.

Repetido con **el orden rotado en cada ronda**, y con la máquina en buen estado:

| NB | 128 | **160** | 192 | 224 | 256 | 320 | 384 |
|---|---|---|---|---|---|---|---|
| GFLOPS (media de 3) | 110,2 | **125,7** | 122,3 | 114,0 | 112,8 | 110,4 | 112,5 |

Las tres corridas de NB = 160 quedan por encima de **todas** las de 224, 256, 320 y 384:
separación limpia. **El efecto real es del 14 %, no del 56 %** — y el óptimo es 160, que
es exactamente el que la primera ronda había elegido. La conclusión de fondo era
correcta; lo inflado era la magnitud.

**Pero el óptimo depende de N.** A N = 30.000, cuatro corridas alternadas en orden
A-B-B-A dan lo contrario:

| | corrida 1 | corrida 2 | media |
|---|---|---|---|
| NB = 160 | 127,2 | 123,2 | 125,2 |
| **NB = 192** | **132,5** | **129,1** | **130,8** |

La peor corrida de NB = 192 supera a la mejor de NB = 160: separación completa, +4,5 % a
favor del 192. Con la matriz grande y bloques más angostos, HPL hace 187 iteraciones de
panel en vez de 156, y cada una trae su ronda de comunicación. **El NB hay que afinarlo
al N con el que se va a reportar**, no a uno más chico y cómodo.

### 5. Rejilla, número de procesos y difusión: nada mueve la aguja

Siete configuraciones, tres rondas con el orden rotado, N = 16.000 y NB = 192:

| config | media | vs base |
|---|---|---|
| base (12 proc, 3×4, BCAST=1) | 127,6 | — |
| rejilla 2×6 | 129,7 | +1,6 % |
| rejilla 4×3 | 120,8 | −5,3 % |
| 10 procesos (2×5) | 124,0 | −2,8 % |
| 8 procesos (2×4) | 118,7 | −7,0 % |
| BCAST = 2 | 125,7 | −1,5 % |
| BCAST = 3 | 116,1 | −9,0 % |

**El hyperthreading no era el problema**: con 10 procesos en vez de 12 el resultado
empata o es levemente peor. Esa hipótesis venía abierta desde el principio y queda
descartada. **Usar menos hilos sí cuesta** —con 8 procesos las tres corridas quedan por
debajo de las tres de la base, sin solaparse—, lo que dice que la máquina no está
puramente limitada por memoria: si lo estuviera, dejar cuatro hilos quietos no se
notaría. **La rejilla 4×3 es peor de verdad**, lo que confirma la regla de HPL de que P
debe ser menor o igual que Q: la factorización del panel baja por una columna de P
procesos, así que una rejilla alta mete más gente en la parte que peor se paraleliza. Y
**la difusión no importa**, como era de esperarse: `BCAST` existe para redes, y aquí los
mensajes viajan por memoria compartida.

Ninguna palanca superó el ruido salvo para empeorar. La configuración que ya se usaba
estaba bien elegida.

### 6. La degradación térmica, medida

El mismo NB = 128 a lo largo de una sesión de quince minutos: **110,4 → 90,2 → 83,1
GFLOPS**, una caída del 25 % con configuración idéntica. Eso explica la anomalía que la
primera ronda solo pudo conjeturar —la corrida de N = 26.880 rindió menos que la de
N = 10.000— y ahora está medida en vez de supuesta.

Y hay un efecto **más grande que la degradación dentro de una sesión: la diferencia entre
sesiones.** El mismo punto (N = 16.000, NB = 192) dio 82,5 GFLOPS en una y 129,1 en otra,
las dos enchufadas y con configuraciones verificadas como idénticas. **Ese 56 % no tiene
explicación comprobada** y es, con diferencia, la mayor fuente de variación de todo el
trabajo: más que NB, más que la librería, más que cualquier parámetro de `HPL.dat`.

Consecuencia práctica: **la sensibilidad al ajuste depende de que la máquina tenga
margen.** En la sesión lenta, el barrido de NB no mostraba ninguna tendencia; en la
rápida, la tendencia es nítida. Cuando el chip está topado, todas las configuraciones se
aplastan contra el mismo techo y afinar no sirve de nada.

### 7. El binding no estaba puesto, y ponerlo no sirve

Este informe listaba el *pinning* como la principal palanca sin probar, dándola por
imposible en WSL2. La afirmación mezclaba dos cosas: fijar un proceso a un **core
físico** sí es imposible, porque la topología que ve Linux es sintética, pero fijarlo a
un **hilo lógico** no lo es, y es lo que evita que el planificador mueva los ranks y les
tire la caché.

Resultó que no había ningún binding. Todas las mediciones anteriores usaron
`mpirun --use-hwthread-cpus -np 12` sin `--bind-to`, y en OpenMPI 4.1 el binding por
defecto con más de dos procesos es al socket; como este equipo tiene uno solo, eso
equivale a no fijar nada. `--report-bindings` lo dice textual para los doce ranks:
`MCW rank N is not bound (or bound to all available processors)`.

Tres políticas, tres rondas con el orden rotado, N = 16.000 y NB = 192:

| política | ronda 1 | ronda 2 | ronda 3 | media |
|---|---|---|---|---|
| defecto (lo que se venía usando) | 119,4 | 119,7 | 124,6 | **121,2** |
| `--bind-to hwthread --map-by hwthread` | 118,9 | 119,7 | 106,0 | 114,9 |
| `--bind-to none` (control) | 119,9 | 123,9 | 119,3 | **121,0** |

**El defecto y el control son el mismo número**, que es la confirmación medida de que el
defecto no fijaba nada. Fijar a hilo lógico no gana: sus dos corridas buenas caen dentro
del rango de la base, y su media baja solo por el derrumbe de 106,0 — que no se descarta,
por la misma razón que no se descartaron los pares 3 y 4 del experimento 1.

La explicación de por qué no ayuda es que **no hay a dónde migrar**. El *pinning* paga
cuando el planificador tiene libertad para mover procesos, y aquí hay doce ranks sobre
doce hilos lógicos: la máquina está completamente suscrita y el planificador no tiene
opción, esté o no declarado el binding. En una corrida con menos ranks que hilos, o
compartiendo la máquina con otra carga, el resultado sería otro.

### 8. N no se puede subir: manda el presupuesto térmico

Con 11 GiB disponibles en WSL2 y una matriz de N = 30.000 que ocupa 6,7 GiB, la regla
estándar de HPL —llenar el 80 % de la memoria— apunta a N ≈ 34.000. Se probó, y es una
regresión: **76,9 GFLOPS, 30,3 % de eficiencia**, un 42 % por debajo de N = 30.000. La
corrida tardó 340,6 s cuando la aritmética predecía 198.

La frecuencia sostenida, por quintos de corrida, explica la diferencia:

| tramo | N = 30.000 (135,9 s) | N = 34.000 (340,6 s) |
|---|---|---|
| 1/5 | 2698 / 3611 MHz | 2672 / 3550 MHz |
| 2/5 | 2293 / 3235 | 2229 / 3165 |
| 3/5 | 2183 / 3088 | 1951 / 2889 |
| 4/5 | 2193 / 3079 | 1740 / 2669 |
| 5/5 | **2235 / 3125** | **1687 / 2542** |

Las dos arrancan en turbo y caen igual durante el primer tercio. La diferencia es el
final: **la corrida corta encuentra un equilibrio térmico —2200/3100 MHz— y lo sostiene;
la larga nunca se estabiliza** y termina un 37 % por debajo de donde empezó, todavía en
caída a los 340 s.

Este paquete de 15 W tiene, entonces, un presupuesto de unos dos minutos y medio de
rendimiento sostenible. **Existe un N óptimo, está donde la duración de la corrida
coincide con ese presupuesto, y es ≈ 30.000** — el que ya se estaba usando, que resulta
ser una elección afortunada y no un cálculo.

Esto falsifica una limitación que este mismo informe declaraba: el techo de N no lo ponía
la memoria de WSL2. Y le pone un asterisco al argumento con el que se justificó subir la
memoria en primer lugar — que en HPL el trabajo útil crece como N³ sobre un sobrecosto de
N²·NB, así que conviene el N más grande posible. **Ese razonamiento supone que la máquina
rinde igual todo el tiempo.** En un portátil limitado por temperatura, agrandar N no es
correr el mismo problema más grande: es correrlo en una máquina más lenta.

### 9. Qué explica el reloj y qué no

Con el muestreo de frecuencia se puede calcular, para cada corrida, su eficiencia contra
**su propio** RPEAK — el que corresponde a la frecuencia que esa corrida sostuvo:

| corrida | N · NB | P / E (MHz) | RPEAK propio | GFLOPS | eficiencia |
|---|---|---|---|---|---|
| `ab_nb192_par1` | 30.000 · 192 | 2285 / 3194 | 277,5 | 132,5 | **47,7 %** |
| `ab_nb192_par2` | 30.000 · 192 | 2253 / 3173 | 275,2 | 129,1 | 46,9 % |
| `ab_nb160_par1` | 30.000 · 160 | 2304 / 3217 | 279,6 | 127,2 | 45,5 % |
| `ab_nb160_par2` | 30.000 · 160 | 2310 / 3226 | 280,4 | 123,2 | 43,9 % |
| `definitiva` | 30.000 · 192 | 2087 / 3031 | 260,8 | 104,0 | 39,9 % |
| `definitiva_nb160` | 30.000 · 160 | **2339 / 3235** | 281,9 | 96,9 | **34,4 %** |
| `n34000_prueba` | 34.000 · 192 | 2042 / 2950 | 254,1 | 76,9 | 30,3 % |

Hay dos regímenes distintos y hasta ahora se venían confundiendo. En `definitiva` el
reloj sí se cayó —2087/3031, el más bajo del grupo— y su RPEAK propio baja a 260,8: ahí
la frecuencia explica parte de la pérdida.

**`definitiva_nb160` es el caso que decide.** Sostuvo la frecuencia más alta de todas las
corridas de N = 30.000 y entregó la eficiencia más baja. Y es idéntica en configuración a
`ab_nb160_par1` —mismo binario de MKL, mismo `HPL.dat`, cinco minutos de diferencia
dentro de la misma sesión—, que alcanzó 45,5 %. **Mismo reloj, 31 % menos de trabajo
útil.**

`definitiva_nb160` era la primera corrida de esa tanda, o sea la única en frío. Así que
el castigo de arranque documentado en [Cómo se mide](#cómo-se-mide-y-por-qué-la-primera-ronda-medía-mal)
**no es térmico ni de frecuencia**: el procesador estaba a pleno reloj sostenido y aun
así rendía un tercio menos. Es lo que allí se conjeturaba —WSL2 tocando por primera vez
las páginas de la matriz— y ahora la frecuencia queda controlada como variable en vez de
supuesta.

También se descartaron las causas de configuración para la variación entre sesiones. El
plan activo es `HP Optimized (Modern Standby)` con `PROCTHROTTLEMAX` al 100 % tanto en
corriente alterna como en batería, y las claves `ActiveOverlayAcPowerScheme` y
`ActiveOverlayDcPowerScheme` del registro están vacías, lo que significa que **el
selector de modo de energía de Windows 11 nunca se movió**. Ni el plan ni el modo
difirieron entre la sesión lenta y la rápida.

## Conclusiones

1. **El RPEAK teórico no aplica a hardware híbrido con frecuencia variable, y la solución
   es medir.** La fórmula del curso funciona en un nodo de APOLO y se rompe en un portátil
   por dos motivos independientes: cores heterogéneos y frecuencia que cambia con la
   temperatura. La salida no es escoger entre el turbo y la base —los dos dan números
   absurdos, 37,6 % y 133,5 %— sino muestrear la frecuencia real durante la misma corrida
   que se está midiendo.

2. **Los E-cores sostienen más frecuencia que los P-cores bajo carga vectorial continua**
   (3,19 contra 2,29 GHz), al revés de lo que sugieren sus turbos de catálogo. Es una
   consecuencia del presupuesto de potencia de 15 W, y no aparece en ninguna
   especificación.

3. **La eficiencia del 47,7 % se descompone en dos factores medidos, y ninguno es la
   librería.** `dgemm` alcanza el 80 % del RPEAK, y HPL captura el 59 % de `dgemm`. El
   primero es el techo físico de la máquina; el segundo es el costo estructural de HPL
   —comunicación entre doce procesos, factorización serial del panel, y reparto
   igualitario entre cores que no son iguales—.

4. **Casi toda la mejora vino de medir mejor, no de afinar.** De 30,2 % a 47,7 %: el
   grueso salió de cambiar el denominador por uno alcanzable y de medir en una sesión sin
   degradar. Los parámetros aportaron poco — NB vale un 14 % y hay que afinarlo al N
   final, y la rejilla, la difusión y el número de procesos no aportaron nada. Para llegar
   al 60 % HPL tendría que capturar el 75 % de `dgemm` en vez del 59 %, y eso se consigue
   con cores homogéneos, memoria de servidor y presupuesto térmico. **Este trabajo no
   muestra cómo afinar un portátil; muestra por qué existen los clústeres.**

5. **Medir mal produce hallazgos falsos que se ven perfectamente creíbles.** El "NB vale
   un 56 %" era una curva limpia, monótona y con explicación física plausible, y era un
   artefacto del orden de las corridas. Se reprodujo el mismo error a propósito en el
   barrido nuevo y volvió a salir igual de convincente. Antes de comparar configuraciones
   hay que cuantificar el error de la propia medición — y luego diseñar el experimento
   para que el orden no se confunda con el parámetro.

6. **En una máquina limitada por temperatura, el tamaño del problema tiene un óptimo, y
   no está en el máximo que quepa en memoria.** La regla estándar de HPL —llenar el 80 %
   de la RAM— supone rendimiento constante y aquí falla: pasado el presupuesto térmico de
   unos dos minutos y medio, la frecuencia deja de estabilizarse y se pierde más en reloj
   de lo que se gana en aritmética. El óptimo está donde la duración de la corrida iguala
   ese presupuesto. Es la misma lección de la conclusión 1 aplicada a otro parámetro: las
   reglas del HPC de servidor suponen una máquina que sostiene su rendimiento, y esa
   suposición es exactamente la que un portátil rompe.

7. **Tres de las cuatro limitaciones que declaraba la segunda ronda resultaron
   falsables en una tarde, y ninguna en la dirección esperada.** El *pinning* no estaba
   sin probar por imposible: no estaba puesto, y ponerlo no cambia nada. El techo de N no
   lo ponía la memoria sino el calor. Y el castigo de la corrida en frío, que se atribuía
   a temperatura, ocurre a pleno reloj. **Declarar una limitación es barato y verificarla
   sale más barato todavía**; el costo de no hacerlo es que una conjetura razonable se
   queda en el informe pareciendo un resultado.

## Limitaciones

- **Sigue sin explicarse el 56 % de variación entre sesiones**, aunque el
  [experimento 9](#9-qué-explica-el-reloj-y-qué-no) estrechó bastante el campo: quedan
  descartados el plan de energía, el modo de energía de Windows y —para el caso análogo
  medido dentro de una sesión— la frecuencia misma. La hipótesis viva ya no es térmica
  sino la ruta de memoria de WSL2, pero **no está probada para el caso entre sesiones**,
  porque aquellas dos tandas se corrieron desde bash y no llevan muestreo de frecuencia.
  Repetirlas con `05_medir_frecuencia.ps1` es el experimento que falta.
- **El resultado negativo del binding puede no transferirse.** Se midió con doce ranks
  sobre doce hilos lógicos, es decir con la máquina completamente suscrita y sin margen
  para que el planificador migre nada. Con menos ranks que hilos, o compartiendo la
  máquina, el binding podría importar. Y fijar a un **core físico** sigue siendo
  imposible desde WSL2 por la topología sintética, así que eso queda sin probar de verdad.
- La medición de frecuencia por WMI da los E-cores en 3,19 GHz sostenidos, cerca de su
  turbo nominal de 3,3; en una corrida corta marcó 3,40, por encima del máximo de
  catálogo. El método tiene por lo menos un pequeño error por exceso, aunque el
  experimento 3 confirma que el orden de magnitud es correcto.
- El valor de 8 FLOP/ciclo de los E-cores proviene de la documentación de Gracemont y no
  se verificó de forma independiente.
- **El N óptimo se acotó con dos puntos, no con un barrido.** El
  [experimento 8](#8-n-no-se-puede-subir-manda-el-presupuesto-térmico) muestra que 34.000
  es peor que 30.000 y explica por qué, pero entre ambos no se midió nada: el máximo real
  podría estar en 31.000 o en 32.000. Barrerlo cuesta unos veinte minutos por punto y no
  se hizo por tiempo. Lo que sí queda establecido es la dirección —el techo es térmico y
  no de memoria—, que es lo que cambia la interpretación.
- Todas las mediciones son de una sola máquina, sin acceso a APOLO.

## Estructura

```
├── resultados/
│   ├── HPL.dat.final          # configuración de la corrida de la primera ronda
│   ├── salida_final.txt       # salida completa de HPL (primera ronda)
│   ├── puntaje.png            # captura del resultado de la primera ronda
│   ├── repetibilidad/         # las dos sesiones que dieron el protocolo de medición
│   ├── comparacion_mkl/       # pares alternados OpenBLAS vs MKL
│   ├── dgemm/                 # banco del techo de la máquina
│   ├── barrido_nb/            # sesión lenta y sesión rápida
│   ├── barrido_rejilla/       # rejilla, número de procesos y difusión
│   ├── binding/               # las tres políticas, con el mapa que imprime OpenMPI
│   └── frecuencia/            # muestreo de frecuencia, corridas definitivas y N=34.000
├── scripts/
│   ├── 00_recon.sh                 # reconocimiento de hardware (pensado para APOLO)
│   ├── 01_barrido_hibrido.sh       # barrido MPI × OpenMP
│   ├── 02_repetibilidad.sh         # cuánto vale una medición
│   ├── 03_compilar_con_mkl.sh      # segundo build, contra Intel MKL
│   ├── 04_comparar_openblas_mkl.sh # comparación alternada A-B
│   ├── 05_medir_frecuencia.ps1     # frecuencia sostenida (PowerShell)
│   ├── 06_banco_dgemm.sh           # techo práctico de la máquina
│   ├── 07_barrido_nb.sh            # barrido de NB por rondas rotadas
│   ├── 08_barrido_rejilla.sh       # rejilla, procesos y difusión
│   ├── 09_definitiva_ab.ps1        # NB=160 vs NB=192 a N=30.000, en A-B-B-A
│   ├── 10_binding.sh               # defecto vs hwthread vs none, por rondas rotadas
│   └── dgemm.c                     # el banco de dgemm
└── .gitignore                      # excluye fuentes de terceros y binarios
```

### Resultado de la primera ronda, para referencia

| | |
|---|---|
| RMAX | 106,24 GFLOPS |
| Configuración | N = 26.880 · NB = 160 · grilla 3×4 · 12 procesos · OpenBLAS |
| Tiempo | 121,89 s · `PASSED`, residual 1,93×10⁻³ |
| Eficiencia reportada entonces | 30,2 % (contra RPEAK turbo) |

![Salida de HPL de la primera ronda](resultados/puntaje.png)

Salida completa en [`resultados/salida_final.txt`](resultados/salida_final.txt),
configuración en [`resultados/HPL.dat.final`](resultados/HPL.dat.final).
