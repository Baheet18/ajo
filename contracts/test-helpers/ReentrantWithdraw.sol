// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAjoCircleWithdraw {
    function withdraw() external;
}

/// @dev Attacker contract whose receive() re-enters AjoCircle.withdraw().
///      Used to verify ReentrancyGuard blocks the second call.
contract ReentrantWithdraw {
    IAjoCircleWithdraw public target;
    bool public attacking;

    constructor(address _target) {
        target = IAjoCircleWithdraw(_target);
    }

    /// @dev Arm the reentrancy attack for the next receive() invocation.
    function setAttacking(bool _attacking) external {
        attacking = _attacking;
    }

    /// @dev Called by the test to trigger the first withdraw().
    function attack() external {
        target.withdraw();
    }

    /// @dev On receiving native ETH from AjoCircle.withdraw(), re-enter once.
    receive() external payable {
        if (attacking) {
            attacking = false; // prevent infinite recursion
            target.withdraw(); // should be blocked by ReentrancyGuard
        }
    }
}
