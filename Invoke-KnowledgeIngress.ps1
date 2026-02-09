<#
.SYNOPSIS
    Watches an inbox directory for new files, sends them to an LLM for
    processing, and writes the results to a knowledge repository.

.DESCRIPTION
    Polls the configured inbox path for files matching the filter pattern.
    Each new file is read, sent to the Anthropic Messages API with the
    configured prompt, and the response is written to the knowledge repo.
    Processed files are moved to an archive directory.

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
$requiredFields = @("InboxPath", "KnowledgeRepoPath", "ApiUrl", "ApiKey", "Model")
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
$ApiUrl           = $Config.ApiUrl
$ApiKey           = $Config.ApiKey
$Model            = $Config.Model
$MaxTokens        = if ($Config.MaxTokens) { $Config.MaxTokens } else { 4096 }
$SystemPrompt     = $Config.SystemPrompt
$UserTemplate     = if ($Config.UserPromptTemplate) { $Config.UserPromptTemplate } else { "{{TRANSCRIPT}}" }

# ── Ensure directories exist ────────────────────────────────────────

foreach ($dir in @($InboxPath, $ArchivePath, $KnowledgeRepo)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "Created directory: $dir"
    }
}

# ── Functions ────────────────────────────────────────────────────────

function Send-ToLLM {
    <#
    .SYNOPSIS
        Sends transcript text to the Anthropic Messages API and returns the response.
    #>
    param(
        [Parameter(Mandatory)][string]$Transcript,
        [Parameter(Mandatory)][string]$SourceFileName
    )

    $userMessage = $UserTemplate -replace "{{TRANSCRIPT}}", $Transcript

    $body = @{
        model      = $Model
        max_tokens = $MaxTokens
        messages   = @(
            @{ role = "user"; content = $userMessage }
        )
    }

    if ($SystemPrompt) {
        $body["system"] = $SystemPrompt
    }

    $jsonBody = $body | ConvertTo-Json -Depth 10

    $headers = @{
        "x-api-key"         = $ApiKey
        "anthropic-version" = "2023-06-01"
        "content-type"      = "application/json"
    }

    Write-Host "  Sending to $Model ..." -ForegroundColor Cyan

    $response = Invoke-RestMethod -Uri $ApiUrl -Method Post -Headers $headers -Body $jsonBody

    # Extract text from the response content blocks
    $resultText = ($response.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join "`n"

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
        Reads a single inbox file, sends it to the LLM, and writes the output.
    #>
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    Write-Host "Processing: $($File.Name)" -ForegroundColor Green

    # Read the transcript
    $transcript = Get-Content $File.FullName -Raw -Encoding UTF8

    if ([string]::IsNullOrWhiteSpace($transcript)) {
        Write-Warning "  Skipping empty file: $($File.Name)"
        return
    }

    # Send to LLM
    $result = Send-ToLLM -Transcript $transcript -SourceFileName $File.Name

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
Write-Host "Model:     $Model"
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
