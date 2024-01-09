param(
    [switch]$InitialSetup,
    [switch]$Backup,
    [switch]$HDR,
    [Switch]$Ult
)

# Welcome text.
Write-Host "===== Yuzu Smash Manager ====="
Write-Host "Initializing...`n"

# --- Variables ---
# ---- Paths & Filesnames ----
# TODO: Write functions to locate installations.
$yuzuDataPath = "$env:USERPROFILE\AppData\Roaming\yuzu"
$yuzuInstallationPath = "$env:USERPROFILE\AppData\Local\yuzu"
$ysmDataPath = "$env:USERPROFILE\AppData\Roaming\Yuzu_Smash_Manager"
$ysmBackupPath = "$ysmDataPath\backup"
$ysmLogPath = "$ysmDataPath\Yuzu_Smash_Manager_log.txt"
$archivePath = "$ysmDataPath\archives"
$dependenciesPath = "$archivePath\dependencies"
$sevenZipPath = 'C:\Program Files\7-Zip\7z.exe'

# ---- URLs ----
# ----- File URLs -----
# NOTE: Eventually the URL download system will be a secondary, backup system.
#   Yuzu Smash Manager will prefer to grab files from the repo.
$ldnAllInOneUrl = "https://cdn.discordapp.com/attachments/1121103766960226496/1188253223761485966/LDN_all_in_one_package.zip?ex=6599da0d&is=6587650d&hm=e3cea7384dad56f144346478b881e8439d16c43d94dc7964edab3b399f0a82fe&"
$legacyDiscoveryUrl = "https://cdn.discordapp.com/attachments/890851835349446686/1191740302566891581/legacy_discovery?ex=65a689a5&is=659414a5&hm=b19cb9b22f67d4ca97da49b3b51c9242be57fb2124e74a894d072260225576fd&"
$saveDataUrl = "https://cdn.discordapp.com/attachments/890851835349446686/1191073579727597589/save_data.rar?ex=65a41cb6&is=6591a7b6&hm=635a5a953b6c7ce64d4dd6b2dbf6b280ed29dbce5f001bafd99c6486004db965&"
$wifiFixUrl = "https://drive.usercontent.google.com/download?id=1f_idi29L7Poxg0Cljbi4oz9ubpukmdXY&export=download"

# Only static files; dynamic links added below.
$fileUrls = @(
    "$ldnAllInOneUrl",
    "$legacyDiscoveryUrl",
    "$saveDataUrl",
    "$wifiFixUrl"
)

# ----- Page URLs -----
$yuzuDownloadPage = "https://yuzu-emu.org/downloads/#windows"
$msVisualDownloadPage = "$yuzuDownloadPage"
$7zipDownloadPage = "https://www.7-zip.org/"


# --- Functions ---
# ---- Handle-Error ----
function Handle-Error {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$LogPath
    )

    # Advanced logging.
    $errorMessage = "ERROR: $($ErrorRecord.Exception.GetType().FullName)"
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timeStamp - $($ErrorRecord.Exception.Message) - $errorMessage - $($ErrorRecord.ScriptStackTrace) - $ErrorRecord."
    $logMessage | Out-File -FilePath $LogPath -Append

    # Handle error.
    switch ($ErrorRecord.Exception.GetType().FullName) {
        "System.Net.WebException" {
            Write-Host "ERROR: Network error occurred. Double check your connection and try again.`n  NOTE: If connection is fine, the file probably no longer exists; ask Null for a copy."

            # Investigation code here.

            exit 1
        }
        default {
            Write-Host "ERROR: Unknown error occured.`n  Check the log at $LogPath"
            exit 1
        }
    }
}

# ---- Get-LatestHdrReleaseUrl ----
function Get-LatestHdrReleaseUrl {
    param(
        [string]$RepoOwner,
        [string]$RepoName,
        [string]$AssetName
    )

    $apiUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"

    try {
        $latestRelease = Invoke-WebRequest -Uri "$apiUrl" -Headers @{ "User-Agent" = "PowerShell" } -UseBasicParsing | ConvertFrom-Json
    } catch {
        Write-Host "Error accessing HDR GitHub API."
        Handle-Error -ErrorRecord $_ -LogPath "$ysmLogPath"
    }

    # Find asset.
    foreach ($asset in $latestRelease.assets) {
        if ($asset.name -eq $AssetName) {
            return $asset.browser_download_url
        }
    }

    Write-Host "Asset $AssetName not found in latest release."
    return $null
}

# ---- Get-LatestYuzuRelease ----
function Get-LatestYuzuRelease {
    param(
        [Parameter(Mandatory=$true)]
        [string]$YuzuUrl
    )

    # TODO: Examine edge cases and determine if returning null will be necessary at any point.

    try {
        $scrapedLinks = (Invoke-WebRequest "$YuzuUrl").Links.Href | Get-Unique
    } catch {
        Write-Host "Error grabbing Yuzu page."
        Handle-Error -ErrorRecord $_ -LogPath "$ysmLogPath"
    }

    $linksArray = -Split "$scrapedLinks"
    $yuzuDownloadLink = $linksArray.Where({$_ -like '*yuzu_install.exe'})

    return "$yuzuDownloadLink"
}

# ---- Get-LatestMSVisual ----
function Get-LatestMSVisualRelease {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VisualUrl
    )

    try {
        $scrapedLinks = (Invoke-WebRequest "$VisualUrl").Links.Href | Get-Unique
    } catch {
        Write-Host "Error grabbing MS Visual page."
        Handle-Error -ErrorRecord $_ -LogPath "$ysmLogPath"
    }

    $linksArray = -Split "$scrapedLinks"
    $msVisualDownloadLink = $linksArray.Where({$_ -like '*aka.ms/*vc_redist.x64.exe'})

    return "$msVisualDownloadLink"
}

# ---- Get-Latest7zipRelease ----
function Get-Latest7zipRelease {
    param(
        [Parameter(Mandatory=$true)]
        [string]$7ZipUrl
    )

    # Hard coding website for now due to unexplained `-7ZipUrl` error.
    $7ZipUrl = "https://www.7-zip.org/"

    try {
        $scrapedLinks = (Invoke-WebRequest "$7ZipUrl").Links.Href | Get-Unique
    }
    catch {
        Write-Host "Error grabbing 7Zip page."
        Handle-Error -ErrorRecord $_ -LogPath "$ysmLogPath"
    }

    $linksArray = -Split "$scrapedLinks"
    $7zipDownloadLink = $linksArray.Where({$_ -like 'a/*-x64.exe'})
    $7zipDownloadLink = "$7ZipUrl" + "$7zipDownloadLink"


    return "$7zipDownloadLink"
}

# ---- Ensure-Files ----
function Ensure-Files {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Urls,
        [Parameter(Mandatory=$true)]
        [string]$DownloadDir
    )

    # Skipped ensuring directory as it will always exist

    foreach ($url in $Urls) {
        $fileName = [System.IO.Path]::GetFileName("$url").Split('?')[0]

        # Special handling of Google Drive file.
        if ($url -like "*drive.usercontent.google.com*") {
            $fileName = "Wifi-Fix (merge with current exef).zip"
        }

        $filePath = Join-Path -Path "$DownloadDir" -ChildPath "$fileName"

        Write-Host "$filePath"

        if (-not (Test-Path "$filePath")) {
            try {
                Write-Host "Downloading $fileName..."
                Invoke-WebRequest -Uri "$url" -OutFile "$filePath"
            } catch {
                Write-Host "Error downloading $fileName."
                Handle-Error -ErrorRecord $_ -LogPath "$ysmLogPath"
            }
        }
    }

    Write-Host "Files ensured."
}

# ---- Ensure-7zip ----
function Ensure-7zip {
    param(
        [string]$SevenZipPath,
        [string]$SevenZipInstallerPath
    )

    if (-not (Test-Path $SevenZipPath)) {
        Write-Host "7-Zip not installed. Opening installer."
        
        try {
            Start-Process -FilePath "$SevenZipInstallerPath" -Wait
        } catch {
            Write-Host "Error with 7Zip installer."
            Handle-Error -ErrorRecord $_ -LogPath "$ysmLogPath"
        }
    }
}

function Ensure-Yuzu {
    param(
        [string]$YuzuPath,
        [string]$YuzuInstallerPath
    )

    if (-not (Test-Path "$YuzuPath")) {
        Write-Host "yuzu is not installed. Opening installer..."

        try {
            Start-Process -FilePath "$YuzuInstallerPath" -Wait
        } catch {
            Write-Host "Error with yuzu installer."
            Handle-Error -ErrorRecord $_ -LogPath "$ysmLogPath"
        }
    }
}

# ---- Backup-YuzuFolder ----
function Backup-YuzuFolder {
    # Get filename, remove file.
    $tempFile = [System.IO.Path]::GetTempFileName()
    Remove-Item $tempFile -Force

    # Get current date and time for backup filename
    $backupName = (Get-Date -Format "yyyy-MM-dd_HH-mm-ss") + "_yuzu.tar"

    try {
        Write-Host "`nStarting backup..."
        Start-Process -FilePath "$sevenZipPath" -ArgumentList "a -ttar `"$tempFile`" `"$yuzuDataPath`"" -NoNewWindow -Wait
        Write-Host "`nDone."
    } catch {
        Write-Host "Error creating backup of yuzu folder."
        Handle-Error -ErrorRecord $_ -LogPath "$ysmLogPath"
    }

    try {
        Write-Host "Moving to backup location: $ysmBackupPath"
        Move-Item -Path "$tempFile" -Destination "$ysmBackupPath\$backupName"
    } catch {
        Write-Host "Error moving backup to Yuzu Manager backup folder."
        Handle-Error -ErrorRecord $_ -LogPath "$ysmLogPath"
    }
}


# --- Initial Setup ---
# Create directories as necessary.
try {
    New-Item -ItemType Directory -Path "$ysmDataPath" -Force | Out-Null
    New-Item -ItemType Directory -Path "$archivePath" -Force | Out-Null
    New-Item -ItemType Directory -Path "$dependenciesPath" -Force | Out-Null
    New-Item -ItemType Directory -Path "$archivePath\created" -Force | Out-Null
    New-Item -ItemType Directory -Path "$ysmBackupPath" -Force | Out-Null
} catch {
    Write-Host "Error creating necessary folders."
    Handle-Error -ErrorRecord $_ -LogPath "$ysmLogPath"
}


# --- Last-Minute Variable Overrides ---
# Probably not fantastic practice, but it'll work for our purposes, for now.
# ---- 7Zip Installer Basename Fix ----
$sevenZipInstallerBasename = Get-Latest7zipRelease -7ZipUrl "$7zipDownloadPage"
$sevenZipInstallerBasename = [System.IO.Path]::GetFileName("$sevenZipInstallerBasename")
$sevenZipInstallerPath = "$dependenciesPath\$sevenZipInstallerBasename"

$yuzuInstallerBasename = Get-LatestYuzuRelease -YuzuUrl "$yuzuDownloadPage"
$yuzuInstallerBasename = [System.IO.Path]::GetFileName("$yuzuInstallerBasename")
$yuzuInstallerPath = "$dependenciesPath\$yuzuInstallerBasename"

# --- Run ---
# ---- Always ----
# ----- Add Dynamic URLs -----
$latestHdrUrl = Get-LatestHdrReleaseUrl -RepoOwner "HDR-Development" -RepoName "HDR-Releases" -AssetName "ryujinx-package.zip"
if ($latestHdrUrl) {
    $fileUrls += "$latestHdrUrl"
}

$latestYuzuUrl = Get-LatestYuzuRelease -YuzuUrl "$yuzuDownloadPage"
if ($latestYuzuUrl) {
    $fileUrls += "$latestYuzuUrl"
}

$latest7ZipUrl = Get-Latest7zipRelease -7ZipUrl "$7zipDownloadPage"
if ($latest7ZipUrl) {
    $fileUrls += "$latest7ZipUrl"
}

$latestMSVisualUrl = Get-LatestMSVisualRelease -VisualUrl "$msVisualDownloadPage"
if ($latestMSVisualUrl) {
    $fileUrls += "$latestMSVisualUrl"
}

# ---- Ensure Dependencies ----
Ensure-Files -Urls $fileUrls -DownloadDir "$dependenciesPath"
Ensure-7zip -SevenZipPath "$sevenZipPath" -SevenZipInstallerPath "$sevenZipInstallerPath"
Ensure-Yuzu -YuzuPath "$yuzuInstallationPath" -YuzuInstallerPath "$yuzuInstallerPath"

# ---- Switches ----
# if ($InitialSetup) {

# }

if ($Backup) {
    Backup-YuzuFolder
}

# --- End ---
Write-Host "`nPress any key to finish..."
# Keep open for invokation from file manager.
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
