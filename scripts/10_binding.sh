#!/bin/bash
# Efecto del binding de procesos MPI a hilos logicos.
#
# Por que: todas las corridas hasta ahora usaron "mpirun --use-hwthread-cpus
# -np 12" sin --bind-to. En OpenMPI 4.1 el binding por defecto con mas de dos
# procesos es al SOCKET, y como este equipo tiene uno solo, los doce ranks
# quedan libres de migrar entre los doce hilos logicos durante toda la corrida.
# El informe listaba el pinning como "la principal palanca sin probar" dandolo
# por imposible en WSL2; eso es cierto para fijar a un CORE FISICO —la
# topologia que ve Linux es sintetica— pero NO para fijar a un hilo logico,
# que es lo que evita la migracion y el descarte de cache.
#
# Que compara:
#   defecto   - exactamente el comando que se uso en todas las mediciones
#   hwthread  - cada rank clavado a un hilo logico
#   ninguno   - migracion libre declarada de forma explicita
#
# El tercero importa como control: si "defecto" y "ninguno" empatan, queda
# confirmado que el defecto no estaba fijando nada.
#
# Uso:  ./10_binding.sh
#       N=20000 RONDAS=5 ./10_binding.sh

set -u

HPL_DIR=${HPL_DIR:-hpl-mkl}
N=${N:-16000}
NB=${NB:-192}
RANKS=${RANKS:-12}
RONDAS=${RONDAS:-3}
ENFRIAR=${ENFRIAR:-15}
POLITICAS=${POLITICAS:-"defecto hwthread ninguno"}

RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TESTING="$RAIZ/$HPL_DIR/testing"
[ -x "$TESTING/xhpl" ] || { echo "No existe $HPL_DIR/testing/xhpl"; exit 1; }

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
SALIDAS="$RAIZ/resultados/binding/$ETIQUETA"
mkdir -p "$SALIDAS"
DATOS=$(mktemp -d)

P=1
for ((i = 1; i * i <= RANKS; i++)); do
  (( RANKS % i == 0 )) && P=$i
done
Q=$(( RANKS / P ))

# Las banderas de cada politica. "defecto" va vacio a proposito: es el comando
# tal cual se uso en todas las mediciones anteriores.
banderas() {
  case "$1" in
    defecto)  echo "" ;;
    hwthread) echo "--bind-to hwthread --map-by hwthread" ;;
    ninguno)  echo "--bind-to none" ;;
    core)     echo "--bind-to core --map-by core:OVERSUBSCRIBE" ;;
    *)        echo "" ;;
  esac
}

escribir_dat() {
  cat > "$TESTING/HPL.dat" <<EOF
HPLinpack benchmark input file
Prueba de binding - generado por 10_binding.sh
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

correr() {  # $1 = politica, $2 = log -> imprime GFLOPS
  escribir_dat
  ( cd "$TESTING" && OMP_NUM_THREADS=1 \
      mpirun --use-hwthread-cpus $(banderas "$1") -np "$RANKS" ./xhpl ) > "$2" 2>&1
  awk '/^WR/ {print $NF}' "$2"
}

# Deja constancia de que esta haciendo cada politica. Es la evidencia de si el
# defecto estaba fijando algo o no; se guarda aunque no se mida.
echo "Registrando el mapa de binding de cada politica..."
for pol in $POLITICAS; do
  ( cd "$TESTING" && mpirun --use-hwthread-cpus $(banderas "$pol") \
      --report-bindings -np "$RANKS" true ) > "$SALIDAS/bindings_$pol.txt" 2>&1
  printf "  %-9s -> %s\n" "$pol" "$(grep -c 'bound to' "$SALIDAS/bindings_$pol.txt") ranks con binding declarado"
done
echo

TOTAL=$(( $(echo $POLITICAS | wc -w) * RONDAS + 2 ))
echo "build=$HPL_DIR  N=$N  NB=$NB  ranks=$RANKS  grid=${P}x${Q}  rondas=$RONDAS"
echo "politicas: $POLITICAS"
echo "$TOTAL corridas en total"
echo

for c in 1 2; do
  echo -n "calentamiento $c/2 (no se cuenta)... "
  G=$(correr defecto "$SALIDAS/calentamiento$c.txt")
  echo "${G:-fallo}"
  sleep "$ENFRIAR"
done
echo

rotar() {
  local arr=($1) n desp i out=()
  n=${#arr[@]}; desp=$(( $2 % n ))
  for ((i = 0; i < n; i++)); do out+=("${arr[$(( (i + desp) % n ))]}"); done
  echo "${out[@]}"
}

for ronda in $(seq 1 "$RONDAS"); do
  echo "--- ronda $ronda de $RONDAS ---"
  for pol in $(rotar "$POLITICAS" $((ronda - 1))); do
    G=$(correr "$pol" "$SALIDAS/${pol}_ronda${ronda}.txt")
    if [ -n "$G" ]; then
      echo "$G" >> "$DATOS/$pol"
      printf "  %-9s %s GFLOPS\n" "$pol" "$(awk -v g="$G" 'BEGIN{printf "%6.1f", g}')"
    else
      printf "  %-9s fallo\n" "$pol"
    fi
    sleep "$ENFRIAR"
  done
done

echo
printf "%-10s %-10s %-10s %-10s\n" "politica" "media" "mejor" "peor"
printf "%.0s-" {1..42}; echo

MEJOR_POL=""; MEJOR_G=0
for pol in $POLITICAS; do
  [ -f "$DATOS/$pol" ] || continue
  read -r media mejor peor <<< "$(awk '
    {s += $1; if (NR == 1 || $1 > mx) mx = $1; if (NR == 1 || $1 < mn) mn = $1}
    END {printf "%.1f %.1f %.1f", s/NR, mx, mn}' "$DATOS/$pol")"
  printf "%-10s %-10s %-10s %-10s\n" "$pol" "$media" "$mejor" "$peor"
  if awk -v a="$media" -v b="$MEJOR_G" 'BEGIN{exit !(a > b)}'; then
    MEJOR_G=$media; MEJOR_POL=$pol
  fi
done

echo
echo "Mejor: $MEJOR_POL con $MEJOR_G GFLOPS de media."
echo "Solo cuenta si las tres corridas de la ganadora superan a las tres de la"
echo "base: con una dispersion de +/-1,3% dentro de sesion, una diferencia de"
echo "medias por debajo del 3% no se puede defender."
echo "Salidas en resultados/binding/$ETIQUETA/"
rm -rf "$DATOS"
