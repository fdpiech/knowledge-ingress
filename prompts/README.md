# Prompts

Prompt templates used by the knowledge ingestion pipeline.

Each prompt is a markdown file with frontmatter metadata. The body contains the
prompt template, which may include `{{variable}}` placeholders that get filled
at runtime.

## Conventions

- One prompt per file
- Frontmatter fields:
  - `name` — unique identifier
  - `description` — what the prompt does
  - `input` — expected variables
  - `output` — what the prompt produces
  - `targetRepo` — which artifact repo receives the output
