#!/bin/bash
# Rejilla de procesos, numero de procesos y variante de difusion.
#
# Las tres palancas que quedaban sin probar despues de la segunda ronda:
#
#   - La rejilla P x Q. Con 12 procesos se puede repartir 3x4, 2x6 o 4x3. Cambia
#     cuantos mensajes viajan por fila y por columna en cada paso del algoritmo.
#   - El numero de procesos. Con 12 sobre 12 hilos, los dos hilos de cada P-core
#     comparten las mismas unidades FMA: no aportan calculo nuevo pero si un
#     proceso mas que sincronizar. Con 10 o con 8 eso se alivia, a costa de
#     dejar hilos sin usar.
#   - BCAST, la forma en que se difunde el panel factorizado a las demas
#     columnas de procesos. 1 = anillo modificado (el que se venia usando),
#     2 = doble anillo, 3 = doble anillo modificado.
#
# Todo lo demas queda fijo: N, NB, build y un hilo de BLAS por proceso.
#
# El orden ROTA en cada ronda. Sin eso, la posicion dentro de la tanda queda
# correlacionada con la configuracion y la degradacion termica se disfraza de
# efecto del parametro — que es exactamente lo que paso en el barrido de NB
# del 2026-09-07 y produjo un hallazgo falso.
#
# Uso:  ./08_barrido_rejilla.sh
#       N=20000 RONDAS=5 ./08_barrido_rejilla.sh

set -u

HPL_DIR=${HPL_DIR:-hpl-mkl}
N=${N:-16000}
NB=${NB:-192}
RONDAS=${RONDAS:-3}
ENFRIAR=${ENFRIAR:-15}

# etiqueta:procesos:P:Q:BCAST
CONFIGS=${CONFIGS:-"base:12:3:4:1 rej_2x6:12:2:6:1 rej_4x3:12:4:3:1 proc10:10:2:5:1 proc8:8:2:4:1 bcast2:12:3:4:2 bcast3:12:3:4:3"}

RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TESTING="$RAIZ/$HPL_DIR/testing"
[ -x "$TESTING/xhpl" ] || { echo "No existe $HPL_DIR/testing/xhpl"; exit 1; }

# Guarda de energia. No explica la diferencia entre sesiones del 2026-09-07
# (las dos corrieron enchufadas), pero con bateria un chip de 15 W queda
# topado por potencia y ninguna comparacion seria valida. WSL2 no expone el
# estado de la bateria, asi que se pregunta a Windows.
verificar_energia() {
  local estado
  estado=$(powershell.exe -NoProfile -Command '(Get-CimInstance Win32_Battery).BatteryStatus' 2>/dev/null | tr -d '\r\n ')
  case "$estado" in
    1|4|5)
      echo "ABORTA: el portatil esta con BATERIA (estado $estado)."
      echo "Enchufalo, o pasa SIN_ENERGIA=1 para medir asi a proposito."
      [ "${SIN_ENERGIA:-0}" = "1" ] || exit 1
      ;;
    "") echo "AVISO: no se pudo leer el estado de la bateria. Verificalo a mano." ;;
    *)  echo "OK - conectado a la corriente." ;;
  esac
}
verificar_energia

SALIDAS="$RAIZ/resultados/barrido_rejilla"
mkdir -p "$SALIDAS"
DATOS=$(mktemp -d)

escribir_dat() {  # $1=P  $2=Q  $3=BCAST
  cat > "$TESTING/HPL.dat" <<EOF
HPLinpack benchmark input file
Barrido de rejilla y difusion - generado por 08_barrido_rejilla.sh
HPL.out      output file name (if any)
6            device out (6=stdout,7=stderr,file)
1            # of problems sizes (N)
$N            Ns
1            # of NBs
$NB          NBs
0            PMAP process mapping (0=Row-,1=Column-major)
1            # of process grids (P x Q)
$1            Ps
$2            Qs
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
$3            BCASTs (0=1rg,1=1rM,2=2rg,3=2rM,4=Lng,5=LnM)
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

correr() {  # $1=procesos $2=P $3=Q $4=BCAST $5=log -> imprime GFLOPS
  escribir_dat "$2" "$3" "$4"
  ( cd "$TESTING" && OMP_NUM_THREADS=1 mpirun --use-hwthread-cpus -np "$1" ./xhpl ) > "$5" 2>&1
  awk '/^WR/ {print $NF}' "$5"
}

rotar() {  # $1 = lista, $2 = posiciones
  local arr=($1) n desp i out=()
  n=${#arr[@]}; desp=$(( $2 % n ))
  for ((i = 0; i < n; i++)); do out+=("${arr[$(( (i + desp) % n ))]}"); done
  echo "${out[@]}"
}

TOTAL=$(( $(echo $CONFIGS | wc -w) * RONDAS + 2 ))
echo "build=$HPL_DIR  N=$N  NB=$NB  rondas=$RONDAS  ->  $TOTAL corridas"
echo

for c in 1 2; do
  echo -n "calentamiento $c/2 (no se cuenta)... "
  G=$(correr 12 3 4 1 "$SALIDAS/calentamiento$c.txt")
  echo "${G:-fallo}"
  sleep "$ENFRIAR"
done
echo

for ronda in $(seq 1 "$RONDAS"); do
  echo "--- ronda $ronda de $RONDAS ---"
  for cfg in $(rotar "$CONFIGS" $((ronda - 1))); do
    IFS=: read -r etiq np p q bc <<< "$cfg"
    G=$(correr "$np" "$p" "$q" "$bc" "$SALIDAS/${etiq}_ronda${ronda}.txt")
    if [ -n "$G" ]; then
      echo "$G" >> "$DATOS/$etiq"
      printf "  %-9s np=%-3s %sx%-3s BCAST=%s  %s GFLOPS\n" \
        "$etiq" "$np" "$p" "$q" "$bc" "$(awk -v g="$G" 'BEGIN{printf "%6.1f", g}')"
    else
      printf "  %-9s np=%-3s %sx%-3s BCAST=%s  fallo\n" "$etiq" "$np" "$p" "$q" "$bc"
    fi
    sleep "$ENFRIAR"
  done
done

# ------------------------------------------------------------------ resumen
BASE=$(awk '{s += $1} END {if (NR) printf "%.1f", s/NR}' "$DATOS/base" 2>/dev/null)
[ -z "$BASE" ] && BASE=0

echo
printf "%-9s %-10s %-10s %-10s %-12s\n" "config" "media" "mejor" "peor" "vs base"
printf "%.0s-" {1..55}; echo

for cfg in $CONFIGS; do
  etiq=${cfg%%:*}
  [ -f "$DATOS/$etiq" ] || continue
  read -r media mejor peor <<< "$(awk '
    {s += $1; if (NR == 1 || $1 > mx) mx = $1; if (NR == 1 || $1 < mn) mn = $1}
    END {printf "%.1f %.1f %.1f", s/NR, mx, mn}' "$DATOS/$etiq")"
  printf "%-9s %-10s %-10s %-10s %-12s\n" "$etiq" "$media" "$mejor" "$peor" \
    "$(awk -v m="$media" -v b="$BASE" 'BEGIN{ if (b > 0) printf "%+.1f%%", 100*(m-b)/b; else printf "-" }')"
done

echo
echo "Base = 12 procesos, rejilla 3x4, BCAST=1 (la de la corrida definitiva)."
echo "La dispersion entre rondas de una misma configuracion ronda el 5-8%:"
echo "una diferencia menor que eso no es real."
echo "Salidas en resultados/barrido_rejilla/"
rm -rf "$DATOS"
