/*

SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>

SPDX-License-Identifier: AGPL-3.0-or-later

*/

/**
 * Second vote-tally flaw (S-P2-4): phantom option id wins the poll.
 *
 * The polling contract stores NO options on-chain (createPoll takes only a
 * window + IPFS multihash), and vote() accepts any uint256 optionId,
 * emitting it verbatim in Voted. The portal is therefore the ONLY layer
 * that could reject an option that is not part of the poll — and it does
 * not: fetchVotesByAddressForPoll decodes the raw choice with
 * parseRawOptionId (dedup only, no range check), the cardinality guard
 * only enforces ballot length 1 for single-choice polls, and every
 * victory condition (plurality, majority, approval, instant-runoff,
 * comparison) declares the winner as whichever option id carries the most
 * SKY, without checking that the id exists in poll.options. Only
 * extractWinnerDefault validates (options.indexOf(defaultValue) !== -1).
 *
 * These tests exercise fetchPollTally end-to-end and assert that:
 *  - a single-choice ballot for a nonexistent option (99) passes the
 *    cardinality guard and is declared the winner by plurality, majority
 *    and instant-runoff when it carries the most SKY;
 *  - the phantom winner is invisible in the per-option results (built
 *    from poll.options only) and winningOptionName is undefined;
 *  - a phantom option with LESS weight than the leading real option does
 *    not win (control).
 */

import { PollInputFormat, PollResultDisplay, PollVictoryConditions } from 'modules/polling/polling.constants';
import { Poll } from 'modules/polling/types';
import { SupportedNetworks } from 'modules/web3/constants/networks';
import { gqlRequest } from '../../../../modules/gql/gqlRequest';
import { mockTallyIndexer } from './__helpers__/mockTallyIndexer';
import { fetchPollTally } from '../fetchPollTally';
import { Mock, vi } from 'vitest';

vi.mock('modules/gql/gqlRequest');

// Poll window enclosing every mocked vote; votes outside it are not counted.
const POLL_START = 50;
const POLL_END = 200;

const PHANTOM_OPTION = '99';

const basePoll = (victoryConditions: any): Poll =>
  ({
    pollId: 1,
    options: {
      '0': 'Abstain',
      '1': 'Yes',
      '2': 'No'
    },
    parameters: {
      inputFormat: {
        type: PollInputFormat.singleChoice,
        abstain: [0],
        options: []
      },
      resultDisplay: PollResultDisplay.singleVoteBreakdown,
      victoryConditions
    }
  } as any as Poll);

function mockVotes(gqlRequestMock: Mock, honestSky: string, attackerSky: string, attackerChoice: string) {
  mockTallyIndexer(gqlRequestMock, {
    delegates: {},
    mainnet: { pollVotes: [] },
    arbitrum: {
      arbitrumPoll: {
        startDate: POLL_START,
        endDate: POLL_END,
        votes: [
          // Honest voter on real option 1 ("Yes").
          { voter: { id: '0x456' }, choice: '1', blockTime: 100 },
          // Attacker on phantom option 99 (not a poll option).
          { voter: { id: '0x123' }, choice: attackerChoice, blockTime: 100 }
        ]
      }
    },
    weights: {
      voters: [
        { id: '0x456', v2VotingPowerChanges: [{ newBalance: honestSky }] },
        { id: '0x123', v2VotingPowerChanges: [{ newBalance: attackerSky }] }
      ]
    }
  });
}

describe('Fetch tally - phantom option id wins (S-P2-4)', () => {
  it('plurality: phantom option 99 wins a single-choice poll when it carries the most SKY', async () => {
    mockVotes(gqlRequest as Mock, '1000000000000000000000', '2000000000000000000000', PHANTOM_OPTION);

    const result = await fetchPollTally(
      basePoll([{ type: PollVictoryConditions.plurality }]),
      SupportedNetworks.MAINNET
    );

    // The phantom option is declared the winner even though it is not a poll option.
    expect(result.winner).toBe(99);
    // No name exists for it, and the per-option results never show it.
    expect(result.winningOptionName).toBeUndefined();
    expect(result.results.find(r => r.optionId === 99)).toBeUndefined();
    expect(result.results.find(r => r.optionId === 1)?.skySupport).toBe('1000');
    expect(result.results.find(r => r.optionId === 1)?.winner).toBe(false);
  });

  it('majority: phantom option 99 wins with >50% of the vote', async () => {
    mockVotes(gqlRequest as Mock, '1000000000000000000000', '2000000000000000000000', PHANTOM_OPTION);

    const result = await fetchPollTally(
      basePoll([{ type: PollVictoryConditions.majority, percent: 50 }]),
      SupportedNetworks.MAINNET
    );

    expect(result.winner).toBe(99);
    expect(result.winningOptionName).toBeUndefined();
  });

  it('instant-runoff: phantom option 99 wins round 1 with a first-preference majority', async () => {
    mockVotes(gqlRequest as Mock, '4000000000000000000000', '6000000000000000000000', PHANTOM_OPTION);

    const result = await fetchPollTally(
      basePoll([{ type: PollVictoryConditions.instantRunoff }]),
      SupportedNetworks.MAINNET
    );

    expect(result.winner).toBe(99);
  });

  it('approval: phantom option 99 wins when it carries the most SKY', async () => {
    mockVotes(gqlRequest as Mock, '1000000000000000000000', '2000000000000000000000', PHANTOM_OPTION);

    const result = await fetchPollTally(
      basePoll([{ type: PollVictoryConditions.approval }]),
      SupportedNetworks.MAINNET
    );

    expect(result.winner).toBe(99);
  });

  it('control: phantom option with less SKY than the leader does not win', async () => {
    mockVotes(gqlRequest as Mock, '1000000000000000000000', '500000000000000000000', PHANTOM_OPTION);

    const result = await fetchPollTally(
      basePoll([{ type: PollVictoryConditions.plurality }]),
      SupportedNetworks.MAINNET
    );

    expect(result.winner).toBe(1);
    expect(result.winningOptionName).toBe('Yes');
  });
});
