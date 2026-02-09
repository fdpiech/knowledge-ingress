<#
.SYNOPSIS
    Watches an inbox directory for new files, sends them to a Copilot Studio
    flow via Power Automate HTTP trigger, and writes the results to a
    knowledge repository.

.DESCRIPTION
    Polls the configured inbox path for files matching the filter pattern.
    Each new file is read, POSTed to a Power Automate HTTP trigger endpoint,
    and the response is written to the knowledge repo. Processed files are
    moved to an archive directory.

.PARAMETER ConfigPath
    Path to the JSON configuration file. Defaults to config.json in the
    script directory.

.PARAMETER Once
    Process any files currently in the inbox and exit instead of polling.

.EXAMPLE
    .\Invoke-KnowledgeIngress.ps1
    # Starts polling the inbox with default config.json

.EXAMPLE
    .\Invoke-KnowledgeIngress.ps1 -ConfigPath C:\myconfig.json -Once
    # Processes current inbox files once using a custom config
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Once
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Load configuration ──────────────────────────────────────────────

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $PSScriptRoot "config.json"
}

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config file not found: $ConfigPath`nCopy config.example.json to config.json and fill in your settings."
    return
}

$Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Validate required settings
$requiredFields = @("InboxPath", "KnowledgeRepoPath", "FlowUrl", "TenantId", "ClientId", "ClientSecret")
foreach ($field in $requiredFields) {
    if (-not $Config.$field) {
        Write-Error "Missing required config field: $field"
        return
    }
}

$InboxPath        = $Config.InboxPath
$ArchivePath      = if ($Config.ArchivePath) { $Config.ArchivePath } else { Join-Path $InboxPath "archive" }
$KnowledgeRepo    = $Config.KnowledgeRepoPath
$PollInterval     = if ($Config.PollIntervalSeconds) { $Config.PollIntervalSeconds } else { 10 }
$FileFilter       = if ($Config.FileFilter) { $Config.FileFilter } else { "*.txt" }
$FlowUrl          = $Config.FlowUrl
$ResponseField    = if ($Config.ResponseField) { $Config.ResponseField } else { "reply" }
$TenantId         = $Config.TenantId
$ClientId         = $Config.ClientId
$ClientSecret     = $Config.ClientSecret

# ── Ensure directories exist ────────────────────────────────────────

foreach ($dir in @($InboxPath, $ArchivePath, $KnowledgeRepo)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "Created directory: $dir"
    }
}

# ── Functions ────────────────────────────────────────────────────────

# Token cache — avoids re-authenticating on every request
$script:CachedToken    = $null
$script:TokenExpiresAt = [datetime]::MinValue

function Get-OAuthToken {
    <#
    .SYNOPSIS
        Acquires an OAuth token using client credentials, with caching.
    #>

    # Return cached token if still valid (with 2-minute buffer)
    if ($script:CachedToken -and [datetime]::UtcNow -lt $script:TokenExpiresAt.AddMinutes(-2)) {
        return $script:CachedToken
    }

    $tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    $scope         = [Uri]::EscapeDataString('https://service.flow.microsoft.com//.default')
    $clientSecretE = [Uri]::EscapeDataString($ClientSecret)
    $tokenBody     = "client_id=$ClientId&client_secret=$clientSecretE&grant_type=client_credentials&scope=$scope"

    Write-Host "  Acquiring OAuth token ..." -ForegroundColor DarkCyan

    $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUri `
        -Headers @{ 'Content-Type' = 'application/x-www-form-urlencoded' } `
        -Body $tokenBody

    if ([string]::IsNullOrWhiteSpace($tokenResponse.access_token)) {
        throw "No access token returned. Check TenantId, ClientId, ClientSecret, and scope."
    }

    $script:CachedToken    = $tokenResponse.access_token
    $script:TokenExpiresAt = [datetime]::UtcNow.AddSeconds($tokenResponse.expires_in)

    Write-Host "  Token acquired (expires in $($tokenResponse.expires_in)s)" -ForegroundColor DarkCyan
    return $script:CachedToken
}

function Send-ToFlow {
    <#
    .SYNOPSIS
        POSTs transcript text to the Power Automate flow endpoint using OAuth
        bearer-token authentication, and returns the response.
    #>
    param(
        [Parameter(Mandatory)][string]$Transcript,
        [Parameter(Mandatory)][string]$SourceFileName
    )

    $accessToken = Get-OAuthToken

    $body = @{
        message  = $Transcript
        filename = $SourceFileName
    } | ConvertTo-Json -Depth 10

    $headers = @{
        'Authorization' = "Bearer $accessToken"
        'Content-Type'  = 'application/json'
    }

    Write-Host "  Sending to Copilot Studio flow ..." -ForegroundColor Cyan

    $response = Invoke-RestMethod -Uri $FlowUrl -Method Post -Headers $headers -Body $body

    # Extract the reply from the configured response field
    $resultText = $response.$ResponseField

    if (-not $resultText) {
        Write-Warning "  Response field '$ResponseField' was empty. Full response:"
        Write-Host ($response | ConvertTo-Json -Depth 5)
    }

    return $resultText
}

function Get-OutputFileName {
    <#
    .SYNOPSIS
        Generates a timestamped output filename from the source file name.
    #>
    param([Parameter(Mandatory)][string]$SourceName)

    $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($SourceName)
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
    return "${timestamp}_${baseName}.md"
}

function Process-InboxFile {
    <#
    .SYNOPSIS
        Reads a single inbox file, sends it to the flow, and writes the output.
    #>
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    Write-Host "Processing: $($File.Name)" -ForegroundColor Green

    # Read the transcript
    $transcript = Get-Content $File.FullName -Raw -Encoding UTF8

    if ([string]::IsNullOrWhiteSpace($transcript)) {
        Write-Warning "  Skipping empty file: $($File.Name)"
        return
    }

    # Send to flow
    $result = Send-ToFlow -Transcript $transcript -SourceFileName $File.Name

    if (-not $result) {
        Write-Warning "  No result returned for $($File.Name), skipping."
        return
    }

    # Write output to knowledge repo
    $outputName = Get-OutputFileName -SourceName $File.Name
    $outputPath = Join-Path $KnowledgeRepo $outputName

    Set-Content -Path $outputPath -Value $result -Encoding UTF8
    Write-Host "  Output written: $outputPath" -ForegroundColor Green

    # Archive the processed file
    $archiveDest = Join-Path $ArchivePath $File.Name
    Move-Item -Path $File.FullName -Destination $archiveDest -Force
    Write-Host "  Archived: $($File.Name)" -ForegroundColor DarkGray
}

# ── Main loop ────────────────────────────────────────────────────────

Write-Host "=== Knowledge Ingress ===" -ForegroundColor Yellow
Write-Host "Inbox:     $InboxPath"
Write-Host "Archive:   $ArchivePath"
Write-Host "Output:    $KnowledgeRepo"
Write-Host "Filter:    $FileFilter"
Write-Host "Endpoint:  $($FlowUrl.Substring(0, [Math]::Min(60, $FlowUrl.Length)))..."
Write-Host "Mode:      $(if ($Once) { 'Single pass' } else { "Polling every ${PollInterval}s" })"
Write-Host ""

do {
    $files = Get-ChildItem -Path $InboxPath -Filter $FileFilter -File -ErrorAction SilentlyContinue

    if ($files) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Found $($files.Count) file(s)" -ForegroundColor Yellow
        foreach ($file in $files) {
            try {
                Process-InboxFile -File $file
            }
            catch {
                Write-Error "  Failed to process $($file.Name): $_"
            }
        }
    }
    elseif (-not $Once) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Inbox empty, waiting..." -ForegroundColor DarkGray
    }

    if (-not $Once) {
        Start-Sleep -Seconds $PollInterval
    }
} while (-not $Once)

Write-Host "Done." -ForegroundColor Yellow
