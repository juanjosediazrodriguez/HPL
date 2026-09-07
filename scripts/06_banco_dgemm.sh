#!/bin/bash
# Techo practico de la maquina: cuantos GFLOPS da dgemm solo, sin HPL alrededor.
#
# Pregunta que responde: HPL midio 114,7 GFLOPS con una frecuencia sostenida
# de 2,45 GHz en los P-cores y 3,40 en los E-cores, lo que da un RPEAK de
# 296,2 GFLOPS y una eficiencia de 38,7%. Eso es bajo para HPL. Hay dos
# explicaciones posibles y esta prueba las separa:
#
#   - Si dgemm solo se acerca a los 296, el techo es real y lo que pierde
#     rendimiento es la estructura de HPL (factorizacion del panel, pivoteo,
#     comunicacion entre procesos).
#   - Si dgemm tambien se queda cerca de 120-140, la maquina no da para mas
#     y el RPEAK calculado no es alcanzable, sin importar lo que digan los
#     contadores de frecuencia. En ese caso el 60% de eficiencia no existe
#     en este hardware.
#
# Prueba cada libreria en dos repartos: un proceso con doce hilos (la libreria
# se organiza sola) y doce procesos de un hilo (como los usa HPL).
#
# Uso:  ./06_banco_dgemm.sh

set -u
cd "$(dirname "$0")"
RAIZ=$(cd .. && pwd)
MKL=${MKL:-/opt/intel/oneapi/mkl/latest}

N_UNO=${N_UNO:-8000}      # 1 proceso: 3 matrices de 8000^2 = 1,5 GB
N_DOCE=${N_DOCE:-3000}    # 12 procesos: 216 MB cada uno = 2,6 GB en total
REPS=${REPS:-3}
ENFRIAR=${ENFRIAR:-20}
RPEAK=${RPEAK:-277.5}     # el de la corrida definitiva (f_P 2,29 / f_E 3,19 GHz)

SALIDAS="$RAIZ/resultados/dgemm"
mkdir -p "$SALIDAS"

# ---------------------------------------------------------------- compilar
echo "Compilando..."

gcc -O3 -march=native dgemm.c -o "$SALIDAS/dgemm_openblas" -lopenblas -lm \
  || { echo "fallo la compilacion contra OpenBLAS"; exit 1; }

gcc -O3 -march=native -DUSA_MKL -fopenmp -I"$MKL/include" dgemm.c \
    -o "$SALIDAS/dgemm_mkl" \
    -Wl,--start-group \
      "$MKL/lib/libmkl_intel_lp64.a" \
      "$MKL/lib/libmkl_gnu_thread.a" \
      "$MKL/lib/libmkl_core.a" \
    -Wl,--end-group -lgomp -lpthread -lm -ldl \
  || { echo "fallo la compilacion contra MKL"; exit 1; }

# Verificacion: el binario de MKL no puede depender de OpenBLAS.
if ldd "$SALIDAS/dgemm_mkl" | grep -qi openblas; then
  echo "FALLO: dgemm_mkl quedo enlazado contra OpenBLAS"
  exit 1
fi
echo "OK - dos binarios, cada uno con su libreria"
echo

# ------------------------------------------------------------------ correr
un_proceso() {   # $1 = binario
  OMP_NUM_THREADS=12 OPENBLAS_NUM_THREADS=12 MKL_NUM_THREADS=12 \
    "$1" "$N_UNO" "$REPS" 2>/dev/null
}

doce_procesos() {  # $1 = binario
  local tmp
  tmp=$(mktemp -d)
  for i in $(seq 1 12); do
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
      "$1" "$N_DOCE" "$REPS" > "$tmp/$i" 2>/dev/null &
  done
  wait
  # Corren a la vez, asi que el rendimiento agregado es la suma de los suyos.
  cat "$tmp"/* | awk '{s += $1} END {printf "%.2f\n", s}'
  rm -rf "$tmp"
}

printf "%-12s %-22s %-10s %-12s\n" "libreria" "reparto" "GFLOPS" "% del RPEAK"
printf "%.0s-" {1..60}; echo

for lib in openblas mkl; do
  BIN="$SALIDAS/dgemm_$lib"

  G=$(un_proceso "$BIN")
  printf "%-12s %-22s %-10s %-12s\n" "$lib" "1 proceso x 12 hilos" "${G:-fallo}" \
    "$(awk -v g="${G:-0}" -v p="$RPEAK" 'BEGIN{printf "%.1f%%", 100*g/p}')"
  sleep "$ENFRIAR"

  G=$(doce_procesos "$BIN")
  printf "%-12s %-22s %-10s %-12s\n" "$lib" "12 procesos x 1 hilo" "${G:-fallo}" \
    "$(awk -v g="${G:-0}" -v p="$RPEAK" 'BEGIN{printf "%.1f%%", 100*g/p}')"
  sleep "$ENFRIAR"
done

echo
echo "Referencia: la corrida definitiva de HPL dio 132,5 GFLOPS, o sea el 47,7% de"
echo "$RPEAK y el 59% de lo que rinde dgemm solo."
echo "Binarios y salidas en resultados/dgemm/"
