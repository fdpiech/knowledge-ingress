<#
.SYNOPSIS
    Main entrypoint for the knowledge-ingress pipeline.

.DESCRIPTION
    Watches the ingress folder (or processes once with -Once) for new transcript files,
    sends them to the Copilot Studio Flow for analysis, writes NORM/TAC/SIG artifacts,
    and optionally commits to git.

.PARAMETER Once
    Process all pending files once and exit (no watch loop).

.PARAMETER File
    Process a single specific file instead of scanning the ingress folder.

.PARAMETER ConfigPath
    Path to settings.json. Defaults to config/settings.json relative to repo root.

.EXAMPLE
    .\Invoke-Ingress.ps1 -Once
    .\Invoke-Ingress.ps1 -File "ingress\meeting\transcript.txt"
    .\Invoke-Ingress.ps1   # watch mode (polls every 10 seconds)
#>

[CmdletBinding()]
param(
    [switch]$Once,
    [string]$File,
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"

# ── Load helpers ─────────────────────────────────────────────────────────────
. (Join-Path $PSScriptRoot "lib.ps1")

# ── Resolve paths ────────────────────────────────────────────────────────────
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $repoRoot "config\settings.json"
}

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config file not found: $ConfigPath"
    exit 1
}

$config   = Read-JsonFile -Path $ConfigPath
$flowUrl  = $config.FlowUrl
$defaults = $config.Defaults

if (-not $flowUrl -or $flowUrl -match "YOUR-.*-HERE") {
    Write-Error "FlowUrl not configured in $ConfigPath. Set it to your Power Automate HTTP trigger URL."
    exit 1
}

$ingressDir   = Join-Path $repoRoot $config.IngressFolder
$runsDir      = Join-Path $repoRoot $config.RunsFolder
$artifactsDir = Join-Path $repoRoot $config.ArtifactsFolder
$logsDir      = Join-Path $repoRoot "logs"
$logFile      = Join-Path $logsDir  "ingress.log"
$errorLogFile = Join-Path $logsDir  "errors.log"

# ── Process a single transcript ─────────────────────────────────────────────

function Invoke-ProcessTranscript {
    param([Parameter(Mandatory)][string]$FilePath)

    $fileName       = Split-Path $FilePath -Leaf
    $transcriptText = Get-Content $FilePath -Raw
    $runTimestamp    = Get-RunTimestamp
    $sha12          = Get-Sha12 -Text $transcriptText
    $runId          = "run_$runTimestamp"
    $threadId       = $defaults.thread_id
    $projectId      = $defaults.project_id
    $createdAt      = Get-UtcNow

    Write-Host "Processing: $fileName" -ForegroundColor Cyan
    Write-Host "  run_id   : $runId"
    Write-Host "  sha12    : $sha12"

    # ── Build request envelope ───────────────────────────────────────────
    $envelope = @{
        project_id = $projectId
        thread_id  = $threadId
        run_id     = $runId
        created_by = $env:USERNAME
        created_at = $createdAt
        raw = @{
            source_ref    = "file(source):$fileName"
            source_type   = $defaults.source_type
            title         = "$($defaults.title_prefix) - $fileName"
            captured_at   = $createdAt
            participants  = $defaults.participants
            tags          = $defaults.tags
            language      = $defaults.language
            transcript_text = $transcriptText
        }
        options = @{
            norm_schema_version = $defaults.schema_versions.norm
            tac_schema_version  = $defaults.schema_versions.tac
            sig_schema_version  = $defaults.schema_versions.sig
            trend_window_days   = $defaults.trend_window_days
        }
    }

    # ── Create run folder ────────────────────────────────────────────────
    $runFolder = Join-Path $runsDir "${runTimestamp}_${sha12}"
    New-Item -ItemType Directory -Path $runFolder -Force | Out-Null

    # Save raw transcript copy and request
    Copy-Item $FilePath (Join-Path $runFolder "raw.txt")
    Write-JsonFile -Path (Join-Path $runFolder "request.json") -Object $envelope

    Write-IngressLog -LogFile $logFile -RunId $runId -ThreadId $threadId -Status "started" -Message "Processing $fileName"

    # ── POST to Flow ─────────────────────────────────────────────────────
    try {
        $result = Invoke-FlowRequest -FlowUrl $flowUrl -Body $envelope
        $response = $result.Response
        $durationMs = $result.DurationMs

        Write-Host "  Flow responded in ${durationMs}ms" -ForegroundColor Green

        # Save response
        Write-JsonFile -Path (Join-Path $runFolder "response.json") -Object $response
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-Host "  Flow call FAILED: $errorMsg" -ForegroundColor Red

        Write-IngressLog -LogFile $errorLogFile -RunId $runId -ThreadId $threadId -Status "error" -Message $errorMsg

        # Save meta as failed
        $meta = @{
            run_id    = $runId
            thread_id = $threadId
            sha12     = $sha12
            source    = $fileName
            status    = "failed"
            error     = $errorMsg
            created_at = $createdAt
        }
        Write-JsonFile -Path (Join-Path $runFolder "meta.json") -Object $meta
        return
    }

    # ── Validate response ────────────────────────────────────────────────
    $valid = $true
    $validationErrors = @()

    if (-not $response.norm) { $valid = $false; $validationErrors += "Missing norm" }
    if (-not $response.tac)  { $valid = $false; $validationErrors += "Missing tac" }
    if (-not $response.sig)  { $valid = $false; $validationErrors += "Missing sig" }

    if ($valid) {
        if ($response.norm.artifact.type -ne "norm") { $valid = $false; $validationErrors += "norm.artifact.type != 'norm'" }
        if ($response.tac.artifact.type  -ne "tac")  { $valid = $false; $validationErrors += "tac.artifact.type != 'tac'" }
        if ($response.sig.artifact.type  -ne "sig")  { $valid = $false; $validationErrors += "sig.artifact.type != 'sig'" }
    }

    if (-not $valid) {
        Write-Host "  Validation FAILED:" -ForegroundColor Red
        $validationErrors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }

        Write-IngressLog -LogFile $errorLogFile -RunId $runId -ThreadId $threadId -Status "validation_error" -Message ($validationErrors -join "; ")

        $meta = @{
            run_id           = $runId
            thread_id        = $threadId
            sha12            = $sha12
            source           = $fileName
            status           = "validation_failed"
            validation_errors = $validationErrors
            duration_ms      = $durationMs
            created_at       = $createdAt
        }
        Write-JsonFile -Path (Join-Path $runFolder "meta.json") -Object $meta
        return
    }

    # ── Write artifacts ──────────────────────────────────────────────────
    $normId = $response.norm.artifact.id
    $tacId  = $response.tac.artifact.id
    $sigId  = $response.sig.artifact.id

    $normPath = Join-Path $artifactsDir "norm\${normId}.json"
    $tacPath  = Join-Path $artifactsDir "tac\${tacId}.json"
    $sigPath  = Join-Path $artifactsDir "sig\${sigId}.json"

    Write-JsonFile -Path $normPath -Object $response.norm
    Write-JsonFile -Path $tacPath  -Object $response.tac
    Write-JsonFile -Path $sigPath  -Object $response.sig

    Write-Host "  Artifacts written:" -ForegroundColor Green
    Write-Host "    NORM: $normPath"
    Write-Host "    TAC : $tacPath"
    Write-Host "    SIG : $sigPath"

    # ── Write run meta ───────────────────────────────────────────────────
    $meta = @{
        run_id      = $runId
        thread_id   = $threadId
        sha12       = $sha12
        source      = $fileName
        status      = "success"
        duration_ms = $durationMs
        created_at  = $createdAt
        artifacts   = @{
            norm = $normPath
            tac  = $tacPath
            sig  = $sigPath
        }
    }
    Write-JsonFile -Path (Join-Path $runFolder "meta.json") -Object $meta

    Write-IngressLog -LogFile $logFile -RunId $runId -ThreadId $threadId -Status "success" -Message "Artifacts written for $fileName (${durationMs}ms)"

    # ── Git commit ───────────────────────────────────────────────────────
    if ($config.Commit) {
        try {
            Invoke-GitCommit `
                -Paths @($normPath, $tacPath, $sigPath, $runFolder) `
                -Message "Ingress $fileName [$runId/$sha12]" `
                -RepoRoot $repoRoot

            Write-Host "  Git commit created." -ForegroundColor Green
        }
        catch {
            Write-Host "  Git commit failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-Host "  Done." -ForegroundColor Green
    Write-Host ""
}

# ── Main ─────────────────────────────────────────────────────────────────────

if ($File) {
    # Single file mode
    if (-not (Test-Path $File)) {
        Write-Error "File not found: $File"
        exit 1
    }
    Invoke-ProcessTranscript -FilePath (Resolve-Path $File).Path
}
elseif ($Once) {
    # Process all pending files once
    $extensions = @("*.txt", "*.md", "*.rtf")
    $files = @()
    foreach ($ext in $extensions) {
        $files += Get-ChildItem -Path $ingressDir -Filter $ext -File -ErrorAction SilentlyContinue
    }

    if ($files.Count -eq 0) {
        Write-Host "No transcript files found in $ingressDir" -ForegroundColor Yellow
        exit 0
    }

    Write-Host "Found $($files.Count) file(s) to process." -ForegroundColor Cyan
    Write-Host ""

    foreach ($f in $files) {
        Invoke-ProcessTranscript -FilePath $f.FullName
    }
}
else {
    # Watch mode — poll every 10 seconds
    Write-Host "Watching $ingressDir for new transcripts... (Ctrl+C to stop)" -ForegroundColor Cyan
    Write-Host ""

    $processed = @{}

    while ($true) {
        $extensions = @("*.txt", "*.md", "*.rtf")
        $files = @()
        foreach ($ext in $extensions) {
            $files += Get-ChildItem -Path $ingressDir -Filter $ext -File -ErrorAction SilentlyContinue
        }

        foreach ($f in $files) {
            if (-not $processed.ContainsKey($f.FullName)) {
                Invoke-ProcessTranscript -FilePath $f.FullName
                $processed[$f.FullName] = $true
            }
        }

        Start-Sleep -Seconds 10
    }
}
