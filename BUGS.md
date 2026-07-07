# DIPs Local Testing - Bug Tracker

Open bugs only. A fixed bug is pruned once its fix — and the why behind any non-obvious
guard — lives at the call site in the tree; git history and the PRs carry the forensics.

Clean slate as of 2026-07-08. The 2 remaining entries were pruned with their fixes merged:
the burst-scale bug (dipper #661 offer pacing and #662 queue priority — a burst now queues
instead of expiring) and the stranded-allocations bug (the pinned indexer-agent's rule
reaper with its subgraph staleness guard, graphprotocol/indexer #1221/#1224/#1225/#1227).
A 50-request burst re-run on a post-#661 pin either confirms the slate stays clean or
re-documents what it finds with fresh numbers. Prior entries live in this file's history.
