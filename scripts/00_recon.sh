#!/bin/bash
# Reconocimiento de APOLO antes de compilar HPL.
# Uso: bash 00_recon.sh > recon.txt 2>&1   (y me pasás recon.txt)
#
# Cada bloque responde una pregunta concreta que hace falta para
# compilar y para afinar HPL.dat.

echo "############ 1. CPU — para el RPEAK y para P x Q ############"
# Sockets, cores por socket, frecuencia y set de instrucciones (AVX2/AVX-512).
# De aqui salen 3 de los 5 factores de RPEAK.
lscpu

echo
echo "############ 2. MEMORIA — para elegir N ############"
# N sale de la RAM disponible: la matriz ocupa 8*N^2 bytes.
free -g
cat /proc/meminfo | grep -i memtotal

echo
echo "############ 3. NODOS Y PARTICIONES DE SLURM ############"
# Que particiones puedo usar, cuantos nodos tienen y con que limites de tiempo.
sinfo -o "%20P %5a %10l %6D %6t %N"
echo "--- detalle de nodos (cores y RAM por nodo) ---"
sinfo -N -o "%N %c %m %f" | head -30

echo
echo "############ 4. MODULOS DISPONIBLES ############"
# Que compilador, que MPI y que BLAS hay instalados.
# La BLAS es la que mas afecta el rendimiento de HPL.
module avail 2>&1 | head -80

echo
echo "--- busqueda dirigida: MPI ---"
module avail 2>&1 | grep -i -E "openmpi|mpich|intel-mpi|impi"
echo "--- busqueda dirigida: BLAS / algebra lineal ---"
module avail 2>&1 | grep -i -E "openblas|mkl|atlas|blis|lapack|blas"
echo "--- busqueda dirigida: compiladores ---"
module avail 2>&1 | grep -i -E "gcc|intel|aocc|llvm"
echo "--- por si HPL ya esta instalado (nos ahorraria compilar) ---"
module avail 2>&1 | grep -i -E "hpl|linpack|hpcc"

echo
echo "############ 5. CUOTA DE DISCO ############"
# HPL compilado pesa poco, pero conviene saber donde estamos parados.
quota -s 2>/dev/null || echo "(sin quota configurada)"
df -h "$HOME" | tail -1

echo
echo "############ 6. IDENTIDAD ############"
whoami
hostname
echo "HOME=$HOME"
