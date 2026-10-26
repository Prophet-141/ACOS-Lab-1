# ============================================================
# ACOS Lab 1 - Windows Version (PowerShell)
# ============================================================
if ($args.Count -ne 3) {
    Write-Host "Usage: .\win_archiver.ps1 <path> <threshold_%> <files_count>" -ForegroundColor Yellow
    exit 1
}

$LogDir = $args[0]
$Threshold = [int]$args[1]
$MFiles = [int]$args[2]
$BackupDir = "C:\backup"

if (-not (Test-Path $LogDir -PathType Container)) {
    Write-Host "ERROR: Directory '$LogDir' does not exist." -ForegroundColor Red
    exit 1
}

if ($Threshold -lt 0 -or $Threshold -gt 100) {
    Write-Host "ERROR: Threshold must be between 0 and 100." -ForegroundColor Red
    exit 1
}

if ($MFiles -le 0) {
    Write-Host "ERROR: Files count must be positive." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}

$DirSizeBytes = (Get-ChildItem -Path $LogDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
if ($null -eq $DirSizeBytes) { $DirSizeBytes = 0 }

$DriveLetter = (Get-Item $LogDir).PSDrive.Name
$Drive = Get-PSDrive -Name $DriveLetter
$TotalSizeBytes = $Drive.Used + $Drive.Free
$UsagePercent = ($DirSizeBytes / $TotalSizeBytes) * 100

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "Directory:          $LogDir"
Write-Host ("Dir Size:           {0:N2} MB" -f ($DirSizeBytes / 1MB))
Write-Host ("Total Size:         {0:N2} GB" -f ($TotalSizeBytes / 1GB))
Write-Host ("Usage Percent:      {0:N10} %" -f $UsagePercent)
Write-Host "Threshold (N):      $Threshold %"
Write-Host "======================================================" -ForegroundColor Cyan

if ($UsagePercent -gt ($Threshold + 0.0001)) {
    Write-Host ">>> Threshold EXCEEDED. Archiving $MFiles oldest files..." -ForegroundColor Green

    $OldestFiles = Get-ChildItem -Path $LogDir -Recurse -File | Sort-Object LastWriteTime | Select-Object -First $MFiles

    if ($null -eq $OldestFiles) {
        Write-Host "No files to archive."
        exit 0
    }

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $ArchiveName = "$BackupDir\backup_$Timestamp.zip"

    try {
        $OldFilesPaths = $OldestFiles.FullName
        Compress-Archive -Path $OldFilesPaths -DestinationPath $ArchiveName -Force
        Write-Host ">>> Archive created successfully: $ArchiveName" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Archive creation failed." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host ">>> Size is within limits. Archiving not required."
}