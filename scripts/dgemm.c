/*
 * Cuantos GFLOPS sostiene una multiplicacion de matrices densa en esta maquina.
 *
 * Sirve para separar dos explicaciones del 38,7% de eficiencia de HPL:
 * o HPL deja rendimiento sobre la mesa, o los 296 GFLOPS de RPEAK calculados
 * con la frecuencia medida no son alcanzables. Esto mide solo dgemm, que es
 * donde HPL se pasa el 90% del tiempo, sin factorizacion ni comunicacion
 * alrededor. Es el techo practico de la maquina.
 *
 * Compilar contra OpenBLAS:
 *   gcc -O3 -march=native dgemm.c -o dgemm_openblas -lopenblas -lm
 * Compilar contra MKL: ver 06_banco_dgemm.sh
 *
 * Uso: ./dgemm_openblas <n> <repeticiones>   -> imprime los mejores GFLOPS
 */

#define _POSIX_C_SOURCE 199309L
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#ifdef USA_MKL
#include <mkl.h>
#else
#include <cblas.h>
#endif

static double ahora(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
}

int main(int argc, char **argv)
{
    int n    = (argc > 1) ? atoi(argv[1]) : 4000;
    int reps = (argc > 2) ? atoi(argv[2]) : 3;

    size_t elems = (size_t)n * (size_t)n;
    double *A = malloc(elems * sizeof(double));
    double *B = malloc(elems * sizeof(double));
    double *C = malloc(elems * sizeof(double));

    if (!A || !B || !C) {
        fprintf(stderr, "sin memoria para n=%d\n", n);
        return 1;
    }

    srand(12345);
    for (size_t i = 0; i < elems; i++) {
        A[i] = (double)rand() / (double)RAND_MAX;
        B[i] = (double)rand() / (double)RAND_MAX;
        C[i] = 0.0;
    }

    /* 2*n^3: cada elemento de C es n multiplicaciones y n sumas. */
    double flops = 2.0 * (double)n * (double)n * (double)n;

    /* Calentamiento: la primera llamada paga la reserva de buffers internos
       de la libreria y el primer contacto con las paginas de memoria. */
    cblas_dgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, n, n, n,
                1.0, A, n, B, n, 0.0, C, n);

    double mejor = 0.0;
    for (int r = 0; r < reps; r++) {
        double t0 = ahora();
        cblas_dgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, n, n, n,
                    1.0, A, n, B, n, 0.0, C, n);
        double dt = ahora() - t0;
        if (dt > 0.0) {
            double g = flops / dt / 1e9;
            if (g > mejor) mejor = g;
        }
    }

    /* Se usa un valor de C para que el optimizador no borre el calculo. */
    fprintf(stderr, "C[0]=%g\n", C[0]);
    printf("%.2f\n", mejor);

    free(A); free(B); free(C);
    return 0;
}
