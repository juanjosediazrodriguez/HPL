<#
    Mide la frecuencia que el procesador sostiene DURANTE una corrida de HPL,
    y con ella calcula un RPEAK alcanzable en vez del RPEAK de catalogo.

    Por que hace falta: el 30,2% de eficiencia del informe sale de dividir el
    RMAX medido entre 352 GFLOPS, que es el RPEAK a frecuencia turbo. Un chip
    de 15 W no sostiene el turbo en diez cores a la vez, asi que ese
    denominador no es alcanzable ni en teoria. Contra el RPEAK a frecuencia
    base (99,2 GFLOPS) la misma corrida da 107%, que es imposible. Los dos
    denominadores estan mal, y el correcto es el de la frecuencia real.

    Por que se mide desde Windows: adentro de WSL2 no hay acceso a los
    contadores del procesador (no hay MSR, y turbostat no funciona). Windows
    si los expone, y por WMI en vez de por contadores de rendimiento para que
    no dependa del idioma del sistema.

    La formula es la de la Lecture 2, separada por tipo de core porque los
    P-cores y los E-cores corren a relojes distintos:

        RPEAK = 2 P-cores x 16 FLOP/ciclo x f_P  +  8 E-cores x 8 FLOP/ciclo x f_E

    Uso:   .\scripts\05_medir_frecuencia.ps1
           .\scripts\05_medir_frecuencia.ps1 -N 20000 -Build hpl-mkl
#>

[CmdletBinding()]
param(
    [int]$N       = 18000,      # ~2,6 GB y ~35 s de corrida: suficientes muestras
    [int]$NB      = 160,
    [int]$Ranks   = 12,
    [string]$Build = 'hpl-2.3',
    [string]$Etiqueta = ''
)

$ErrorActionPreference = 'Stop'

# FLOP por ciclo de cada tipo de core (ver hallazgo 1 del workshop):
#   P-core Golden Cove : 256 bits / 64 = 4 doubles x 2 (FMA) x 2 (unidades) = 16
#   E-core Gracemont   : 128 bits / 64 = 2 doubles x 2 (FMA) x 2 (unidades) = 8
$FlopCicloP = 16 ; $NucleosP = 2
$FlopCicloE = 8  ; $NucleosE = 8

# En Alder Lake, Windows enumera primero los hilos de los P-cores.
$HilosP = @('0,0','0,1','0,2','0,3')

if (-not $Etiqueta) { $Etiqueta = $Build }

$Raiz    = Split-Path -Parent $PSScriptRoot
$Testing = Join-Path $Raiz "$Build\testing"
if (-not (Test-Path (Join-Path $Testing 'xhpl'))) { throw "No existe $Build\testing\xhpl" }

$Salidas = Join-Path $Raiz "resultados\frecuencia\$Etiqueta"
New-Item -ItemType Directory -Path $Salidas -Force | Out-Null

# --------------------------------------------------------------- grid P x Q
$P = 1
for ($i = 1; $i * $i -le $Ranks; $i++) { if ($Ranks % $i -eq 0) { $P = $i } }
$Q = $Ranks / $P

# ----------------------------------------------------------------- HPL.dat
# Se escribe con saltos de linea de Unix: HPL lo lee desde Linux.
$dat = @"
HPLinpack benchmark input file
Medicion de frecuencia - generado por 05_medir_frecuencia.ps1
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
"@
[System.IO.File]::WriteAllText((Join-Path $Testing 'HPL.dat'), ($dat -replace "`r`n", "`n"))

# ------------------------------------------------------------------ lanzar
$RutaWsl = '/mnt/c' + ($Raiz.Substring(2) -replace '\\', '/')
$LogWsl  = "$RutaWsl/resultados/frecuencia/$Etiqueta/corrida.txt"
$LogWin  = Join-Path $Salidas 'corrida.txt'

# El comando se escribe a un archivo en vez de pasarlo con -c: Start-Process
# no entrecomilla los argumentos que le llegan en lista, asi que un comando
# con espacios se parte y bash solo recibe la primera palabra.
$comando = "cd $RutaWsl/$Build/testing && OMP_NUM_THREADS=1 mpirun --use-hwthread-cpus -np $Ranks ./xhpl > $LogWsl 2>&1"
$runWin  = Join-Path $Salidas 'run.sh'
$runWsl  = "$RutaWsl/resultados/frecuencia/$Etiqueta/run.sh"
[System.IO.File]::WriteAllText($runWin, "#!/bin/bash`n$comando`n")

$errWin = Join-Path $Salidas 'wsl-error.txt'

Write-Host "build=$Build  N=$N  NB=$NB  ranks=$Ranks  grid=${P}x${Q}"
Write-Host "Lanzando HPL en WSL2 y muestreando la frecuencia cada segundo..."
Write-Host ""

$proc = Start-Process -FilePath 'wsl' -ArgumentList '-e','bash',$runWsl `
        -PassThru -NoNewWindow -RedirectStandardError $errWin

# --------------------------------------------------------------- muestrear
$muestras = New-Object System.Collections.Generic.List[object]
$t0 = Get-Date

while (-not $proc.HasExited) {
    $c = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation |
         Where-Object { $_.Name -notlike '*_Total*' }   # la instancia se llama "0,_Total"

    $seg = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    foreach ($i in $c) {
        $muestras.Add([pscustomobject]@{
            Segundo   = $seg
            Hilo      = $i.Name
            Tipo      = if ($HilosP -contains $i.Name) { 'P' } else { 'E' }
            Nominal   = [double]$i.ProcessorFrequency
            Porcentaje= [double]$i.PercentProcessorPerformance
            MHz       = [double]$i.ProcessorFrequency * [double]$i.PercentProcessorPerformance / 100
            Uso       = [double]$i.PercentProcessorTime
        })
    }
    Start-Sleep -Milliseconds 900
}

$duracion = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
$muestras | Export-Csv -Path (Join-Path $Salidas 'muestras.csv') -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------------ RMAX
if (-not (Test-Path $LogWin)) {
    Write-Host "HPL no dejo salida. Codigo de salida de wsl: $($proc.ExitCode)"
    if ((Test-Path $errWin) -and (Get-Item $errWin).Length -gt 0) {
        Write-Host "Error reportado por WSL:"
        Get-Content $errWin
    } else {
        Write-Host "WSL no reporto ningun error. Comando que se intento correr:"
        Write-Host "  $comando"
    }
    exit 1
}
# -CaseSensitive es obligatorio: sin el, "Written by ... UTK" del encabezado
# de HPL tambien casa con ^WR y se termina leyendo "UTK" como si fuera el
# resultado. El patron pide ademas el resto del codigo de la variante.
$linea = Select-String -Path $LogWin -Pattern '^WR[0-9A-Za-z]+\s' -CaseSensitive | Select-Object -First 1
if (-not $linea) {
    Write-Host "HPL no produjo una linea de resultado. Ultimas lineas del log:"
    Get-Content $LogWin -Tail 15
    exit 1
}
$RMax = [double](($linea.Line -split '\s+')[-1])
$paso = if (Select-String -Path $LogWin -Pattern 'PASSED' -Quiet) { 'PASSED' } else { 'FALLO' }

# ------------------------------------------------------- descartar bordes
# Los primeros y ultimos segundos son arranque y cierre, no calculo sostenido.
$segundos = $muestras.Segundo | Sort-Object -Unique
if ($segundos.Count -gt 8) {
    $corte1 = $segundos[3]
    $corte2 = $segundos[-3]
    $utiles = $muestras | Where-Object { $_.Segundo -ge $corte1 -and $_.Segundo -le $corte2 }
} else {
    $utiles = $muestras
}

$fP = ($utiles | Where-Object Tipo -eq 'P' | Measure-Object MHz -Average).Average / 1000
$fE = ($utiles | Where-Object Tipo -eq 'E' | Measure-Object MHz -Average).Average / 1000
$usoP = ($utiles | Where-Object Tipo -eq 'P' | Measure-Object Uso -Average).Average
$usoE = ($utiles | Where-Object Tipo -eq 'E' | Measure-Object Uso -Average).Average

$rpeakSostenido = $NucleosP * $FlopCicloP * $fP + $NucleosE * $FlopCicloE * $fE
$rpeakBase      = $NucleosP * $FlopCicloP * 1.3 + $NucleosE * $FlopCicloE * 0.9
$rpeakTurbo     = $NucleosP * $FlopCicloP * 4.4 + $NucleosE * $FlopCicloE * 3.3

# ---------------------------------------------------------------- reporte
Write-Host ""
Write-Host "=== Corrida ==="
Write-Host ("duracion        : {0} s  ({1} muestras por hilo)" -f $duracion, $segundos.Count)
Write-Host ("RMAX medido     : {0:N1} GFLOPS   [{1}]" -f $RMax, $paso)
Write-Host ""
Write-Host "=== Frecuencia sostenida durante el calculo ==="
Write-Host ("P-cores ({0} hilos) : {1:N2} GHz   (uso {2:N0}%)" -f $HilosP.Count, $fP, $usoP)
Write-Host ("E-cores ({0} hilos) : {1:N2} GHz   (uso {2:N0}%)" -f (12 - $HilosP.Count), $fE, $usoE)
Write-Host ""
Write-Host "=== RPEAK segun que frecuencia se use ==="
Write-Host ("a frecuencia base    : {0,6:N1} GFLOPS  -> eficiencia {1,5:N1}%" -f $rpeakBase,      (100 * $RMax / $rpeakBase))
Write-Host ("a frecuencia turbo   : {0,6:N1} GFLOPS  -> eficiencia {1,5:N1}%" -f $rpeakTurbo,     (100 * $RMax / $rpeakTurbo))
Write-Host ("a frecuencia MEDIDA  : {0,6:N1} GFLOPS  -> eficiencia {1,5:N1}%" -f $rpeakSostenido, (100 * $RMax / $rpeakSostenido))
Write-Host ""
Write-Host "Muestras crudas en resultados\frecuencia\$Etiqueta\muestras.csv"
