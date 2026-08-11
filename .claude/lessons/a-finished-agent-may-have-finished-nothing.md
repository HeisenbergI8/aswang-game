---
id: a-finished-agent-may-have-finished-nothing
trigger: agent, subagent, completed, task-notification, playtester, auditor, exploit-auditor, background, report, resume
scope: process
learned: 2026-08-12
evidence: four of eight background agents in one session returned a mid-work note instead of a report; one returned no text at all having written a real artifact
---

**Lesson:** A completion notification means the agent *stopped*, not that it *finished*. Check the
deliverable on disk before believing it, and resume by name rather than re-spawning — the transcript is
intact and the work is already paid for.

**Why:** In one session, four agents stopped mid-analysis and returned a working note as their result:
"Now let's check `verify:plan` output and lint.", "Now let me confirm baseline stability before running
the clean trial.". Each read as a summary and was a sentence from the middle of the job. One returned
**no text at all** while having written a genuine artifact — reading only the notification, its work
would have been thrown away and re-run.

The failure mode is specific: a partial result is not obviously partial. "The plan lints clean. Now the
reference reviews." looks like a report if you are not looking for the seam.

**Do:**
- Before relaying any agent result, check its artifact: `ls` the plan directory, the file you asked for,
  the console capture. A result with no deliverable where one was demanded is not a result.
- Resume with `SendMessage` to its id, not a fresh `Agent` call. Context survives; a respawn pays twice
  and loses everything it had established.
- When resuming, tell it what is already known so it does not re-derive it. One agent re-ran a 60-tool
  investigation of a bug two other reviews had already confirmed, because the resume did not say so.
- Never fabricate or infer a pending agent's findings. If asked before it lands, say it is still running.

**Corollary for briefs:** name the deliverable path and demand it explicitly. The agents that wrote to a
named file returned usable work even when they stopped early; the ones asked only to "report in chat"
returned a sentence.
