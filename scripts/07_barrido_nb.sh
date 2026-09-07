#!/bin/bash
# Barrido de NB sobre el build de MKL, con el protocolo de medicion bueno.
#
# Por que se rehace: el barrido original (01_barrido_hibrido.sh y la tabla del
# informe) corria un NB tras otro, una sola vez cada uno y sin calentamiento.
# El 2026-09-07 se midio que las dos primeras corridas de una sesion salen
# bajas (85 -> 102 -> 117 GFLOPS), asi que el primer NB de aquella tabla
# quedo subvalorado y con el se calculo el "NB vale un 56% de rendimiento".
#
# Que cambia aqui:
#   - Se mide por RONDAS: todos los NB una vez, luego otra, luego otra. Asi
#     cualquier deriva de la sesion afecta a todos por igual.
#   - Dos corridas de calentamiento que no se cuentan.
#   - Se corre sobre hpl-mkl, que gano el banco de dgemm por 4,3%.
#   - El rango llega hasta 384: MKL suele preferir bloques mas grandes que
#     OpenBLAS, y el barrido viejo se quedaba en 256.
#
# Uso:  ./07_barrido_nb.sh
#       N=20000 RONDAS=5 NBS="160 192 224" ./07_barrido_nb.sh

set -u

HPL_DIR=${HPL_DIR:-hpl-mkl}
N=${N:-16000}
RANKS=${RANKS:-12}
RONDAS=${RONDAS:-3}
ENFRIAR=${ENFRIAR:-15}
NBS=${NBS:-"128 160 192 224 256 320 384"}

RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TESTING="$RAIZ/$HPL_DIR/testing"
[ -x "$TESTING/xhpl" ] || { echo "No existe $HPL_DIR/testing/xhpl"; exit 1; }

# Guarda de energia. NO explica la diferencia entre sesiones del 2026-09-07
# —las dos tandas de ese dia corrieron enchufadas y aun asi el mismo punto
# (N=16000, NB=192) dio 82,5 y 129,1 GFLOPS, un 56% sin causa identificada—,
# pero un chip de 15 W con bateria si queda topado por potencia y eso
# invalidaria cualquier comparacion. Se lee desde Windows porque WSL2 no
# expone el estado de la bateria.
verificar_energia() {
  local estado
  estado=$(powershell.exe -NoProfile -Command '(Get-CimInstance Win32_Battery).BatteryStatus' 2>/dev/null | tr -d '\r\n ')
  case "$estado" in
    1|4|5)
      echo "ABORTA: el portatil esta con BATERIA (estado $estado)."
      echo "Enchufalo y vuelve a correr, o pasa SIN_ENERGIA=1 para medir asi a proposito."
      [ "${SIN_ENERGIA:-0}" = "1" ] || exit 1
      ;;
    "")
      echo "AVISO: no se pudo leer el estado de la bateria. Verifica a mano que este enchufado."
      ;;
    *)
      echo "OK - conectado a la corriente."
      ;;
  esac
}
verificar_energia

ETIQUETA=${ETIQUETA:-sesion}
SALIDAS="$RAIZ/resultados/barrido_nb/$ETIQUETA"
mkdir -p "$SALIDAS"
DATOS=$(mktemp -d)

# Grid mas cuadrado posible con P*Q = RANKS.
P=1
for ((i = 1; i * i <= RANKS; i++)); do
  (( RANKS % i == 0 )) && P=$i
done
Q=$(( RANKS / P ))

escribir_dat() {  # $1 = NB
  cat > "$TESTING/HPL.dat" <<EOF
HPLinpack benchmark input file
Barrido de NB - generado por 07_barrido_nb.sh
HPL.out      output file name (if any)
6            device out (6=stdout,7=stderr,file)
1            # of problems sizes (N)
$N            Ns
1            # of NBs
$1          NBs
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

correr() {  # $1 = NB, $2 = log -> imprime GFLOPS
  escribir_dat "$1"
  ( cd "$TESTING" && OMP_NUM_THREADS=1 mpirun --use-hwthread-cpus -np "$RANKS" ./xhpl ) > "$2" 2>&1
  awk '/^WR/ {print $NF}' "$2"
}

TOTAL=$(( $(echo $NBS | wc -w) * RONDAS + 2 ))
echo "build=$HPL_DIR  N=$N  ranks=$RANKS  grid=${P}x${Q}  rondas=$RONDAS"
echo "NB a probar: $NBS"
echo "$TOTAL corridas en total"
echo

for c in 1 2; do
  echo -n "calentamiento $c/2 (no se cuenta)... "
  G=$(correr 192 "$SALIDAS/calentamiento$c.txt")
  echo "${G:-fallo}"
  sleep "$ENFRIAR"
done
echo

# Rota la lista en cada ronda. Sin esto, el orden dentro de la ronda queda
# perfectamente correlacionado con el NB: el primero siempre corre con la
# maquina mas fria y el ultimo con la mas caliente, y sale una curva
# descendente que parece un efecto de NB pero es el reloj cayendose. Paso
# exactamente eso en la ronda 1 del 2026-09-07.
rotar() {  # $1 = lista, $2 = cuantas posiciones
  local arr=($1) n desp i out=()
  n=${#arr[@]}; desp=$(( $2 % n ))
  for ((i = 0; i < n; i++)); do out+=("${arr[$(( (i + desp) % n ))]}"); done
  echo "${out[@]}"
}

for ronda in $(seq 1 "$RONDAS"); do
  echo "--- ronda $ronda de $RONDAS ---"
  for nb in $(rotar "$NBS" $((ronda - 1))); do
    G=$(correr "$nb" "$SALIDAS/nb${nb}_ronda${ronda}.txt")
    if [ -n "$G" ]; then
      echo "$G" >> "$DATOS/$nb"
      printf "  NB=%-5s %s GFLOPS\n" "$nb" "$(awk -v g="$G" 'BEGIN{printf "%6.1f", g}')"
    else
      printf "  NB=%-5s fallo\n" "$nb"
    fi
    sleep "$ENFRIAR"
  done
done

echo
printf "%-6s %-10s %-10s %-10s %-12s\n" "NB" "media" "mejor" "peor" "% de dgemm"
printf "%.0s-" {1..52}; echo

MEJOR_NB=""; MEJOR_G=0
for nb in $NBS; do
  [ -f "$DATOS/$nb" ] || continue
  read -r media mejor peor <<< "$(awk '
    {s += $1; if (NR == 1 || $1 > mx) mx = $1; if (NR == 1 || $1 < mn) mn = $1}
    END {printf "%.1f %.1f %.1f", s/NR, mx, mn}' "$DATOS/$nb")"
  printf "%-6s %-10s %-10s %-10s %-12s\n" "$nb" "$media" "$mejor" "$peor" \
    "$(awk -v g="$media" 'BEGIN{printf "%.1f%%", 100*g/210.9}')"
  if awk -v a="$media" -v b="$MEJOR_G" 'BEGIN{exit !(a > b)}'; then
    MEJOR_G=$media; MEJOR_NB=$nb
  fi
done

echo
echo "Mejor: NB=$MEJOR_NB con $MEJOR_G GFLOPS de media."
echo "Referencia: dgemm solo da 210,9 GFLOPS; el RPEAK medido es 296,2."
echo "Salidas en resultados/barrido_nb/"
rm -rf "$DATOS"
