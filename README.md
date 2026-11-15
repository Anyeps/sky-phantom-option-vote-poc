# Sky (vote.sky.money) — phantom option id wins the poll

**Severity: Critical (web/app tier, $100k central case).**
Immunefi report draft: [`REPORT-DRAFT.md`](REPORT-DRAFT.md).
Full evidence: [`FINDINGS.md`](FINDINGS.md).

A ballot for an option that does **not exist** in the poll can be declared
the winner. Two halves, jointly sufficient:

1. **On-chain:** the Arbitrum polling contract
   `0x4f4e551b4920a5417F8d4e7f8f099660dAdadcEC` (`Polling.sol`, Sourcify
   full match, solc 0.6.6) stores no options — `createPoll` takes only a
   window + IPFS hash. `vote()` checks only that the poll-id and
   option-id arrays have equal length, then emits `Voted` verbatim for
   any `uint256` optionId.
2. **Off-chain:** the portal tally (`fetchPollTally` in
   `skybase-foundation/sky-governance-portal`) never validates that a
   ballot option exists in `poll.options`. The #82775 cardinality guard
   only enforces ballot length 1 for single-choice polls — a single
   phantom option passes it. Every victory condition (plurality,
   majority, approval, IRV) then declares the winner as whichever
   option id carries the most SKY.

Measured: phantom option **99** with 2000 SKY beats honest 1000 SKY for
option 1 and becomes the winner under plurality, majority (66.7%), IRV
and approval; `winningOptionName` is `undefined` and option 99 is
invisible in the per-option results. Maps exactly onto the listed Sky
Critical impact *"Manipulation of governance voting result deviating
from voted outcome"*.

## Run the on-chain fork test (Foundry, 8/8)

```bash
git clone https://github.com/Anyeps/sky-phantom-option-vote-poc
cd sky-phantom-option-vote-poc
forge install foundry-rs/forge-std@v1.17.0 --no-commit
forge test --fork-url https://arbitrum-one.publicnode.com -vv
```

Expected: **8 passed, 0 failed.** The tests assert against the deployed
contract's live state (poll 1657 exists, `npoll` > 1657), so they run
against the latest block. A pinned fork block also works if your RPC
serves archive state — the tests were first run at block 524447762
(`forge test --fork-url <rpc> --fork-block-number 524447762`); note that
`arbitrum-one.publicnode.com` now returns 403 for archive requests, so
use the latest block there or another archive-capable Arbitrum RPC for
a pinned block.

## Run the tally test (real portal code, vitest, 5/5 + 3/3 regression)

`test/fetchTallyPhantomOption.spec.ts` runs the REAL `fetchPollTally`
end to end via the portal repo's own `mockTallyIndexer` harness. It must
live inside a clone of the portal repo:

```bash
git clone https://github.com/skybase-foundation/sky-governance-portal
cd sky-governance-portal
git checkout 6ba12d50
npx -y pnpm@11.5.0 install
cp /path/to/sky-phantom-option-vote-poc/test/fetchTallyPhantomOption.spec.ts \
   modules/polling/api/__tests__/fetchTallyPhantomOption.spec.ts
npx vitest run modules/polling/api/__tests__/fetchTallyPhantomOption.spec.ts
# 5/5 pass; the #82775 regression spec passes 3/3 alongside it:
npx vitest run modules/polling/api/__tests__/fetchTallyAmplification.spec.ts
```

## Bytecode check (no dark spell)

```bash
# compile Polling.sol with solc 0.6.6 / istanbul / optimizer off, compare
# against cast code 0x4f4e551b4920a5417F8d4e7f8f099660dAdadcEC (Arbitrum)
python3 bytecode_cmp.py /tmp/polling-deployed.hex out/Polling.sol/Polling.json
# MATCH, byte-identical after stripping CBOR metadata
```

## Key addresses

- Arbitrum polling: `0x4f4e551b4920a5417F8d4e7f8f099660dAdadcEC`
- Mainnet polling: `0xD3A9FE267852281a1e6307a1C37CDfD76d39b133`
- Portal repo: `skybase-foundation/sky-governance-portal` @ `6ba12d50`

## Files

- `REPORT-DRAFT.md` — submission-ready Immunefi draft (NOT submitted).
- `FINDINGS.md` — full evidence, severity mapping, honest caveats.
- `test/SP24PhantomVote.t.sol` — Foundry fork test, 8/8 pass.
- `test/fetchTallyPhantomOption.spec.ts` — vitest spec (real tally), 5/5.
- `Polling.sol` — deployed source (Sourcify full match).
- `bytecode_cmp.py`, `foundry.toml`, `remappings.txt` — harness.
