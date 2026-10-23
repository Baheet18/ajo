// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IAjoCircleWithdraw {
    function withdraw() external;
}

/// @dev Malicious ERC-20: on every `transfer` call it attempts to re-enter
///      `withdraw()` on the AjoCircle contract.  Used to test ReentrancyGuard.
///      With the pull-payment model, `withdraw()` is the only function that
///      performs a safeTransfer, so that is the correct reentrancy vector.
contract ReentrantMockERC20 is ERC20 {
    uint8 private _dec;
    address public target;   // AjoCircle address
    uint256 public circleId; // kept for API compatibility
    bool public attacking;

    constructor(string memory name_, string memory symbol_, uint8 decimals_)
        ERC20(name_, symbol_)
    {
        _dec = decimals_;
    }

    function decimals() public view override returns (uint8) { return _dec; }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev Set the reentrancy attack parameters.
    function setAttackParams(address _target, uint256 _circleId) external {
        target   = _target;
        circleId = _circleId;
    }

    /// @dev Arm the attack.
    function setAttacking(bool _attacking) external {
        attacking = _attacking;
    }

    /// @dev Override transfer to re-enter withdraw() once when attack is armed.
    function transfer(address to, uint256 amount) public override returns (bool) {
        bool ok = super.transfer(to, amount);
        if (attacking && target != address(0)) {
            attacking = false;                            // prevent further recursion
            IAjoCircleWithdraw(target).withdraw();        // should be blocked by guard
        }
        return ok;
    }
}
