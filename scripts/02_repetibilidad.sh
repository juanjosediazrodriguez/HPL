#!/bin/bash
# Cuanto vale una medicion de HPL en este portatil.
#
# Motivo: tres corridas identicas (N=10000, NB=160, 12 ranks) dieron 53.3,
# 98.3 y 115.7 GFLOPS el 2026-09-07. Un factor de 2.2 entre la peor y la
# mejor. Con esa dispersion no se puede comparar ninguna configuracion
# contra otra, asi que primero hay que medir el error de la propia medida.
#
# Corre la misma configuracion muchas veces y reporta minimo, maximo,
# promedio y dispersion. Si la dispersion baja al enfriar mas o al dejar la
# maquina quieta, ya sabemos como hay que medir de aqui en adelante.
#
# NOTA SOBRE WSL2: la topologia que reporta es falsa. Dice 6 cores de 2 hilos
# uniformes; el i5-1235U tiene 2 P-cores con hyperthreading y 8 E-cores sin
# el (10 cores, 12 hilos). Los numeros de CPU son virtuales y Hyper-V los
# reubica cuando quiere, asi que aqui NO se puede fijar un proceso a un core
# fisico. Cualquier experimento de afinidad pide Linux nativo o APOLO.
#
# Uso:  ./02_repetibilidad.sh
#       RANKS=6 REPS=10 ENFRIAR=60 ./02_repetibilidad.sh

set -u
cd "$(dirname "$0")/../hpl-2.3/testing" || { echo "no encuentro hpl-2.3/testing/"; exit 1; }

N=${N:-10000}
NB=${NB:-160}
RANKS=${RANKS:-12}
REPS=${REPS:-8}
ENFRIAR=${ENFRIAR:-45}
# Corridas previas que no se cuentan. Medido el 2026-09-07: la maquina llega
# a su regimen estable en la tercera corrida (85.5 -> 102.2 -> 116-119 GFLOPS).
# Con dos de calentamiento la dispersion baja de 14.6% a ~4%.
CALENTAR=${CALENTAR:-2}

SALIDAS="../../resultados/repetibilidad"
mkdir -p "$SALIDAS"

# Grid mas cuadrado posible con P*Q = RANKS, y P <= Q.
P=1
for ((i = 1; i * i <= RANKS; i++)); do
  (( RANKS % i == 0 )) && P=$i
done
Q=$(( RANKS / P ))

cat > HPL.dat <<EOF
HPLinpack benchmark input file
Repetibilidad - generado por 02_repetibilidad.sh
HPL.out      output file name (if any)
6            device out (6=stdout,7=stderr,file)
1            # of problems sizes (N)
$N            Ns
1            # of NBs
$NB          NBs
0            PMAP process mapping (0=Row-,1=Column-major)
1            # of process grids (P x Q)
$P            Ps
$Q            Qs
16.0         threshold
1            # of panel fact
2            PFACTs (0=left, 1=Crout, 2=Right)
1            # of recursive stopping criterium
4            NBMINs (>= 1)
1            # of panels in recursion
2            NDIVs
1            # of recursive panel fact.
2            RFACTs (0=left, 1=Crout, 2=Right)
1            # of broadcast
1            BCASTs (0=1rg,1=1rM,2=2rg,3=2rM,4=Lng,5=LnM)
1            # of lookahead depth
1            DEPTHs (>=0)
2            SWAP (0=bin-exch,1=long,2=mix)
64           swapping threshold
0            L1 in (0=transposed,1=no-transposed) form
0            U  in (0=transposed,1=no-transposed) form
1            Equilibration (0=no,1=yes)
8            memory alignment in double (> 0)
EOF

correr() {  # $1 = nombre del log
  OMP_NUM_THREADS=1 mpirun --use-hwthread-cpus -np "$RANKS" ./xhpl > "$1" 2>&1
  awk '/^WR/ {print $NF}' "$1"
}

echo "N=$N  NB=$NB  ranks=$RANKS  grid=${P}x${Q}  reps=$REPS  enfriar=${ENFRIAR}s"
echo

for c in $(seq 1 "$CALENTAR"); do
  echo -n "calentamiento $c/$CALENTAR (no se cuenta)... "
  G=$(correr "$SALIDAS/calentamiento${c}.txt")
  echo "${G:-fallo}"
  sleep "$ENFRIAR"
done
[ "$CALENTAR" -gt 0 ] && echo

printf "%-5s %-12s %-10s\n" "rep" "GFLOPS" "residual"
printf "%.0s-" {1..30}; echo

DATOS=""
for rep in $(seq 1 "$REPS"); do
  LOG="$SALIDAS/rep${rep}.txt"
  G=$(correr "$LOG")
  if grep -q PASSED "$LOG"; then RES="PASSED"; else RES="FALLO"; fi

  if [ -n "$G" ]; then
    DATOS="$DATOS $G"
    printf "%-5s %-12.1f %-10s\n" "$rep" "$G" "$RES"
  else
    printf "%-5s %-12s %-10s\n" "$rep" "fallo" "$RES"
  fi

  [ "$rep" -lt "$REPS" ] && sleep "$ENFRIAR"
done

echo
echo "$DATOS" | awk '
{
  n = 0
  for (i = 1; i <= NF; i++) { v[++n] = $i + 0; s += $i }
  if (n == 0) { print "sin datos"; exit }
  min = max = v[1]
  for (i = 1; i <= n; i++) { if (v[i] < min) min = v[i]; if (v[i] > max) max = v[i] }
  prom = s / n
  for (i = 1; i <= n; i++) d += (v[i] - prom) ^ 2
  desv = (n > 1) ? sqrt(d / (n - 1)) : 0
  printf "corridas validas : %d\n", n
  printf "minimo           : %.1f GFLOPS\n", min
  printf "maximo           : %.1f GFLOPS\n", max
  printf "promedio         : %.1f GFLOPS\n", prom
  printf "desviacion       : %.1f GFLOPS  (%.1f%% del promedio)\n", desv, 100 * desv / prom
  printf "dispersion       : %.1f%%  ((max-min)/max)\n", 100 * (max - min) / max
}'

echo
echo "Salidas completas en resultados/repetibilidad/"
