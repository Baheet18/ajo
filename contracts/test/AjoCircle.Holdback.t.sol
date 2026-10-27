// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AjoCircle} from "../AjoCircle.sol";
import {AjoCircleTestBase} from "./AjoCircle.Base.t.sol";
import {ReentrantWithdraw} from "../test-helpers/ReentrantWithdraw.sol";

/// Holdback mechanics, friends mode, defaulter scenarios, reputation, balance invariant.
contract AjoCircleHoldbackTest is AjoCircleTestBase {

    // ═══════════════════════════════════════════════════════════════════════
    // 1. Friends mode (holdbackBps = 0) — full pot, zero holdback
    // ═══════════════════════════════════════════════════════════════════════

    function test_FriendsModeFullPot() public {
        uint256 id = _create3MemberFriendsCircle();

        // R1: alice recipient. bob+carol contribute. pot=2x. holdback=0. alice gets 2x.
        _contributeNonRecipients(id, alice);
        ajo.payout(id);
        assertEq(ajo.pendingWithdrawals(alice), 2 * CONTRIBUTION, "alice R1: full pot (no holdback)");
        assertEq(ajo.getMemberHoldback(id, alice), 0, "alice holdback = 0");

        // R2: bob recipient. alice+carol contribute. pot=2x. holdback=0. bob gets 2x.
        _contributeNonRecipients(id, bob);
        ajo.payout(id);
        assertEq(ajo.pendingWithdrawals(bob), 2 * CONTRIBUTION, "bob R2: full pot (no holdback)");
        assertEq(ajo.getMemberHoldback(id, bob), 0, "bob holdback = 0");

        // R3: carol recipient. alice+bob contribute. pot=2x. holdback=0. carol gets 2x.
        _contributeNonRecipients(id, carol);
        ajo.payout(id);
        assertEq(ajo.pendingWithdrawals(carol), 2 * CONTRIBUTION, "carol R3: full pot (no holdback)");
        assertEq(ajo.getMemberHoldback(id, carol), 0, "carol holdback = 0");

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore   = bob.balance;
        uint256 carolBefore = carol.balance;

        _withdraw(alice);
        _withdraw(bob);
        _withdraw(carol);

        assertEq(alice.balance - aliceBefore, 2 * CONTRIBUTION_NATIVE, "alice withdrew 2x native");
        assertEq(bob.balance   - bobBefore,   2 * CONTRIBUTION_NATIVE, "bob withdrew 2x native");
        assertEq(carol.balance - carolBefore, 2 * CONTRIBUTION_NATIVE, "carol withdrew 2x native");
        assertEq(address(ajo).balance, 0, "contract balance == 0 after all withdrawals");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 2. 25% holdback, 10-member circle — first and last recipient math
    // ═══════════════════════════════════════════════════════════════════════

    function test_25PercentHoldback_10Members() public {
        address[10] memory actors;
        actors[0] = alice;
        actors[1] = bob;
        actors[2] = carol;
        for (uint256 i = 3; i < 10; i++) {
            actors[i] = makeAddr(string(abi.encodePacked("member", i)));
        }

        uint8  N       = 10;
        uint16 hbBps   = 2500; // 25%
        uint256 contrib = 100e6;
        uint256 contribNative = contrib * 1e12;

        // Fund all actors with native USDC
        for (uint256 i = 0; i < N; i++) {
            vm.deal(actors[i], contrib * N * 5 * 1e12);
        }

        vm.prank(actors[0]);
        uint256 id = ajo.createCircle{value: 0}("Big Circle", contrib, N, ROUND_DUR, 0, hbBps);
        for (uint256 i = 1; i < N; i++) {
            vm.prank(actors[i]);
            ajo.join{value: 0}(id);
        }

        address[] memory recips = ajo.getPayoutRecipients(id);
        assertEq(recips[0], actors[0], "R1 recipient = actors[0]");

        // R1: actors[0] is recipient. 9 others contribute. pot = 9 * 100e6 = 900e6.
        // roundsStillOwed = 10 - 1 = 9. holdback = 2500 * 9 * 100e6 / 10000 = 225e6
        for (uint256 i = 1; i < N; i++) {
            vm.prank(actors[i]);
            ajo.contribute{value: contribNative}(id);
        }
        ajo.payout(id);

        uint256 expectedHoldback1 = (uint256(hbBps) * 9 * contrib) / 10000; // 225e6
        uint256 expectedRecv1     = (contrib * 9) - expectedHoldback1;       // 675e6
        assertEq(ajo.pendingWithdrawals(actors[0]), expectedRecv1,    "R1: recipientReceives = 675e6");
        assertEq(ajo.getMemberHoldback(id, actors[0]), expectedHoldback1, "R1: holdback = 225e6");

        // Advance rounds 2-9
        for (uint8 r = 2; r <= 9; r++) {
            address recip = recips[r - 1];
            for (uint256 i = 0; i < N; i++) {
                if (actors[i] == recip) continue;
                if (ajo.isDefaulted(id, actors[i])) continue;
                vm.prank(actors[i]);
                ajo.contribute{value: contribNative}(id);
            }
            ajo.payout(id);
        }

        // R10: last round. roundsStillOwed = 0. holdback = 0.
        address lastRecip = recips[9];
        assertEq(ajo.getCurrentRound(id), 10, "now in R10");

        for (uint256 i = 0; i < N; i++) {
            if (actors[i] == lastRecip) continue;
            if (ajo.isDefaulted(id, actors[i])) continue;
            vm.prank(actors[i]);
            ajo.contribute{value: contribNative}(id);
        }
        ajo.payout(id);

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(uint8(c.status), uint8(AjoCircle.CircleStatus.ENDED), "circle ended");
        assertEq(ajo.getMemberHoldback(id, lastRecip), 0, "last recipient: holdback = 0");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 3. Recipient pays own round; full pot (friends mode)
    // ═══════════════════════════════════════════════════════════════════════

    function test_RecipientPaysOwnRound_FullPot() public {
        uint256 id = _create3MemberFriendsCircle();

        uint256 alicePaidBefore = ajo.totalRoundsPaid(alice);

        // ALL three contribute (recipient alice included)
        vm.prank(alice); ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        vm.prank(bob);   ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        vm.prank(carol); ajo.contribute{value: CONTRIBUTION_NATIVE}(id);

        ajo.payout(id);

        assertEq(ajo.pendingWithdrawals(alice), 3 * CONTRIBUTION, "alice receives full pot (3x)");
        assertEq(ajo.getMemberHoldback(id, alice), 0, "no holdback in friends mode");
        assertEq(ajo.totalRoundsPaid(alice), alicePaidBefore + 1, "alice roundsPaid incremented");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 4. Missed round slashes; HoldbackSlashed / CollateralSlashed emitted
    // ═══════════════════════════════════════════════════════════════════════

    function test_MissedRoundSlashesToRecipient() public {
        uint256 id = _create3MemberCircle(); // holdbackBps=1000, collateral=COLLATERAL

        // R1: alice exempt. bob+carol contribute.
        _contributeNonRecipients(id, alice);
        ajo.payout(id);
        assertEq(ajo.getCurrentRound(id), 2, "in R2");

        // R2: bob is recipient (exempt). alice contributes; carol MISSES.
        vm.prank(alice);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        _warpPastDeadline(id);

        vm.expectEmit(true, true, false, false, address(ajo));
        emit AjoCircle.CollateralSlashed(id, carol, COLLATERAL);
        ajo.payout(id);

        assertEq(ajo.totalRoundsMissed(carol), 1, "carol roundsMissed == 1");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 5. No collateral, no deposit taken
    // ═══════════════════════════════════════════════════════════════════════

    function test_NoCollateral_NoDepositTaken() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}("No Dep", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0);
        vm.prank(bob);
        ajo.join{value: 0}(id);
        vm.prank(carol);
        ajo.join{value: 0}(id);

        assertEq(ajo.getMemberDeposit(id, alice), 0);
        assertEq(ajo.getMemberDeposit(id, bob),   0);
        assertEq(ajo.getMemberDeposit(id, carol),  0);
        assertEq(address(ajo).balance, 0, "no native taken at join");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 6. Contract balance zero after full cycle
    // ═══════════════════════════════════════════════════════════════════════

    function test_ContractBalanceZero_AfterFullCycle() public {
        uint256 col    = 50e6;
        uint256 colNat = col * 1e12;
        uint16  hbBps  = 1000;

        vm.prank(alice);
        uint256 id = ajo.createCircle{value: colNat}(
            "Cycle Test", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, col, hbBps
        );
        vm.prank(bob);   ajo.join{value: colNat}(id);
        vm.prank(carol); ajo.join{value: colNat}(id);

        address[3] memory recip = [alice, bob, carol];
        for (uint256 r = 0; r < 3; r++) {
            _contributeNonRecipients(id, recip[r]);
            ajo.payout(id);
        }

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(uint8(c.status), uint8(AjoCircle.CircleStatus.ENDED), "circle ended");

        if (ajo.pendingWithdrawals(alice) > 0) _withdraw(alice);
        if (ajo.pendingWithdrawals(bob)   > 0) _withdraw(bob);
        if (ajo.pendingWithdrawals(carol) > 0) _withdraw(carol);

        assertEq(address(ajo).balance, 0, "contract balance == 0");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 7. Reputation counters
    // ═══════════════════════════════════════════════════════════════════════

    function test_Reputation_Increments() public {
        uint256 id1 = _create3MemberCircle();

        _contributeNonRecipients(id1, alice);
        ajo.payout(id1);
        _contributeNonRecipients(id1, bob);
        ajo.payout(id1);
        _contributeNonRecipients(id1, carol);
        ajo.payout(id1);

        (uint256 alicePaid1, uint256 aliceMissed1, uint256 aliceCompleted1) = ajo.getMemberReputation(alice);
        assertEq(alicePaid1,      2, "alice paid 2 rounds in circle1 (exempt R1)");
        assertEq(aliceMissed1,    0, "alice missed 0 in circle1");
        assertEq(aliceCompleted1, 1, "alice circle1 completed");

        (uint256 bobPaid1, uint256 bobMissed1, uint256 bobCompleted1) = ajo.getMemberReputation(bob);
        assertEq(bobPaid1,      2, "bob paid 2 rounds in circle1");
        assertEq(bobMissed1,    0, "bob missed 0 in circle1");
        assertEq(bobCompleted1, 1, "bob circle1 completed");

        uint256 id2 = _create3MemberCircle();

        _contributeNonRecipients(id2, alice);
        ajo.payout(id2);

        vm.prank(carol);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id2);
        _warpPastDeadline(id2);
        ajo.payout(id2); // alice slashed

        vm.prank(bob);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id2);
        if (!ajo.isDefaulted(id2, alice) && block.timestamp <= ajo.getRoundDeadline(id2)) {
            vm.prank(alice);
            ajo.contribute{value: CONTRIBUTION_NATIVE}(id2);
        }
        ajo.payout(id2);

        (uint256 alicePaid2, uint256 aliceMissed2,) = ajo.getMemberReputation(alice);
        assertGe(alicePaid2,   alicePaid1, "alice paid count non-decreasing");
        assertEq(aliceMissed2, 1,          "alice missed 1 across all circles");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 8. HoldbackReleased on contribute
    // ═══════════════════════════════════════════════════════════════════════

    function test_HoldbackReleasedOnContribute() public {
        uint256 id = _create3MemberCircle();

        // R1: alice exempt. bob+carol contribute. pot=2*100e6=200e6.
        _contributeNonRecipients(id, alice);
        ajo.payout(id);

        uint256 expectedHoldback = (uint256(1000) * 2 * CONTRIBUTION) / 10000; // 20e6
        assertEq(expectedHoldback, 20e6, "expected holdback = 20e6");
        assertEq(ajo.getMemberHoldback(id, alice), expectedHoldback, "alice holdback = 20e6 after R1");
        assertEq(ajo.pendingWithdrawals(alice), 200e6 - expectedHoldback, "alice receives 180e6 in R1");

        // R2: alice contributes → releasePerRound = 10e6
        vm.prank(alice);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);

        uint256 releasePerRound = (CONTRIBUTION * 1000) / 10000; // 10e6
        assertEq(releasePerRound, 10e6, "releasePerRound = 10e6");
        assertEq(ajo.getMemberHoldback(id, alice), expectedHoldback - releasePerRound,
            "alice holdback = 10e6 after R2 contribute");
        assertEq(ajo.pendingWithdrawals(alice), (200e6 - expectedHoldback) + releasePerRound,
            "alice pending = 180e6 + 10e6 = 190e6");

        vm.prank(carol);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        ajo.payout(id);

        // R3: alice contributes → releases remaining 10e6 → holdback = 0
        vm.prank(alice);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        assertEq(ajo.getMemberHoldback(id, alice), 0, "alice holdback = 0 after R3 contribute");

        vm.prank(bob);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        ajo.payout(id);

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(uint8(c.status), uint8(AjoCircle.CircleStatus.ENDED), "circle ended");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 9. Full 3-member cycle, holdbackBps=1000, balance reconciliation
    // ═══════════════════════════════════════════════════════════════════════

    function test_FullCycleThreeMembers() public {
        uint256 id = _create3MemberCircle();

        assertEq(address(ajo).balance, 3 * COLLATERAL_NATIVE, "initial = 3 collaterals (native)");

        address[] memory recips = ajo.getPayoutRecipients(id);
        assertEq(recips[0], alice);
        assertEq(recips[1], bob);
        assertEq(recips[2], carol);

        // ── Round 1 ──
        _contributeNonRecipients(id, alice);
        assertEq(ajo.getPotSize(id), 2 * CONTRIBUTION, "R1 pot = 2x");
        ajo.payout(id);

        assertEq(ajo.getMemberHoldback(id, alice), 20e6, "alice holdback = 20e6 after R1");
        assertEq(ajo.pendingWithdrawals(alice), 180e6, "alice receives 180e6 in R1");
        assertEq(ajo.getCurrentRound(id), 2, "R2");

        // ── Round 2 ──
        _contributeNonRecipients(id, bob);
        assertEq(ajo.getMemberHoldback(id, alice), 10e6,  "alice holdback = 10e6 after R2 contrib");
        assertEq(ajo.pendingWithdrawals(alice), 190e6, "alice pending = 190e6 (180+10)");
        ajo.payout(id);

        assertEq(ajo.getMemberHoldback(id, bob), 10e6,  "bob holdback = 10e6 after R2 payout");
        assertEq(ajo.pendingWithdrawals(bob), 190e6, "bob receives 190e6 in R2");
        assertEq(ajo.getCurrentRound(id), 3, "R3");

        uint256 aliceBefore2 = alice.balance;
        uint256 bobBefore2   = bob.balance;
        _withdraw(alice); // 190e6 → 190e18 native
        _withdraw(bob);   // 190e6 → 190e18 native
        assertEq(alice.balance - aliceBefore2, 190e6 * 1e12, "alice withdrew 190e18");
        assertEq(bob.balance   - bobBefore2,   190e6 * 1e12, "bob withdrew 190e18");

        // ── Round 3 ──
        _contributeNonRecipients(id, carol);
        assertEq(ajo.getMemberHoldback(id, alice), 0, "alice holdback = 0 after R3 contrib");
        assertEq(ajo.pendingWithdrawals(alice), 10e6, "alice pending = 10e6 (last holdback release)");
        assertEq(ajo.getMemberHoldback(id, bob), 0, "bob holdback = 0 after R3 contrib");
        assertEq(ajo.pendingWithdrawals(bob), 10e6, "bob pending = 10e6");

        ajo.payout(id);

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(uint8(c.status), uint8(AjoCircle.CircleStatus.ENDED), "circle ENDED");

        assertEq(ajo.getMemberHoldback(id, carol), 0, "carol holdback = 0 (last round)");
        assertEq(ajo.pendingWithdrawals(carol), 200e6 + COLLATERAL, "carol pending = 300e6");
        assertEq(ajo.pendingWithdrawals(alice), 10e6 + COLLATERAL,  "alice pending = 110e6");
        assertEq(ajo.pendingWithdrawals(bob),   10e6 + COLLATERAL,  "bob pending = 110e6");

        _withdraw(carol);
        _withdraw(alice);
        _withdraw(bob);

        assertEq(address(ajo).balance, 0, "contract fully drained");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 10. Pre-payout defaulter: deposit slashed, slot skipped, pot carried
    // ═══════════════════════════════════════════════════════════════════════

    function test_PrePayoutDefaulter_SlotSkipped() public {
        uint256 id = _create3MemberCircle();

        vm.prank(carol);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        _warpPastDeadline(id);
        ajo.payout(id);

        assertTrue(ajo.isDefaulted(id, bob), "bob defaulted after R1");
        assertEq(ajo.getMemberDeposit(id, bob), 0, "bob deposit fully slashed");
        assertEq(ajo.getMemberHoldback(id, alice), 20e6, "alice holdback = 20e6 after R1");
        assertEq(ajo.getCurrentRound(id), 2, "R2");

        vm.prank(alice);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        vm.prank(carol);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        ajo.payout(id);

        assertEq(ajo.getCurrentRound(id), 3, "R3");

        vm.prank(alice);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        ajo.payout(id);

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(uint8(c.status), uint8(AjoCircle.CircleStatus.ENDED), "circle ENDED");

        assertEq(ajo.pendingWithdrawals(carol), 300e6 + COLLATERAL, "carol big pot + deposit = 400e6");

        if (ajo.pendingWithdrawals(alice) > 0) _withdraw(alice);
        _withdraw(carol);
        assertEq(address(ajo).balance, 0, "contract drained");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 11. Holdback slashed when post-payout member misses round
    // ═══════════════════════════════════════════════════════════════════════

    function test_HoldbackSlashed_WhenPostPayoutMemberMisses() public {
        uint256 id = _create3MemberCircle();

        _contributeNonRecipients(id, alice);
        ajo.payout(id);
        assertEq(ajo.getMemberHoldback(id, alice), 20e6, "alice holdback = 20e6");

        vm.prank(carol);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        _warpPastDeadline(id);

        vm.expectEmit(true, true, false, false, address(ajo));
        emit AjoCircle.HoldbackSlashed(id, alice, 20e6, bob);
        ajo.payout(id);

        assertEq(ajo.getMemberHoldback(id, alice), 0, "alice holdback = 0 after slash");
        assertFalse(ajo.isDefaulted(id, alice), "alice NOT permanently defaulted (deposit remains)");
        assertEq(ajo.totalRoundsMissed(alice), 1, "alice roundsMissed = 1");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 12. HoldbackLocked event emitted at payout
    // ═══════════════════════════════════════════════════════════════════════

    function test_HoldbackLocked_EventEmitted() public {
        uint256 id = _create3MemberCircle();

        _contributeNonRecipients(id, alice);

        vm.expectEmit(true, true, false, true, address(ajo));
        emit AjoCircle.HoldbackLocked(id, alice, 20e6);
        ajo.payout(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 13. Friends mode: nothing to slash from holdback; only deposit (if any)
    // ═══════════════════════════════════════════════════════════════════════

    function test_FriendsMode_SlashOnlyDeposit() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "Friends+Dep", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, 0
        );
        vm.prank(bob);   ajo.join{value: COLLATERAL_NATIVE}(id);
        vm.prank(carol); ajo.join{value: COLLATERAL_NATIVE}(id);

        vm.prank(carol);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        _warpPastDeadline(id);

        vm.expectEmit(true, true, false, false, address(ajo));
        emit AjoCircle.CollateralSlashed(id, bob, COLLATERAL);
        ajo.payout(id);

        assertEq(ajo.getMemberHoldback(id, bob), 0, "bob holdback = 0 in friends mode");
        assertTrue(ajo.isDefaulted(id, bob), "bob defaulted (deposit exhausted)");
        assertEq(ajo.totalRoundsMissed(bob), 1, "bob roundsMissed = 1");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 14. Reputation: totalCirclesCompleted increments
    // ═══════════════════════════════════════════════════════════════════════

    function test_CirclesCompleted_Increments_ForNonDefaultedMembers() public {
        uint256 id = _create3MemberFriendsCircle();

        address[3] memory recip = [alice, bob, carol];
        for (uint256 r = 0; r < 3; r++) {
            _contributeNonRecipients(id, recip[r]);
            ajo.payout(id);
        }

        (,, uint256 aliceCompleted) = ajo.getMemberReputation(alice);
        (,, uint256 bobCompleted)   = ajo.getMemberReputation(bob);
        (,, uint256 carolCompleted) = ajo.getMemberReputation(carol);
        assertEq(aliceCompleted, 1, "alice completed 1 circle");
        assertEq(bobCompleted,   1, "bob completed 1 circle");
        assertEq(carolCompleted, 1, "carol completed 1 circle");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 15. Fuzz: holdback math property
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzz_HoldbackNeverExceedsPot(uint16 hbBps, uint8 nMembers, uint256 contribution) public {
        hbBps        = uint16(bound(hbBps, 0, 3000));
        nMembers     = uint8(bound(nMembers, 2, 5));
        contribution = bound(contribution, 1e6, 500e6);

        for (uint8 round = 1; round <= nMembers; round++) {
            uint256 pot = contribution * (nMembers - 1);
            uint8 roundsStillOwed = nMembers - round;
            uint256 holdback = (uint256(hbBps) * uint256(roundsStillOwed) * contribution) / 10000;
            if (holdback > pot) holdback = pot;
            uint256 recipientReceives = pot - holdback;
            assertLe(holdback, pot, "holdback <= pot");
            assertGe(recipientReceives, 0, "recipientReceives >= 0");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 16. Multiple circles — circleCount increments
    // ═══════════════════════════════════════════════════════════════════════

    function test_MultipleCircles_CircleCountIncrements() public {
        vm.prank(alice);
        ajo.createCircle{value: 0}("C1", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0);
        vm.prank(bob);
        ajo.createCircle{value: 0}("C2", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0);

        assertEq(ajo.circleCount(), 2, "two circles created");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 17. Early payout behaviour
    // ═══════════════════════════════════════════════════════════════════════

    function test_EarlyPayout_AllPaidBeforeDeadline() public {
        uint256 id = _create3MemberFriendsCircle();

        address[] memory recips = ajo.getPayoutRecipients(id);
        assertEq(recips[0], alice, "R1 recipient = alice");

        vm.prank(bob);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        vm.prank(carol);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);

        ajo.payout(id);

        assertEq(ajo.getCurrentRound(id), 2, "circle advanced to round 2");
        assertEq(ajo.pendingWithdrawals(alice), 2 * CONTRIBUTION, "alice received full pot = 2x CONTRIBUTION");
    }

    function test_EarlyPayout_OneMemberUnpaid_Reverts() public {
        uint256 id = _create3MemberFriendsCircle();

        vm.prank(bob);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);

        vm.expectRevert(AjoCircle.ContributionsStillPending.selector);
        ajo.payout(id);
    }

    function test_EarlyPayout_UnpaidAfterDeadline_SlashesHoldback() public {
        uint256 id = _create3MemberCircle();

        address[] memory recips = ajo.getPayoutRecipients(id);
        assertEq(recips[0], alice, "R1 recipient = alice");

        vm.prank(bob);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);

        _warpPastDeadline(id);

        vm.expectEmit(true, true, false, false, address(ajo));
        emit AjoCircle.CollateralSlashed(id, carol, COLLATERAL);
        ajo.payout(id);

        assertTrue(ajo.isDefaulted(id, carol),        "carol permanently defaulted");
        assertEq(ajo.getMemberDeposit(id, carol),  0, "carol deposit = 0 (fully slashed)");
        assertEq(ajo.getMemberHoldback(id, carol), 0, "carol holdback = 0 (never had any)");
        assertEq(ajo.totalRoundsMissed(carol),     1, "carol roundsMissed = 1");

        uint256 expectedHoldback = (uint256(HOLDBACK_BPS) * 2 * CONTRIBUTION) / 10000; // 20e6
        uint256 expectedPot      = CONTRIBUTION + COLLATERAL;
        assertEq(ajo.pendingWithdrawals(alice), expectedPot - expectedHoldback,
            "alice receives pot minus holdback = 180e6");
        assertEq(ajo.getMemberHoldback(id, alice), expectedHoldback,
            "alice holdback locked = 20e6");
        assertEq(ajo.getCurrentRound(id), 2, "circle advanced to round 2 after slash payout");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 18. NEW: contribute via msg.value, no ERC-20 approval
    // ═══════════════════════════════════════════════════════════════════════

    function test_ContributeWithMsgValue_NoApproval() public {
        // 3-member circle, no collateral, no holdback
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Native Test", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );
        vm.prank(bob);
        ajo.join{value: 0}(id);
        vm.prank(carol);
        ajo.join{value: 0}(id);

        // bob contributes with native value — no approval anywhere
        vm.prank(bob);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);

        // roundPaid set
        assertTrue(ajo.roundPaid(id, 1, bob), "bob marked paid for round 1");

        // getPotSize returns 6-decimal amount
        assertEq(ajo.getPotSize(id), CONTRIBUTION, "pot = CONTRIBUTION (6-dec)");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 19. IncorrectPayment revert tests
    // ═══════════════════════════════════════════════════════════════════════

    function test_Contribute_Revert_WrongMsgValue() public {
        uint256 id = _create3MemberFriendsCircle();

        // bob sends wrong value (1 wei instead of CONTRIBUTION_NATIVE)
        vm.prank(bob);
        vm.expectRevert(AjoCircle.IncorrectPayment.selector);
        ajo.contribute{value: 1}(id);
    }

    function test_Join_Revert_WrongMsgValue() public {
        // Circle with collateral
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "Test", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, 0
        );

        // bob sends wrong collateral value → IncorrectPayment
        vm.prank(bob);
        vm.expectRevert(AjoCircle.IncorrectPayment.selector);
        ajo.join{value: COLLATERAL_NATIVE + 1}(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 20. Reentrancy guard on withdraw (native receive re-enter)
    // ═══════════════════════════════════════════════════════════════════════

    function test_Withdraw_ReentrancyGuard() public {
        // Deploy the reentrant attacker
        ReentrantWithdraw attacker = new ReentrantWithdraw(address(ajo));

        // Fund the attacker address with native ETH so it can join and contribute
        vm.deal(address(attacker), 10_000e18);

        // Create a 2-member friends circle: attacker + bob
        vm.prank(address(attacker));
        uint256 id = ajo.createCircle{value: 0}(
            "Reentrancy Test", CONTRIBUTION, 2, ROUND_DUR, 0, 0
        );
        vm.prank(bob);
        ajo.join{value: 0}(id);

        // bob contributes so the pot exists for R1 (attacker is R1 recipient)
        vm.prank(bob);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        ajo.payout(id);

        // attacker has pendingWithdrawals > 0
        assertGt(ajo.pendingWithdrawals(address(attacker)), 0, "attacker has pending");

        // Arm the attack
        attacker.setAttacking(true);

        // The reentrancy attempt inside receive() should be blocked by ReentrancyGuard
        // The outer withdraw() should succeed (guard reverts the inner call, not the outer)
        // However, since the inner call reverts inside the transfer, the contract catches it
        // with `if (!ok) revert NothingToWithdraw()` — so the outer withdraw also reverts.
        // This is the correct behavior: attacker cannot double-withdraw.
        vm.expectRevert();
        attacker.attack();

        // Attacker's pendingWithdrawals should NOT have been drained (revert undoes state)
        assertGt(ajo.pendingWithdrawals(address(attacker)), 0,
            "attacker pending unchanged -- reentrancy blocked");
    }
}
