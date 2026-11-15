# S-P2-4 — Vote/governance portal: phantom option id wins the poll

## Verdict: FOUND — Critical (web/app tier)

A ballot for an option that does not exist in the poll can be declared the
winner of the poll. The polling contract cannot prevent it (options live
off-chain by design) and the portal tally never checks that a ballot option
exists in `poll.options`. This is a **second, distinct** vote-tally flaw
after Immunefi #82775 (Jul 2026): #82775 was duplicated bytes amplifying
weight; this is an **invalid option id winning outright**. It maps exactly
onto the listed Critical impact "Manipulation of governance voting result
deviating from voted outcome" — $100,000 web/app tier when it changes the
final winner of an active poll.

## 1. What was located (the "work first" step)

The polling contract + portal source were NOT in `sky-ecosystem` (the
`governance-portal` repo there is the Jan-2023 Maker portal; `vote` does
not exist as an org repo). Located via GitHub code search for
`fetchPollTally` + the #82775 post-mortem
(https://forum.skyeco.com/t/post-mortem-for-immunefi-bug-report-82775/28214):

- **Portal repo (live, vote.sky.money): `skybase-foundation/sky-governance-portal`
  @ `6ba12d50` (2026-11-13)** — `modules/polling/api/fetchPollTally.ts`
  (266 lines), `modules/polling/helpers/parseRawOptionId.ts`,
  `modules/polling/api/victory_conditions/{plurality,majority,approval,
  instantRunoff,default,comparison}.ts`,
  `modules/polling/api/fetchVotesByAddress.ts`.
- **Arbitrum polling contract: `0x4f4e551b4920a5417F8d4e7f8f099660dAdadcEC`**
  (from `modules/contracts/generated.ts:1683`, chain 42161). Mainnet polling:
  `0xD3A9FE267852281a1e6307a1C37CDfD76d39b133`.
- **Contract source: `Polling.sol` (3,685 chars), Sourcify full match**
  (creationMatch + runtimeMatch), solc **0.6.6**, evmVersion **istanbul**,
  optimizer **off**. Verified independently below (bytecode MATCH).

Dead ends recorded: `sky-ecosystem/governance-portal` (Jan 2023, old Maker
portal, no `fetchPollTally`); `sky-ecosystem/vote` (does not exist);
chainlog.makerdao.com (Cloudflare 308, JS-only, mainnet-focused anyway);
generic web search for `fetchPollTally`/`parseRawOptionId` (unindexed);
`sky-money` / `skyeco` orgs (do not exist); `skybase` org (4 unrelated
repos). The `skybase-foundation/governance-portal-v2` repo is an older
copy of the same portal code (same files, older ref).

## 2. Root cause

Two halves, each insufficient alone, jointly sufficient:

**(a) On-chain: `Polling.sol` cannot validate options.** `createPoll`
takes only `(startDate, endDate, multiHash, url)` — the option list lives
in the off-chain IPFS document, so the contract has nothing to validate
against. Both `vote()` overloads check ONLY array-length equality and
then emit `Voted` verbatim:

- `Polling.sol:73-80` — `vote(uint256[] pollIds, uint256[] optionIds)`:
  `require(pollIds.length == optionIds.length, "non-matching-length")`,
  then `emit Voted(msg.sender, pollIds[i], optionIds[i])` per entry.
- `Polling.sol:82-...` — EIP-712 gasless `vote(...)`: same length check +
  signature/nonce/expiry checks, same verbatim emission. (Code-read;
  the direct path was fork-tested, the permit path shares the loop.)

No poll-existence check, no window check, no optionId range check.

**(b) Off-chain: the tally never validates option existence.**
`fetchVotesByAddressForPoll` decodes the raw choice with
`parseRawOptionId` (`modules/polling/helpers/parseRawOptionId.ts:25` —
dedup via `Set` only, no range check) and returns the ballot as-is.
`fetchPollTally` (`modules/polling/api/fetchPollTally.ts:86`) applies the
#82775 cardinality guard — single-choice ballots must have
`ballot.length === 1` — which a single phantom option **passes**
(length 1). Every victory condition then declares the winner as
whichever option id carries the most SKY, with no check against
`poll.options`:

- `plurality.ts:44-45`, `approval.ts:48-49` —
  `sortedOptions[0].option` returned directly.
- `majority.ts` — same aggregation; winner is the top option if it
  clears the percent threshold.
- `instantRunoff.ts:74,154` — `winner = parseInt(option)` for any
  first-preference majority / final survivor.
- `comparison.ts` — same aggregation; a phantom option passing the
  threshold is returned first. (Code-read; tested via plurality /
  majority / IRV / approval.)
- Only `default.ts` validates (`options.indexOf(defaultValue) !== -1`).

The per-option `results` array is built from `Object.keys(poll.options)`
only (`fetchPollTally.ts:190,259`), so the phantom winner is invisible
there and `winningOptionName = poll.options[99]` is `undefined` — the
`winner` field itself is the corrupted output.

## 3. Evidence — Part A: on-chain fork test (8/8 pass)

`test/SP24PhantomVote.t.sol`, Arbitrum fork block **524447762**
(`https://arbitrum-one.publicnode.com`), contract
`0x4f4e551b4920a5417F8d4e7f8f099660dAdadcEC`:

| Test | Result |
|---|---|
| `testContractIdentity` — name "MakerDAO Polling", version "Arbitrum.1", `npoll` > 1657 | PASS |
| `testPhantomOptionVoteOnFreshPoll` — createPoll on the fork, then `vote([pollId],[99])` → `Voted` emitted with optionId 99 | PASS |
| `testPhantomOptionVoteOnRealPoll1657` — `vote([1657],[99])` on the real Nov-09 poll (window ended; vote() enforces no window) → emitted | PASS |
| `testPhantomOptionMaxUint` — `vote([1657],[type(uint256).max])` → emitted | PASS |
| `testDuplicatedByteBallotStillEmittedRaw` — `vote([1657],[0x0101010101010101])` (#82775 payload) emitted verbatim | PASS |
| `testMultiOptionRawStillEmittedRaw` — `vote([1657],[513])` (0x0201 → ballot [1,2]) emitted verbatim | PASS |
| `testHonestVoteControl` — `vote([1657],[1])` works | PASS |
| `testMismatchedLengthsRevertControl` — `vote([1657],[1,2])` reverts `"non-matching-length"` | PASS |

## 4. Evidence — Part B: real tally code (vitest, 5/5 + 3/3 regression)

`test/fetchTallyPhantomOption.spec.ts` (copy in this PoC's `test/`;
original added to the cloned portal repo at
`modules/polling/api/__tests__/fetchTallyPhantomOption.spec.ts`), run
with the repo's own `mockTallyIndexer` harness — the REAL
`fetchPollTally` end to end. Single-choice poll, options
{0: Abstain, 1: Yes, 2: No}, in-window mocked votes:

| Test | Result |
|---|---|
| plurality: honest 1000 SKY → option 1; attacker 2000 SKY → option 99 → **winner 99**, `winningOptionName` undefined, no option 99 in `results`, Yes support '1000', Yes `winner: false` | PASS |
| majority 50%: same votes → **winner 99** (2000/3000 = 66.7%) | PASS |
| instant-runoff: attacker 6000 SKY → 99 vs honest 4000 → 1 → **winner 99** (round-1 majority) | PASS |
| approval: same as plurality → **winner 99** | PASS |
| control: attacker 500 SKY → 99 vs honest 1000 → 1 → **winner 1**, name 'Yes' | PASS |

Regression control: the repo's own
`fetchTallyAmplification.spec.ts` (#82775) still passes **3/3** —
duplicated-byte ballots are counted once and multi-option single-choice
ballots are discarded. The fix for #82775 holds; this is a different
hole it did not close. (Unrelated test-env noise: MetaMask analytics
fetch fails with EPROTO in the sandbox; assertions unaffected.)

## 5. Evidence — bytecode (no dark spell)

Deployed Arbitrum polling contract is **byte-identical** to
`Polling.sol` compiled with solc 0.6.6 / istanbul / optimizer off:
3,901 bytes, 3,848 after stripping CBOR metadata, no immutables
(`bytecode_cmp.py`, `/tmp/bcbuild-polling`). Sourcify reports
creationMatch + runtimeMatch. The source read in §2 IS the deployed code.

## 6. Severity mapping + honest caveats

- **Central case: Critical, web/app tier $100,000.** The tally's
  `winner` field — the value governance reads to decide a poll — is
  flipped from a real option to a nonexistent one. That is verbatim
  the listed Critical impact "Manipulation of governance voting result
  deviating from voted outcome", and it changes the final winner of an
  active poll (not display-only: the `winner` field, not just a
  percentage, is corrupted).
- **What it needs:** (1) an active poll — polls run weekly (Mon 16:00
  UTC, 3 days); 0 active at check time (15 Nov), next opens ~17 Nov;
  the vote must be cast in-window (the indexer drops out-of-window
  votes) and (2) more SKY weight than the leading real option's
  support — the attacker's OWN weight, no amplification. Realistic for
  a whale/delegate in a low-turnout poll; the bar is higher than
  #82775's (which multiplied a small weight).
- **Honest flags:** (1) polls are off-chain signal — the winner does
  not execute anything on-chain by itself; governance still has to act
  on it. (2) The corruption is LOUD: `winningOptionName` is
  `undefined` and no option is marked winner in the per-option
  results, so a human reading the poll page sees a broken outcome, not
  a plausible fake winner. Triage could argue $10k (display-only) if
  it treats the broken display as the whole effect — but the `winner`
  field itself is the program's decision input, which is the $100k
  case. (3) The EIP-712 gasless path was code-read, not fork-tested
  (same emission loop, no validation). (4) `comparison` was code-read,
  not vitest-tested (identical aggregation pattern).
- **Fix (one line class):** in `fetchPollTally` (or
  `fetchVotesByAddressForPoll`), drop ballots containing any option not
  in `poll.options` — the same place the cardinality guard lives. The
  contract cannot fix this: options are off-chain by design.
- **Submission note:** this is the first Sky finding that maps exactly
  onto a listed Critical impact at the top tier. No draft written per
  task constraints; Studio-wave candidate (same 100-credit fee question
  as the other Immunefi programs — confirm waiver at submit time).

## 7. Harness lessons

- GitHub code search (`search_code` via the official connector) finds
  repos the web cannot: `fetchPollTally` is unindexed by web search
  but instantly locates `skybase-foundation/sky-governance-portal`.
- The live portal is NOT under `sky-ecosystem` (that org's
  `governance-portal` is the Jan-2023 Maker portal). The Sky-era code
  lives under `skybase-foundation/`.
- Sourcify API v1 is removed; use v2
  `?fields=sources,metadata`. Arbiscan curl is bot-blocked (empty
  reply); Sourcify v2 is the reliable source path.
- `forge build` auto-installs old solc via svm (0.6.6 worked first
  try); `evm_version = 'istanbul'` + `optimizer = false` reproduces
  the deployed build exactly.
- The portal repo uses pnpm 11.5.0 (no pnpm/corepack on PATH — use
  `npx -y pnpm@11.5.0 install`, ~3 min). Its own
  `mockTallyIndexer` + vitest specs are the faithful way to drive the
  REAL tally code; do not re-implement the tally in Solidity.
- `vm.recordLogs` + topic matching is the robust way to assert
  `Voted` emissions (topics: [sig, voter, pollId, optionId]).

## 8. Files

- `test/SP24PhantomVote.t.sol` — Foundry fork test, 8/8 pass, Arbitrum
  fork block 524447762.
- `test/fetchTallyPhantomOption.spec.ts` — vitest spec (real
  `fetchPollTally`), 5/5 pass; regression spec 3/3 pass.
- `Polling.sol` — deployed source (Sourcify full match).
- `bytecode_cmp.py`, `foundry.toml`, `remappings.txt` — harness.
- `FINDINGS.md` (this file), `README.md`.
- Portal repo clone: `~/workspace/hunts/sky/repos/sky-gov-portal/`
  @ `6ba12d50` (spec added at
  `modules/polling/api/__tests__/fetchTallyPhantomOption.spec.ts`).
