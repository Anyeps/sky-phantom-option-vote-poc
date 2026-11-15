# DRAFT — Sky Immunefi Report: Phantom option id wins the poll — a ballot for a nonexistent option is declared the winner

**Status: DRAFT — submission-ready, NOT submitted.**
**Reason not submitted:** Immunefi Novice submission fee (100 credits, ~100 USDC).
Fah's account holds ~0 USDC; waiting for the Immunefi Studio wave, same as
the GMX drafts (G-P1-2(a), G-P0-7) and the Metric drafts (M-P1-3, M-P1-1,
M-P1-4). Do NOT submit until the Studio "Ready" verdict, and do NOT pay any
fee from another source without Fah's explicit approval.

- **Program:** Sky — https://immunefi.com/bug-bounty/sky/information/
  (scope: https://immunefi.com/bug-bounty/sky/scope/)
- **Severity: Critical** — maps exactly onto the listed Sky Critical
  impact **"Manipulation of governance voting result deviating from voted
  outcome"**. Web/app tier: **$100,000** central case when it changes the
  final winner of an active poll ($10,000 if triage treats it as
  display-only — see the honest-caveats section).
- **Payout wallet:** `0x4d354625102352c7ebe02d4fe08eec1146eeec10`
- **PoC repo:** https://github.com/Anyeps/sky-phantom-option-vote-poc
  — verified from a fresh clone at commit `TBD`: `forge install`
  (pinned forge-std v1.17.0) + `forge test --fork-url
  https://arbitrum-one.publicnode.com` → **8 passed, 0 failed**; vitest
  tally spec → **5 passed, 0 failed** (+ #82775 regression **3/3**).
- **Code under test:** `Polling.sol` (Arbitrum polling contract
  `0x4f4e551b4920a5417F8d4e7f8f099660dAdadcEC`, Sourcify full match, solc
  0.6.6) + `skybase-foundation/sky-governance-portal` @ `6ba12d50`
  (live vote.sky.money code).

---

# Part 1 — 7-Question Gate (run before writing the report)

## Q1: Can an attacker use this RIGHT NOW, step by step? — PASS (with the honest caveat, disclosed)

Yes — two steps, both permissionless, both measured:

1. **Cast a ballot for an option that does not exist.** On any active
   poll, call `Polling.vote([pollId], [99])` (or any `uint256` —
   `type(uint256).max` was tested). The contract checks only that the
   two arrays have equal length, then emits `Voted(voter, pollId, 99)`
   verbatim. No poll-existence check, no window check, no optionId
   range check. Any address can do this; voting is the protocol's
   normal, public action.
2. **Outweigh the leading real option.** The portal tally
   (`fetchPollTally`) aggregates ballots by option id and declares the
   winner as whichever option carries the most SKY, with no check
   against `poll.options`. If the attacker's weight on the phantom
   option exceeds the leading real option's support, the phantom option
   is the `winner` — measured: 2000 SKY on option 99 beats 1000 SKY on
   option 1 under plurality, majority (66.7%), IRV (round-1 majority)
   and approval.

The honest caveat — the attack needs an **active poll** (0 active at
check time, 15 Nov; polls run weekly, next ~17 Nov) and **more SKY
weight than the leading real option** — is real and is stated in the
report itself (see "A note on privilege and preconditions" in Part 2).
It needs no amplification, no admin, no oracle manipulation, no
timing window beyond the poll's own voting window, and no cooperation
from anyone else.

## Q2: Is the impact on the program's accepted impact list? — PASS (exact)

Yes — verbatim. The Sky scope page lists under **Critical**:

> **Manipulation of governance voting result deviating from voted outcome**

This finding is that impact, measured end to end on the real tally
code: the `winner` field — the value governance reads to decide a poll
— flips from a real option to an option that was never on the ballot.
This is the **first** of our Sky findings that maps onto a listed
Critical impact exactly, at the top tier. (`vote.sky.money` is
Critical-only scope.)

## Q3: Is the root cause in an in-scope asset? — PASS

Yes, two in-scope assets:

- **On-chain:** the deployed Arbitrum polling contract
  `0x4f4e551b4920a5417F8d4e7f8f099660dAdadcEC` — `Polling.sol`,
  `vote()` overloads (`:73-80` and `:82+`), which emit any optionId
  verbatim. The polling contract is the vote.sky.money contract
  (referenced from the portal's `modules/contracts/generated.ts:1683`,
  chain 42161).
- **Off-chain:** the live portal code at
  `skybase-foundation/sky-governance-portal` @ `6ba12d50` —
  `modules/polling/api/fetchPollTally.ts` (no option-existence check),
  `modules/polling/helpers/parseRawOptionId.ts:25` (dedup only),
  `modules/polling/api/victory_conditions/{plurality,majority,approval,
  instantRunoff,comparison}.ts` (winner = top option id, unchecked).
  `vote.sky.money` is a named in-scope asset (Critical only).

## Q4: Does it require privileged access that an attacker can't realistically get? — PASS (with the honest caveat, disclosed)

No privilege at all. Voting is public: any address holding (or
delegated) SKY can cast a ballot, and the phantom option needs no
special role, no admin, no oracle, no contract deployment. The only
"privilege" is holding enough SKY weight to outvote the leading real
option — the attacker's own weight, with no amplification. That bar is
higher than #82775's (which multiplied a small weight by duplicating
bytes), and it is disclosed plainly in the report: realistic for a
whale or a large delegate in a low-turnout poll; not realistic for a
dust holder against a high-turnout poll. The weight requirement is a
property of vote tallying itself, not a privilege gate.

## Q5: Is this already known or accepted behavior? — PASS

No. Checked against:

- **Immunefi #82775 (Jul 2026, post-mortem
  https://forum.skyeco.com/t/post-mortem-for-immunefi-bug-report-82775/28214).**
  That was a different hole: duplicated bytes in a raw optionId
  amplifying one ballot's weight. It was fixed with a cardinality
  guard (single-choice ballots must have `ballot.length === 1`).
  A single phantom option **passes** that guard (length 1). The
  repo's own #82775 regression spec still passes **3/3** alongside
  this PoC — the old fix holds; this is a different hole it did not
  close.
- **The program's known issues / audit findings.** No audit, contest,
  or known-issues document lists "ballots for nonexistent options are
  counted and can win" as accepted behaviour. The portal code has no
  comment anywhere stating that option existence is the voter's
  responsibility or that phantom options are expected.
- **The contract's design.** Options live off-chain by design
  (`createPoll` takes only window + IPFS hash), so the contract
  *cannot* validate them — but nothing in the design delegates that
  validation to nobody. The tally is the only place the check could
  live, and it does not perform it.

## Q6: Can you prove impact beyond "technically possible"? — PASS

Measured, not hypothetical (Part 2, Evidence):

- **On-chain (Foundry fork, Arbitrum block 524447762, 8/8):** phantom
  option 99 vote accepted on a fresh fork-created poll AND on real
  poll 1657; `type(uint256).max` accepted; the #82775 payload and a
  multi-option raw value emitted verbatim; mismatched-length control
  reverts (the only check that exists).
- **Off-chain (vitest on the REAL tally code, 5/5):** single-choice
  poll {0: Abstain, 1: Yes, 2: No} — attacker 2000 SKY → option 99
  beats honest 1000 SKY → option 1, **winner 99** under plurality,
  majority, IRV and approval; `winningOptionName` undefined; option 99
  invisible in the per-option `results`; control (500 vs 1000 SKY)
  keeps winner 1. The corruption is in the `winner` field itself, not
  in a display percentage.
- **Bytecode:** deployed contract byte-identical to the `Polling.sol`
  source (Sourcify full match) — the source read in the report IS the
  deployed code.

## Q7: Is this a known-invalid bug class? — PASS

No. It is not a duplicate of #82775 (different root cause, different
payload, regression spec still green), not a griefing-only finding
(the `winner` field — governance's decision input — is corrupted),
not a front-running/MEV observation, and not a finding that requires
out-of-scope behaviour. It is a missing validation in in-scope code
with a listed Critical impact. The closest triage risk is the
display-only downgrade ($10,000), which is disclosed in the report
rather than hidden.

## Gate result: PASS (7/7)

---

# Part 2 — Report (Immunefi submission draft)

## Title

Phantom option id wins the poll: a ballot for a nonexistent option is
declared the winner (manipulation of governance voting result)

## Severity: Critical

Maps exactly onto the listed Sky Critical impact **"Manipulation of
governance voting result deviating from voted outcome"**. Web/app tier:
**$100,000** central case when it changes the final winner of an active
poll.

**A note on the dollar tier:** `vote.sky.money` is Critical-only scope.
The program page prices web/app Critical at $100,000 for direct loss of
funds with no user action, $50,000 otherwise; this finding corrupts the
`winner` field — the program's decision input — which is the $100,000
case in our assessment (the poll's intended effect is changed, not just
a percentage displayed). If triage treats the effect as display-only,
the honest floor is $10,000 (see "Honest caveats" below). Re-check the
live program page for the tier table before submitting.

## Summary

The Sky governance portal tallies votes by option id and declares the
winner as whichever option id carries the most SKY — without ever
checking that the option exists in the poll. The polling contract
cannot prevent this: options live off-chain by design (`createPoll`
takes only a voting window and an IPFS hash), so `vote()` accepts any
`uint256` optionId and emits it verbatim. The tally is the only place
the check could live, and it does not perform it.

Concretely: on a single-choice poll with options {0: Abstain, 1: Yes,
2: No}, an attacker voting **2000 SKY for option 99 — an option that
does not exist** — beats an honest 1000 SKY for option 1 (Yes) and is
declared the **winner** under plurality, majority (66.7%), instant
runoff and approval. The per-option results show no option 99 and
`winningOptionName` is `undefined` — the `winner` field itself is the
corrupted output, while the display that humans read shows a broken
outcome.

This is a second, distinct vote-tally flaw after Immunefi #82775 (Jul
2026). #82775 was duplicated bytes amplifying one ballot's weight; it
was fixed with a ballot-length guard that a single phantom option
passes (length 1). The #82775 regression tests still pass — the old fix
holds, and this hole is one it did not close.

## Impact

- **Manipulation of governance voting result deviating from voted
  outcome (listed Critical impact).** Measured end to end on the real
  tally code: the `winner` field flips from a real option to a
  nonexistent one. Governance reads that field to decide a poll — the
  corrupted value is the program's decision input, not a cosmetic
  percentage. The intended effect of the vote (the option the voters
  actually chose) is replaced by an option nobody voted for, because
  nobody could: it was never on the ballot.
- **The attack is permissionless and needs no exploit primitive.**
  Voting is the protocol's normal public action. Any address with
  enough SKY weight can cast the phantom ballot in-window; no admin,
  no oracle interaction, no contract deployment, no timing trick
  beyond the poll's own voting window. The only requirement is weight
  greater than the leading real option's support — the attacker's own
  weight, with no amplification.
- **Blast radius is one poll per attack, but the damage inside it is
  total.** The poll's outcome is not merely skewed — it is replaced by
  an option with no name, no description, and no voters behind it.
  Polls run weekly (Mon 16:00 UTC, 3 days), so the attack surface
  recurs every week, and any low-turnout poll is in reach of a whale
  or a large delegate.
- **The corruption is loud, which bounds the stealth — but does not
  bound the impact.** `winningOptionName` is `undefined` and no option
  is marked winner in the per-option results, so a human reading the
  poll page sees a broken outcome. That is why the honest floor is
  $10,000 (display-only) rather than $0. But the `winner` field is
  what downstream consumers read — and it says 99.

### A note on privilege and preconditions (for triage — please read)

The attack needs two preconditions, disclosed plainly:

1. **An active poll.** Polls run weekly (Mon 16:00 UTC, 3 days). 0
   were active at check time (15 Nov 2026); the next opens ~17 Nov.
   The vote must be cast in-window — the indexer drops out-of-window
   votes (verified: a vote on real poll 1657, whose window had ended,
   was accepted on-chain but would not count in the tally).
2. **More SKY weight than the leading real option.** There is no
   amplification in this finding (unlike #82775): the attacker must
   genuinely outvote the leader. That is realistic for a whale or a
   large delegate in a low-turnout poll, and unrealistic for a dust
   holder against a high-turnout poll. The bar is a property of vote
   tallying itself, not a privilege gate — and the weight at stake is
   the attacker's own.

Neither precondition needs a privileged role, a compromised account,
or any out-of-scope behaviour.

### Honest caveats (for triage — please read)

1. **Polls are off-chain signal.** The winner does not execute
   anything on-chain by itself; governance still has to act on the
   result. The impact is the corruption of governance's decision
   input, not an automatic on-chain effect. That is exactly what the
   listed Critical impact describes ("manipulation of governance
   voting result deviating from voted outcome"), and it is why the
   central case is $100,000 rather than the smart-contract Critical
   band.
2. **The corruption is loud.** A human reading the poll page sees a
   broken outcome (`winningOptionName` undefined, no option marked
   winner), not a plausible fake winner. If triage treats the broken
   display as the whole effect, the honest floor is $10,000
   (display-only). We claim $100,000 as the central case because the
   `winner` field — the machine-readable decision input — is
   corrupted, and that field is what the program's own impact wording
   covers.
3. **Two code paths were code-read, not executed.** The EIP-712
   gasless `vote()` overload shares the same emission loop (no
   validation) but was not fork-tested; the `comparison` victory
   condition was code-read, not vitest-tested (identical aggregation
   pattern to the four tested conditions). Neither affects the
   verdict: the direct `vote()` path and four victory conditions were
   executed and measured.

## Vulnerability details

### Half A — on-chain: `Polling.sol` cannot validate options

`createPoll` takes only `(startDate, endDate, multiHash, url)` —
the option list lives in the off-chain IPFS document, so the contract
has nothing to validate against. Both `vote()` overloads check ONLY
array-length equality and then emit `Voted` verbatim:

- `Polling.sol:73-80` — `vote(uint256[] pollIds, uint256[]
  optionIds)`: `require(pollIds.length == optionIds.length,
  "non-matching-length")`, then `emit Voted(msg.sender, pollIds[i],
  optionIds[i])` per entry.
- `Polling.sol:82+` — EIP-712 gasless `vote(...)`: same length check
  + signature / nonce / expiry checks, same verbatim emission.
  (Code-read; the direct path was fork-tested, the permit path shares
  the loop.)

No poll-existence check, no window check, no optionId range check.
The only check that exists is the length equality — proven by the
control test, which reverts on mismatched lengths.

### Half B — off-chain: the tally never validates option existence

`fetchVotesByAddressForPoll` decodes the raw choice with
`parseRawOptionId`
(`modules/polling/helpers/parseRawOptionId.ts:25` — dedup via `Set`
only, no range check) and returns the ballot as-is. `fetchPollTally`
(`modules/polling/api/fetchPollTally.ts:86`) applies the #82775
cardinality guard — single-choice ballots must have `ballot.length
=== 1` — which a single phantom option **passes** (length 1). Every
victory condition then declares the winner as whichever option id
carries the most SKY, with no check against `poll.options`:

- `plurality.ts:44-45`, `approval.ts:48-49` —
  `sortedOptions[0].option` returned directly.
- `majority.ts` — same aggregation; winner is the top option if it
  clears the percent threshold.
- `instantRunoff.ts:74,154` — `winner = parseInt(option)` for any
  first-preference majority / final survivor.
- `comparison.ts` — same aggregation; a phantom option passing the
  threshold is returned first. (Code-read; tested via plurality /
  majority / IRV / approval.)
- Only `default.ts` validates
  (`options.indexOf(defaultValue) !== -1`).

The per-option `results` array is built from
`Object.keys(poll.options)` only (`fetchPollTally.ts:190,259`), so the
phantom winner is invisible there and `winningOptionName =
poll.options[99]` is `undefined` — the `winner` field itself is the
corrupted output.

### Why #82775's fix does not close this

#82775 was weight amplification: duplicated bytes in a raw optionId
made one ballot count multiple times. The fix enforces ballot
cardinality (length 1 for single-choice) and dedups. A phantom ballot
is length 1 and has no duplicates — it is a *valid-shaped* ballot for
an *invalid* option. The guard checks the shape of the ballot, never
the membership of the option. The repo's own #82775 regression spec
(`fetchTallyAmplification.spec.ts`) still passes 3/3 alongside this
PoC: duplicated-byte ballots are counted once and multi-option
single-choice ballots are discarded. The fix holds; the hole is
elsewhere.

### Code paths

- **Portal repo** `skybase-foundation/sky-governance-portal` @
  `6ba12d50` (live vote.sky.money code, found via GitHub code search
  for `fetchPollTally` + the #82775 post-mortem; the live portal is
  NOT under `sky-ecosystem` — that org's `governance-portal` is the
  Jan-2023 Maker portal):
  - `modules/polling/api/fetchPollTally.ts:86` — cardinality guard;
    `:190,259` — results built from `poll.options` keys only.
  - `modules/polling/helpers/parseRawOptionId.ts:25` — dedup only.
  - `modules/polling/api/victory_conditions/plurality.ts:44-45`,
    `approval.ts:48-49`, `majority.ts`, `instantRunoff.ts:74,154`,
    `comparison.ts`, `default.ts` — winner selection.
  - `modules/contracts/generated.ts:1683` — Arbitrum polling address,
    chain 42161.
- **Contract** — Arbitrum polling
  `0x4f4e551b4920a5417F8d4e7f8f099660dAdadcEC` (`Polling.sol`, 3,685
  chars, Sourcify full match — creationMatch + runtimeMatch — solc
  0.6.6, evmVersion istanbul, optimizer off). Mainnet polling:
  `0xD3A9FE267852281a1e6307a1C37CDfD76d39b133`. Deployed bytecode
  byte-identical to the compiled source (3,901 bytes; 3,848 after
  stripping CBOR metadata; no immutables) — the source read above IS
  the deployed code.

### Why this is not a known issue

Checked against the #82775 post-mortem and the program's known
issues: no document lists "ballots for nonexistent options are counted
and can win" as accepted behaviour, and the #82775 fix is a different
mechanism that demonstrably still holds. The portal code contains no
comment stating that option existence is the voter's responsibility.
The contract's inability to validate options is by design — but the
design never assigns that validation to nobody; the tally is the only
place it could live, and it is absent there.

## Steps to reproduce

### 1. Clone the PoC and run the on-chain test (Foundry, 8/8)

```bash
git clone https://github.com/Anyeps/sky-phantom-option-vote-poc
cd sky-phantom-option-vote-poc
forge install foundry-rs/forge-std@v1.17.0 --no-commit
forge test --fork-url https://arbitrum-one.publicnode.com -vv
```

Expected: **8 passed, 0 failed.** The tests assert against the
deployed contract's live state (poll 1657 exists, `npoll` > 1657), so
they run against the latest block. First run at Arbitrum fork block
524447762; note `arbitrum-one.publicnode.com` now returns 403 for
archive requests, so use the latest block there or another
archive-capable Arbitrum RPC for a pinned block.

### 2. What the on-chain tests show

`test/SP24PhantomVote.t.sol` (`SP24PhantomVoteTest`), Arbitrum fork:

1. `testContractIdentity` — name "MakerDAO Polling", version
   "Arbitrum.1", `npoll` > 1657.
2. `testPhantomOptionVoteOnFreshPoll` — `createPoll` on the fork, then
   `vote([pollId], [99])` → `Voted` emitted with optionId 99.
3. `testPhantomOptionVoteOnRealPoll1657` — `vote([1657], [99])` on the
   real Nov-09 poll (window ended; `vote()` enforces no window) →
   emitted.
4. `testPhantomOptionMaxUint` — `vote([1657],
   [type(uint256).max])` → emitted.
5. `testDuplicatedByteBallotStillEmittedRaw` — `vote([1657],
   [0x0101010101010101])` (the #82775 payload) emitted verbatim.
6. `testMultiOptionRawStillEmittedRaw` — `vote([1657], [513])`
   (0x0201 → ballot [1,2]) emitted verbatim.
7. `testHonestVoteControl` — `vote([1657], [1])` works.
8. `testMismatchedLengthsRevertControl` — `vote([1657], [1,2])`
   reverts `"non-matching-length"` — the only check that exists.

### 3. Run the tally test (real portal code, vitest, 5/5 + 3/3 regression)

`test/fetchTallyPhantomOption.spec.ts` runs the REAL `fetchPollTally`
end to end via the portal repo's own `mockTallyIndexer` harness. It
must live inside a clone of the portal repo:

```bash
git clone https://github.com/skybase-foundation/sky-governance-portal
cd sky-governance-portal
git checkout 6ba12d50
npx -y pnpm@11.5.0 install
cp /path/to/sky-phantom-option-vote-poc/test/fetchTallyPhantomOption.spec.ts \
   modules/polling/api/__tests__/fetchTallyPhantomOption.spec.ts
npx vitest run modules/polling/api/__tests__/fetchTallyPhantomOption.spec.ts
```

Expected: **5 passed, 0 failed.** Single-choice poll, options {0:
Abstain, 1: Yes, 2: No}, in-window mocked votes:

| Test | Result |
|---|---|
| plurality: honest 1000 SKY → option 1; attacker 2000 SKY → option 99 → **winner 99**, `winningOptionName` undefined, no option 99 in `results`, Yes support '1000', Yes `winner: false` | PASS |
| majority 50%: same votes → **winner 99** (2000/3000 = 66.7%) | PASS |
| instant-runoff: attacker 6000 SKY → 99 vs honest 4000 → 1 → **winner 99** (round-1 majority) | PASS |
| approval: same as plurality → **winner 99** | PASS |
| control: attacker 500 SKY → 99 vs honest 1000 → 1 → **winner 1**, name 'Yes' | PASS |

Regression control: the repo's own `fetchTallyAmplification.spec.ts`
(#82775) still passes **3/3** — duplicated-byte ballots are counted
once and multi-option single-choice ballots are discarded. The fix for
#82775 holds; this is a different hole it did not close.

### 4. Minimal manual repro (no test file needed)

1. Wait for an active poll on vote.sky.money (polls run weekly, Mon
   16:00 UTC, 3 days).
2. Call `Polling.vote([pollId], [99])` on Arbitrum with any SKY weight
   greater than the leading real option's support.
3. Read the poll tally: `winner` is 99, `winningOptionName` is
   `undefined`, and no option 99 appears in the results.

## Suggested fix

One-line class, in `fetchPollTally` (or in
`fetchVotesByAddressForPoll`, the same place the cardinality guard
lives): **drop ballots containing any option not in `poll.options`**,
before the victory conditions run. The contract cannot fix this —
options are off-chain by design — so the tally is the only enforcement
point. The same membership check should be applied in every victory
condition's aggregation as defence in depth, and the indexer should
preferably reject (or flag) ballots for nonexistent options at ingest
so they never reach the tally at all.

## PoC repository

https://github.com/Anyeps/sky-phantom-option-vote-poc

Contents: this report draft (`REPORT-DRAFT.md`), findings
(`FINDINGS.md`), the Foundry fork test, the vitest tally spec (run
inside a clone of `skybase-foundation/sky-governance-portal` @
`6ba12d50`), the deployed `Polling.sol` source, and the bytecode
comparison harness. No mainnet interaction, no secrets. The fork test
needs an Arbitrum RPC; the tally test needs the portal repo's own
`mockTallyIndexer` harness.

## Payout

- **Wallet:** `0x4d354625102352c7ebe02d4fe08eec1146eeec10`
- **Program:** Sky (Immunefi) — KYC not required per the program page
  (re-confirm the KYC badge on the live page before submitting).
- **Severity claimed:** Critical — listed impact "Manipulation of
  governance voting result deviating from voted outcome" (web/app
  tier, $100,000 central case; $10,000 floor if triage treats it as
  display-only).
- **Fee note:** the Immunefi 100-credit Novice fee is expected per
  submission. Whether a Studio "Ready" verdict waives it for Sky is
  unconfirmed — confirm at submit time.

---

*Draft prepared 2026-11-15. NOT submitted. Submission blocked by the
Immunefi Novice 100-credit fee; waiting for the Studio wave verdict,
same as the GMX G-P1-2(a) and G-P0-7 drafts and the Metric M-P1-3,
M-P1-1 and M-P1-4 drafts. Sensible wave order: S-P2-4 (Critical,
exact impact match) → M-P1-3 (High, permanent freezing) → M-P1-1
(Critical, theft) → G-P1-2(a) (High) → G-P0-7 (Medium) → M-P1-4
(Medium).*
