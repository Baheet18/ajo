// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AjoCircle} from "../AjoCircle.sol";
import {AjoCircleTestBase} from "./AjoCircle.Base.t.sol";

contract AjoCircleCoreTest is AjoCircleTestBase {

    // ═══════════════════════════════════════════════════════════════════════
    // 1. createCircle — happy path & reverts
    // ═══════════════════════════════════════════════════════════════════════

    function test_CreateCircle_SetsFieldsCorrectly() public {
        vm.expectEmit(true, true, false, true, address(ajo));
        emit AjoCircle.CircleCreated(
            1, alice, "Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, HOLDBACK_BPS
        );

        vm.prank(alice);
        uint256 id = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, HOLDBACK_BPS
        );

        assertEq(id, 1, "circleId == 1");
        assertEq(ajo.circleCount(), 1, "circleCount == 1");

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(c.name,               "Test Circle");
        assertEq(c.creator,            alice);
        assertEq(c.contributionAmount, CONTRIBUTION);
        assertEq(c.memberCount,        MEMBER_COUNT);
        assertEq(c.roundDuration,      ROUND_DUR);
        assertEq(c.collateralAmount,   COLLATERAL);
        assertEq(c.holdbackBps,        HOLDBACK_BPS);
        assertEq(uint8(c.status),      uint8(AjoCircle.CircleStatus.PENDING));
        assertEq(c.currentRound,       0);
        assertEq(c.members.length,     1, "creator auto-joins");
    }

    function test_CreateCircle_CreatorAutoJoins_CollateralTaken() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, HOLDBACK_BPS
        );

        assertTrue(ajo.isMember(id, alice), "alice is member");
        assertEq(address(ajo).balance, COLLATERAL_NATIVE, "contract holds collateral as native");
        assertEq(ajo.getMemberDeposit(id, alice), COLLATERAL, "alice deposit recorded (6-dec)");
    }

    function test_CreateCircle_RevertIf_ZeroContribution() public {
        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidContributionAmount.selector);
        ajo.createCircle{value: 0}("X", 0, MEMBER_COUNT, ROUND_DUR, 0, 0);
    }

    function test_CreateCircle_RevertIf_MemberCountTooLow() public {
        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidMemberCount.selector);
        ajo.createCircle{value: 0}("X", CONTRIBUTION, 1, ROUND_DUR, 0, 0);
    }

    function test_CreateCircle_RevertIf_MemberCountTooHigh() public {
        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidMemberCount.selector);
        ajo.createCircle{value: 0}("X", CONTRIBUTION, 11, ROUND_DUR, 0, 0);
    }

    function test_CreateCircle_RevertIf_RoundDurationTooShort() public {
        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidRoundDuration.selector);
        ajo.createCircle{value: 0}("X", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR - 1, 0, 0);
    }

    function test_InvalidHoldbackBps_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidHoldbackBps.selector);
        ajo.createCircle{value: 0}("X", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 3001);
    }

    function test_CreateCircle_MaxHoldbackBps_Succeeds() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}("Max HB", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 3000);
        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(c.holdbackBps, 3000);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 2. join
    // ═══════════════════════════════════════════════════════════════════════

    function test_Join_EmitsMemberJoined_AndStartsCircleOnLastMember() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, HOLDBACK_BPS
        );

        vm.expectEmit(true, true, false, true, address(ajo));
        emit AjoCircle.MemberJoined(id, bob, 2);
        vm.prank(bob);
        ajo.join{value: COLLATERAL_NATIVE}(id);

        vm.expectEmit(true, true, false, true, address(ajo));
        emit AjoCircle.CircleStarted(id, block.timestamp + ROUND_DUR);
        vm.prank(carol);
        ajo.join{value: COLLATERAL_NATIVE}(id);

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(uint8(c.status),  uint8(AjoCircle.CircleStatus.ACTIVE));
        assertEq(c.currentRound,   1);
        assertEq(c.roundDeadline,  block.timestamp + ROUND_DUR);
    }

    function test_Join_CollateralTransferred() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, HOLDBACK_BPS
        );

        uint256 before = address(ajo).balance;
        vm.prank(bob);
        ajo.join{value: COLLATERAL_NATIVE}(id);
        assertEq(address(ajo).balance, before + COLLATERAL_NATIVE, "native collateral held");
        assertEq(ajo.getMemberDeposit(id, bob), COLLATERAL, "bob deposit recorded (6-dec)");
    }

    function test_Join_Revert_AlreadyMember() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, HOLDBACK_BPS
        );

        vm.prank(alice);
        vm.expectRevert(AjoCircle.AlreadyMember.selector);
        ajo.join{value: COLLATERAL_NATIVE}(id);
    }

    function test_Join_Revert_CircleFull() public {
        uint256 id = _create3MemberCircle();

        vm.prank(dave);
        vm.expectRevert(AjoCircle.CircleFull.selector);
        ajo.join{value: COLLATERAL_NATIVE}(id);
    }

    function test_Join_Revert_WrongMsgValue() public {
        // Create circle with collateral — joining with wrong msg.value reverts IncorrectPayment
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, HOLDBACK_BPS
        );

        // bob sends half the required collateral
        vm.prank(bob);
        vm.expectRevert(AjoCircle.IncorrectPayment.selector);
        ajo.join{value: COLLATERAL_NATIVE / 2}(id);
    }

    function test_Join_Revert_WrongMsgValue_ZeroCollateral_NonzeroValue() public {
        // Create circle with NO collateral — joining with any value != 0 reverts IncorrectPayment
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "No Collateral", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );

        vm.prank(bob);
        vm.expectRevert(AjoCircle.IncorrectPayment.selector);
        ajo.join{value: 1}(id);
    }

    function test_NoCollateral_NoDepositTaken() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}("No Collateral", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0);
        vm.prank(bob);
        ajo.join{value: 0}(id);
        vm.prank(carol);
        ajo.join{value: 0}(id);

        assertEq(ajo.getMemberDeposit(id, alice), 0, "alice deposit == 0");
        assertEq(ajo.getMemberDeposit(id, bob),   0, "bob deposit == 0");
        assertEq(ajo.getMemberDeposit(id, carol),  0, "carol deposit == 0");
        assertEq(address(ajo).balance, 0, "no native taken at join");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 3. contribute — reverts
    // ═══════════════════════════════════════════════════════════════════════

    function test_Contribute_Revert_NotMember() public {
        uint256 id = _create3MemberCircle();

        vm.prank(dave);
        vm.expectRevert(AjoCircle.NotMember.selector);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
    }

    function test_Contribute_Revert_CircleNotActive() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "X", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, HOLDBACK_BPS
        );

        vm.prank(bob);
        vm.expectRevert(AjoCircle.CircleNotActive.selector);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
    }

    function test_Contribute_Revert_AlreadyContributed() public {
        uint256 id = _create3MemberCircle();

        vm.prank(bob);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);

        vm.prank(bob);
        vm.expectRevert(AjoCircle.AlreadyContributed.selector);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
    }

    function test_Contribute_Revert_RoundDeadlinePassed() public {
        uint256 id = _create3MemberCircle();

        _warpPastDeadline(id);

        vm.prank(bob);
        vm.expectRevert(AjoCircle.RoundDeadlinePassed.selector);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
    }

    function test_Contribute_Revert_MemberDefaultedAlready() public {
        uint256 id = _create3MemberCircle();
        // bob misses R1, gets slashed. no holdback, deposit slashed → permanently defaulted.
        vm.prank(carol);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        _warpPastDeadline(id);
        ajo.payout(id); // bob defaulted

        // advance R2 deadline too
        _warpPastDeadline(id);

        vm.prank(bob);
        vm.expectRevert(AjoCircle.MemberDefaultedAlready.selector);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
    }

    function test_Contribute_Revert_WrongMsgValue() public {
        uint256 id = _create3MemberCircle();

        // bob sends wrong value (half of required)
        vm.prank(bob);
        vm.expectRevert(AjoCircle.IncorrectPayment.selector);
        ajo.contribute{value: CONTRIBUTION_NATIVE / 2}(id);
    }

    function test_Contribute_EmitsContributionMade() public {
        uint256 id = _create3MemberCircle();

        vm.expectEmit(true, true, true, true, address(ajo));
        emit AjoCircle.ContributionMade(id, 1, bob, CONTRIBUTION);
        vm.prank(bob);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);

        assertTrue(ajo.roundPaid(id, 1, bob), "bob marked paid");
        assertEq(ajo.getPotSize(id), CONTRIBUTION, "pot has 1 contribution (6-dec)");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 4. payout — reverts
    // ═══════════════════════════════════════════════════════════════════════

    function test_Payout_Revert_ContributionsStillPending_BeforeDeadline() public {
        uint256 id = _create3MemberCircle();
        vm.prank(bob);
        ajo.contribute{value: CONTRIBUTION_NATIVE}(id);

        assertLt(block.timestamp, ajo.getRoundDeadline(id));
        vm.expectRevert(AjoCircle.ContributionsStillPending.selector);
        ajo.payout(id);
    }

    function test_Payout_Revert_CircleNotActive_OnPendingCircle() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "X", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, HOLDBACK_BPS
        );

        vm.expectRevert(AjoCircle.CircleNotActive.selector);
        ajo.payout(id);
    }

    function test_Payout_Revert_CircleNotActive_AfterEnded() public {
        uint256 id = _create3MemberCircle();
        address[3] memory recip = [alice, bob, carol];
        for (uint256 r = 0; r < 3; r++) {
            _contributeNonRecipients(id, recip[r]);
            ajo.payout(id);
        }
        vm.expectRevert(AjoCircle.CircleNotActive.selector);
        ajo.payout(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 5. cancelCircle
    // ═══════════════════════════════════════════════════════════════════════

    function test_CancelCircle_RefundsDeposits() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "X", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, HOLDBACK_BPS
        );
        vm.prank(bob);
        ajo.join{value: COLLATERAL_NATIVE}(id);

        // Record native balances before cancel (after prank-calls that cost ETH)
        assertEq(ajo.pendingWithdrawals(alice), 0, "no pending before cancel");
        assertEq(ajo.pendingWithdrawals(bob),   0, "no pending before cancel");

        vm.expectEmit(true, false, false, false, address(ajo));
        emit AjoCircle.CircleCancelled(id);
        vm.prank(alice);
        ajo.cancelCircle(id);

        // pendingWithdrawals is in 6-decimal units
        assertEq(ajo.pendingWithdrawals(alice), COLLATERAL, "alice pending = collateral (6-dec)");
        assertEq(ajo.pendingWithdrawals(bob),   COLLATERAL, "bob pending = collateral (6-dec)");

        // withdraw sends COLLATERAL * 1e12 native each
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore   = bob.balance;
        _withdraw(alice);
        _withdraw(bob);
        assertEq(alice.balance - aliceBefore, COLLATERAL_NATIVE, "alice refunded native");
        assertEq(bob.balance   - bobBefore,   COLLATERAL_NATIVE, "bob refunded native");
    }

    function test_CancelCircle_Revert_NotCreator() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "X", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, HOLDBACK_BPS
        );
        vm.prank(bob);
        ajo.join{value: COLLATERAL_NATIVE}(id);

        vm.prank(bob);
        vm.expectRevert(AjoCircle.NotCreator.selector);
        ajo.cancelCircle(id);
    }

    function test_CancelCircle_Revert_NotPending() public {
        uint256 id = _create3MemberCircle(); // already ACTIVE

        vm.prank(alice);
        vm.expectRevert(AjoCircle.CircleNotPending.selector);
        ajo.cancelCircle(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 6. withdraw — reverts
    // ═══════════════════════════════════════════════════════════════════════

    function test_Withdraw_Revert_NothingToWithdraw() public {
        vm.prank(dave);
        vm.expectRevert(AjoCircle.NothingToWithdraw.selector);
        ajo.withdraw();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 7. view helpers
    // ═══════════════════════════════════════════════════════════════════════

    function test_GetMembers_ReturnsAll() public {
        uint256 id = _create3MemberCircle();
        address[] memory members = ajo.getMembers(id);
        assertEq(members.length, 3);
        assertEq(members[0], alice);
        assertEq(members[1], bob);
        assertEq(members[2], carol);
    }

    function test_GetPayoutRecipients_MatchesMemberOrder() public {
        uint256 id = _create3MemberCircle();
        address[] memory r = ajo.getPayoutRecipients(id);
        assertEq(r[0], alice);
        assertEq(r[1], bob);
        assertEq(r[2], carol);
    }

    function test_GetNextRecipient_BeforeStart() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}("X", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0);
        assertEq(ajo.getNextRecipient(id), alice);
    }

    function test_InvalidCircle_Reverts() public {
        vm.expectRevert(AjoCircle.InvalidCircle.selector);
        ajo.getCircle(99);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 8. fuzz — createCircle parameter bounds
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzz_CreateCircle_ValidParams(
        uint256 contribution,
        uint8   members,
        uint256 duration,
        uint256 collateral,
        uint16  hbBps
    ) public {
        contribution = bound(contribution, 1, 1_000_000e6);
        members      = uint8(bound(members, 2, 10));
        duration     = bound(duration, 300, 30 days);
        collateral   = bound(collateral, 0, 1_000e6);
        hbBps        = uint16(bound(hbBps, 0, 3000));

        // Fund alice with enough native for collateral
        uint256 nativeNeeded = collateral * 1e12 + 1_000e18;
        vm.deal(alice, nativeNeeded);

        vm.prank(alice);
        uint256 id = ajo.createCircle{value: collateral * 1e12}(
            "Fuzz", contribution, members, duration, collateral, hbBps
        );
        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(c.holdbackBps,        hbBps);
        assertEq(c.contributionAmount, contribution);
        assertEq(uint8(c.memberCount), members);
    }

    function testFuzz_CreateCircle_InvalidHoldbackBps(uint16 hbBps) public {
        hbBps = uint16(bound(hbBps, 3001, type(uint16).max));

        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidHoldbackBps.selector);
        ajo.createCircle{value: 0}("X", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, hbBps);
    }
}
