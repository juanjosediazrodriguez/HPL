#!/bin/bash
# Barrido MPI x OpenMP para HPL en un solo nodo.
#
# La idea: los 12 hilos de la maquina se pueden repartir de varias formas
# entre procesos MPI (que se comunican con mensajes) e hilos de OpenBLAS
# (que se comunican leyendo la misma memoria). En una sola maquina la
# segunda via suele ser mas barata, pero hay que medirlo.
#
# Se usa N chico a proposito: cada corrida dura segundos y lo que interesa
# es comparar configuraciones entre si, no el numero absoluto.

set -u
cd "$(dirname "$0")/../hpl-2.3/testing" || { echo "no encuentro testing/"; exit 1; }

N=10000
NB=160

# formato -> ranks:hilos:P:Q   (ranks x hilos debe dar 12)
CONFIGS="12:1:3:4 6:2:2:3 4:3:2:2 2:6:1:2 1:12:1:1"

printf "%-6s %-8s %-6s %-12s\n" "ranks" "hilos" "PxQ" "GFLOPS"
printf "%.0s-" {1..40}; echo

for c in $CONFIGS; do
  R=${c%%:*}; resto=${c#*:}
  T=${resto%%:*}; resto=${resto#*:}
  P=${resto%%:*}
  Q=${resto##*:}

  cat > HPL.dat <<EOF
HPLinpack benchmark input file
Barrido hibrido - generado por 01_barrido_hibrido.sh
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

  G=$(OMP_NUM_THREADS=$T mpirun --use-hwthread-cpus -np "$R" ./xhpl 2>/dev/null \
      | awk '/^WR/ {print $(NF)}')

  printf "%-6s %-8s %-6s %-12s\n" "$R" "$T" "${P}x${Q}" "${G:-fallo}"
done

echo
echo "Referencia de la corrida anterior: 12 ranks x 1 hilo = 121.4 GFLOPS (sin enchufar)"
