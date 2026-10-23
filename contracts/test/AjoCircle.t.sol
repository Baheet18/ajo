// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {AjoCircle} from "../AjoCircle.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";
import {ReentrantMockERC20} from "../test-helpers/ReentrantMockERC20.sol";

// Canonical Arc Testnet USDC address (matches AjoCircle.USDC constant).
address constant USDC_ADDR = 0x3600000000000000000000000000000000000000;

contract AjoCircleTest is Test {
    // ── state ──────────────────────────────────────────────────────────────
    AjoCircle  internal ajo;
    MockERC20  internal usdc; // handle bound to USDC_ADDR after etch

    address internal alice = makeAddr("alice");
    address internal bob   = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave  = makeAddr("dave");

    // Circle parameters
    uint256 internal constant CONTRIBUTION = 100e6;  // 100 "USDC" (6 dec)
    uint8   internal constant MEMBER_COUNT = 3;
    uint256 internal constant ROUND_DUR    = 300;    // == MIN_ROUND_DURATION

    // ── setUp: runs before EVERY test ──────────────────────────────────────
    function setUp() public {
        // 1. Deploy a real MockERC20 to get its runtime bytecode.
        MockERC20 template = new MockERC20("Mock USDC", "mUSDC", 6);

        // 2. Etch the bytecode to the canonical USDC constant address.
        vm.etch(USDC_ADDR, address(template).code);

        // 3. Bind the handle — storage at USDC_ADDR is empty after etch.
        usdc = MockERC20(USDC_ADDR);

        // 4. Deploy AjoCircle; its USDC constant now has ERC-20 bytecode behind it.
        ajo = new AjoCircle();

        // 5. Seed every actor with 10x CONTRIBUTION to cover collateral + 3 rounds.
        _mintAndApprove(alice, 10 * CONTRIBUTION);
        _mintAndApprove(bob,   10 * CONTRIBUTION);
        _mintAndApprove(carol, 10 * CONTRIBUTION);
        _mintAndApprove(dave,  10 * CONTRIBUTION);
    }

    // ── internal helpers ───────────────────────────────────────────────────

    function _mintAndApprove(address who, uint256 amount) internal {
        usdc.mint(who, amount);
        vm.prank(who);
        usdc.approve(address(ajo), type(uint256).max);
    }

    /// Creates a 3-member JOIN_ORDER circle. Circle is ACTIVE after carol joins.
    function _create3MemberCircle() internal returns (uint256 circleId) {
        vm.prank(alice);
        circleId = ajo.createCircle("Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR);
        vm.prank(bob);
        ajo.join(circleId);
        vm.prank(carol);
        ajo.join(circleId);
    }

    /// All three members contribute in the current round.
    function _allContribute(uint256 circleId) internal {
        vm.prank(alice); ajo.contribute(circleId);
        vm.prank(bob);   ajo.contribute(circleId);
        vm.prank(carol); ajo.contribute(circleId);
    }

    /// Helper: claim pendingWithdrawals for a user.
    function _withdraw(address who) internal {
        vm.prank(who);
        ajo.withdraw();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 1. DEPLOYMENT & INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    function test_CreateCircle_SetsFieldsCorrectly() public {
        vm.expectEmit(true, true, false, true, address(ajo));
        emit AjoCircle.CircleCreated(1, alice, "Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR);

        vm.prank(alice);
        uint256 id = ajo.createCircle("Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR);

        assertEq(id, 1, "circleId should be 1");
        assertEq(ajo.circleCount(), 1, "circleCount should be 1");

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(c.name,               "Test Circle");
        assertEq(c.creator,            alice);
        assertEq(c.contributionAmount, CONTRIBUTION);
        assertEq(c.memberCount,        MEMBER_COUNT);
        assertEq(c.roundDuration,      ROUND_DUR);
        assertEq(uint8(c.status),      uint8(AjoCircle.CircleStatus.PENDING));
        assertEq(c.currentRound,       0);
        assertEq(c.members.length,     1, "creator auto-joins");
    }

    function test_CreateCircle_CreatorAutoJoins() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle("Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR);

        assertTrue(ajo.isMember(id, alice), "alice should be member");
        assertEq(usdc.balanceOf(address(ajo)), CONTRIBUTION, "contract holds 1 collateral");
    }

    function test_CreateCircle_RevertIf_ZeroContribution() public {
        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidContributionAmount.selector);
        ajo.createCircle("X", 0, MEMBER_COUNT, ROUND_DUR);
    }

    function test_CreateCircle_RevertIf_MemberCountTooLow() public {
        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidMemberCount.selector);
        ajo.createCircle("X", CONTRIBUTION, 1, ROUND_DUR);
    }

    function test_CreateCircle_RevertIf_MemberCountTooHigh() public {
        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidMemberCount.selector);
        ajo.createCircle("X", CONTRIBUTION, 11, ROUND_DUR);
    }

    function test_CreateCircle_RevertIf_RoundDurationTooShort() public {
        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidRoundDuration.selector);
        ajo.createCircle("X", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR - 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 2. JOIN
    // ═══════════════════════════════════════════════════════════════════════

    function test_Join_EmitsMemberJoined_AndStartsCircleOnLastMember() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle("Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR);

        vm.expectEmit(true, true, false, true, address(ajo));
        emit AjoCircle.MemberJoined(id, bob, 2);
        vm.prank(bob);
        ajo.join(id);

        vm.expectEmit(true, true, false, true, address(ajo));
        emit AjoCircle.CircleStarted(id, block.timestamp + ROUND_DUR);
        vm.prank(carol);
        ajo.join(id);

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(uint8(c.status),   uint8(AjoCircle.CircleStatus.ACTIVE));
        assertEq(c.currentRound,    1);
        assertEq(c.roundDeadline,   block.timestamp + ROUND_DUR);
    }

    function test_Join_CollateralTransferred() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle("Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR);

        uint256 before = usdc.balanceOf(address(ajo));
        vm.prank(bob);
        ajo.join(id);
        assertEq(usdc.balanceOf(address(ajo)), before + CONTRIBUTION, "collateral held");
    }

    function test_Join_Revert_AlreadyMember() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle("Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR);

        vm.prank(alice);
        vm.expectRevert(AjoCircle.AlreadyMember.selector);
        ajo.join(id);
    }

    // SCENARIO 6 — Once the circle is ACTIVE (full), extra join must revert CircleFull
    // With our fix, CircleFull is checked before CircleNotPending
    function test_Join_Revert_CircleNotPending_WhenCircleIsFull() public {
        uint256 id = _create3MemberCircle(); // alice+bob+carol → ACTIVE (full)

        // dave tries to join a full ACTIVE circle
        // With new check order: AlreadyMember → CircleFull → CircleNotPending
        // members.length (3) >= memberCount (3) → CircleFull fires first
        vm.prank(dave);
        vm.expectRevert(AjoCircle.CircleFull.selector);
        ajo.join(id);
    }

    // SCENARIO 6b — CircleFull fires when PENDING but at capacity
    // After the fix, CircleFull is checked before CircleNotPending
    function test_Join_Revert_CircleFull_WhenPendingAtCapacity() public {
        // Use a 2-member circle so the second join activates it
        // Try to trick: create 2-member circle, after alice joins (1 member), bob joins and activates,
        // then carol joins a FULL PENDING circle by forking time — not possible in a single tx.
        // Instead: create circle, manually check order. With new check ordering:
        // isMember → CircleFull → CircleNotPending
        // For a PENDING circle at capacity: only possible if creator creates and capacity==1,
        // but min capacity is 2. The only reachable path to capacity in PENDING is the normal join flow.
        // After the last join the circle activates, so CircleFull is practically only hit if someone
        // front-runs the last join slot. We test with a 2-member circle.
        vm.prank(alice);
        uint256 id2 = ajo.createCircle("2Member", CONTRIBUTION, 2, ROUND_DUR);
        // Alice has joined, 1/2 slots taken. Bob joins, circle activates.
        vm.prank(bob);
        ajo.join(id2); // circle goes ACTIVE now

        // Now carol tries to join ACTIVE circle: should hit CircleNotPending because
        // circle.members.length (2) >= memberCount (2) checks first, but circle is also not PENDING.
        // With our reordered checks: AlreadyMember → CircleFull → CircleNotPending
        // carol is NOT a member, circle.members.length (2) >= memberCount (2) → CircleFull
        vm.prank(carol);
        vm.expectRevert(AjoCircle.CircleFull.selector);
        ajo.join(id2);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 3. CONTRIBUTE
    // ═══════════════════════════════════════════════════════════════════════

    function test_Contribute_HappyPath_EmitsEvent() public {
        uint256 id = _create3MemberCircle();

        vm.expectEmit(true, true, true, true, address(ajo));
        emit AjoCircle.ContributionMade(id, 1, alice, CONTRIBUTION);
        vm.prank(alice);
        ajo.contribute(id);

        assertTrue(ajo.roundPaid(id, 1, alice), "alice marked paid");
        assertEq(ajo.getPotSize(id), CONTRIBUTION, "pot has 1 contribution");
    }

    function test_Contribute_Revert_NotMember() public {
        uint256 id = _create3MemberCircle();

        vm.prank(dave);
        vm.expectRevert(AjoCircle.NotMember.selector);
        ajo.contribute(id);
    }

    function test_Contribute_Revert_CircleNotActive() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle("X", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR);
        // Still PENDING — only alice joined

        vm.prank(alice);
        vm.expectRevert(AjoCircle.CircleNotActive.selector);
        ajo.contribute(id);
    }

    // SCENARIO 5 — Double contribution must revert AlreadyContributed
    function test_Contribute_Revert_AlreadyContributed() public {
        uint256 id = _create3MemberCircle();

        vm.prank(alice);
        ajo.contribute(id);

        vm.prank(alice);
        vm.expectRevert(AjoCircle.AlreadyContributed.selector);
        ajo.contribute(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SCENARIO 2 — Payout before everyone paid AND before deadline
    // ═══════════════════════════════════════════════════════════════════════

    function test_Payout_Revert_ContributionsStillPending_BeforeDeadline() public {
        uint256 id = _create3MemberCircle();

        // Only alice contributes — deadline has not passed
        vm.prank(alice);
        ajo.contribute(id);

        assertLt(block.timestamp, ajo.getRoundDeadline(id), "should be before deadline");

        vm.expectRevert(AjoCircle.ContributionsStillPending.selector);
        ajo.payout(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SCENARIO 1 — Full happy path: 3 rounds, all pay, everyone gets collateral back
    // Uses pull-payment: payout credits pendingWithdrawals; recipients must call withdraw()
    // ═══════════════════════════════════════════════════════════════════════

    function test_FullHappyPath_3Members_JoinOrder() public {
        uint256 id = _create3MemberCircle();

        // After joining: contract holds 3 collaterals
        assertEq(usdc.balanceOf(address(ajo)), 3 * CONTRIBUTION, "initial collateral");

        // JOIN_ORDER payout: alice → bob → carol
        address[] memory recipients = ajo.getPayoutRecipients(id);
        assertEq(recipients[0], alice);
        assertEq(recipients[1], bob);
        assertEq(recipients[2], carol);

        // ──────── Round 1 ────────
        _allContribute(id);
        assertEq(ajo.getPotSize(id), 3 * CONTRIBUTION, "round-1 pot should be 3x");

        vm.expectEmit(true, true, true, false, address(ajo));
        emit AjoCircle.RoundPayout(id, 1, alice, 3 * CONTRIBUTION);
        ajo.payout(id);

        // alice's pendingWithdrawals credited but not yet withdrawn
        assertEq(ajo.pendingWithdrawals(alice), 3 * CONTRIBUTION, "alice pending R1");
        assertEq(ajo.getCurrentRound(id), 2, "should advance to round 2");

        uint256 aliceBalBefore = usdc.balanceOf(alice);
        _withdraw(alice);
        assertEq(usdc.balanceOf(alice), aliceBalBefore + 3 * CONTRIBUTION, "alice withdrew R1 payout");

        // ──────── Round 2 ────────
        _allContribute(id);

        vm.expectEmit(true, true, true, false, address(ajo));
        emit AjoCircle.RoundPayout(id, 2, bob, 3 * CONTRIBUTION);
        ajo.payout(id);

        assertEq(ajo.pendingWithdrawals(bob), 3 * CONTRIBUTION, "bob pending R2");
        uint256 bobBalBefore = usdc.balanceOf(bob);
        _withdraw(bob);
        assertEq(usdc.balanceOf(bob), bobBalBefore + 3 * CONTRIBUTION, "bob withdrew R2 payout");

        // ──────── Round 3 ────────
        uint256 aliceBalBeforeR3 = usdc.balanceOf(alice);
        uint256 bobBalBeforeR3   = usdc.balanceOf(bob);
        uint256 carolBalBeforeR3 = usdc.balanceOf(carol);

        _allContribute(id);

        vm.expectEmit(true, true, true, false, address(ajo));
        emit AjoCircle.RoundPayout(id, 3, carol, 3 * CONTRIBUTION);
        ajo.payout(id);

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(uint8(c.status), uint8(AjoCircle.CircleStatus.ENDED), "circle should be ENDED");

        // SCENARIO 4 — collateral refunds are in pendingWithdrawals after circle ends
        // alice: paid R3 contribution, gets collateral refund credit
        assertEq(ajo.pendingWithdrawals(alice), CONTRIBUTION, "alice collateral refund pending");
        assertEq(ajo.pendingWithdrawals(bob),   CONTRIBUTION, "bob collateral refund pending");
        // carol: R3 payout + collateral refund
        assertEq(ajo.pendingWithdrawals(carol), 3 * CONTRIBUTION + CONTRIBUTION, "carol payout+refund pending");

        // Withdraw for all
        _withdraw(alice);
        _withdraw(bob);
        _withdraw(carol);

        // alice: before R3 paid contribution (-1x), then withdrew refund (+1x) → net 0
        assertEq(usdc.balanceOf(alice), aliceBalBeforeR3 - CONTRIBUTION + CONTRIBUTION, "alice net R3");
        // bob: same
        assertEq(usdc.balanceOf(bob), bobBalBeforeR3 - CONTRIBUTION + CONTRIBUTION, "bob net R3");
        // carol: paid contribution (-1x), got 3x payout + 1x refund = +4x → net +3x
        assertEq(usdc.balanceOf(carol), carolBalBeforeR3 - CONTRIBUTION + 4 * CONTRIBUTION, "carol net R3");

        // Contract balance should be 0
        assertEq(usdc.balanceOf(address(ajo)), 0, "contract fully drained");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SCENARIO 3 — Payout after deadline with one defaulter
    // ═══════════════════════════════════════════════════════════════════════

    function test_Payout_AfterDeadline_OneDefaulter_SlashesAndSkips() public {
        uint256 id = _create3MemberCircle();

        // ──────── Round 1: carol defaults ────────
        vm.prank(alice); ajo.contribute(id);
        vm.prank(bob);   ajo.contribute(id);
        vm.warp(block.timestamp + ROUND_DUR + 1);

        vm.expectEmit(true, true, false, true, address(ajo));
        emit AjoCircle.MemberDefaulted(id, carol, 1);

        vm.expectEmit(true, true, false, true, address(ajo));
        emit AjoCircle.CollateralSlashed(id, carol, CONTRIBUTION);

        // Pot = 2 contributions + carol slashed collateral = 3x
        vm.expectEmit(true, true, true, false, address(ajo));
        emit AjoCircle.RoundPayout(id, 1, alice, 3 * CONTRIBUTION);

        ajo.payout(id);

        assertEq(ajo.pendingWithdrawals(alice), 3 * CONTRIBUTION, "alice pending R1 (with slash)");
        assertTrue(ajo.isDefaulted(id, carol), "carol defaulted");
        assertTrue(ajo.collateralSlashed(id, carol), "carol slashed");
        assertEq(ajo.getCurrentRound(id), 2, "advance to round 2");

        uint256 aliceBalBefore = usdc.balanceOf(alice);
        _withdraw(alice);
        assertEq(usdc.balanceOf(alice), aliceBalBefore + 3 * CONTRIBUTION, "alice got slash pot");

        // ──────── Round 2: only alice & bob contribute (carol defaulted) ────────
        vm.prank(alice); ajo.contribute(id);
        vm.prank(bob);   ajo.contribute(id);

        vm.expectEmit(true, true, true, false, address(ajo));
        emit AjoCircle.RoundPayout(id, 2, bob, 2 * CONTRIBUTION);

        ajo.payout(id);

        assertEq(ajo.pendingWithdrawals(bob), 2 * CONTRIBUTION, "bob pending R2");
        uint256 bobBalBefore = usdc.balanceOf(bob);
        _withdraw(bob);
        assertEq(usdc.balanceOf(bob), bobBalBefore + 2 * CONTRIBUTION, "bob got R2 payout");
        assertEq(ajo.getCurrentRound(id), 3, "advance to round 3");

        // ──────── Round 3: carol's slot is defaulted ────────
        // Before deadline, alice & bob must contribute (non-defaulted must pay).
        vm.prank(alice); ajo.contribute(id);
        vm.prank(bob);   ajo.contribute(id);

        // With the orphan-pot fix: contributions are redistributed to contributors (alice & bob, 1x each)
        ajo.payout(id);

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(uint8(c.status), uint8(AjoCircle.CircleStatus.ENDED), "circle ENDED");

        // After end: alice & bob get R3 contributions back (1x each) + collateral refund (1x each)
        assertEq(ajo.pendingWithdrawals(alice), 2 * CONTRIBUTION, "alice: R3 refund + collateral");
        assertEq(ajo.pendingWithdrawals(bob),   2 * CONTRIBUTION, "bob: R3 refund + collateral");
        assertEq(ajo.pendingWithdrawals(carol),  0, "carol: defaulted, no refund");

        uint256 aliceFinalBefore = usdc.balanceOf(alice);
        uint256 bobFinalBefore   = usdc.balanceOf(bob);
        _withdraw(alice);
        _withdraw(bob);
        assertEq(usdc.balanceOf(alice), aliceFinalBefore + 2 * CONTRIBUTION, "alice final withdraw");
        assertEq(usdc.balanceOf(bob),   bobFinalBefore   + 2 * CONTRIBUTION, "bob final withdraw");

        // Contract should be fully drained
        assertEq(usdc.balanceOf(address(ajo)), 0, "no funds locked");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SCENARIO 4 — Collateral refund explicit per-member balance assertions
    // ═══════════════════════════════════════════════════════════════════════

    function test_CollateralRefund_NonDefaultersGetBack_DefaulterGetsNothing() public {
        uint256 id = _create3MemberCircle();

        uint256 aliceAfterJoin = usdc.balanceOf(alice);
        uint256 bobAfterJoin   = usdc.balanceOf(bob);
        uint256 carolAfterJoin = usdc.balanceOf(carol);

        // ──────── Round 1 — carol defaults ────────
        vm.prank(alice); ajo.contribute(id);
        vm.prank(bob);   ajo.contribute(id);
        vm.warp(block.timestamp + ROUND_DUR + 1);
        ajo.payout(id);
        _withdraw(alice); // alice gets R1 payout (3x)

        // ──────── Round 2 — alice & bob contribute, bob gets payout ────────
        vm.prank(alice); ajo.contribute(id);
        vm.prank(bob);   ajo.contribute(id);
        ajo.payout(id);
        _withdraw(bob); // bob gets R2 payout (2x)

        // ──────── Round 3 — carol defaulted, alice & bob contribute, orphan pot redistributed ────────
        vm.prank(alice); ajo.contribute(id);
        vm.prank(bob);   ajo.contribute(id);
        ajo.payout(id);
        // circle ends; collateral refunded + R3 contributions redistributed to alice & bob
        _withdraw(alice);
        _withdraw(bob);

        uint256 aliceFinal = usdc.balanceOf(alice);
        uint256 bobFinal   = usdc.balanceOf(bob);
        uint256 carolFinal = usdc.balanceOf(carol);

        // Alice net:
        //   - aliceAfterJoin (9x)
        //   - R1 contribution: -1x → 8x
        //   - R1 payout (3x): +3x → 11x
        //   - R2 contribution: -1x → 10x
        //   - R3 contribution: -1x → 9x
        //   - R3 orphan refund (1x): +1x → 10x
        //   - collateral refund (1x): +1x → 11x
        // Net from aliceAfterJoin: +2x
        assertEq(aliceFinal, aliceAfterJoin + 2 * CONTRIBUTION, "alice net");

        // Bob net:
        //   - bobAfterJoin (9x)
        //   - R1 contribution: -1x → 8x
        //   - R2 contribution: -1x → 7x
        //   - R2 payout (2x): +2x → 9x
        //   - R3 contribution: -1x → 8x
        //   - R3 orphan refund (1x): +1x → 9x
        //   - collateral refund (1x): +1x → 10x
        // Net from bobAfterJoin: +1x
        assertEq(bobFinal, bobAfterJoin + CONTRIBUTION, "bob net");

        // Carol: defaulted → no payout, no refund, no R3 contribution
        assertEq(carolFinal, carolAfterJoin, "carol: no change after default");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SCENARIO 7 — Reentrancy guard blocks re-entrant payout()
    // Note: with pull-payment, payout() only credits storage — no external call.
    // Reentrancy is tested on withdraw() instead (the only function doing safeTransfer).
    // ═══════════════════════════════════════════════════════════════════════

    function test_Reentrancy_WithdrawBlockedByGuard() public {
        // 1. Deploy a reentrant ERC-20 and etch it onto the canonical USDC address.
        ReentrantMockERC20 rTemplate = new ReentrantMockERC20("Reentrant USDC", "rUSDC", 6);
        vm.etch(USDC_ADDR, address(rTemplate).code);
        ReentrantMockERC20 attackToken = ReentrantMockERC20(USDC_ADDR);

        // 2. Mint and approve for circle members.
        attackToken.mint(alice, 10 * CONTRIBUTION);
        attackToken.mint(bob,   10 * CONTRIBUTION);
        attackToken.mint(carol, 10 * CONTRIBUTION);

        vm.prank(alice); attackToken.approve(address(ajo), type(uint256).max);
        vm.prank(bob);   attackToken.approve(address(ajo), type(uint256).max);
        vm.prank(carol); attackToken.approve(address(ajo), type(uint256).max);

        // 3. Create circle and fill it.
        vm.prank(alice);
        uint256 id = ajo.createCircle("Reentrant", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR);
        vm.prank(bob);   ajo.join(id);
        vm.prank(carol); ajo.join(id);

        // 4. All contribute in R1 — payout credits alice's pendingWithdrawals.
        vm.prank(alice); ajo.contribute(id);
        vm.prank(bob);   ajo.contribute(id);
        vm.prank(carol); ajo.contribute(id);
        ajo.payout(id);

        // 5. Configure the reentrant token: on safeTransfer to alice, try to re-enter withdraw().
        attackToken.setAttackParams(address(ajo), id);
        attackToken.setAttacking(true);

        // 6. withdraw() should revert because the token tries to re-enter.
        vm.prank(alice);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        ajo.withdraw();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Cancel circle (escape hatch for unfilled pending circles)
    // ═══════════════════════════════════════════════════════════════════════

    function test_CancelCircle_RefundsCollateral() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle("Test", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR);
        vm.prank(bob);
        ajo.join(id);

        // alice cancels
        vm.expectEmit(true, false, false, false, address(ajo));
        emit AjoCircle.CircleCancelled(id);
        vm.prank(alice);
        ajo.cancelCircle(id);

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(uint8(c.status), uint8(AjoCircle.CircleStatus.ENDED), "cancelled = ENDED");

        assertEq(ajo.pendingWithdrawals(alice), CONTRIBUTION, "alice collateral refund");
        assertEq(ajo.pendingWithdrawals(bob),   CONTRIBUTION, "bob collateral refund");

        uint256 aliceBal = usdc.balanceOf(alice);
        uint256 bobBal   = usdc.balanceOf(bob);
        _withdraw(alice);
        _withdraw(bob);
        assertEq(usdc.balanceOf(alice), aliceBal + CONTRIBUTION);
        assertEq(usdc.balanceOf(bob),   bobBal   + CONTRIBUTION);
    }

    function test_CancelCircle_Revert_NotCreator() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle("Test", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR);

        vm.prank(bob);
        vm.expectRevert(AjoCircle.NotCreator.selector);
        ajo.cancelCircle(id);
    }

    function test_CancelCircle_Revert_WhenActive() public {
        uint256 id = _create3MemberCircle(); // already ACTIVE

        vm.prank(alice);
        vm.expectRevert(AjoCircle.CircleNotPending.selector);
        ajo.cancelCircle(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Withdraw edge cases
    // ═══════════════════════════════════════════════════════════════════════

    function test_Withdraw_Revert_NothingToWithdraw() public {
        vm.prank(alice);
        vm.expectRevert(AjoCircle.NothingToWithdraw.selector);
        ajo.withdraw();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Additional edge cases
    // ═══════════════════════════════════════════════════════════════════════

    function test_Payout_Revert_CircleNotActive_OnPendingCircle() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle("X", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR);

        vm.expectRevert(AjoCircle.CircleNotActive.selector);
        ajo.payout(id);
    }

    function test_Payout_Revert_CircleNotActive_AfterEnded() public {
        uint256 id = _create3MemberCircle();

        for (uint8 r = 0; r < MEMBER_COUNT; r++) {
            _allContribute(id);
            ajo.payout(id);
        }

        vm.expectRevert(AjoCircle.CircleNotActive.selector);
        ajo.payout(id);
    }

    function test_GetCircle_Revert_InvalidCircle() public {
        vm.expectRevert(AjoCircle.InvalidCircle.selector);
        ajo.getCircle(0);

        vm.expectRevert(AjoCircle.InvalidCircle.selector);
        ajo.getCircle(999);
    }

    function test_GetMembers_ReturnsCorrectOrder() public {
        uint256 id = _create3MemberCircle();
        address[] memory members = ajo.getMembers(id);
        assertEq(members.length, 3);
        assertEq(members[0], alice);
        assertEq(members[1], bob);
        assertEq(members[2], carol);
    }

    function test_GetNextRecipient_BeforeStart_ReturnsFirstInPayoutOrder() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle("Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR);
        assertEq(ajo.getNextRecipient(id), alice);
    }

    function test_GetNextRecipient_DuringRound() public {
        uint256 id = _create3MemberCircle();
        assertEq(ajo.getNextRecipient(id), alice);
    }

    function test_HasMemberPaid_TrueAfterContribute() public {
        uint256 id = _create3MemberCircle();

        assertFalse(ajo.hasMemberPaid(id, alice), "not paid yet");
        vm.prank(alice);
        ajo.contribute(id);
        assertTrue(ajo.hasMemberPaid(id, alice), "paid");
    }

    function test_GetRoundDeadline_ReturnsCorrectDeadline() public {
        uint256 id = _create3MemberCircle();
        assertEq(ajo.getRoundDeadline(id), block.timestamp + ROUND_DUR);
    }

    function test_GetRoundPaidStatus_ReturnsBoolArray() public {
        uint256 id = _create3MemberCircle();

        bool[] memory beforePay = ajo.getRoundPaidStatus(id, 1);
        assertEq(beforePay.length, 3);
        assertFalse(beforePay[0]); assertFalse(beforePay[1]); assertFalse(beforePay[2]);

        vm.prank(alice);
        ajo.contribute(id);

        bool[] memory postPay = ajo.getRoundPaidStatus(id, 1);
        assertTrue(postPay[0]);
        assertFalse(postPay[1]);
        assertFalse(postPay[2]);
    }

    function test_TwoCircles_IsolatedState() public {
        uint256 id1 = _create3MemberCircle();

        address d1 = makeAddr("d1");
        address d2 = makeAddr("d2");
        address d3 = makeAddr("d3");
        _mintAndApprove(d1, 10 * CONTRIBUTION);
        _mintAndApprove(d2, 10 * CONTRIBUTION);
        _mintAndApprove(d3, 10 * CONTRIBUTION);

        vm.prank(d1);
        uint256 id2 = ajo.createCircle("Circle 2", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR);
        vm.prank(d2); ajo.join(id2);
        vm.prank(d3); ajo.join(id2);

        assertFalse(ajo.isMember(id1, d1), "d1 not in circle 1");
        assertFalse(ajo.isMember(id2, alice), "alice not in circle 2");
        assertEq(ajo.getCurrentRound(id1), 1);
        assertEq(ajo.getCurrentRound(id2), 1);
    }

    function test_DefaultedMember_CannotContribute() public {
        uint256 id = _create3MemberCircle();

        vm.prank(alice); ajo.contribute(id);
        vm.prank(bob);   ajo.contribute(id);
        vm.warp(block.timestamp + ROUND_DUR + 1);
        ajo.payout(id);

        vm.prank(carol);
        vm.expectRevert(AjoCircle.MemberDefaultedAlready.selector);
        ajo.contribute(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Fuzz: contribution amount and member count boundaries
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzz_CreateCircle_ValidParams(
        uint256 contribution,
        uint8 memberCount,
        uint256 roundDuration
    ) public {
        contribution  = bound(contribution, 1, 1e18);
        memberCount   = uint8(bound(memberCount, 2, 10));
        roundDuration = bound(roundDuration, 300, 30 days);

        usdc.mint(alice, contribution * 11);
        vm.prank(alice);
        usdc.approve(address(ajo), type(uint256).max);

        vm.prank(alice);
        uint256 id = ajo.createCircle("Fuzz", contribution, memberCount, roundDuration);

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(c.contributionAmount, contribution);
        assertEq(c.memberCount, memberCount);
        assertEq(c.roundDuration, roundDuration);
    }

    function testFuzz_CreateCircle_InvalidMemberCount(uint8 memberCount) public {
        vm.assume(memberCount < 2 || memberCount > 10);

        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidMemberCount.selector);
        ajo.createCircle("X", CONTRIBUTION, memberCount, ROUND_DUR);
    }

    function testFuzz_CreateCircle_InvalidRoundDuration(uint256 roundDuration) public {
        roundDuration = bound(roundDuration, 0, 299);

        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidRoundDuration.selector);
        ajo.createCircle("X", CONTRIBUTION, MEMBER_COUNT, roundDuration);
    }
}
