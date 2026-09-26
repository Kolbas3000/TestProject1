<#
.SYNOPSIS
    Разрешает git-конфликты во всех файлах проекта, оставляя выбранную сторону.
.DESCRIPTION
    Находит файлы с маркерами конфликтов (<<<<<<<, =======, >>>>>>>),
    один раз спрашивает пользователя, какую сторону оставить (Left/Ours/HEAD или Right/Theirs/Incoming),
    и применяет выбор ко всем найденным файлам.
.PARAMETER Root
    Корневая папка для поиска. По умолчанию — текущая.
.PARAMETER ExcludeDirs
    Папки, которые нужно пропустить (по умолчанию .git, Library, Temp, obj, Logs, Build, Builds, UserSettings).
.PARAMETER DryRun
    Только показать, что будет сделано, без записи.
.EXAMPLE
    .\Resolve-AllConflicts.ps1
.EXAMPLE
    .\Resolve-AllConflicts.ps1 -Root .\Assets -DryRun
#>
param(
    [string]$Root = (Get-Location).ProviderPath,

    [string[]]$ExcludeDirs = @(
        '.git', 'Library', 'Temp', 'obj', 'Logs', 'Build', 'Builds',
        'UserSettings', 'node_modules', '.vs', '.idea', 'packages'
    ),

    [switch]$DryRun
)

# --- Ввод пользователя ---
Write-Host "Какую сторону конфликта оставить?"
Write-Host "  [L] Left  (ours / HEAD / текущая ветка)"
Write-Host "  [R] Right (theirs / входящая ветка)"
$choice = Read-Host "Введите L или R (по умолчанию R)"

$keep = 'Right'
if ($choice -and $choice.Trim().ToUpper() -eq 'L') {
    $keep = 'Left'
}

Write-Host ""
Write-Host "Будет оставлена сторона: $keep" -ForegroundColor Cyan
Write-Host ""

# --- Поиск файлов с конфликтами ---
$rootFull = (Resolve-Path -LiteralPath $Root).ProviderPath

Write-Host "Сканирование: $rootFull"

$allFiles = Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force -ErrorAction SilentlyContinue

$conflictFiles = New-Object System.Collections.Generic.List[string]
$pattern = '^(<<<<<<< |=======$|>>>>>>> )'

foreach ($f in $allFiles) {
    # Пропускаем исключённые папки
    $skip = $false
    foreach ($ex in $ExcludeDirs) {
        if ($f.FullName -match [regex]::Escape("\$ex\")) { $skip = $true; break }
    }
    if ($skip) { continue }

    # Пропускаем бинарные/большие файлы по расширению
    if ($f.Extension -match '^\.(png|jpg|jpeg|gif|bmp|tga|exe|dll|so|dylib|zip|7z|rar|psd|fbx|assetbundle|unitypackage|meta)$') {
        continue
    }

    try {
        # Быстрая проверка: содержит ли файл маркеры
        $hasMarker = Select-String -LiteralPath $f.FullName -Pattern '^<<<<<<< ' -List -ErrorAction Stop
        if ($hasMarker) {
            $conflictFiles.Add($f.FullName)
        }
    } catch { }
}

if ($conflictFiles.Count -eq 0) {
    Write-Host "Файлов с конфликтами не найдено." -ForegroundColor Yellow
    return
}

Write-Host "Найдено файлов с конфликтами: $($conflictFiles.Count)" -ForegroundColor Yellow
foreach ($cf in $conflictFiles) {
    Write-Host "  $cf"
}
Write-Host ""

if ($DryRun) {
    Write-Host "DryRun: изменения не записаны." -ForegroundColor Yellow
    return
}

# --- Обработка файлов ---
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$totalBlocks = 0
$processed   = 0

foreach ($file in $conflictFiles) {
    try {
        # Определяем кодировку: пробуем UTF-8 без BOM, сохраняем в том же виде
        $bytes   = [System.IO.File]::ReadAllBytes($file)
        $hasBom  = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

        $lines = [System.IO.File]::ReadAllLines($file)
        $out   = New-Object System.Collections.Generic.List[string]
        $state = 'Normal'
        $fileBlocks = 0

        foreach ($line in $lines) {
            if ($line -match '^<<<<<<< ') {
                $state = 'Ours'
                continue
            }
            elseif ($line -match '^=======\s*$') {
                if ($state -eq 'Ours') { $state = 'Theirs' }
                continue
            }
            elseif ($line -match '^>>>>>>> ') {
                if ($state -eq 'Theirs') { $state = 'Normal'; $fileBlocks++ }
                continue
            }

            if ($state -eq 'Normal') {
                $out.Add($line)
            }
            elseif ($state -eq 'Ours' -and $keep -eq 'Left') {
                $out.Add($line)
            }
            elseif ($state -eq 'Theirs' -and $keep -eq 'Right') {
                $out.Add($line)
            }
        }

        # Записываем обратно
        if ($hasBom) {
            $enc = New-Object System.Text.UTF8Encoding($true)
        } else {
            $enc = $utf8NoBom
        }
        [System.IO.File]::WriteAllLines($file, $out, $enc)

        $totalBlocks += $fileBlocks
        $processed++
        Write-Host "OK: $file  (блоков: $fileBlocks)" -ForegroundColor Green
    }
    catch {
        Write-Host "ОШИБКА: $file — $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Готово. Обработано файлов: $processed из $($conflictFiles.Count), блоков: $totalBlocks" -ForegroundColor Cyan
Write-Host "Не забудьте выполнить: git add -A" -ForegroundColor Cyan