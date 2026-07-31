---
name: natural-writing
description: >
  Write documents that read like a human wrote them, not an AI. Cuts AI-tell
  vocabulary and transitions, breaks up robotic structure and uniform sentence
  rhythm, and anchors the piece to a specific audience, medium, and voice. Use
  this whenever drafting or revising any multi-paragraph prose document for the
  user: essays, blog posts, reports, cover letters, self-assessments, promo
  cases, proposals, README prose, or longer emails, even when the user does not
  explicitly ask for it to "sound human." Also use when the user asks to
  humanize, de-AI, or make writing sound less robotic or less like ChatGPT. Do
  not apply to code, commit messages, or quick conversational replies.
user_invocable: true
arguments:
  - name: target
    description: "Optional: text to revise, a file path to a draft, or a short description of the document to write. If omitted, use the document currently in play."
    required: false
---

# Natural writing

You're writing something a person will read: an essay, a report, a cover letter, a self-assessment. The goal is prose that reads like a human wrote it, because AI prose has a recognizable fingerprint and readers hold it against you. It reads as low-effort, or evasive, or like you couldn't be bothered to write the thing yourself.

That fingerprint is statistical. Models reach for the same inflated vocabulary, the same tidy symmetric structure, the same even sentence lengths, the same hedged both-sides tone. Your job is to strip the fingerprint and keep the writing good.

**One caveat first, because none of what follows is a rule.** Everything below is a default, not a law. Never trade away clarity, accuracy, or the reader's time just to dodge a tell. In a genuinely formal or technical document some of these patterns are correct, and the notes say so where it matters. Use judgment. The point is to write well, not to beat a detector.

## Before you write: anchor the piece

The fastest way to sound like a generic AI article is to write one. Before drafting, pin down four things:

- **Audience.** Who reads this, and what do they already know? A promo committee, a hiring manager, and a teammate each need something different.
- **Medium.** A Slack post, a design doc, and a cover letter have different shapes and formality. Match it.
- **Purpose.** What should the reader do or believe when they finish? Write toward that.
- **Voice.** Confident? Wry? Plain and direct? Pick one and hold it across the whole piece.

If any of these are unclear and would change how you write, ask the user one quick question instead of guessing and falling back on blog-voice. Anchoring concretely is the highest-leverage move here. It does more work than any banned-word list.

## The tells, and why they read as machine

### Vocabulary
Some words are rare in real human writing but pour out of models, so they read as machine-selected. Avoid by default:

> delve, tapestry, testament, multifaceted, nuance / nuanced, crucial, paramount, pivotal, realm, landscape, showcase, leverage (as a verb), robust, seamless, foster, underscore, resonate, myriad, boasts, elevate

That's a starting list, not the whole set. The deeper habit: when a plainer word exists, use it. "Important" beats "crucial." "Use" beats "leverage."

### Transitions and openers
Cut the connective scaffolding: *Furthermore, Moreover, Additionally, In conclusion, Ultimately, It's important to note, It's worth noting.* A human just deletes these. They announce filler, and the sentence almost always reads better with nothing in front of it.

### Punctuation: the em dash
The em dash (—) is the single most recognizable tell right now. Default to routing around it with a comma, a period, or parentheses. If you still want one, treat that as a signal the sentence wants restructuring. Watch two related habits: the reflexive rule-of-three ("fast, reliable, and scalable"), which models produce on autopilot, and semicolon overuse.

### Formatting: technical tokens in prose
In flowing prose, don't drop inline-code spans, backticked identifiers, ALL_CAPS constants, or raw flag and path fragments into your sentences. Say it in plain language. Write "one worker," not `NUM_WORKERS=1`. Write "the retry limit," not `max_retries`. Write "the config file," not a raw path. A code token mid-sentence reads as machine output or copy-paste, and it breaks the reading rhythm for a person.

The exception is real: in a genuine technical document where the literal token *is* the content, keep it exact. A README command, an API reference, or an error string the reader will search for should stay verbatim. The test is whether the reader needs the exact string or just the idea behind it.

### Structure
Models love symmetry: a tidy intro, then three balanced bullets, then a conclusion that restates the intro. Humans write lopsided. Let paragraphs run to unequal lengths. Skip the summarizing final paragraph and end on your last concrete point instead of a recap. When a piece falls naturally into "intro, three points, wrap-up," that's the tell talking, so break it.

### Rhythm
This is what the "burstiness" and "perplexity" advice is really about, minus the jargon. Models hold sentence length roughly constant. Humans don't. A long, winding sentence that piles clause on clause and takes its time gets followed by a short one. Then a fragment. Like this. Vary it on purpose and the prose stops sounding metronomic.

### Tone and content
These tells survive even after you've fixed every word:

- **Hedging and over-qualification.** "It could be argued that this may perhaps suggest..." Commit to the claim or cut it.
- **Throat-clearing.** "In today's fast-paced world..." Delete the windup and open with the substance.
- **Relentless even-handedness.** Not every point needs a counterpoint. Sometimes the honest answer is just yes.
- **Forced positivity.** The upbeat, everything-is-exciting register reads as marketing, and in a self-assessment it reads as evasive. State the hard parts plainly.

## Write well, not just clean

Avoiding tells is half the job. The other half is writing that's actually good, which dodges most tells for free:

- Prefer concrete nouns and strong verbs over abstraction. "I shipped the API" beats "I was responsible for the delivery of API capabilities."
- Commit. Say what you did and what happened. Confidence isn't a tell; it's the absence of hedging.
- Use specific detail: numbers, names, dates, the rewrite you didn't plan for. Detail is exactly what abstraction and AI both lack.
- Cut anything that doesn't earn its place.

## Revising an existing draft

When the ask is "humanize this" or "make this sound less like AI," don't rewrite blindly. Read the draft once for the fingerprint, then fix in this order, preserving meaning at each step:

1. Vocabulary: swap inflated words for plain ones.
2. Transitions and openers: delete the scaffolding.
3. Formatting: turn code tokens into language wherever they aren't load-bearing.
4. Structure: break the symmetry, drop the recap.
5. Rhythm: vary sentence length.
6. Tone: cut hedging, throat-clearing, and forced positivity.

Hold onto the author's meaning and any real constraints (length limits, required sections). You're changing how it reads, not what it says.

## What good looks like

**Before:**
> In today's fast-paced engineering environment, it is crucial to recognize that my contributions have been multifaceted. Furthermore, I spearheaded several key initiatives that delivered significant value. Ultimately, this demonstrates my readiness for the next level.

**After:**
> I shipped the batch-inference API this spring. It took three months and a rewrite I hadn't planned for. Two teams depend on it now.

The rewrite drops the throat-clearing opener and the "crucial / multifaceted" vocabulary, deletes the "Furthermore" and the "Ultimately" recap, varies the sentence lengths, and trades an abstract claim of readiness for concrete evidence that makes the point on its own.
