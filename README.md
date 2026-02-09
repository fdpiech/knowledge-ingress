# knowledge-ingress

Watches an inbox directory for transcript files, sends them to a Copilot
Studio flow via Power Automate HTTP trigger, and writes the results to a
separate knowledge repository.

## How it works

```
inbox/              ──▶  Invoke-KnowledgeIngress.ps1  ──▶  knowledge-repo/
  meeting-notes.txt        (reads file, POSTs to flow)       2026-02-09_meeting-notes.md
  interview.txt            (captures response)               2026-02-09_interview.md
                           (archives original)
inbox/archive/
  meeting-notes.txt   ◀── processed files land here
```

1. Drop a file in the inbox directory
2. The script picks it up, reads the content
3. POSTs it to the Power Automate HTTP trigger (Copilot Studio flow)
4. Writes the flow's response to the knowledge repo (a separate git repo)
5. Moves the original file to the archive directory

## Setup

```powershell
# 1. Copy the example config and fill in your settings
Copy-Item config.example.json config.json

# 2. Edit config.json — set your OAuth credentials, Flow URL, and paths
notepad config.json

# 3. Run it
.\Invoke-KnowledgeIngress.ps1
```

### Azure AD app registration

The script authenticates using the OAuth 2.0 client credentials flow. You need
an Azure AD app registration with permission to call your Power Automate flow:

1. In the Azure portal, create (or reuse) an **App Registration**
2. Note the **Application (client) ID** and **Directory (tenant) ID**
3. Under **Certificates & secrets**, create a client secret and copy the value
4. Under **API permissions**, add `https://service.flow.microsoft.com//.default`
   (the double-slash is intentional)
5. Grant admin consent for the permission

Put the tenant ID, client ID, and secret into `config.json`.

## Configuration

| Field | Description |
|---|---|
| `InboxPath` | Directory to watch for new files |
| `ArchivePath` | Where processed files are moved (default: inbox/archive) |
| `KnowledgeRepoPath` | Output directory — point this at your knowledge git repo |
| `PollIntervalSeconds` | How often to check for new files (default: 10) |
| `FileFilter` | File pattern to match (default: `*.txt`) |
| `TenantId` | Azure AD tenant ID |
| `ClientId` | App registration client ID |
| `ClientSecret` | App registration client secret value |
| `FlowUrl` | Power Automate flow endpoint URL |
| `ResponseField` | JSON field in the flow response that contains the result (default: `reply`) |

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
