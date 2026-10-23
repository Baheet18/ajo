// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AjoCircle is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum CircleStatus {
        PENDING,
        ACTIVE,
        ENDED
    }

    struct Circle {
        string name;
        address creator;
        uint256 contributionAmount;
        uint8 memberCount;
        uint256 roundDuration;
        CircleStatus status;
        uint8 currentRound; // 1-indexed; 0 = not started
        uint256 roundDeadline;
        address[] members; // join order
        address[] payoutRecipients; // payout order
        bool[] defaulted; // indexed by member position
    }

    event CircleCreated(
        uint256 indexed circleId,
        address indexed creator,
        string name,
        uint256 contributionAmount,
        uint8 memberCount,
        uint256 roundDuration
    );
    event MemberJoined(uint256 indexed circleId, address indexed member, uint8 position);
    event CircleStarted(uint256 indexed circleId, uint256 roundDeadline);
    event ContributionMade(uint256 indexed circleId, uint8 indexed round, address indexed member, uint256 amount);
    event RoundPayout(uint256 indexed circleId, uint8 indexed round, address indexed recipient, uint256 amount);
    event MemberDefaulted(uint256 indexed circleId, address indexed member, uint8 round);
    event CollateralSlashed(uint256 indexed circleId, address indexed member, uint256 amount);
    event BondLocked(uint256 indexed circleId, address indexed member, uint256 amount);
    event BondReleased(uint256 indexed circleId, address indexed member, uint256 amount);
    event BondSlashed(uint256 indexed circleId, address indexed member, uint256 amount, address recipient);
    event CollateralRefunded(uint256 indexed circleId, address indexed member, uint256 amount);
    event CircleEnded(uint256 indexed circleId);
    event CircleCancelled(uint256 indexed circleId);
    event Withdrawn(address indexed recipient, uint256 amount);

    error InvalidCircle();
    error InvalidContributionAmount();
    error InvalidMemberCount();
    error InvalidRoundDuration();
    error CircleNotPending();
    error CircleNotActive();
    error CircleEndedAlready();
    error AlreadyMember();
    error CircleFull();
    error NotMember();
    error NotCreator();
    error AlreadyContributed();
    error RoundDeadlinePassed();
    error MemberDefaultedAlready();
    error ContributionsStillPending();
    error NothingToWithdraw();

    uint256 public constant MIN_ROUND_DURATION = 300;
    address public constant USDC = 0x3600000000000000000000000000000000000000;

    IERC20 private constant USDC_TOKEN = IERC20(USDC);

    uint256 public circleCount;
    mapping(uint256 => Circle) public circles;

    mapping(uint256 => mapping(uint8 => mapping(address => bool))) public roundPaid;
    mapping(uint256 => mapping(address => bool)) public isDefaulted;
    mapping(uint256 => mapping(address => uint256)) public memberDeposit;
    mapping(uint256 => mapping(address => uint256)) public memberBond;
    mapping(uint256 => mapping(address => uint256)) public memberIndex;
    mapping(uint256 => mapping(address => bool)) public isMember;
    mapping(uint256 => mapping(uint8 => uint256)) private roundPot;
    mapping(address => uint256) public pendingWithdrawals;

    function createCircle(
        string calldata name,
        uint256 contributionAmount,
        uint8 memberCount,
        uint256 roundDuration
    ) external nonReentrant returns (uint256 circleId) {
        if (contributionAmount == 0) revert InvalidContributionAmount();
        if (memberCount < 2 || memberCount > 10) revert InvalidMemberCount();
        if (roundDuration < MIN_ROUND_DURATION) revert InvalidRoundDuration();

        circleId = ++circleCount;

        Circle storage circle = circles[circleId];
        circle.name = name;
        circle.creator = msg.sender;
        circle.contributionAmount = contributionAmount;
        circle.memberCount = memberCount;
        circle.roundDuration = roundDuration;
        circle.status = CircleStatus.PENDING;

        emit CircleCreated(circleId, msg.sender, name, contributionAmount, memberCount, roundDuration);

        _join(circleId, msg.sender);
    }

    function join(uint256 circleId) external nonReentrant {
        _join(circleId, msg.sender);
    }

    function cancelCircle(uint256 circleId) external nonReentrant {
        Circle storage circle = circles[circleId];
        _requireValidCircle(circleId);

        if (circle.status != CircleStatus.PENDING) revert CircleNotPending();
        if (circle.creator != msg.sender) revert NotCreator();

        uint256 len = circle.members.length;
        for (uint256 i = 0; i < len; i++) {
            address member = circle.members[i];
            uint256 toRefund = memberDeposit[circleId][member];
            pendingWithdrawals[member] += toRefund;
            memberDeposit[circleId][member] = 0;
            emit CollateralRefunded(circleId, member, toRefund);
        }

        circle.status = CircleStatus.ENDED;
        circle.roundDeadline = 0;

        emit CircleCancelled(circleId);
    }

    function contribute(uint256 circleId) external nonReentrant {
        Circle storage circle = circles[circleId];
        _requireValidCircle(circleId);

        if (circle.status != CircleStatus.ACTIVE) revert CircleNotActive();
        if (!isMember[circleId][msg.sender]) revert NotMember();
        if (isDefaulted[circleId][msg.sender]) revert MemberDefaultedAlready();

        uint8 round = circle.currentRound;
        if (roundPaid[circleId][round][msg.sender]) revert AlreadyContributed();
        if (circle.roundDeadline > 0 && block.timestamp > circle.roundDeadline) revert RoundDeadlinePassed();

        USDC_TOKEN.safeTransferFrom(msg.sender, address(this), circle.contributionAmount);

        roundPaid[circleId][round][msg.sender] = true;
        roundPot[circleId][round] += circle.contributionAmount;

        emit ContributionMade(circleId, round, msg.sender, circle.contributionAmount);

        if (memberBond[circleId][msg.sender] > 0) {
            uint256 release = circle.contributionAmount;
            if (release > memberBond[circleId][msg.sender]) release = memberBond[circleId][msg.sender];
            memberBond[circleId][msg.sender] -= release;
            pendingWithdrawals[msg.sender] += release;
            emit BondReleased(circleId, msg.sender, release);
        }
    }

    function payout(uint256 circleId) external nonReentrant {
        Circle storage circle = circles[circleId];
        _requireValidCircle(circleId);
        if (circle.status != CircleStatus.ACTIVE) revert CircleNotActive();

        uint8 round = circle.currentRound;
        uint256 pot = roundPot[circleId][round];

        // Capture permanent-default status BEFORE slashing (slashing may mark recipient isDefaulted)
        address recipient = circle.payoutRecipients[round - 1];
        bool recipientAlreadyDefaulted = isDefaulted[circleId][recipient];

        if (block.timestamp < circle.roundDeadline) {
            uint256 mLen = circle.members.length;
            for (uint256 i = 0; i < mLen; i++) {
                address member = circle.members[i];
                if (!isDefaulted[circleId][member] && !roundPaid[circleId][round][member]) {
                    revert ContributionsStillPending();
                }
            }
        } else {
            pot += _slashDefaulters(circleId, round);
        }

        // recipientAlreadyDefaulted = true means they were excluded in a PRIOR round
        // (before their payout slot). Skip their payout; carry pot forward.
        // recipientAlreadyDefaulted = false means they are either:
        //   (a) paid this round — normal payout
        //   (b) missed this round (just marked by _slashDefaulters OR post-payout miss)
        //   Either way, they receive the pot minus their own missed share (if any).
        if (recipientAlreadyDefaulted) {
            // Skip permanently defaulted recipient
            if (round < circle.memberCount) {
                roundPot[circleId][round + 1] += pot;
            } else {
                _distributeToContributors(circleId, round, pot);
            }
        } else {
            // Recipient is eligible — check if they missed THIS round
            bool recipientMissed = !roundPaid[circleId][round][recipient];
            if (recipientMissed) {
                uint256 deduct = circle.contributionAmount;
                if (deduct > pot) deduct = pot;
                pot -= deduct;
            }

            uint8 roundsRemaining = circle.memberCount - round;
            uint256 bond = uint256(roundsRemaining) * circle.contributionAmount;
            if (bond > pot) bond = pot;

            uint256 recipientReceives = pot - bond;
            pendingWithdrawals[recipient] += recipientReceives;
            memberBond[circleId][recipient] += bond;

            if (pot > 0) emit RoundPayout(circleId, round, recipient, recipientReceives);
            if (bond > 0) emit BondLocked(circleId, recipient, bond);
        }

        circle.currentRound = round + 1;

        if (circle.currentRound > circle.memberCount) {
            _endCircleAndRefund(circleId);
            return;
        }

        circle.roundDeadline = block.timestamp + circle.roundDuration;
    }

    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NothingToWithdraw();

        pendingWithdrawals[msg.sender] = 0;
        USDC_TOKEN.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function getCircle(uint256 circleId) external view returns (Circle memory) {
        _requireValidCircle(circleId);
        return circles[circleId];
    }

    function getMembers(uint256 circleId) external view returns (address[] memory) {
        _requireValidCircle(circleId);
        return circles[circleId].members;
    }

    function getPayoutRecipients(uint256 circleId) external view returns (address[] memory) {
        _requireValidCircle(circleId);
        return circles[circleId].payoutRecipients;
    }

    function getCurrentRound(uint256 circleId) external view returns (uint8) {
        _requireValidCircle(circleId);
        return circles[circleId].currentRound;
    }

    function getNextRecipient(uint256 circleId) external view returns (address) {
        _requireValidCircle(circleId);

        Circle storage circle = circles[circleId];
        if (circle.payoutRecipients.length == 0) return address(0);

        if (circle.currentRound == 0) {
            return circle.payoutRecipients[0];
        }

        if (circle.currentRound > circle.memberCount) {
            return address(0);
        }

        return circle.payoutRecipients[circle.currentRound - 1];
    }

    function getRoundPaidStatus(uint256 circleId, uint8 round) external view returns (bool[] memory paidStatus) {
        _requireValidCircle(circleId);

        Circle storage circle = circles[circleId];
        if (round == 0 || round > circle.memberCount) revert InvalidCircle();

        uint256 len = circle.members.length;
        paidStatus = new bool[](len);

        for (uint256 i = 0; i < len; i++) {
            paidStatus[i] = roundPaid[circleId][round][circle.members[i]];
        }
    }

    function hasMemberPaid(uint256 circleId, address member) external view returns (bool) {
        _requireValidCircle(circleId);
        Circle storage circle = circles[circleId];
        return roundPaid[circleId][circle.currentRound][member];
    }

    function getMemberDefaulted(uint256 circleId, address member) external view returns (bool) {
        _requireValidCircle(circleId);
        return isDefaulted[circleId][member];
    }

    function getMemberDeposit(uint256 circleId, address member) external view returns (uint256) {
        _requireValidCircle(circleId);
        return memberDeposit[circleId][member];
    }

    function getMemberBond(uint256 circleId, address member) external view returns (uint256) {
        _requireValidCircle(circleId);
        return memberBond[circleId][member];
    }

    function getRoundDeadline(uint256 circleId) external view returns (uint256) {
        _requireValidCircle(circleId);
        return circles[circleId].roundDeadline;
    }

    function getPotSize(uint256 circleId) external view returns (uint256) {
        _requireValidCircle(circleId);
        Circle storage circle = circles[circleId];
        return roundPot[circleId][circle.currentRound];
    }

    function _join(uint256 circleId, address member) internal {
        Circle storage circle = circles[circleId];
        _requireValidCircle(circleId);

        if (isMember[circleId][member]) revert AlreadyMember();
        if (circle.members.length >= circle.memberCount) revert CircleFull();
        if (circle.status != CircleStatus.PENDING) revert CircleNotPending();

        USDC_TOKEN.safeTransferFrom(member, address(this), circle.contributionAmount);
        memberDeposit[circleId][member] = circle.contributionAmount;

        uint256 index = circle.members.length;
        circle.members.push(member);
        circle.payoutRecipients.push(member);
        circle.defaulted.push(false);

        isMember[circleId][member] = true;
        memberIndex[circleId][member] = index;

        emit MemberJoined(circleId, member, uint8(index + 1));

        if (circle.members.length == circle.memberCount) {
            circle.status = CircleStatus.ACTIVE;
            circle.currentRound = 1;
            circle.roundDeadline = block.timestamp + circle.roundDuration;

            emit CircleStarted(circleId, circle.roundDeadline);
        }
    }

    function _slashDefaulters(uint256 circleId, uint8 round) private returns (uint256 additionalPot) {
        Circle storage circle = circles[circleId];
        uint256 mLen = circle.members.length;

        for (uint256 i = 0; i < mLen; i++) {
            address member = circle.members[i];
            if (isDefaulted[circleId][member]) continue;
            if (roundPaid[circleId][round][member]) continue;

            if (memberBond[circleId][member] > 0) {
                uint256 slash = circle.contributionAmount;
                if (slash > memberBond[circleId][member]) slash = memberBond[circleId][member];
                memberBond[circleId][member] -= slash;
                additionalPot += slash;
                emit BondSlashed(circleId, member, slash, address(0));
            } else {
                isDefaulted[circleId][member] = true;
                uint256 idx = memberIndex[circleId][member];
                circle.defaulted[idx] = true;
                emit MemberDefaulted(circleId, member, round);

                uint256 slash = circle.contributionAmount;
                if (slash > memberDeposit[circleId][member]) slash = memberDeposit[circleId][member];
                memberDeposit[circleId][member] -= slash;
                additionalPot += slash;
                emit CollateralSlashed(circleId, member, slash);
            }
        }
    }

    function _distributeToContributors(uint256 circleId, uint8 round, uint256 pot) private {
        if (pot == 0) return;
        Circle storage circle = circles[circleId];
        uint256 mLen = circle.members.length;
        uint256 count = 0;
        for (uint256 i = 0; i < mLen; i++) {
            if (roundPaid[circleId][round][circle.members[i]]) count++;
        }
        if (count == 0) return;
        uint256 share = pot / count;
        uint256 rem = pot % count;
        bool first = true;
        for (uint256 i = 0; i < mLen; i++) {
            address m = circle.members[i];
            if (!roundPaid[circleId][round][m]) continue;
            uint256 amt = share + (first ? rem : 0);
            first = false;
            pendingWithdrawals[m] += amt;
        }
    }

    function _endCircleAndRefund(uint256 circleId) internal {
        Circle storage circle = circles[circleId];
        circle.status = CircleStatus.ENDED;
        circle.roundDeadline = 0;

        uint256 len = circle.members.length;
        for (uint256 i = 0; i < len; i++) {
            address member = circle.members[i];
            uint256 toRefund = memberBond[circleId][member] + memberDeposit[circleId][member];
            if (toRefund > 0) {
                memberBond[circleId][member] = 0;
                memberDeposit[circleId][member] = 0;
                pendingWithdrawals[member] += toRefund;
                emit CollateralRefunded(circleId, member, toRefund);
            }
        }

        emit CircleEnded(circleId);
    }

    function _requireValidCircle(uint256 circleId) internal view {
        if (circleId == 0 || circleId > circleCount) revert InvalidCircle();
    }
}
