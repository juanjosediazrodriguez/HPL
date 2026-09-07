#!/bin/bash
# Compila una segunda copia de HPL enlazada contra Intel MKL en vez de OpenBLAS.
#
# Por que NO se usa ./configure: su deteccion de BLAS esta fija en el codigo,
# encuentra OpenBLAS y descarta el LIBS que uno le pase. El log del intento del
# 2026-09-07 lo dice literal: "checking for dgemm_ in OpenBLAS... yes", y el
# binario resultante quedo enlazado contra OpenBLAS igual que el original.
#
# En su lugar se usa la via clasica de HPL: un Make.<arch> que declara a mano
# donde esta la libreria. Es lo que hace la plantilla setup/Make.Linux_Intel64,
# adaptada aqui a gcc + OpenMPI (la original asume compilador y MPI de Intel).
#
# Se enlaza contra mkl_sequential y de forma estatica: la mejor configuracion
# medida es 12 procesos MPI x 1 hilo de BLAS, asi que MKL no debe abrir hilos
# propios que peleen con los procesos.
#
# Requisito: sudo apt install -y intel-oneapi-mkl-devel

set -eu
cd "$(dirname "$0")/.."
RAIZ=$(pwd)
DESTINO="$RAIZ/hpl-mkl"
TARBALL="$RAIZ/hpl-2.3.tar.gz"
MKL=${MKL:-/opt/intel/oneapi/mkl/latest}

# ------------------------------------------------------------------ chequeos
for f in "$MKL/include/mkl.h" \
         "$MKL/lib/libmkl_intel_lp64.a" \
         "$MKL/lib/libmkl_sequential.a" \
         "$MKL/lib/libmkl_core.a"; do
  [ -f "$f" ] || { echo "Falta $f"; echo "Instala: sudo apt install -y intel-oneapi-mkl-devel"; exit 1; }
done
echo "MKL encontrado en $MKL"

command -v mpicc >/dev/null || { echo "No hay mpicc en el PATH"; exit 1; }

# ------------------------------------------------------------------ fuentes
[ -d "$DESTINO" ] && { echo "Borrando hpl-mkl/ para compilar desde cero..."; rm -rf "$DESTINO"; }

if [ ! -f "$TARBALL" ]; then
  echo "Bajando el fuente de netlib..."
  wget -q https://www.netlib.org/benchmark/hpl/hpl-2.3.tar.gz -O "$TARBALL"
fi

echo "Extrayendo una copia limpia en hpl-mkl/..."
mkdir -p "$DESTINO"
tar -xzf "$TARBALL" -C "$DESTINO" --strip-components=1

# ------------------------------------------------------------------ Make.mkl
# Ojo: TOPdir va con ruta absoluta porque el make de HPL entra y sale de
# subcarpetas, asi que no sirve una ruta relativa ni $(CURDIR).
cat > "$DESTINO/Make.mkl" <<EOF
SHELL        = /bin/sh
CD           = cd
CP           = cp
LN_S         = ln -fs
MKDIR        = mkdir -p
RM           = /bin/rm -f
TOUCH        = touch

ARCH         = mkl

TOPdir       = $DESTINO
INCdir       = \$(TOPdir)/include
BINdir       = \$(TOPdir)/bin/\$(ARCH)
LIBdir       = \$(TOPdir)/lib/\$(ARCH)
HPLlib       = \$(LIBdir)/libhpl.a

# mpicc ya agrega por su cuenta lo que hace falta de MPI.
MPdir        =
MPinc        =
MPlib        =

# Enlazado estatico contra MKL secuencial.
LAdir        = $MKL
LAinc        = \$(LAdir)/include
LAlib        = -Wl,--start-group \\
               \$(LAdir)/lib/libmkl_intel_lp64.a \\
               \$(LAdir)/lib/libmkl_sequential.a \\
               \$(LAdir)/lib/libmkl_core.a \\
               -Wl,--end-group -lpthread -lm -ldl

F2CDEFS      = -DAdd__ -DF77_INTEGER=int -DStringSunStyle

HPL_INCLUDES = -I\$(INCdir) -I\$(INCdir)/\$(ARCH) -I\$(LAinc) \$(MPinc)
HPL_LIBS     = \$(HPLlib) \$(LAlib) \$(MPlib)

# Sin -DHPL_DETAILED_TIMING ni -DHPL_PROGRESS_REPORT: agregan medicion interna
# y salida por pantalla, y el build de OpenBLAS contra el que se compara
# tampoco los tiene.
HPL_OPTS     =
HPL_DEFS     = \$(F2CDEFS) \$(HPL_OPTS) \$(HPL_INCLUDES)

CC           = mpicc
CCNOOPT      = \$(HPL_DEFS)
CCFLAGS      = \$(HPL_DEFS) -O3 -march=native -w

LINKER       = mpicc
LINKFLAGS    = \$(CCFLAGS)

ARCHIVER     = ar
ARFLAGS      = r
RANLIB       = echo
EOF

# ------------------------------------------------------------------ compilar
cd "$DESTINO"
echo "Compilando (un par de minutos)..."
make arch=mkl > "$RAIZ/hpl-mkl-build.log" 2>&1 \
  || { echo "Fallo la compilacion. Las ultimas lineas del log:"; tail -n 25 "$RAIZ/hpl-mkl-build.log"; exit 1; }

BIN="$DESTINO/bin/mkl/xhpl"
[ -x "$BIN" ] || { echo "Compilo pero no aparecio bin/mkl/xhpl"; tail -n 25 "$RAIZ/hpl-mkl-build.log"; exit 1; }

# El script de medicion espera <build>/testing/xhpl, asi que se copia alla.
mkdir -p "$DESTINO/testing"
cp "$BIN" "$DESTINO/testing/xhpl"

# ------------------------------------------------------------ verificacion
echo
echo "=== Verificacion ==="

if ldd "$BIN" | grep -qi openblas; then
  echo "FALLO: el binario quedo enlazado contra OpenBLAS, no contra MKL."
  ldd "$BIN" | grep -i blas
  exit 1
fi
echo "OK  - no aparece OpenBLAS entre sus dependencias"

N_MKL=$(nm "$BIN" 2>/dev/null | grep -ci mkl || true)
if [ "$N_MKL" -eq 0 ]; then
  echo "FALLO: el binario no tiene ni un simbolo de MKL."
  exit 1
fi
echo "OK  - $N_MKL simbolos de MKL dentro del binario"

echo "OK  - tamano: $(du -h "$BIN" | cut -f1)  (el de OpenBLAS pesa $(du -h "$RAIZ/hpl-2.3/testing/xhpl" 2>/dev/null | cut -f1))"

echo
echo "Listo. Siguiente paso: la comparacion alternada A-B."
