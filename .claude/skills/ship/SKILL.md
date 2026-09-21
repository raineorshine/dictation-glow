---
name: ship
description: "Finish a change in the dictation-glow repo: build signed, run the tests, commit, rebase on origin/main, squash, push to origin/main, fast-forward the local main, install and relaunch. Use only when the user explicitly asks for the change to be shipped, landed, or pushed to main — never because a change looks finished."
---

# Ship (finish a change → land it on origin/main)

Taken from axshot's skill of the same name and cut to what is true here: there is a real test
suite, there is no test lock, and the one thing that matters most cannot be checked by either.

Solo-developer workflow: squash the current branch, usually in a worktree, to a single commit and
push it to `origin/main`. No PR, and no merge commits.

**Shipping is asked for, never inferred.** A change that is finished, verified and clean is a change
ready to ship, not one to ship — say so and stop. Only the user saying to ship, land, merge or push
it starts this procedure, or a skill the user invoked whose own procedure ends in one.

`origin/main` is the source of truth, not the local `main` ref, which can be behind what another
session pushed. Pushing from the worktree keeps shipping independent of the main checkout.

## Procedure

### 1. Gates: tests, then a signed build

```bash
swift test && ./build.sh --no-install
```

`swift test` covers `DictationGlowCore` and nothing that touches `NSWindow`, `SMAppService` or the
live notification stream. `--no-install` keeps an unverified build out of `/Applications`; the last
line must name the signing identity.

**Neither gate says the band is on screen.** A green suite and a clean build are consistent with a
window ordered in at alpha zero, and a screen capture is not evidence either way (AGENTS.md,
"Verifying the overlay"). A change to the overlay ships when a person has looked at it:

```bash
.build/debug/dictation-glow --show-band 6
```

If nobody looked, the commit body says so in a line of its own — that is the one thing nothing else
will record.

### 2. Commit all staged and unstaged changes

Bring the writing level with the change first, so it lands in this ship rather than a follow-up.
Nothing regenerates any of it:

- **`README.md`**, for anything a user would notice.
- **`CONCEPTS.md`**, when the change moves what a word means here — Band, Edge, Listening. A concept
  described as the code used to behave is worse than no entry.
- **`AGENTS.md`**, for a rule a future session would otherwise break, and **`docs/`** where the
  change made something untrue. A problem that cost real time to work out is a file under
  `docs/solutions/` with its frontmatter, not a paragraph in the commit message.

Then generate the message from the diff: Conventional Commits — `feat:`, `fix:`, `docs:` — with a
lower-case subject under about 60 characters, and a body that says why rather than what.

### 3. Rebase on origin/main

```bash
git fetch origin && git rebase origin/main
```

Resolve conflicts, preferring the branch's changes unless clearly wrong, then `git add` and
`git rebase --continue`.

**Prefer the branch's changes, not its copy of whole files.** A worktree cut before something landed
holds the old copy of every file that change touched, and preferring that side reverts the other
change with no marker and no mention in the message. Before resolving a conflict in a file this
branch did not set out to change, list what landed in it:

```bash
git log --oneline $(git merge-base HEAD origin/main)..origin/main -- <file>
```

Re-run the gates after any rebase that brought code in: step 1 signed off on a different tree.

### 4. Squash all commits into one

```bash
git reset --soft origin/main && git commit -m "subject" -m "body"
```

### 5. Push to origin/main

```bash
git push origin HEAD:main
```

This is the ship. **If the push is rejected as non-fast-forward,** someone landed first and nothing
was lost: back to step 3, redo step 4 onto the new base, and push again.

### 6. Fast-forward the local main, install, and relaunch

```bash
MAIN=$(git worktree list | head -1 | awk '{print $1}') && git -C "$MAIN" merge --ff-only origin/main
```

**A branch holding commits the main checkout also has diverges it by being shipped.** Step 4 rewrote
them into one, so the fast-forward can refuse although nothing is unshipped. Install from the
worktree in that case, which is what was pushed, and leave the main checkout's ref alone.

```bash
./build.sh
```

**Installing does not replace the app that is running.** The accessory launched at login holds the
old binary until it is restarted, and it answers the same distributed notifications as anything
started since — so the band the user sees is the old one until:

```bash
pkill -f 'DictationGlow.app/Contents/MacOS/dictation-glow'; open -a /Applications/DictationGlow.app
```

The login-item record belongs to the signed identity rather than the path, so it survives the
reinstall. Never re-register it, and never read `SMAppService.mainApp.status` from anything but the
installed copy — reading repoints the record at whichever bundle read it (AGENTS.md).

### 7. Put `🚀 ` on the title

The push in step 5 is what counts as shipped, whatever step 6 managed, so the prefix goes on here
and not at the start. Nothing needs restoring if the ship falls over, since it was never set. Say
nothing about it in the response.

### 8. Post-ship

If the user confirms this worktree is no longer needed:

```bash
BRANCH=$(git branch --show-current) && MAIN=$(git worktree list | head -1 | awk '{print $1}') && git -C "$MAIN" worktree remove <this-worktree-path> && git -C "$MAIN" branch -d "$BRANCH"
```

### 9. Extract the learnings

Invoke the `learn` skill. Whatever the session learned about the app, the tree or the workflow is
still in context now and in nobody's an hour later, so this is the last stage of shipping and needs
no ask. Skip it where the learnings were written as the work went — and then say in one line where
they went, rather than saying nothing.

`learn` puts `📚 ` on the title; put `🚀 ` back when it finishes.

### 10. Print the completion message

Print `🚀 Shipped` as the last line of the response, after the learn report.
