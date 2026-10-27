// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AjoCircle} from "../AjoCircle.sol";
import {AjoCircleTestBase} from "./AjoCircle.Base.t.sol";

/// Tests for leave(), setPayoutOrder(), cancelCircle expiry, and
/// getCircleCreatedAt() / isPendingExpired() view helpers.
contract AjoCircleLeaveTest is AjoCircleTestBase {

    // ═══════════════════════════════════════════════════════════════════════
    // 1. leave() — basic
    // ═══════════════════════════════════════════════════════════════════════

    /// Member joins with collateral, leaves → deposit credited to pendingWithdrawals.
    function test_Leave_RefundsDeposit() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "Leave Test", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, 0
        );
        vm.prank(bob);
        ajo.join{value: COLLATERAL_NATIVE}(id);

        assertEq(ajo.pendingWithdrawals(bob), 0, "bob pending before leave");

        vm.expectEmit(true, true, false, false, address(ajo));
        emit AjoCircle.MemberLeft(id, bob);
        vm.prank(bob);
        ajo.leave(id);

        assertEq(ajo.pendingWithdrawals(bob), COLLATERAL, "bob pending == COLLATERAL after leave");
        assertFalse(ajo.isMember(id, bob), "bob no longer a member");
    }

    /// Member joins a no-collateral circle, leaves → clean exit, no deposit.
    function test_Leave_NoDeposit() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Friends Leave", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );
        vm.prank(bob);
        ajo.join{value: 0}(id);

        uint256 contractBalBefore = address(ajo).balance;

        vm.prank(bob);
        ajo.leave(id);

        assertFalse(ajo.isMember(id, bob), "bob no longer a member");
        assertEq(ajo.pendingWithdrawals(bob), 0, "no deposit to refund");
        assertEq(address(ajo).balance, contractBalBefore, "contract balance unchanged");
    }

    /// After leave(), getMembers() does not contain the leaver.
    function test_Leave_RemovesFromMembers() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Remove Test", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );
        vm.prank(bob);
        ajo.join{value: 0}(id);

        vm.prank(bob);
        ajo.leave(id);

        address[] memory members = ajo.getMembers(id);
        assertEq(members.length, 1, "only creator remains");
        for (uint256 i = 0; i < members.length; i++) {
            assertTrue(members[i] != bob, "bob not in members");
        }
    }

    /// Creator calls leave() → IsCreator.
    function test_Leave_Revert_Creator() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Creator Leave", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );

        vm.prank(alice);
        vm.expectRevert(AjoCircle.IsCreator.selector);
        ajo.leave(id);
    }

    /// Non-member calls leave() → NotAMember.
    function test_Leave_Revert_NotMember() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Non-Member Leave", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );

        vm.prank(dave);
        vm.expectRevert(AjoCircle.NotAMember.selector);
        ajo.leave(id);
    }

    /// leave() on an ACTIVE circle → CircleNotPending.
    function test_Leave_Revert_AfterActive() public {
        // _create3MemberCircle() results in an ACTIVE circle
        uint256 id = _create3MemberCircle();

        vm.prank(bob);
        vm.expectRevert(AjoCircle.CircleNotPending.selector);
        ajo.leave(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 2. leave() + payout order
    // ═══════════════════════════════════════════════════════════════════════

    /// 4-member circle (in a 5-slot circle so it stays PENDING),
    /// setPayoutOrder([eve,carol,bob,alice]), bob leaves →
    /// payoutRecipients = [eve,carol,alice] (bob removed, others order-preserved).
    function test_Leave_PreservesPayoutOrder() public {
        address eve = makeAddr("eve"); // 4th member
        vm.deal(eve, 10_000e18);

        // Use memberCount=5 so 4 members still leaves circle PENDING
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Order Test", CONTRIBUTION, 5, ROUND_DUR, 0, 0
        );
        vm.prank(bob);   ajo.join{value: 0}(id);
        vm.prank(carol); ajo.join{value: 0}(id);
        vm.prank(eve);   ajo.join{value: 0}(id);
        // 4 members in a 5-slot circle → still PENDING

        // Set order: [eve, carol, bob, alice]
        address[] memory order = new address[](4);
        order[0] = eve;
        order[1] = carol;
        order[2] = bob;
        order[3] = alice;

        vm.prank(alice);
        ajo.setPayoutOrder(id, order);

        // Verify order was set
        address[] memory prBefore = ajo.getPayoutRecipients(id);
        assertEq(prBefore[0], eve,   "pre-leave slot 0 = eve");
        assertEq(prBefore[2], bob,   "pre-leave slot 2 = bob");

        // bob leaves — order-preserving removal from payoutRecipients
        vm.prank(bob);
        ajo.leave(id);

        address[] memory pr = ajo.getPayoutRecipients(id);
        assertEq(pr.length, 3, "3 recipients remaining");
        assertEq(pr[0], eve,   "slot 0 = eve");
        assertEq(pr[1], carol, "slot 1 = carol");
        assertEq(pr[2], alice, "slot 2 = alice");
    }

    /// Member leaves, new member joins → circle eventually starts normally.
    function test_Leave_ThenJoinFillsCircle() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Refill Test", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );
        vm.prank(bob);
        ajo.join{value: 0}(id);

        // bob leaves
        vm.prank(bob);
        ajo.leave(id);

        // dave joins — circle now has alice + dave (2 members, needs 3)
        vm.prank(dave);
        ajo.join{value: 0}(id);

        // carol joins — fills the last slot, circle should become ACTIVE
        vm.prank(carol);
        ajo.join{value: 0}(id);

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(uint8(c.status), uint8(AjoCircle.CircleStatus.ACTIVE), "circle is ACTIVE");
        assertEq(c.currentRound, 1, "round 1 started");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 3. setPayoutOrder()
    // ═══════════════════════════════════════════════════════════════════════

    /// Creator sets [carol, alice, bob] on 3-member circle → payoutRecipients matches.
    function test_SetPayoutOrder_Success() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Order", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );
        vm.prank(bob);   ajo.join{value: 0}(id);
        // carol not yet joined → only 2 members, need 3
        // Use a 2-member circle for simplicity; alice is creator
        // Actually test requires 3 members — let carol join but circle stays PENDING
        // because MEMBER_COUNT=3 and carol joining completes it → ACTIVE. So use memberCount=4.

        // Restart with 4-member circle so carol joining does not activate it
        ajo = new AjoCircle();
        vm.deal(alice, 10_000e18);
        vm.deal(bob,   10_000e18);
        vm.deal(carol, 10_000e18);

        vm.prank(alice);
        id = ajo.createCircle{value: 0}("Order", CONTRIBUTION, 4, ROUND_DUR, 0, 0);
        vm.prank(bob);   ajo.join{value: 0}(id);
        vm.prank(carol); ajo.join{value: 0}(id);

        // circle has 3 members, still PENDING (need 4)
        address[] memory order = new address[](3);
        order[0] = carol;
        order[1] = alice;
        order[2] = bob;

        vm.expectEmit(true, false, false, true, address(ajo));
        emit AjoCircle.PayoutOrderSet(id, order);
        vm.prank(alice);
        ajo.setPayoutOrder(id, order);

        address[] memory pr = ajo.getPayoutRecipients(id);
        assertEq(pr.length, 3);
        assertEq(pr[0], carol);
        assertEq(pr[1], alice);
        assertEq(pr[2], bob);
    }

    /// Creator sets [bob, alice] for 2 of 3 slots, carol joins after →
    /// payoutRecipients = [bob, alice, carol].
    function test_SetPayoutOrder_LateJoiner_Appended() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Late Join", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );
        vm.prank(bob);
        ajo.join{value: 0}(id);

        // Only alice + bob in circle (2 of 3); set order for current 2 members
        address[] memory order = new address[](2);
        order[0] = bob;
        order[1] = alice;

        vm.prank(alice);
        ajo.setPayoutOrder(id, order);

        // carol joins → appended to payoutRecipients as 3rd slot
        vm.prank(carol);
        ajo.join{value: 0}(id);

        // circle is now ACTIVE (all 3 filled)
        address[] memory pr = ajo.getPayoutRecipients(id);
        assertEq(pr.length, 3);
        assertEq(pr[0], bob,   "slot 0 = bob");
        assertEq(pr[1], alice, "slot 1 = alice");
        assertEq(pr[2], carol, "slot 2 = carol (late joiner appended)");
    }

    /// setPayoutOrder reverts after circle becomes ACTIVE.
    function test_SetPayoutOrder_LockedAfterStart() public {
        uint256 id = _create3MemberCircle(); // ACTIVE

        address[] memory order = new address[](3);
        order[0] = carol;
        order[1] = bob;
        order[2] = alice;

        vm.prank(alice);
        vm.expectRevert(AjoCircle.CircleNotPending.selector);
        ajo.setPayoutOrder(id, order);
    }

    /// Non-creator calls setPayoutOrder → NotCreator.
    function test_SetPayoutOrder_Revert_NotCreator() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Order", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );
        vm.prank(bob);
        ajo.join{value: 0}(id);

        address[] memory order = new address[](2);
        order[0] = bob;
        order[1] = alice;

        vm.prank(bob);
        vm.expectRevert(AjoCircle.NotCreator.selector);
        ajo.setPayoutOrder(id, order);
    }

    /// Array with wrong length → InvalidOrder.
    function test_SetPayoutOrder_Revert_WrongLength() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Order", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );
        vm.prank(bob);
        ajo.join{value: 0}(id);

        // Circle has 2 members; pass array of 3
        address[] memory order = new address[](3);
        order[0] = alice;
        order[1] = bob;
        order[2] = carol;

        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidOrder.selector);
        ajo.setPayoutOrder(id, order);
    }

    /// Array with duplicate member → InvalidOrder.
    function test_SetPayoutOrder_Revert_Duplicate() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Order", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );
        vm.prank(bob);
        ajo.join{value: 0}(id);

        // Pass [alice, alice] — duplicate
        address[] memory order = new address[](2);
        order[0] = alice;
        order[1] = alice;

        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidOrder.selector);
        ajo.setPayoutOrder(id, order);
    }

    /// Array contains non-member address → InvalidOrder.
    function test_SetPayoutOrder_Revert_NonMember() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Order", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );
        vm.prank(bob);
        ajo.join{value: 0}(id);

        // Pass [alice, dave] — dave is not a member
        address[] memory order = new address[](2);
        order[0] = alice;
        order[1] = dave;

        vm.prank(alice);
        vm.expectRevert(AjoCircle.InvalidOrder.selector);
        ajo.setPayoutOrder(id, order);
    }

    /// Full 3-member cycle with order [carol, bob, alice] — verify round recipients follow order.
    function test_SetPayoutOrder_PayoutsFollowNewOrder() public {
        // Use no-collateral, no-holdback for simplicity
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "OrderCycle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );
        vm.prank(bob);
        ajo.join{value: 0}(id);

        // Set order [carol, bob, alice] before carol joins (2 members currently)
        address[] memory order2 = new address[](2);
        order2[0] = bob;
        order2[1] = alice;
        vm.prank(alice);
        ajo.setPayoutOrder(id, order2);

        // carol joins last → appended at slot 2
        vm.prank(carol);
        ajo.join{value: 0}(id);

        // circle is now ACTIVE with order [bob, alice, carol]
        address[] memory pr = ajo.getPayoutRecipients(id);
        assertEq(pr[0], bob,   "R1 recipient = bob");
        assertEq(pr[1], alice, "R2 recipient = alice");
        assertEq(pr[2], carol, "R3 recipient = carol");

        // R1: bob is recipient → alice and carol contribute
        vm.prank(alice); ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        vm.prank(carol); ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        ajo.payout(id);
        assertEq(ajo.pendingWithdrawals(bob), 2 * CONTRIBUTION, "R1: bob got pot");

        // R2: alice is recipient → bob and carol contribute
        vm.prank(bob);   ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        vm.prank(carol); ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        ajo.payout(id);
        assertEq(ajo.pendingWithdrawals(alice), 2 * CONTRIBUTION, "R2: alice got pot");

        // R3: carol is recipient → alice and bob contribute
        vm.prank(alice); ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        vm.prank(bob);   ajo.contribute{value: CONTRIBUTION_NATIVE}(id);
        ajo.payout(id);
        assertEq(ajo.pendingWithdrawals(carol), 2 * CONTRIBUTION, "R3: carol got pot");

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(uint8(c.status), uint8(AjoCircle.CircleStatus.ENDED), "circle ENDED");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 4. cancelCircle expiry
    // ═══════════════════════════════════════════════════════════════════════

    /// After expiry, any member (non-creator) can cancel and deposits are refunded.
    function test_Cancel_Expiry_AnyMember() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "Expiry Cancel", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, 0
        );
        vm.prank(bob);
        ajo.join{value: COLLATERAL_NATIVE}(id);

        // Warp past PENDING_EXPIRY (7 days)
        vm.warp(block.timestamp + 7 days + 1);

        vm.expectEmit(true, false, false, false, address(ajo));
        emit AjoCircle.CircleCancelled(id);
        vm.prank(bob);
        ajo.cancelCircle(id);

        // Both alice and bob should have their deposits refunded
        assertEq(ajo.pendingWithdrawals(alice), COLLATERAL, "alice deposit refunded");
        assertEq(ajo.pendingWithdrawals(bob),   COLLATERAL, "bob deposit refunded");

        AjoCircle.Circle memory c = ajo.getCircle(id);
        assertEq(uint8(c.status), uint8(AjoCircle.CircleStatus.ENDED), "circle ENDED");
    }

    /// After expiry, a non-member cannot cancel → NotAMember.
    function test_Cancel_Expiry_Revert_NotMember() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Expiry NM", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(dave); // dave is not a member
        vm.expectRevert(AjoCircle.NotAMember.selector);
        ajo.cancelCircle(id);
    }

    /// Non-creator tries to cancel before expiry → NotCreator.
    function test_Cancel_Revert_NotExpiredYet() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Not Expired", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );
        vm.prank(bob);
        ajo.join{value: 0}(id);

        // Do NOT warp — circle is not expired
        vm.prank(bob);
        vm.expectRevert(AjoCircle.NotCreator.selector);
        ajo.cancelCircle(id);
    }

    /// After expiry, joining → CircleExpired.
    function test_Join_Revert_CircleExpired() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Expired Join", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(bob);
        vm.expectRevert(AjoCircle.CircleExpired.selector);
        ajo.join{value: 0}(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 5. getCircleCreatedAt / isPendingExpired
    // ═══════════════════════════════════════════════════════════════════════

    /// circleCreatedAt is stored correctly at circle creation.
    function test_GetCircleCreatedAt() public {
        uint256 ts = block.timestamp;
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Timestamp", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );
        assertEq(ajo.getCircleCreatedAt(id), ts, "createdAt == block.timestamp at creation");
    }

    /// isPendingExpired returns false before 7 days elapse.
    function test_IsPendingExpired_False() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Not Expired", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );

        vm.warp(block.timestamp + 7 days - 1);
        assertFalse(ajo.isPendingExpired(id), "not expired before 7 days");
    }

    /// isPendingExpired returns true after 7 days elapse.
    function test_IsPendingExpired_True() public {
        vm.prank(alice);
        uint256 id = ajo.createCircle{value: 0}(
            "Expired", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );

        vm.warp(block.timestamp + 7 days + 1);
        assertTrue(ajo.isPendingExpired(id), "expired after 7 days + 1 second");
    }

    /// isPendingExpired returns false for an ACTIVE circle (status != PENDING).
    function test_IsPendingExpired_FalseAfterActive() public {
        uint256 id = _create3MemberCircle(); // ACTIVE after carol joins

        // Warp well past 7 days — but status is ACTIVE so isPendingExpired must return false
        vm.warp(block.timestamp + 30 days);
        assertFalse(ajo.isPendingExpired(id), "active circle is never pending-expired");
    }
}
