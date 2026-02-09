<#
.SYNOPSIS
    Shared helper functions for the knowledge-ingress PowerShell pipeline.
#>

# ── Hashing ──────────────────────────────────────────────────────────────────

function Get-Sha256Hash {
    <#
    .SYNOPSIS  Returns the full SHA-256 hex hash of a string.
    #>
    param([Parameter(Mandatory)][string]$Text)

    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha    = [System.Security.Cryptography.SHA256]::Create()
    $hash   = $sha.ComputeHash($bytes)
    return ($hash | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Get-Sha12 {
    <#
    .SYNOPSIS  Returns the first 12 characters of the SHA-256 hash (for short IDs).
    #>
    param([Parameter(Mandatory)][string]$Text)

    return (Get-Sha256Hash -Text $Text).Substring(0, 12)
}

# ── Timestamps ───────────────────────────────────────────────────────────────

function Get-UtcNow {
    <#
    .SYNOPSIS  Returns current UTC time as ISO-8601 string.
    #>
    return [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Get-RunTimestamp {
    <#
    .SYNOPSIS  Returns a timestamp suitable for run_id: YYYYMMDD_HHmmss
    #>
    return [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
}

# ── File I/O ─────────────────────────────────────────────────────────────────

function Write-JsonFile {
    <#
    .SYNOPSIS  Writes an object as pretty-printed JSON to a file.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Object
    )

    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $Object | ConvertTo-Json -Depth 20 | Set-Content -Path $Path -Encoding UTF8
}

function Read-JsonFile {
    <#
    .SYNOPSIS  Reads a JSON file and returns the parsed object.
    #>
    param([Parameter(Mandatory)][string]$Path)

    return Get-Content $Path -Raw | ConvertFrom-Json
}

# ── HTTP ─────────────────────────────────────────────────────────────────────

function Invoke-FlowRequest {
    <#
    .SYNOPSIS  POSTs a JSON body to a Flow URL and returns the parsed response.
    #>
    param(
        [Parameter(Mandatory)][string]$FlowUrl,
        [Parameter(Mandatory)]$Body,
        [int]$TimeoutSec = 180
    )

    $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $response = Invoke-RestMethod `
        -Uri         $FlowUrl `
        -Method      POST `
        -Body        $json `
        -ContentType "application/json" `
        -TimeoutSec  $TimeoutSec

    $stopwatch.Stop()

    return @{
        Response   = $response
        DurationMs = $stopwatch.ElapsedMilliseconds
    }
}

# ── Git ──────────────────────────────────────────────────────────────────────

function Invoke-GitCommit {
    <#
    .SYNOPSIS  Stages specified paths and creates a commit.
    #>
    param(
        [Parameter(Mandatory)][string[]]$Paths,
        [Parameter(Mandatory)][string]$Message,
        [string]$RepoRoot = "."
    )

    Push-Location $RepoRoot
    try {
        foreach ($p in $Paths) {
            git add $p
        }
        git commit -m $Message
    }
    finally {
        Pop-Location
    }
}

# ── Logging ──────────────────────────────────────────────────────────────────

function Write-IngressLog {
    <#
    .SYNOPSIS  Appends a structured log line to the ingress log file.
    #>
    param(
        [Parameter(Mandatory)][string]$LogFile,
        [Parameter(Mandatory)][string]$RunId,
        [string]$ThreadId = "",
        [string]$Status   = "info",
        [string]$Message  = ""
    )

    $entry = @{
        timestamp = Get-UtcNow
        run_id    = $RunId
        thread_id = $ThreadId
        status    = $Status
        message   = $Message
    } | ConvertTo-Json -Compress

    Add-Content -Path $LogFile -Value $entry -Encoding UTF8
}
