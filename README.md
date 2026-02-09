# knowledge-ingress

Code and prompts for inbound transcript management. Artifacts (processed
transcripts, structured knowledge, etc.) live in their own separate git
repositories.

## Architecture

```
knowledge-ingress/          <-- this repo: code + prompts
├── src/                    TypeScript source
│   ├── artifact-repos.ts   Manage external artifact repos
│   ├── cli.ts              CLI commands
│   ├── types.ts            Shared type definitions
│   └── index.ts            Public API
├── prompts/                Prompt templates for the pipeline
├── config/
│   ├── repos.json          Registry of artifact repos (local, gitignored)
│   └── repos.example.json  Example configuration
└── ...

../transcripts-raw/         <-- artifact repo (separate git)
../knowledge-base/          <-- artifact repo (separate git)
```

### Why separate repos?

- **History isolation** — artifact repos can grow large with binary or
  generated content without bloating the code repo's git history.
- **Independent versioning** — artifacts follow their own release cadence.
- **Access control** — different people/systems may need access to artifacts
  vs. code.
- **Multiple artifact stores** — different types of output (raw transcripts,
  processed summaries, structured data) can each have their own repo.

## Setup

```bash
npm install
cp config/repos.example.json config/repos.json   # then edit paths/remotes
```

## Managing artifact repos

```bash
# Initialize a new artifact repo on disk and register it
npm run artifact-repo:init -- my-artifacts ../my-artifacts "Description here"

# List all configured repos
npm run artifact-repo:list

# Validate all repos exist and are healthy
npm run artifact-repo:validate
```

## Programmatic usage

```typescript
import { initRepo, writeArtifact, readArtifact } from "knowledge-ingress";

// Write a processed artifact to a repo
await writeArtifact("knowledge-base", "summaries/2026-02-09.md", content);

// Read it back
const summary = await readArtifact("knowledge-base", "summaries/2026-02-09.md");
```

## Prompts

Prompt templates live in `prompts/`. Each is a markdown file with frontmatter
that specifies inputs, outputs, and which artifact repo receives the result.
See `prompts/README.md` for conventions.

## Development

```bash
npm run dev          # Run with tsx
npm run build        # Compile TypeScript
npm run typecheck    # Type-check without emitting
npm run lint         # Lint source
npm test             # Run tests
```

## License

MIT
