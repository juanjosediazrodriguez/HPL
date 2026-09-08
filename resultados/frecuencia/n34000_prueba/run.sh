#!/bin/bash
cd /mnt/c/Users/jjdia/Documents/semestre_6/Codigo/Scar/HPL/hpl-mkl/testing && OMP_NUM_THREADS=1 mpirun --use-hwthread-cpus -np 12 ./xhpl > /mnt/c/Users/jjdia/Documents/semestre_6/Codigo/Scar/HPL/resultados/frecuencia/n34000_prueba/corrida.txt 2>&1
