// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AjoCircle} from "../AjoCircle.sol";

abstract contract AjoCircleTestBase is Test {
    AjoCircle internal ajo;

    address internal alice = makeAddr("alice");
    address internal bob   = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave  = makeAddr("dave");

    uint256 internal constant CONTRIBUTION        = 100e6;   // 6-decimal
    uint256 internal constant COLLATERAL          = 100e6;   // 6-decimal
    uint256 internal constant CONTRIBUTION_NATIVE = 100e6 * 1e12; // 100e18 — msg.value
    uint256 internal constant COLLATERAL_NATIVE   = 100e6 * 1e12; // 100e18 — msg.value
    uint8   internal constant MEMBER_COUNT        = 3;
    uint256 internal constant ROUND_DUR           = 300;
    uint16  internal constant HOLDBACK_BPS        = 1000; // 10%

    function setUp() public virtual {
        ajo = new AjoCircle();

        // Give each actor plenty of native USDC for all rounds + collateral
        vm.deal(alice, 10_000e18);
        vm.deal(bob,   10_000e18);
        vm.deal(carol, 10_000e18);
        vm.deal(dave,  10_000e18);
    }

    // ── helpers ────────────────────────────────────────────────────────────

    /// 3-member circle: holdbackBps=HOLDBACK_BPS (10%), collateral=COLLATERAL
    /// Starts ACTIVE after carol joins. Order: alice→bob→carol.
    function _create3MemberCircle() internal returns (uint256 circleId) {
        vm.prank(alice);
        circleId = ajo.createCircle{value: COLLATERAL_NATIVE}(
            "Test Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, COLLATERAL, HOLDBACK_BPS
        );
        vm.prank(bob);
        ajo.join{value: COLLATERAL_NATIVE}(circleId);
        vm.prank(carol);
        ajo.join{value: COLLATERAL_NATIVE}(circleId);
    }

    /// 3-member circle with holdbackBps=0, no collateral (friends mode)
    function _create3MemberFriendsCircle() internal returns (uint256 circleId) {
        vm.prank(alice);
        circleId = ajo.createCircle{value: 0}(
            "Friends Circle", CONTRIBUTION, MEMBER_COUNT, ROUND_DUR, 0, 0
        );
        vm.prank(bob);
        ajo.join{value: 0}(circleId);
        vm.prank(carol);
        ajo.join{value: 0}(circleId);
    }

    /// All non-recipient members contribute in the current round.
    function _contributeNonRecipients(uint256 circleId, address recipient) internal {
        if (alice != recipient) { vm.prank(alice); ajo.contribute{value: CONTRIBUTION_NATIVE}(circleId); }
        if (bob   != recipient) { vm.prank(bob);   ajo.contribute{value: CONTRIBUTION_NATIVE}(circleId); }
        if (carol != recipient) { vm.prank(carol);  ajo.contribute{value: CONTRIBUTION_NATIVE}(circleId); }
    }

    function _withdraw(address who) internal {
        vm.prank(who);
        ajo.withdraw();
    }

    function _warpPastDeadline(uint256 circleId) internal {
        vm.warp(ajo.getRoundDeadline(circleId) + 1);
    }

    /// Advance one full round: all non-recipients contribute then payout.
    function _advanceRound(uint256 circleId, address recipient) internal {
        _contributeNonRecipients(circleId, recipient);
        ajo.payout(circleId);
    }
}
