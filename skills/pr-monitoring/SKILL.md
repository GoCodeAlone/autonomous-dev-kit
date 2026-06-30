---
name: pr-monitoring
description: Use after creating a PR to automatically monitor CI checks and review comments, fixing issues and pushing updates autonomously
---

> Condensed format: load `autodev:condensed-pipeline-writing` to expand shorthand.

# PR Monitoring

## Overview

Monitor a pull request (or a set of PRs) for CI failures and review comments, automatically fixing issues and pushing updates. Runs as a background agent after autonomous PR creation.

**Core principle:** The PR is the final quality gate. Monitor it, fix what breaks, respond to feedback — all without human intervention.

## When to Use

Invoked automatically by `finishing-a-development-branch` in autonomous mode after creating a PR. Can also be invoked manually for any open PR.

## Single Agent vs. One Agent per PR

When multiple PRs were created in the same session, prefer launching **one monitor agent that covers all PRs** to reduce GitHub API request volume. You may launch one agent per PR instead if the PRs are on unrelated codebases, if you anticipate heavy parallel CI load, or if a previous shared monitor was rate-limited. Default to the single-agent approach and only deviate with a reason.

## Waiting for CI: the sanctioned pattern

For a pure CI-wait (poll until checks settle, then act), prefer a blocking poll-loop
over a long-lived monitor Agent. The pattern is host-scoped.

<host: claude-code>
**Recommended default — a bash poll-loop, not a long-lived monitor Agent.** Issue a
`Bash` tool call with `run_in_background: true` running a **bounded** sleep-loop that
polls `gh pr checks <pr>` until no check is `pending` (or a failure), prints a settle
line, and exits. The harness re-invokes the lead **once** on exit (≈0 tokens while it
sleeps); the lead then reads the result and admin-merges on `failures=0`.

Bound the loop so it can never spin forever, e.g.:

```bash
for i in $(seq 1 120); do            # 120 × 30s = 60 min cap
  raw=$(gh pr checks <pr> --json bucket 2>/dev/null)
  fail=$(echo "$raw" | jq '[.[]|select(.bucket=="fail")]|length')
  pend=$(echo "$raw" | jq '[.[]|select(.bucket=="pending")]|length')
  { [ "$fail" != 0 ] && [ -n "$fail" ]; } && { echo "FAILURES=$fail"; break; }
  { [ "$pend" = 0 ] || [ -z "$pend" ]; } && { echo "SETTLED"; break; }
  sleep 30
done
```

On the 120-iteration cap, print a timeout line and exit for the lead to restart.

**Why not a background Agent for this:** a `run_in_background` **Agent** told to
sleep-loop tends to return after ~1 cycle and re-complete repeatedly (the agent loop is
not a blocking sleep) — observed early-exiting ~6× in one run. The bash sleep-loop
genuinely blocks to completion.
</host>

<host: codex, cursor, opencode>
Use your host's equivalent poll mechanism. Where no blocking-background-bash exists, the
sanctioned fallback is **self-poll on each lead wakeup**: run `gh pr checks <pr>` once
per turn and re-check on the next turn. This loses fire-on-event but is reliable; do not
dispatch a background Agent expecting it to block on a sleep-loop.
</host>

<host: hermes-agent>
Use `terminal(background=true, notify_on_complete=true)` with a bounded bash sleep-loop
(same pattern as the Claude Code bash poll-loop above) that polls `gh pr checks <pr>`
until settled. The Hermes `terminal` tool genuinely blocks to completion in background mode.
Use `process(action='poll')` to check status and `process(action='log')` to read results.
</host>

**Fallback (all hosts):** the background-Agent monitor in "The Process" below remains the
tool for multi-PR review-comment handling that needs active fix-and-push; note its
early-exit failure mode and prefer the poll-loop / self-poll for a pure CI-wait.

## The Process

Run a `balanced`-tier agent that monitors PRs in a loop for up to **60 minutes**, polling every **10 minutes**, until all CI checks pass and no unresolved reviews remain.

<host: claude-code>
Use the Agent tool to run the monitor in the background:

````
Agent tool (general-purpose, model: balanced, run_in_background: true):
  description: "Monitor PR(s) <numbers> for CI and reviews"
  prompt: |
    You are monitoring one or more pull requests and automatically fixing issues.

    ## Setup

    PRs to monitor (repeat the loop below for each):
    | PR # | URL | Branch | Base | Design doc | Plan doc |
    |------|-----|--------|------|------------|----------|
    | <n>  | <url> | <branch> | <base> | <path or N/A> | <path or N/A> |

    ## Worktree Setup

    Before starting the loop, ensure every branch has its own git worktree so
    you never need to `git checkout` mid-session (which would discard in-flight
    changes on the current branch):

    ```bash
    # For each PR branch that doesn't already have a worktree:
    git worktree add ../<branch>-monitor <branch>
    ```

    When working on a fix for PR #N, `cd` into that branch's worktree directory.
    Always confirm which branch you are on with `git branch --show-current` before
    making any edits, commits, or pushes.

    ## Session Limits

    - **Maximum session duration:** 60 minutes from when this agent starts.
    - **Poll interval:** 10 minutes between full check cycles across all PRs.
    - Track elapsed time; when fewer than 10 minutes remain, finish the current
      cycle and then write the timeout status report (see step 3) before exiting.

    ## Monitor Loop

    Repeat until exit conditions are met or the 60-minute session limit is reached:

    ### 1. Check CI Status (per PR)

    For each PR:

    ```bash
    gh pr checks <number> --json name,state,conclusion,detailsUrl
    ```

    **If any check fails:**
    a. Extract the run ID from the `detailsUrl` field of the failing check
       (the URL has the form `.../runs/<run-id>/...`):
       ```bash
       gh pr checks <number> --json name,state,conclusion,detailsUrl \
         | jq '.[] | select(.conclusion == "FAILURE") | .detailsUrl'
       # run-id is the numeric segment after /runs/ in that URL
       ```
    b. Read the failure logs: `gh run view <run-id> --log-failed`
    c. Identify the root cause
    d. `cd` into that PR's worktree directory and confirm the branch:
       ```bash
       cd ../<branch>-monitor
       git branch --show-current   # must equal <branch>
       ```
    e. Fix the issue in the codebase
    f. Run the relevant tests locally to verify
    g. Commit and push:
       ```bash
       git add <specific-files>
       git commit -m "fix: address CI failure in <check-name>"
       git push
       ```
    h. Return to the next PR in the loop

    **Safety:** Max 5 fix attempts per unique CI failure. After 5, comment on the PR:
    "Unable to automatically resolve CI failure in <check-name> after 5 attempts. Manual intervention needed."

    ### 2. Check Review Comments (per PR)

    Use GraphQL to fetch review threads — this gives both the thread IDs needed
    for resolution and the author login and comment IDs needed to reply in-thread:

    ```bash
    gh api graphql -f query='
      query($owner: String!, $repo: String!, $number: Int!) {
        repository(owner: $owner, name: $repo) {
          pullRequest(number: $number) {
            reviewThreads(first: 100) {
              nodes {
                id
                isResolved
                isOutdated
                comments(first: 1) {
                  nodes {
                    databaseId
                    url
                    author { login }
                    body
                  }
                }
              }
            }
          }
        }
      }
    ' -f owner=<owner> -f repo=<repo> -F number=<number>
    ```

    To reply to a review thread, use the REST API with the `databaseId` of the
    first comment in the thread (the `in_reply_to` parameter):
    ```bash
    gh api repos/<owner>/<repo>/pulls/<number>/comments \
      --method POST \
      --field body="Addressed in <commit-sha>" \
      --field in_reply_to=<databaseId>
    ```

    Also fetch any "CHANGES_REQUESTED" reviews:

    ```bash
    gh api repos/<owner>/<repo>/pulls/<number>/reviews \
      --jq '.[] | select(.state == "CHANGES_REQUESTED") | {id, body, user: .user.login}'
    ```

    **Bot detection:** treat a commenter as a bot if their login ends in `[bot]`
    or matches a known review bot (e.g. `copilot-pull-request-reviewer`,
    `github-advanced-security`, `datadog`, `codeclimate`, `sonarcloud`). Apply
    the same address-then-resolve flow to bot comments as to human comments.

    **If new unresolved, non-outdated threads are found:**
    a. Read the comment carefully
    b. `cd` into that PR's worktree directory and confirm the branch:
       ```bash
       cd ../<branch>-monitor
       git branch --show-current   # must equal <branch>
       ```
    c. Implement the requested change
    d. Run tests to verify
    e. Commit and push
    f. Reply to the comment: "Addressed in <commit-sha>"
    g. **Resolve the thread** after verification unless the max revision rounds
       safety limit was exceeded (required for addressed comments, especially bot comments):
       ```bash
       gh api graphql -f query='
         mutation($threadId: ID!) {
           resolveReviewThread(input: {threadId: $threadId}) {
             thread { isResolved }
           }
         }
       ' -f threadId="<thread-id>"
       ```

    **Safety:** Max 3 revision rounds per review comment. After 3, reply:
    "I've attempted to address this feedback but may need clarification. Flagging for manual review."
    Leave the thread **unresolved** — do NOT resolve it, as that would mask the outstanding concern.
    It will be surfaced in the timeout status report as needing manual intervention.

    ### 3. Check Exit Conditions

    A PR is **complete** when ALL of:
    - All CI checks passing (green)
    - No unresolved, non-outdated review threads
    - No pending "changes requested" reviews

    **On all PRs complete (clean exit):**
    - For each PR that is merged AND whose base-branch CI is green for the merge
      commit AND that has a design + plan in `docs/plans/` for its branch, invoke
      `autodev:post-merge-retrospective` to produce a retro in `docs/retros/`.
    - Report final status.

    **On session timeout (60-minute limit reached):**
    Write a status report to stdout in this format so the orchestrator can decide
    whether to restart:

    ```
    PR-MONITOR TIMEOUT REPORT
    Elapsed: ~60 min
    PRs still needing attention:
      - PR #<n> <url>: <one-line summary of remaining work>
    PRs complete:
      - PR #<n> <url>: all checks green, no open threads
    Action required: restart autodev:pr-monitoring for the PRs listed above.
    ```

    Then exit. The orchestrator (lead agent) will read this report via the
    activity log and start a new monitor agent for the remaining PRs.

    ### 4. Wait Between Cycles

    Sleep **10 minutes** (600 seconds) between full check cycles across all PRs.
    Do not poll more frequently — this keeps GitHub API usage well within limits.
````
</host>

<host: codex, opencode, cursor>

Use your host's equivalent mechanism to periodically poll the following in a loop,
with a **10-minute** wait between full cycles and a **60-minute** total session cap:

- `gh pr checks <number>` — fix any failing CI checks; use a separate worktree
  per branch so you never switch branches mid-session
- GraphQL `reviewThreads` query — fetch unresolved, non-outdated threads; address
  each one, reply "Addressed in <commit-sha>", then resolve the thread via the
  `resolveReviewThread` GraphQL mutation unless the 3 revision-round safety limit
  was exceeded. Apply this to bot comments (any login ending in `[bot]`, or known
  bots such as `copilot-pull-request-reviewer`, `github-advanced-security`,
  `datadog`) the same as human comments.
- `gh api repos/<owner>/<repo>/pulls/<number>/reviews` — handle any "CHANGES_REQUESTED" reviews

When the 60-minute limit is reached before all PRs are clean, write a timeout
status report listing which PRs still need attention, then exit. The orchestrator
should start a new monitor for the remaining PRs.

When a PR has merged with green base-branch CI and a design + plan exist in
`docs/plans/` for its branch, invoke `autodev:post-merge-retrospective` to
write a retro in `docs/retros/`. If the PR was closed without merge, skip the
retro and exit cleanly.

</host>

<host: hermes-agent>

Use `terminal` to run `gh pr checks <number>` and fix failing CI checks. For
background monitoring, use `terminal(background=true, notify_on_complete=true)`
with a bounded sleep-loop (same pattern as the Claude Code bash poll-loop above).
Use `process(action='poll')` and `process(action='log')` to read results.

Follow the same poll cycle: 10-minute wait between full cycles, 60-minute total
session cap. Use a separate worktree per branch so you never switch branches
mid-session.

When a PR has merged with green base-branch CI and a design + plan exist in
`docs/plans/` for its branch, invoke `autodev:post-merge-retrospective` to
write a retro in `docs/retros/`. If the PR was closed without merge, skip the
retro and exit cleanly.

</host>


## Safety Limits

| Limit | Value | On Exceed |
|-------|-------|-----------|
| CI fix attempts per failure | 5 | Comment on PR, stop fixing that check |
| Revision rounds per comment | 3 | Reply with escalation, leave thread unresolved, surface in timeout report |
| Total monitoring duration | 60 min | Write timeout status report; orchestrator restarts a new monitor |
| Poll interval | 10 min (600s) | — do not poll more frequently |
| Push frequency | Max 1 per 60s | Queue fixes, batch push |

## Orchestrator Restart Guidance

When the monitor agent times out (60 min), it writes a `PR-MONITOR TIMEOUT REPORT`
to its output. The orchestrator (lead agent) should watch for this via the activity
log, read the report, and start a new `autodev:pr-monitoring` agent scoped to
only the PRs still listed as needing attention. Repeat until all PRs are clean.

## Integration

**Called by:**
- `finishing-a-development-branch` (autonomous mode) — after PR creation

**Calls:**
- `autodev:post-merge-retrospective` — on its own clean exit when the PR has merged with green base-branch CI

**Uses:**
- `gh` CLI for all GitHub operations
- `autodev:systematic-debugging` principles for CI failure analysis
