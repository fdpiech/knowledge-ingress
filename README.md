# knowledge-ingress

Watches an inbox directory for transcript files, sends them to an LLM for
processing, and writes the results to a separate knowledge repository.

## How it works

```
inbox/              ──▶  Invoke-KnowledgeIngress.ps1  ──▶  knowledge-repo/
  meeting-notes.txt        (reads file, calls LLM)          2026-02-09_meeting-notes.md
  interview.txt            (writes structured output)        2026-02-09_interview.md
                           (archives original)
inbox/archive/
  meeting-notes.txt   ◀── processed files land here
```

1. Drop a file in the inbox directory
2. The script picks it up, reads the content
3. Sends it to the Anthropic API with the configured prompt
4. Writes the structured result to the knowledge repo (a separate git repo)
5. Moves the original file to the archive directory

## Setup

```powershell
# 1. Copy the example config and fill in your settings
Copy-Item config.example.json config.json

# 2. Edit config.json — set your paths and API key
notepad config.json

# 3. Run it
.\Invoke-KnowledgeIngress.ps1
```

## Configuration

| Field | Description |
|---|---|
| `InboxPath` | Directory to watch for new files |
| `ArchivePath` | Where processed files are moved (default: inbox/archive) |
| `KnowledgeRepoPath` | Output directory — point this at your knowledge git repo |
| `PollIntervalSeconds` | How often to check for new files (default: 10) |
| `FileFilter` | File pattern to match (default: `*.txt`) |
| `ApiUrl` | LLM API endpoint |
| `ApiKey` | API key |
| `Model` | Model to use |
| `MaxTokens` | Max response tokens (default: 4096) |
| `SystemPrompt` | System prompt sent to the LLM |
| `UserPromptTemplate` | User message template — `{{TRANSCRIPT}}` is replaced with file contents |

## Usage

```powershell
# Poll continuously (default)
.\Invoke-KnowledgeIngress.ps1

# Process current inbox files once and exit
.\Invoke-KnowledgeIngress.ps1 -Once

# Use a custom config file
.\Invoke-KnowledgeIngress.ps1 -ConfigPath C:\other\config.json
```

## Artifact repos

The output directory (`KnowledgeRepoPath`) is intended to be its own git
repository. This keeps generated artifacts out of this code repo. You can
point multiple instances of the script at different artifact repos by using
different config files.

## License

MIT
