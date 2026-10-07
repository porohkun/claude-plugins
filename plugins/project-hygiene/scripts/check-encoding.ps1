<#
Проверяет файлы на UTF-8 with BOM и переводы строк CRLF (требование эталона), ничего не меняя:
печатает нарушения и возвращает ненулевой код, если они есть. Параметры и правила обхода — те же,
что у fix-encoding.ps1: -Root, -Path, -Filter, -ExcludedDirs.
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string[]]$Path,
    [string]$Filter,
    [string[]]$ExcludedDirs
)

& (Join-Path $PSScriptRoot 'fix-encoding.ps1') @PSBoundParameters -CheckOnly
exit $LASTEXITCODE
