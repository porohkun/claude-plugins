<#
Приводит файлы к UTF-8 with BOM и переводам строк CRLF (требование эталона для cs, csproj, sln,
slnx и xaml). С -CheckOnly ничего не меняет, только перечисляет нарушения.

Без -Path обходит -Root (по умолчанию — корень git-репозитория текущей папки; вне репозитория
-Root обязателен) и берёт файлы, имя которых подходит под -Filter. Пропускаются скрытые файлы и
папки, ссылки на папки и папки .git, .vs, bin, obj, out, packages, node_modules.
-ExcludedDirs добавляет свои исключения: имя папки исключает её на любом уровне, путь от корня
(Папка/Подпапка) — только эту папку.

С -Path обрабатываются только перечисленные файлы и папки (пути — от текущей папки), -Root не
используется. Папки из -Path обходятся по тем же правилам. -Path и -ExcludedDirs принимают и
список через запятую одной строкой.

Файлы в нужном виде не перезаписываются. Похожие на бинарные (байты 0x00 без BOM UTF-16/UTF-32)
пропускаются. Файлы, которые не декодируются в своей кодировке (например, cp1251 без BOM), не
трогаются и попадают в ошибки.

Код выхода: 0 — всё в порядке; 1 — есть ошибки, а с -CheckOnly — ещё и нарушения.
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string[]]$Path = @(),
    [string]$Filter = '\.(cs|csproj|sln|slnx|xaml)$',
    [string[]]$ExcludedDirs = @(),
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'

trap {
    Write-Output "Ошибка: $($_.Exception.Message)"
    exit 1
}

# Перенаправленный вывод иначе уходит в OEM-кодировке консоли, и кириллица в нём не читается.
# Консоли может не быть вовсе — тогда переключать нечего.
if ([Console]::IsOutputRedirected) {
    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    } catch {
    }
}

function Get-ErrorText($errorRecord) {
    $exception = $errorRecord.Exception
    while ($exception.InnerException) {
        $exception = $exception.InnerException
    }

    $exception.Message
}

function Split-List([string[]]$values) {
    @($values | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-StartsWith([byte[]]$bytes, [byte[]]$prefix) {
    if ($bytes.Length -lt $prefix.Length) {
        return $false
    }

    for ($i = 0; $i -lt $prefix.Length; $i++) {
        if ($bytes[$i] -ne $prefix[$i]) {
            return $false
        }
    }

    return $true
}

function Find-RepoRoot {
    $dir = (Get-Location).ProviderPath
    while ($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir '.git')) {
            return $dir
        }

        $dir = [System.IO.Path]::GetDirectoryName($dir)
    }
}

# Исключения обхода
$excludedNames = @('.git', '.vs', 'bin', 'obj', 'out', 'packages', 'node_modules')
$excludedPaths = @()
foreach ($entry in (Split-List $ExcludedDirs)) {
    $dir = ($entry.Replace('/', '\') -replace '^(\.\\)+', '').Trim('\')
    if (-not $dir) {
        continue
    }

    if ($dir.Contains('\')) {
        $excludedPaths += $dir
    } else {
        $excludedNames += $dir
    }
}

$files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
$errors = New-Object System.Collections.Generic.List[string]

function Add-TreeFiles([string]$start) {
    $pending = New-Object System.Collections.Generic.Stack[object]
    $pending.Push(@($start, ''))
    while ($pending.Count -gt 0) {
        $dirPath, $dirRel = $pending.Pop()
        try {
            $items = @(Get-ChildItem -LiteralPath $dirPath)
        } catch {
            $errors.Add("$dirPath : не удалось прочитать папку: $(Get-ErrorText $_)")
            continue
        }

        foreach ($item in $items) {
            if (-not $item.PSIsContainer) {
                if ($item.Name -match $Filter) {
                    $files.Add($item)
                }

                continue
            }

            $rel = if ($dirRel) { "$dirRel\$($item.Name)" } else { $item.Name }
            if ($item.Name -in $excludedNames -or $rel -in $excludedPaths) {
                continue
            }

            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                continue
            }

            $pending.Push(@($item.FullName, $rel))
        }
    }
}

# Сбор файлов
$pathEntries = Split-List $Path
if ($pathEntries.Count -gt 0) {
    foreach ($entry in $pathEntries) {
        $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($entry)
        if ([System.IO.Directory]::Exists($full)) {
            Add-TreeFiles $full
        } elseif ([System.IO.File]::Exists($full)) {
            if ([System.IO.Path]::GetFileName($full) -match $Filter) {
                $files.Add((New-Object System.IO.FileInfo -ArgumentList $full))
            }
        } else {
            $errors.Add("$entry : не найден")
        }
    }
} else {
    if (-not $Root) {
        $Root = Find-RepoRoot
        if (-not $Root) {
            Write-Output 'Текущая папка не в git-репозитории: укажи -Root или -Path.'
            exit 1
        }
    }

    try {
        $rootPath = (Resolve-Path -LiteralPath $Root).ProviderPath
    } catch {
        Write-Output "Корень не найден: $Root"
        exit 1
    }

    Add-TreeFiles $rootPath
}

# Проверка и исправление
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$knownBoms = @(
    @{ Name = 'UTF-8'; Bom = [byte[]](0xEF, 0xBB, 0xBF); Encoding = (New-Object System.Text.UTF8Encoding($false, $true)) },
    @{ Name = 'UTF-32 LE'; Bom = [byte[]](0xFF, 0xFE, 0x00, 0x00); Encoding = (New-Object System.Text.UTF32Encoding($false, $false, $true)) },
    @{ Name = 'UTF-32 BE'; Bom = [byte[]](0x00, 0x00, 0xFE, 0xFF); Encoding = (New-Object System.Text.UTF32Encoding($true, $false, $true)) },
    @{ Name = 'UTF-16 LE'; Bom = [byte[]](0xFF, 0xFE); Encoding = (New-Object System.Text.UnicodeEncoding($false, $false, $true)) },
    @{ Name = 'UTF-16 BE'; Bom = [byte[]](0xFE, 0xFF); Encoding = (New-Object System.Text.UnicodeEncoding($true, $false, $true)) }
)
$utf8Strict = $knownBoms[0].Encoding

$violations = New-Object System.Collections.Generic.List[string]
$binary = New-Object System.Collections.Generic.List[string]
$checked = 0
$changed = 0

foreach ($file in ($files | Sort-Object -Property FullName -Unique)) {
    $filePath = $file.FullName
    $checked++
    try {
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
    } catch {
        $errors.Add("$filePath : не удалось прочитать: $(Get-ErrorText $_)")
        continue
    }

    $bom = $knownBoms | Where-Object { Test-StartsWith $bytes $_.Bom } | Select-Object -First 1
    if (-not $bom -and [Array]::IndexOf($bytes, [byte]0) -ge 0) {
        $binary.Add($filePath)
        continue
    }

    $encodingName = if ($bom) { $bom.Name } else { 'UTF-8' }
    $encoding = if ($bom) { $bom.Encoding } else { $utf8Strict }
    $offset = if ($bom) { $bom.Bom.Length } else { 0 }
    try {
        $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    } catch {
        $errors.Add("$filePath : не читается как $encodingName, перекодируй вручную")
        continue
    }

    $problems = @()
    if (-not $bom) {
        $problems += 'нет BOM'
    } elseif ($bom.Name -ne 'UTF-8') {
        $problems += "$($bom.Name) вместо UTF-8"
    }

    $normalized = [regex]::Replace($text, '\r\n?|\n', "`r`n")
    if (-not [string]::Equals($normalized, $text, [System.StringComparison]::Ordinal)) {
        $problems += 'переводы строк не CRLF'
    }

    if ($problems.Count -eq 0) {
        continue
    }

    $description = $problems -join ', '
    if ($CheckOnly) {
        $violations.Add("$filePath : $description")
        continue
    }

    try {
        [System.IO.File]::WriteAllText($filePath, $normalized, $utf8Bom)
        $changed++
        Write-Output "исправлено: $filePath ($description)"
    } catch {
        $errors.Add("$filePath : не удалось записать: $(Get-ErrorText $_)")
    }
}

# Итог
if ($violations.Count -gt 0) {
    Write-Output 'Нарушения:'
    foreach ($line in $violations) {
        Write-Output "  $line"
    }
}

if ($binary.Count -gt 0) {
    Write-Output 'Пропущены, похожи на бинарные:'
    foreach ($line in $binary) {
        Write-Output "  $line"
    }
}

if ($errors.Count -gt 0) {
    Write-Output 'Ошибки:'
    foreach ($line in $errors) {
        Write-Output "  $line"
    }
}

$result = if ($CheckOnly) { "нарушений: $($violations.Count)" } else { "исправлено: $changed" }
Write-Output "Проверено файлов: $checked, $result, ошибок: $($errors.Count)."

if ($errors.Count -gt 0 -or $violations.Count -gt 0) {
    exit 1
}

exit 0
