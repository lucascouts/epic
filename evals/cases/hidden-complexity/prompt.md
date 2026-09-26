---
tags: [artifacts]
runs: 1
max_turns: 40
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill, Agent]
---

/epic:epic Our app is a Next.js site with server-side rendering, a Postgres database and 47 themed components; its code is not in this workspace, so plan from this description. Add a dark mode toggle to the settings page — it needs to persist the preference in the DB, sync across devices, respect the system preference, handle the SSR hydration mismatch, and update all 47 themed components.
