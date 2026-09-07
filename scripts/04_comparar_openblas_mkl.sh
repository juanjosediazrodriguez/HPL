#!/bin/bash
# OpenBLAS contra Intel MKL, alternando las corridas dentro de la misma sesion.
#
# Por que alternadas: el 2026-09-07 el mismo binario dio 117.5 +/- 1.5 GFLOPS
# en una sesion y 111.0 +/- 7.7 en otra. Dentro de una tanda la maquina es
# estable; entre tandas se mueve un 6%. Corriendo A, B, A, B, ... esa deriva
# afecta a las dos por igual y se puede medir la diferencia par por par, que
# es lo que de verdad responde si la libreria cambio algo.
#
# Una sola variable cambia entre A y B: contra que BLAS quedo enlazado xhpl.
# N, NB, ranks, grid e hilos son identicos.
#
# Uso:  ./04_comparar_openblas_mkl.sh
#       PARES=10 ENFRIAR=60 ./04_comparar_openblas_mkl.sh

set -u
RAIZ=$(cd "$(dirname "$0")/.." && pwd)

N=${N:-10000}
NB=${NB:-160}
RANKS=${RANKS:-12}
PARES=${PARES:-6}
ENFRIAR=${ENFRIAR:-30}

A_DIR=hpl-2.3 ; A_NOM=openblas
B_DIR=hpl-mkl ; B_NOM=mkl

SALIDAS="$RAIZ/resultados/comparacion_mkl"
mkdir -p "$SALIDAS"

for d in "$A_DIR" "$B_DIR"; do
  [ -x "$RAIZ/$d/testing/xhpl" ] || { echo "Falta $d/testing/xhpl"; exit 1; }
done

# Grid mas cuadrado posible con P*Q = RANKS.
P=1
for ((i = 1; i * i <= RANKS; i++)); do
  (( RANKS % i == 0 )) && P=$i
done
Q=$(( RANKS / P ))

escribir_dat() {  # $1 = carpeta del build
  cat > "$RAIZ/$1/testing/HPL.dat" <<EOF
HPLinpack benchmark input file
Comparacion OpenBLAS vs MKL - generado por 04_comparar_openblas_mkl.sh
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
}

correr() {  # $1 = carpeta del build, $2 = archivo de log -> imprime GFLOPS
  ( cd "$RAIZ/$1/testing" \
    && OMP_NUM_THREADS=1 mpirun --use-hwthread-cpus -np "$RANKS" ./xhpl ) > "$2" 2>&1
  awk '/^WR/ {print $NF}' "$2"
}

escribir_dat "$A_DIR"
escribir_dat "$B_DIR"

echo "N=$N  NB=$NB  ranks=$RANKS  grid=${P}x${Q}  pares=$PARES  enfriar=${ENFRIAR}s"
echo

# Calentamiento: una de cada una, sin contar. La maquina llega a regimen
# estable en la tercera corrida (medido el 2026-09-07).
for d in "$A_DIR" "$B_DIR"; do
  echo -n "calentando $d (no se cuenta)... "
  G=$(correr "$d" "$SALIDAS/calentamiento_$d.txt")
  echo "${G:-fallo}"
  sleep "$ENFRIAR"
done
echo

printf "%-6s %-12s %-12s %-12s\n" "par" "$A_NOM" "$B_NOM" "dif"
printf "%.0s-" {1..46}; echo

PARESFILE=$(mktemp)
for par in $(seq 1 "$PARES"); do
  GA=$(correr "$A_DIR" "$SALIDAS/${A_NOM}_par${par}.txt"); sleep "$ENFRIAR"
  GB=$(correr "$B_DIR" "$SALIDAS/${B_NOM}_par${par}.txt")

  if [ -n "$GA" ] && [ -n "$GB" ]; then
    echo "$GA $GB" >> "$PARESFILE"
    printf "%-6s %-12.1f %-12.1f %+-12.1f\n" "$par" "$GA" "$GB" \
      "$(awk -v a="$GA" -v b="$GB" 'BEGIN{print b-a}')"
  else
    printf "%-6s %-12s %-12s %-12s\n" "$par" "${GA:-fallo}" "${GB:-fallo}" "-"
  fi

  [ "$par" -lt "$PARES" ] && sleep "$ENFRIAR"
done

echo
awk -v a_nom="$A_NOM" -v b_nom="$B_NOM" '
{ a[NR] = $1; b[NR] = $2; d[NR] = $2 - $1; sa += $1; sb += $2; sd += ($2 - $1) }
END {
  n = NR
  if (n == 0) { print "sin datos"; exit }
  ma = sa / n; mb = sb / n; md = sd / n
  for (i = 1; i <= n; i++) {
    va += (a[i] - ma) ^ 2; vb += (b[i] - mb) ^ 2; vd += (d[i] - md) ^ 2
  }
  sda = (n > 1) ? sqrt(va / (n - 1)) : 0
  sdb = (n > 1) ? sqrt(vb / (n - 1)) : 0
  sdd = (n > 1) ? sqrt(vd / (n - 1)) : 0
  err = (n > 1) ? sdd / sqrt(n) : 0

  printf "pares validos    : %d\n", n
  printf "%-16s : %.1f +/- %.1f GFLOPS\n", a_nom, ma, sda
  printf "%-16s : %.1f +/- %.1f GFLOPS\n", b_nom, mb, sdb
  printf "diferencia media : %+.1f GFLOPS  (%+.1f%%)\n", md, 100 * md / ma
  printf "error de la dif. : +/- %.1f GFLOPS\n", err
  print ""
  if (err > 0 && (md > 2 * err || md < -2 * err))
    printf "VEREDICTO: diferencia real. %s gana por %+.1f%%\n", (md > 0 ? b_nom : a_nom), 100 * (md > 0 ? md : -md) / ma
  else
    printf "VEREDICTO: empate. La diferencia cabe dentro del error de la medicion.\n"
}' "$PARESFILE"

rm -f "$PARESFILE"
echo
echo "Salidas completas en resultados/comparacion_mkl/"
