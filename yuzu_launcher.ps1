param(
    [switch]$InitialSetup,
    [switch]$HDR,
    [Switch]$Ult
)

# --- Variables ---
# ---- Paths & Filesnames ----
$yuzuPath = "$env:USERPROFILE\AppData\Roaming\yuzu"
$yuzuArchivePath = "$yuzuPath\archives"
$dependenciesPath = "$yuzuArchivePath\dependencies"
$sevenZipPath = "C:\Program Files\7-Zip\7z.exe"
$sevenZipInstallerBasename = "7z2301-x64.exe"
$sevenZipInstallerPath = "$dependenciesPath\$sevenZipInstallerBasename"

# ---- URLs ----
$sevenZipUrl = "https://www.7-zip.org/a/7z2301-x64.exe"
$ldnAllInOneUrl = "https://cdn.discordapp.com/attachments/1121103766960226496/1188253223761485966/LDN_all_in_one_package.zip?ex=6599da0d&is=6587650d&hm=e3cea7384dad56f144346478b881e8439d16c43d94dc7964edab3b399f0a82fe&"
$legacyDiscoveryUrl = "https://cdn.discordapp.com/attachments/890851835349446686/1191740302566891581/legacy_discovery?ex=65a689a5&is=659414a5&hm=b19cb9b22f67d4ca97da49b3b51c9242be57fb2124e74a894d072260225576fd&"
$saveDataUrl = "https://cdn.discordapp.com/attachments/890851835349446686/1191073579727597589/save_data.rar?ex=65a41cb6&is=6591a7b6&hm=635a5a953b6c7ce64d4dd6b2dbf6b280ed29dbce5f001bafd99c6486004db965&"
$wifiFixUrl = "https://drive.usercontent.google.com/download?id=1f_idi29L7Poxg0Cljbi4oz9ubpukmdXY&export=download"

# Only static files; HDR will be acquired dynamically so it always grabs the latest release. See Get-LatestHDRReleaseUrl.
$fileUrls = @(
    $sevenZipUrl,
    $ldnAllInOneUrl,
    $legacyDiscoveryUrl,
    $saveDataUrl,
    $wifiFixUrl
)

# --- Functions ---
# ---- Get-LatestHdrReleaseUrl ----
function Get-LatestHdrReleaseUrl {
    param(
        [string]$RepoOwner,
        [string]$RepoName,
        [string]$AssetName
    )

    $apiUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"

    try {
        $latestRelease = Invoke-WebRequest -Uri $apiUrl -Headers @{ "User-Agent" = "PowerShell" } -UseBasicParsing | ConvertFrom-Json

        # Find asset.
        foreach ($asset in $latestRelease.assets) {
            if ($asset.name -eq $AssetName) {
                return $asset.browser_download_url
            }
        }
        Write-Host "Asset $AssetName not found in latest release."
        return $null
    } catch {
        Write-Host "Error retrieving latest release: $_"
        return $null
    }
}

# ---- Ensure-Files ----
function Ensure-Files {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Urls,
        [Parameter(Mandatory=$true)]
        [string]$DownloadDir
        # [string]$SevenZipInstallerName
    )

    # Skipped ensuring directory as it will always exist

    foreach ($url in $Urls) {
        $fileName = [System.IO.Path]::GetFileName($url).Split('?')[0]

        # Special handling of Google Drive file.
        if ($url -like "*drive.usercontent.google.com*") {
            $fileName = "Wifi-Fix (merge with current exef).zip"
        }

        $filePath = Join-Path -Path $DownloadDir -ChildPath $fileName

        if (-not (Test-Path $filePath)) {
            Write-Host "Downloading $fileName..."
            Invoke-WebRequest -Uri $url -OutFile $filePath
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
        Write-Host "7-Zip not installed. Installing..."
        
        try {
            Write-Host "Starting installer..."
            Start-Process -FilePath $SevenZipInstallerPath -Wait
        } catch {
            Write-Host "Error when trying to launch installer."
            Write-Host "Installer likely does not exist."
        }
    }
}

# --- Initial Setup ---
# Create directories as necessary.
New-Item -ItemType Directory -Path "$yuzuArchivePath" -Force | Out-Null
New-Item -ItemType Directory -Path "$dependenciesPath" -Force | Out-Null
New-Item -ItemType Directory -Path "$yuzuArchivePath\created" -Force | Out-Null

# --- Run ---
# ---- Always ----
# Append latest HDR release to $fileUrls
$latestHdrUrl = Get-LatestHdrReleaseUrl -RepoOwner "HDR-Development" -RepoName "HDR-Releases" -AssetName "ryujinx-package.zip"
if ($latestHdrUrl) {
    $fileUrls += $latestHdrUrl
}

# Ensure dependencies
Ensure-Files -Urls $fileUrls -DownloadDir "$dependenciesPath"
Ensure-7zip -SevenZipPath "$sevenZipPath" -SevenZipInstallerPath "$sevenZipInstallerPath"

# ---- Switches ----
