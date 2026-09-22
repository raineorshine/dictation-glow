#!/usr/bin/env node
/**
 * The one gate that reads prose, and it reads only the citations in it.
 *
 * Neither `swift test` nor `./build.sh` looks at `docs/`, so a path that moves
 * and a mechanism that is replaced leave the prose standing and wrong. This
 * checks the two parts of a doc that are mechanical enough to check:
 *
 * - **Every cited path resolves**, at the repo root or under one of the source
 *   roots, since docs name `GlowOverlay.swift` as readily as
 *   `Sources/DictationGlowCore/GlowOverlay.swift`. Relative links between docs
 *   resolve the same way.
 * - **No line numbers.** A `:NN` resolves forever and drifts silently: the
 *   reader who checks it lands on whatever moved into that position and reads
 *   it as confirmation, which is worse than a dangling reference. Every line
 *   number in this repo's solution docs had drifted by the time the rule was
 *   written — `GlowOverlay.swift:176` for `BandView.build(on:)` now points 70
 *   lines short of it. Name the symbol instead; it moves with the thing it
 *   names.
 *
 * What it cannot check is whether the prose still describes the code. That
 * stays a reader's job, which is why the rule is to write docs that claim as
 * little about the present tree as the lesson allows.
 *
 * Ported from github-triage, which runs the same check from `npm run lint`.
 * The logic is shared; `ROOTS` and `FOREIGN` are what differ per repo.
 */
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs'
import { join, dirname, resolve } from 'node:path'

/** A cited path is tried at the repo root and then under each of these. */
const ROOTS = ['.', 'Sources/DictationGlowCore', 'Sources/dictation-glow']

/**
 * Files in other repositories, named here because reading them is how parts of
 * this app were designed. Nothing local can resolve them, and they are not this
 * repo's to keep in step — the line numbers still come off, since a drifted
 * citation into a repo you cannot see is worse, not better.
 */
const FOREIGN = ['axshot.swift', 'TeamsAccessibility.swift', 'Sources/MicState/MicPresence.swift']

/** A path-shaped token in backticks, with an optional `:NN` or `:NN-MM` suffix. */
const CITATION =
  /`((?:\.?[A-Za-z0-9_-]+\/)*[A-Za-z0-9_.-]+\.(?:swift|sh|json|md|mjs))(:\d+(?:-\d+)?)?`/g

/** Any `file.ext:NN`, backticked or not — the form the ban is about. */
const LINE_NUMBER = /[A-Za-z0-9_./-]+\.(?:swift|sh|json|md|mjs):\d+/g

/** A bare `` `:NN` ``, which carries a line number on the back of an earlier citation. */
const BARE_LINE_NUMBER = /`:\d+(?:[-,]\d+)*`/g

/** A relative link to another doc, with the anchor dropped. */
const DOC_LINK = /\]\((\.[^)#\s]*\.md)(?:#[^)\s]*)?\)/g

function markdownFiles(dir) {
  return readdirSync(dir).flatMap(entry => {
    const path = join(dir, entry)
    if (statSync(path).isDirectory()) return markdownFiles(path)
    return path.endsWith('.md') ? [path] : []
  })
}

/** The line a match falls on, for an error message that can be jumped to. */
function lineOf(source, index) {
  return source.slice(0, index).split('\n').length
}

const failures = []

for (const file of markdownFiles('docs')) {
  const source = readFileSync(file, 'utf8')

  for (const match of source.matchAll(CITATION)) {
    if (FOREIGN.includes(match[1])) continue
    if (ROOTS.some(root => existsSync(join(root, match[1])))) continue
    failures.push(`${file}:${lineOf(source, match.index)} cites ${match[1]}, which does not exist`)
  }

  for (const match of source.matchAll(DOC_LINK)) {
    if (existsSync(resolve(dirname(file), match[1]))) continue
    failures.push(`${file}:${lineOf(source, match.index)} links ${match[1]}, which does not exist`)
  }

  for (const pattern of [LINE_NUMBER, BARE_LINE_NUMBER]) {
    for (const match of source.matchAll(pattern)) {
      failures.push(
        `${file}:${lineOf(source, match.index)} cites a line number (${match[0]}) — name the symbol instead`,
      )
    }
  }
}

if (failures.length) {
  console.error(`${failures.length} bad citation${failures.length === 1 ? '' : 's'}:`)
  for (const failure of failures) console.error(`  ${failure}`)
  process.exit(1)
}
