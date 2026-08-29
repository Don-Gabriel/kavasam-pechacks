$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$cloudRoot = Join-Path $projectRoot 'cloud'
$mobileRoot = Join-Path $projectRoot 'mobile'
$python = Join-Path $cloudRoot '.venv\Scripts\python.exe'
$adb = 'C:\Android\Sdk\platform-tools\adb.exe'
$gatewayUrl = 'http://127.0.0.1:8080'

if (-not (Test-Path -LiteralPath $python)) {
    throw 'Gateway environment is missing. Run: python -m venv cloud\.venv'
}
if (-not (Test-Path -LiteralPath $adb)) {
    throw "ADB was not found at $adb"
}

$gateway = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
if (-not $gateway) {
    Start-Process `
        -FilePath $python `
        -ArgumentList @('-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', '8080') `
        -WorkingDirectory $cloudRoot `
        -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

$health = Invoke-RestMethod -Uri "$gatewayUrl/health"
Write-Host "Gateway ready. Gemini configured: $($health.geminiConfigured)"

$device = (& $adb devices) | Select-String "\tdevice$" | Select-Object -First 1
if (-not $device) {
    throw 'No Android phone is connected. Reconnect USB, enable USB debugging, and run this script again.'
}
$serial = ($device.ToString() -split "\t")[0]

& $adb -s $serial reverse tcp:8080 tcp:8080

$buildTemp = Join-Path $projectRoot '.jtmp'
New-Item -ItemType Directory -Force -Path $buildTemp | Out-Null
$env:TEMP = $buildTemp
$env:TMP = $buildTemp

Push-Location $mobileRoot
try {
    flutter build apk --debug --dart-define="KAVASAM_AI_BASE_URL=$gatewayUrl"
    & $adb -s $serial install -r 'build\app\outputs\flutter-apk\app-debug.apk'
    & $adb -s $serial shell cmd role add-role-holder android.app.role.DIALER app.kavasam.kavasam_mobile
    & $adb -s $serial shell cmd role add-role-holder android.app.role.CALL_SCREENING app.kavasam.kavasam_mobile
    & $adb -s $serial shell am force-stop app.kavasam.kavasam_mobile
    & $adb -s $serial shell am start -n app.kavasam.kavasam_mobile/.MainActivity
} finally {
    Pop-Location
}

Write-Host 'Kavasam Hybrid is installed. Enable Optional cloud AI and Community caller ID under Insights.'
