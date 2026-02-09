<#
.SYNOPSIS
    Hello World round-trip test for the Copilot Studio Flow.

.DESCRIPTION
    Sends a simple { "name": "Frank" } payload to the HelloWorld Flow,
    receives a JSON greeting, and displays it.

    This proves: PowerShell -> HTTP -> Copilot Flow -> Prompt -> Response -> PowerShell

.PARAMETER Name
    The name to send in the greeting request. Defaults to "Frank".

.PARAMETER FlowUrl
    The HTTP trigger URL for the HelloWorld Flow in Copilot Studio / Power Automate.
    If not provided, reads from config/settings.json (HelloWorldFlowUrl).

.EXAMPLE
    .\Test-HelloWorld.ps1
    .\Test-HelloWorld.ps1 -Name "Alice"
    .\Test-HelloWorld.ps1 -FlowUrl "https://prod-XX.logic.azure.com/..."
#>

[CmdletBinding()]
param(
    [string]$Name = "Frank",
    [string]$FlowUrl
)

$ErrorActionPreference = "Stop"

# ── Resolve Flow URL ─────────────────────────────────────────────────────────
if (-not $FlowUrl) {
    $configPath = Join-Path $PSScriptRoot "..\config\settings.json"
    if (Test-Path $configPath) {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $FlowUrl = $config.HelloWorldFlowUrl
    }
}

if (-not $FlowUrl -or $FlowUrl -match "YOUR-.*-HERE") {
    Write-Host ""
    Write-Host "ERROR: No valid Flow URL configured." -ForegroundColor Red
    Write-Host ""
    Write-Host "To fix this:" -ForegroundColor Yellow
    Write-Host "  1. Create the HelloWorld Flow in Copilot Studio (see prompts/helloworld.txt for the prompt)."
    Write-Host "  2. Copy the HTTP trigger URL."
    Write-Host "  3. Either:"
    Write-Host "     a) Pass it directly:  .\Test-HelloWorld.ps1 -FlowUrl 'https://...'"
    Write-Host "     b) Set it in config/settings.json under 'HelloWorldFlowUrl'"
    Write-Host ""
    exit 1
}

# ── Build request ────────────────────────────────────────────────────────────
$body = @{ name = $Name } | ConvertTo-Json -Compress

Write-Host ""
Write-Host "=== Hello World Round-Trip Test ===" -ForegroundColor Cyan
Write-Host "  Flow URL : $($FlowUrl.Substring(0, [Math]::Min(60, $FlowUrl.Length)))..." -ForegroundColor DarkGray
Write-Host "  Payload  : $body"
Write-Host ""

# ── POST to Flow ─────────────────────────────────────────────────────────────
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

try {
    $response = Invoke-RestMethod `
        -Uri      $FlowUrl `
        -Method   POST `
        -Body     $body `
        -ContentType "application/json" `
        -TimeoutSec 30

    $stopwatch.Stop()

    Write-Host "SUCCESS  ($($stopwatch.ElapsedMilliseconds) ms)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Response:" -ForegroundColor Yellow
    $response | ConvertTo-Json -Depth 5 | Write-Host

    # ── Basic validation ─────────────────────────────────────────────────
    $pass = $true

    if ($response.message) {
        Write-Host ""
        Write-Host "[PASS] Response has 'message' field: $($response.message)" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Response missing 'message' field" -ForegroundColor Red
        $pass = $false
    }

    if ($response.timestamp) {
        Write-Host "[PASS] Response has 'timestamp' field: $($response.timestamp)" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Response missing 'timestamp' field" -ForegroundColor Red
        $pass = $false
    }

    Write-Host ""
    if ($pass) {
        Write-Host "=== HELLO WORLD TEST PASSED ===" -ForegroundColor Green
    } else {
        Write-Host "=== HELLO WORLD TEST FAILED (unexpected response shape) ===" -ForegroundColor Red
    }
}
catch {
    $stopwatch.Stop()
    Write-Host "FAILED  ($($stopwatch.ElapsedMilliseconds) ms)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red

    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
        Write-Host "HTTP Status: $statusCode" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  - Is the Flow URL correct and active?"
    Write-Host "  - Does the Flow accept POST with Content-Type: application/json?"
    Write-Host "  - Check the Flow run history in Power Automate for errors."
    exit 1
}
