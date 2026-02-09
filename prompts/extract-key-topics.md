---
name: extract-key-topics
description: Extract key topics and themes from a raw transcript
input:
  - transcript: The raw transcript text
output: A structured JSON list of topics with supporting quotes
targetRepo: knowledge-base
---

Analyze the following transcript and extract the key topics discussed.

For each topic, provide:
1. A concise topic name
2. A one-sentence summary
3. 1-3 direct quotes from the transcript that support this topic
4. Confidence level (high, medium, low)

Return the result as a JSON array.

## Transcript

{{transcript}}
