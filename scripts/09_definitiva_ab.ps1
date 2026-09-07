<#
    NB = 160 contra NB = 192 a N = 30.000, alternando dentro de la misma sesion.

    Por que hace falta: dos corridas sueltas del 2026-09-07, en sesiones
    distintas, dieron 104,0 GFLOPS con NB=192 y 96,9 con NB=160. Pero entre
    sesiones esta maquina se mueve hasta un 56% con configuracion identica,
    asi que un 7% entre dos corridas unicas no prueba nada.

    El orden es A-B-B-A (160, 192, 192, 160) y no A-B-A-B: asi cada NB corre
    una vez temprano y una vez tarde, y la degradacion termica de la sesion
    queda repartida por igual entre los dos. Con A-B-A-B, A siempre correria
    en la posicion mas fria.

    Cada corrida usa 05_medir_frecuencia.ps1, que mide el RMAX y la frecuencia
    sostenida de la misma corrida y de ahi saca la eficiencia.

    Uso:  .\scripts\09_definitiva_ab.ps1
          .\scripts\09_definitiva_ab.ps1 -Pares 3 -Enfriar 180
#>

[CmdletBinding()]
param(
    [int]$Pares   = 2,
    [int]$N       = 30000,
    [int]$Enfriar = 120,        # segundos entre corridas
    [string]$Build = 'hpl-mkl'
)

$ErrorActionPreference = 'Stop'
$Raiz = Split-Path -Parent $PSScriptRoot

$orden = @()
foreach ($p in 1..$Pares) {
    # Par impar: 160 primero. Par par: 192 primero. Eso da A-B-B-A.
    if ($p % 2 -eq 1) { $orden += ,@(160, $p); $orden += ,@(192, $p) }
    else              { $orden += ,@(192, $p); $orden += ,@(160, $p) }
}

Write-Host "N=$N  build=$Build  pares=$Pares  ->  $($orden.Count) corridas"
Write-Host "Orden: $(($orden | ForEach-Object { $_[0] }) -join ' -> ')"
Write-Host "Cada corrida son ~3 minutos mas $Enfriar s de enfriamiento."
Write-Host ""

$i = 0
foreach ($item in $orden) {
    $nb  = $item[0]
    $par = $item[1]
    $i++
    $etiqueta = "ab_nb${nb}_par${par}"

    Write-Host "=========== corrida $i de $($orden.Count): NB=$nb (par $par) ==========="
    & (Join-Path $PSScriptRoot '05_medir_frecuencia.ps1') `
        -N $N -NB $nb -Build $Build -Etiqueta $etiqueta

    if ($i -lt $orden.Count) {
        Write-Host ""
        Write-Host "enfriando $Enfriar s..."
        Start-Sleep -Seconds $Enfriar
        Write-Host ""
    }
}

# ------------------------------------------------------------------ resumen
Write-Host ""
Write-Host "=================== RESUMEN ==================="
Write-Host ""
"{0,-16} {1,-10} {2,-10}" -f 'corrida', 'GFLOPS', 'segundos' | Write-Host
"-" * 40 | Write-Host

foreach ($item in $orden) {
    $nb  = $item[0]
    $par = $item[1]
    $log = Join-Path $Raiz "resultados\frecuencia\ab_nb${nb}_par${par}\corrida.txt"
    if (Test-Path $log) {
        $l = Select-String -Path $log -Pattern '^WR[0-9A-Za-z]+\s' -CaseSensitive | Select-Object -First 1
        if ($l) {
            $campos = ($l.Line -split '\s+')
            "{0,-16} {1,-10} {2,-10}" -f "NB=$nb par$par", $campos[-1], $campos[-2] | Write-Host
        }
    }
}

Write-Host ""
Write-Host "Detalle de cada corrida (frecuencia y eficiencia) en resultados\frecuencia\ab_nb*\"
