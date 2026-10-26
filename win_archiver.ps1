# ============================================================
# ACOS Lab 1 - Windows Version (PowerShell)
# ============================================================

# Проверяем, что передано 3 аргумента: путь, порог и количество файлов
if ($args.Count -ne 3) {
    Write-Host "Usage: .\win_archiver.ps1 <path> <threshold_%> <files_count>" -ForegroundColor Yellow
    exit 1
}

# Читаем аргументы командной строки
$LogDir = $args[0]
$Threshold = [int]$args[1]
$MFiles = [int]$args[2]
$BackupDir = "C:\backup"

# Проверяем, что указанный каталог существует
if (-not (Test-Path $LogDir -PathType Container)) {
    Write-Host "ERROR: Directory '$LogDir' does not exist." -ForegroundColor Red
    exit 1
}

# Порог должен быть в диапазоне 0–100 %
if ($Threshold -lt 0 -or $Threshold -gt 100) {
    Write-Host "ERROR: Threshold must be between 0 and 100." -ForegroundColor Red
    exit 1
}

# Количество файлов для должно быть положительным
if ($MFiles -le 0) {
    Write-Host "ERROR: Files count must be positive." -ForegroundColor Red
    exit 1
}

# Если нет каталога для резервных копий, то создаём его
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}

# Считаем размер всех файлов в каталоге рекурсивно
$DirSizeBytes = (Get-ChildItem -Path $LogDir -Recurse -File | Measure-Object -Property Length -Sum).Sum

# Если файлов нет, сумма будет $null, то заменяем её на 0.
if ($null -eq $DirSizeBytes) { $DirSizeBytes = 0 }

# Определяем диск, на котором находится каталог, и считаем его общий размер как сумму занятого и свободного места
$DriveLetter = (Get-Item $LogDir).PSDrive.Name
$Drive = Get-PSDrive -Name $DriveLetter
$TotalSizeBytes = $Drive.Used + $Drive.Free

# Вычисляем, какую часть диска занимает каталог
$UsagePercent = ($DirSizeBytes / $TotalSizeBytes) * 100

# Выводим исходные данные и рассчитанные значения
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "Directory:          $LogDir"
Write-Host ("Dir Size:           {0:N2} MB" -f ($DirSizeBytes / 1MB))
Write-Host ("Total Size:         {0:N2} GB" -f ($TotalSizeBytes / 1GB))
Write-Host ("Usage Percent:      {0:N10} %" -f $UsagePercent)
Write-Host "Threshold (N):      $Threshold %"
Write-Host "======================================================" -ForegroundColor Cyan

# Если доля каталога превышает порог — архивируем M самых старых файлов. 0.0001 - защита от погрешности вычислений с плавающей точкой
if ($UsagePercent -gt ($Threshold + 0.0001)) {
    Write-Host ">>> Threshold EXCEEDED. Archiving $MFiles oldest files..." -ForegroundColor Green
	
    # Сортируем файлы по времени последнего изменения и берём первые M штук
    $OldestFiles = Get-ChildItem -Path $LogDir -Recurse -File | Sort-Object LastWriteTime | Select-Object -First $MFiles
	
    # Если подходящих файлов нет, то не архивируем
    if ($null -eq $OldestFiles) {
        Write-Host "No files to archive."
        exit 0
    }

	# Формируем имя архива по текущей дате и времени
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $ArchiveName = "$BackupDir\backup_$Timestamp.zip"
	
	# Пытаемся создать ZIP-архив из выбранных файлов
    try {
        $OldFilesPaths = $OldestFiles.FullName
        Compress-Archive -Path $OldFilesPaths -DestinationPath $ArchiveName -Force
        Write-Host ">>> Archive created successfully: $ArchiveName" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Archive creation failed." -ForegroundColor Red
        exit 1
    }
} else {
	# Если размер каталога не превышен, то архивация не нужна.
    Write-Host ">>> Size is within limits. Archiving not required."
}