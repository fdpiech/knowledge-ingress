---
name: summarize-transcript
description: Produce a structured summary of a transcript
input:
  - transcript: The raw transcript text
  - context: Optional prior context or related summaries
output: A markdown summary document
targetRepo: knowledge-base
---

Produce a structured summary of the following transcript.

The summary should include:
- **Title**: A descriptive title for the conversation
- **Participants**: Who was involved (if identifiable)
- **Key Points**: Bulleted list of the main points discussed
- **Decisions Made**: Any decisions or conclusions reached
- **Action Items**: Any next steps or follow-ups mentioned
- **Open Questions**: Unresolved topics or questions raised

{{#if context}}
## Prior Context

{{context}}
{{/if}}

## Transcript

{{transcript}}
