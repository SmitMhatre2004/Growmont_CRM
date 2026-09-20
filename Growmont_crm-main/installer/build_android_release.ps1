<#
.SYNOPSIS
    Growmont CRM Android release pipeline.

.DESCRIPTION
    The Android counterpart to build_release.ps1, following the same shape:

      1. Read the version from flutterapp/pubspec.yaml (single source of
         truth — see RELEASE.md).
      2. Enforce the two Android-specific release rules that Windows does
         not have (see "Version rules" below). This is the step that
         catches a re-released version before it reaches users.
      3. flutter clean / pub get / build apk --release
      4. Verify the built APK's real versionCode and versionName (read
         from Gradle's output-metadata.json) match pubspec.yaml.
      5. Verify the APK is signed with the release keystore — not the
         debug key — by comparing certificate fingerprints.
      6. Package as installer/Output/growmont-<version>.apk with a
         SHA-256 sibling, matching the name UpdateService looks for.
      7. Record the released versionCode/versionName in the ledger.

.PARAMETER AllowSameVersionName
    Permit packaging a versionName that has already been released. Off by
    default because the in-app updater compares versionName: re-releasing
    the same one produces an APK that no existing install will ever be
    prompted to download. Only useful for rebuilding an artifact you have
    not actually published yet.

.PARAMETER SkipSignatureCheck
    Skip the certificate-fingerprint verification in step 5. Not
    recommended — that check is what would catch a debug-signed APK, which
    cannot be installed over a release-signed one.

.EXAMPLE
    .\installer\build_android_release.ps1
#>

[CmdletBinding()]
param(
    [switch]$AllowSameVersionName,
    [switch]$SkipSignatureCheck
)

$ErrorActionPreference = 'Stop'

# ── Paths ────────────────────────────────────────────────────────────────
$InstallerDir = $PSScriptRoot
$RepoRoot     = Split-Path -Parent $InstallerDir
$AppDir       = Join-Path $RepoRoot 'flutterapp'
$PubspecPath  = Join-Path $AppDir 'pubspec.yaml'
$AndroidDir   = Join-Path $AppDir 'android'
$KeyPropsPath = Join-Path $AndroidDir 'key.properties'
$LedgerPath   = Join-Path $AndroidDir 'released_version_codes.txt'
$OutputDir    = Join-Path $InstallerDir 'Output'

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Fail {
    param([string]$Message)
    Write-Host ""
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

# ── 1. Read version from pubspec.yaml ───────────────────────────────────
Write-Step "Reading version from pubspec.yaml"

if (-not (Test-Path $PubspecPath)) {
    Fail "pubspec.yaml not found at $PubspecPath"
}

$versionMatch = Select-String -Path $PubspecPath -Pattern '^version:\s*(\S+)' |
    Select-Object -First 1

if (-not $versionMatch) {
    Fail "Could not find a top-level 'version:' line in $PubspecPath"
}

$fullVersion = $versionMatch.Matches[0].Groups[1].Value.Trim()   # e.g. "1.1.0+2"

# Unlike Windows, Android genuinely needs the build number: it becomes
# versionCode, which is the only thing the OS uses to decide whether an
# APK is an upgrade. A bare "1.1.0" would silently become versionCode 1.
if ($fullVersion -notmatch '^(\d+\.\d+\.\d+)\+(\d+)$') {
    Fail @"
Version '$fullVersion' in pubspec.yaml is missing the build number.
Android release builds require the MAJOR.MINOR.PATCH+BUILD form (e.g.
1.1.0+2) -- the part after '+' becomes versionCode.
"@
}

$versionName = $Matches[1]              # e.g. "1.1.0"
$versionCode = [int]$Matches[2]         # e.g. 2

Write-Host "pubspec.yaml version : $fullVersion"
Write-Host "versionName (APK name): $versionName"
Write-Host "versionCode (upgrade key): $versionCode"

# ── 2. Version rules ─────────────────────────────────────────────────────
#
# Rule A: versionCode must strictly increase. Android compares versionCode
#         to decide whether an APK is an upgrade; a lower one is rejected
#         outright as INSTALL_FAILED_VERSION_DOWNGRADE, and an equal one
#         reinstalls without being treated as an update.
#
# Rule B: versionName must not repeat. UpdateService._isNewer() compares
#         versionName strings, so a re-released 1.1.0 is not "newer" than
#         an installed 1.1.0 -- nobody is ever prompted, on either
#         platform. This is the failure that looks like "the updater is
#         broken" when the release itself is the problem.
Write-Step "Checking version against previously released builds"

$releasedCodes = @()
$releasedNames = @()
$lastEntry     = $null

if (Test-Path $LedgerPath) {
    foreach ($line in (Get-Content $LedgerPath)) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -match '^(\d+)\s+(\S+)') {
            $releasedCodes += [int]$Matches[1]
            $releasedNames += $Matches[2]
            $lastEntry = @{ Code = [int]$Matches[1]; Name = $Matches[2] }
        }
    }
}

# Suggested next values, used in the failure messages below.
$nameParts = $versionName -split '\.'
$nextPatchName = "$($nameParts[0]).$($nameParts[1]).$([int]$nameParts[2] + 1)"

# Rebuilding the most recent entry unchanged is normal and allowed: you
# build, install on a device, find a problem, and build again before
# anything is published. Only the ledger's newest entry qualifies, and it
# is not recorded twice.
$isRebuildOfLatest = $false
if ($null -ne $lastEntry -and
    $lastEntry.Code -eq $versionCode -and
    $lastEntry.Name -eq $versionName) {
    $isRebuildOfLatest = $true
}

if ($releasedCodes.Count -eq 0) {
    Write-Host "No previous Android releases recorded -- this is the first."
} elseif ($isRebuildOfLatest) {
    Write-Host "Rebuilding $versionName ($versionCode), the most recent entry." -ForegroundColor Yellow
    Write-Host "If it was already published, bump the version instead." -ForegroundColor Yellow
} else {
    $highestCode = ($releasedCodes | Measure-Object -Maximum).Maximum
    Write-Host "Highest released versionCode: $highestCode"

    if ($versionCode -le $highestCode) {
        Fail @"
versionCode $versionCode has already been used (highest: $highestCode).

Android will refuse to install this APK over an existing install -- the
package installer treats a versionCode that is not strictly greater as a
downgrade or a plain reinstall, never an update.

Fix: bump the number after '+' in pubspec.yaml, e.g.
    version: $nextPatchName+$($highestCode + 1)

This is independent of versionName: even when re-releasing the same
user-facing version, the build number must still go up.
"@
    }

    if ($releasedNames -contains $versionName -and -not $AllowSameVersionName) {
        Fail @"
versionName '$versionName' has already been released.

The in-app updater compares versionName, not versionCode
(UpdateService._isNewer). Publishing '$versionName' a second time means
every existing install compares '$versionName' against '$versionName',
finds nothing newer, and never shows the update prompt -- on Windows as
well as Android. The release would reach only people installing fresh.

Fix: bump the patch version in pubspec.yaml, e.g.
    version: $nextPatchName+$versionCode

Re-run with -AllowSameVersionName only to rebuild an artifact you have
not actually published yet.
"@
    }

    if ($releasedNames -contains $versionName) {
        Write-Host "versionName '$versionName' reused (-AllowSameVersionName)." -ForegroundColor Yellow
        Write-Host "Existing installs will NOT be prompted to update." -ForegroundColor Yellow
    }
}

# ── Signing credentials must be present ─────────────────────────────────
if (-not (Test-Path $KeyPropsPath)) {
    Fail @"
android/key.properties not found.

It holds the release signing credentials and is gitignored by design, so
it does not arrive with a fresh clone. Restore it and growmont-release.jks
from your backup before building a release. See ANDROID_RELEASE.md.
"@
}

# ── 3. Clean Flutter Android release build ──────────────────────────────
Push-Location $AppDir
try {
    Write-Step "flutter clean"
    flutter clean
    if ($LASTEXITCODE -ne 0) { Fail "flutter clean failed" }

    Write-Step "flutter pub get"
    flutter pub get
    if ($LASTEXITCODE -ne 0) { Fail "flutter pub get failed" }

    # A single universal APK, not --split-per-abi: the download button on
    # the website is one link, and picking the right ABI is not something
    # to ask a user to do. The size cost is acceptable for sideloading.
    Write-Step "flutter build apk --release"
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { Fail "flutter build apk --release failed" }
} finally {
    Pop-Location
}

$ApkPath = Join-Path $AppDir 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $ApkPath)) {
    Fail "Expected APK not found at $ApkPath"
}

# ── 4. Verify the built APK's embedded version ──────────────────────────
# Gradle writes the real values it compiled into the APK here, so this
# catches a stale or mis-configured build the same way the Windows
# pipeline's FileVersion check does.
Write-Step "Verifying APK versionCode/versionName"

$MetadataPath = Join-Path $AppDir 'build\app\outputs\apk\release\output-metadata.json'
if (-not (Test-Path $MetadataPath)) {
    Fail "output-metadata.json not found at $MetadataPath -- cannot verify the built APK's version."
}

$metadata = Get-Content $MetadataPath -Raw | ConvertFrom-Json
$element = $metadata.elements | Select-Object -First 1

if ($null -eq $element) {
    Fail "output-metadata.json contained no build elements."
}

$builtCode = [int]$element.versionCode
$builtName = [string]$element.versionName

if ($builtCode -ne $versionCode -or $builtName -ne $versionName) {
    Fail @"
The built APK does not match pubspec.yaml.
  pubspec.yaml : $versionName ($versionCode)
  built APK    : $builtName ($builtCode)
Do not publish this build. This usually means flutter clean did not take
effect; re-run and confirm build/ was actually removed.
"@
}

Write-Host "APK reports $builtName ($builtCode) -- matches pubspec.yaml."

# ── 5. Verify the signing certificate ───────────────────────────────────
# The failure this guards against is shipping a debug-signed APK. Android
# will not install an update signed by a different key than the installed
# app, and the recovery is uninstall-first -- which destroys the user's
# local growmont.db. Comparing fingerprints proves the APK carries the
# same certificate as the release keystore.
if (-not $SkipSignatureCheck) {
    Write-Step "Verifying APK signing certificate"

    $buildToolsRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk\build-tools'
    $apkSigner = $null
    if (Test-Path $buildToolsRoot) {
        $apkSigner = Get-ChildItem $buildToolsRoot -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
    }

    if (-not $apkSigner) {
        Fail "apksigner not found under $buildToolsRoot. Install Android SDK build-tools, or re-run with -SkipSignatureCheck to bypass (not recommended)."
    }

    $signerOutput = & $apkSigner verify --print-certs $ApkPath
    if ($LASTEXITCODE -ne 0) {
        Fail "apksigner could not verify $ApkPath -- the APK may be unsigned."
    }

    $apkDigestLine = $signerOutput |
        Where-Object { $_ -match 'Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F]+)' } |
        Select-Object -First 1
    if (-not $apkDigestLine) {
        Fail "Could not read the signing certificate digest from apksigner output."
    }
    $apkDigest = ([regex]::Match($apkDigestLine, '([0-9a-fA-F]{64})')).Value.ToLower()

    # Read the expected fingerprint out of the keystore itself.
    $keyProps = @{}
    foreach ($line in (Get-Content $KeyPropsPath)) {
        if ($line -match '^\s*([^#=]+?)\s*=\s*(.*)$') {
            $keyProps[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }

    $storeFile = Join-Path $AndroidDir $keyProps['storeFile']
    if (-not (Test-Path $storeFile)) {
        Fail "Keystore not found at $storeFile (from key.properties)."
    }

    $keytoolOutput = & keytool -list -v `
        -keystore $storeFile `
        -alias $keyProps['keyAlias'] `
        -storepass $keyProps['storePassword'] 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail "keytool could not read the keystore -- check the credentials in key.properties."
    }

    $keystoreDigestLine = $keytoolOutput |
        Where-Object { $_ -match 'SHA256:' } |
        Select-Object -First 1
    if (-not $keystoreDigestLine) {
        Fail "Could not read the SHA-256 fingerprint from the keystore."
    }
    $keystoreDigest = (($keystoreDigestLine -split 'SHA256:')[1] -replace '[^0-9a-fA-F]', '').ToLower()

    if ($apkDigest -ne $keystoreDigest) {
        Fail @"
The APK is NOT signed with the release keystore.

  APK certificate      : $apkDigest
  Release keystore     : $keystoreDigest

This is almost always a debug-signed build. Publishing it would produce an
APK that existing users cannot install over their current version, and the
only way out for them is uninstalling -- which deletes their local
growmont.db. Do not publish this build.
"@
    }

    Write-Host "APK is signed with the release keystore."
} else {
    Write-Host "Skipping signature verification (-SkipSignatureCheck)." -ForegroundColor Yellow
}

# ── 6. Package with the release naming convention ───────────────────────
# The filename is load-bearing: UpdateService matches assets by the
# `growmont-<version>.apk` prefix/extension pair declared in
# version_constants.dart. A differently-named asset is silently invisible
# to the updater.
Write-Step "Packaging release artifact"

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$releaseApkPath = Join-Path $OutputDir "growmont-$versionName.apk"
Copy-Item $ApkPath $releaseApkPath -Force

$hash = (Get-FileHash -Algorithm SHA256 $releaseApkPath).Hash.ToLower()
$checksumPath = "$releaseApkPath.sha256"
Set-Content -Path $checksumPath -Value "$hash  $(Split-Path -Leaf $releaseApkPath)" -Encoding utf8

$sizeMb = [math]::Round((Get-Item $releaseApkPath).Length / 1MB, 1)
Write-Host "APK      : $releaseApkPath ($sizeMb MB)"
Write-Host "Checksum : $checksumPath"

# ── 7. Record the release ───────────────────────────────────────────────
Write-Step "Recording release in ledger"

if (-not (Test-Path $LedgerPath)) {
    $header = @(
        '# Android releases, oldest first: <versionCode> <versionName> <UTC date>',
        '#',
        '# Written by installer/build_android_release.ps1, which refuses to',
        '# package a versionCode at or below the highest listed here (Android',
        '# rejects it as a downgrade) or a versionName already listed (the',
        '# in-app updater would never prompt for it). Commit this file --',
        '# it is the record of what versionCodes are already in the wild.'
    )
    # ASCII, not utf8: Windows PowerShell 5.1's Set-Content -Encoding utf8
    # emits a BOM, which would show up as stray bytes at the head of a
    # committed, human-read file. The content here is ASCII by construction.
    Set-Content -Path $LedgerPath -Value $header -Encoding ascii
}

if ($isRebuildOfLatest) {
    Write-Host "Already recorded ($versionCode $versionName) -- not duplicating."
} else {
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    Add-Content -Path $LedgerPath -Value "$versionCode $versionName $stamp" -Encoding ascii
    Write-Host "Recorded: $versionCode $versionName $stamp"
}

Write-Step "Done"
Write-Host "Android release ready: $releaseApkPath" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. Install this APK on a real device and confirm it opens and syncs." -ForegroundColor Green
Write-Host "  2. Publish a GitHub release tagged v$versionName on CruciaTos/GrowmontCRM_Release." -ForegroundColor Green
Write-Host "  3. Upload the .apk and .sha256 (alongside the Windows .exe and its .sha256)." -ForegroundColor Green
Write-Host "  4. Commit the updated ledger: flutterapp/android/released_version_codes.txt" -ForegroundColor Green
