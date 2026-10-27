// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AjoCircle is ReentrancyGuard {
    uint256 public constant MIN_ROUND_DURATION = 300;
    address public constant USDC = 0x3600000000000000000000000000000000000000;
    uint16 public constant MAX_HOLDBACK_BPS = 3000; // 30%
    uint256 private constant NATIVE_SCALE = 1e12; // 1 native USDC = 1e12 ERC-20 units (18 dec vs 6 dec)
    // Note: native USDC sent outside the protocol entry points (e.g. via selfdestruct) cannot be
    // recovered. This is an accepted limitation of a no-admin design; selfdestruct is deprecated
    // on most EVM chains and poses negligible risk.

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
        uint256 collateralAmount; // 0 = no deposit required at join
        uint16 holdbackBps; // 0-3000, basis points of holdback from payout
        CircleStatus status;
        uint8 currentRound; // 1-indexed; 0 = not started
        uint256 roundDeadline;
        address[] members;
        address[] payoutRecipients;
        bool[] defaulted;
    }

    event CircleCreated(
        uint256 indexed circleId,
        address indexed creator,
        string name,
        uint256 contributionAmount,
        uint8 memberCount,
        uint256 roundDuration,
        uint256 collateralAmount,
        uint16 holdbackBps
    );
    event MemberJoined(uint256 indexed circleId, address indexed member, uint8 position);
    event MemberLeft(uint256 indexed circleId, address indexed member);
    event PayoutOrderSet(uint256 indexed circleId, address[] order);
    event CircleStarted(uint256 indexed circleId, uint256 roundDeadline);
    event ContributionMade(uint256 indexed circleId, uint8 indexed round, address indexed member, uint256 amount);
    event RoundPayout(uint256 indexed circleId, uint8 indexed round, address indexed recipient, uint256 amount);
    event MemberDefaulted(uint256 indexed circleId, address indexed member, uint8 round);
    event CollateralSlashed(uint256 indexed circleId, address indexed member, uint256 amount);
    event HoldbackLocked(uint256 indexed circleId, address indexed member, uint256 amount);
    event HoldbackReleased(uint256 indexed circleId, address indexed member, uint256 amount);
    event HoldbackSlashed(uint256 indexed circleId, address indexed member, uint256 amount, address recipient);
    event CollateralRefunded(uint256 indexed circleId, address indexed member, uint256 amount);
    event CircleEnded(uint256 indexed circleId);
    event CircleCancelled(uint256 indexed circleId);
    event Withdrawn(address indexed recipient, uint256 amount);

    error InvalidCircle();
    error InvalidContributionAmount();
    error InvalidMemberCount();
    error InvalidRoundDuration();
    error InvalidHoldbackBps();
    error CircleNotPending();
    error CircleNotActive();
    error CircleEndedAlready();
    error AlreadyMember();
    error CircleFull();
    error NotMember();
    error NotAMember(); // caller is not a member (for leave)
    error IsCreator(); // creator cannot leave (use cancelCircle)
    error CircleExpired(); // pending circle has expired — use cancelCircle
    error InvalidOrder(); // setPayoutOrder array is not a valid permutation
    error NotCreator();
    error AlreadyContributed();
    error RoundDeadlinePassed();
    error MemberDefaultedAlready();
    error ContributionsStillPending();
    error NothingToWithdraw();
    error IncorrectPayment();

    uint256 public circleCount;
    mapping(uint256 => Circle) public circles;
    mapping(uint256 => mapping(uint8 => mapping(address => bool))) public roundPaid;
    mapping(uint256 => mapping(address => bool)) public isDefaulted;
    mapping(uint256 => mapping(address => uint256)) public memberDeposit; // collateral locked at join
    mapping(uint256 => mapping(address => uint256)) public memberHoldback; // holdback locked at payout
    mapping(uint256 => mapping(address => uint256)) public memberIndex;
    mapping(uint256 => mapping(address => uint256)) public payoutIndex; // position in payoutRecipients[]
    mapping(uint256 => mapping(address => bool)) public isMember;
    mapping(uint256 => mapping(uint8 => uint256)) private roundPot;
    mapping(address => uint256) public pendingWithdrawals;

    // Global reputation counters (incremented across all circles)
    mapping(address => uint256) public totalRoundsPaid;
    mapping(address => uint256) public totalRoundsMissed;
    mapping(address => uint256) public totalCirclesCompleted;

    // Pending circle expiry: 7 days after creation, any member may cancel
    uint256 public constant PENDING_EXPIRY = 7 days;
    mapping(uint256 => uint256) public circleCreatedAt; // timestamp when circle was created

    function createCircle(
        string calldata name,
        uint256 contributionAmount,
        uint8 memberCount,
        uint256 roundDuration,
        uint256 collateralAmount,
        uint16 holdbackBps
    ) external payable nonReentrant returns (uint256 circleId) {
        if (contributionAmount == 0) revert InvalidContributionAmount();
        if (memberCount < 2 || memberCount > 10) revert InvalidMemberCount();
        if (roundDuration < MIN_ROUND_DURATION) revert InvalidRoundDuration();
        if (holdbackBps > MAX_HOLDBACK_BPS) revert InvalidHoldbackBps();

        circleId = ++circleCount;
        Circle storage circle = circles[circleId];
        circle.name = name;
        circle.creator = msg.sender;
        circle.contributionAmount = contributionAmount;
        circle.memberCount = memberCount;
        circle.roundDuration = roundDuration;
        circle.collateralAmount = collateralAmount;
        circle.holdbackBps = holdbackBps;
        circle.status = CircleStatus.PENDING;
        circleCreatedAt[circleId] = block.timestamp;

        emit CircleCreated(
            circleId,
            msg.sender,
            name,
            contributionAmount,
            memberCount,
            roundDuration,
            collateralAmount,
            holdbackBps
        );
        _join(circleId, msg.sender);
    }

    function join(uint256 circleId) external payable nonReentrant {
        _join(circleId, msg.sender);
    }

    function cancelCircle(uint256 circleId) external nonReentrant {
        Circle storage circle = circles[circleId];
        _requireValidCircle(circleId);
        if (circle.status != CircleStatus.PENDING) revert CircleNotPending();

        bool isExpired = block.timestamp >= circleCreatedAt[circleId] + PENDING_EXPIRY;
        if (circle.creator != msg.sender) {
            // Non-creator may only cancel if circle has expired AND they are a member
            if (!isExpired) revert NotCreator();
            if (!isMember[circleId][msg.sender]) revert NotAMember();
        }

        uint256 len = circle.members.length;
        for (uint256 i = 0; i < len; i++) {
            address member = circle.members[i];
            uint256 toRefund = memberDeposit[circleId][member];
            if (toRefund > 0) {
                memberDeposit[circleId][member] = 0;
                pendingWithdrawals[member] += toRefund;
                emit CollateralRefunded(circleId, member, toRefund);
            }
        }

        circle.status = CircleStatus.ENDED;
        circle.roundDeadline = 0;
        emit CircleCancelled(circleId);
    }

    /// @notice Leave a PENDING circle. Creator cannot leave; use cancelCircle instead.
    /// Refunds collateral deposit to pendingWithdrawals. Removes member via swap-and-pop.
    function leave(uint256 circleId) external nonReentrant {
        _requireValidCircle(circleId);
        Circle storage circle = circles[circleId];
        if (circle.status != CircleStatus.PENDING) revert CircleNotPending();
        if (!isMember[circleId][msg.sender]) revert NotAMember();
        if (circle.creator == msg.sender) revert IsCreator();

        // Refund deposit
        uint256 deposit = memberDeposit[circleId][msg.sender];
        if (deposit > 0) {
            memberDeposit[circleId][msg.sender] = 0;
            pendingWithdrawals[msg.sender] += deposit;
            emit CollateralRefunded(circleId, msg.sender, deposit);
        }

        uint256 last = circle.members.length - 1;

        // --- Swap-and-pop members[] (using memberIndex) ---
        uint256 mIdx = memberIndex[circleId][msg.sender];
        if (mIdx != last) {
            address lastMember = circle.members[last];
            circle.members[mIdx] = lastMember;
            circle.defaulted[mIdx] = circle.defaulted[last];
            memberIndex[circleId][lastMember] = mIdx;
        }
        circle.members.pop();
        circle.defaulted.pop();

        // --- Order-preserving removal from payoutRecipients[] ---
        uint256 pIdx = payoutIndex[circleId][msg.sender];
        uint256 prLen = circle.payoutRecipients.length;
        for (uint256 i = pIdx; i < prLen - 1; i++) {
            address shifted = circle.payoutRecipients[i + 1];
            circle.payoutRecipients[i] = shifted;
            payoutIndex[circleId][shifted] = i;
        }
        circle.payoutRecipients.pop();

        isMember[circleId][msg.sender] = false;
        delete memberIndex[circleId][msg.sender];
        delete payoutIndex[circleId][msg.sender];

        emit MemberLeft(circleId, msg.sender);
    }

    /// @notice Creator sets the payout order while circle is PENDING.
    /// The order array must contain exactly the current members, each exactly once.
    /// Members who join after this is called are appended to the end of payoutRecipients.
    /// The order locks permanently when the circle becomes ACTIVE (all slots filled).
    function setPayoutOrder(uint256 circleId, address[] calldata order) external nonReentrant {
        _requireValidCircle(circleId);
        Circle storage circle = circles[circleId];
        if (circle.status != CircleStatus.PENDING) revert CircleNotPending();
        if (circle.creator != msg.sender) revert NotCreator();

        uint256 len = circle.members.length;
        if (order.length != len) revert InvalidOrder();

        // Verify it is an exact permutation of current members
        // Use a temporary bool array indexed by memberIndex
        bool[] memory seen = new bool[](len);
        for (uint256 i = 0; i < len; i++) {
            address m = order[i];
            if (!isMember[circleId][m]) revert InvalidOrder();
            uint256 mIdx = memberIndex[circleId][m];
            if (seen[mIdx]) revert InvalidOrder(); // duplicate
            seen[mIdx] = true;
        }

        // Apply: replace payoutRecipients with the given order for the first len slots
        // (slots beyond len will be filled by future _join calls appending to payoutRecipients)
        for (uint256 i = 0; i < len; i++) {
            circle.payoutRecipients[i] = order[i];
        }

        for (uint256 i = 0; i < len; i++) {
            payoutIndex[circleId][order[i]] = i;
        }

        emit PayoutOrderSet(circleId, order);
    }

    function contribute(uint256 circleId) external payable nonReentrant {
        Circle storage circle = circles[circleId];
        _requireValidCircle(circleId);
        if (circle.status != CircleStatus.ACTIVE) revert CircleNotActive();
        if (!isMember[circleId][msg.sender]) revert NotMember();
        if (isDefaulted[circleId][msg.sender]) revert MemberDefaultedAlready();

        uint8 round = circle.currentRound;
        if (roundPaid[circleId][round][msg.sender]) revert AlreadyContributed();
        if (circle.roundDeadline > 0 && block.timestamp > circle.roundDeadline) revert RoundDeadlinePassed();

        if (msg.value != circle.contributionAmount * NATIVE_SCALE) revert IncorrectPayment();

        roundPaid[circleId][round][msg.sender] = true;
        roundPot[circleId][round] += circle.contributionAmount;
        totalRoundsPaid[msg.sender]++;

        emit ContributionMade(circleId, round, msg.sender, circle.contributionAmount);

        // Release holdback pro-rata: one round's share of their holdback
        uint256 hb = memberHoldback[circleId][msg.sender];
        if (hb > 0) {
            // The holdback was sized as holdbackBps * (roundsOwed * contribution) / 10000 at payout time.
            // Each subsequent round they pay, release contributionAmount * holdbackBps / 10000.
            uint256 releasePerRound = (circle.contributionAmount * circle.holdbackBps) / 10000;
            if (releasePerRound == 0) releasePerRound = 0; // no-op but explicit
            uint256 toRelease = releasePerRound < hb ? releasePerRound : hb;
            if (toRelease > 0) {
                memberHoldback[circleId][msg.sender] -= toRelease;
                pendingWithdrawals[msg.sender] += toRelease;
                emit HoldbackReleased(circleId, msg.sender, toRelease);
            }
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
            // Early payout: all non-defaulted, non-recipient members must have paid
            uint256 mLen = circle.members.length;
            for (uint256 i = 0; i < mLen; i++) {
                address member = circle.members[i];
                if (member == recipient) continue;
                if (!isDefaulted[circleId][member] && !roundPaid[circleId][round][member]) {
                    revert ContributionsStillPending();
                }
            }
        } else {
            pot += _slashDefaulters(circleId, round);
        }

        if (recipientAlreadyDefaulted) {
            // Recipient was permanently excluded before this round — skip, carry pot forward
            if (round < circle.memberCount) {
                roundPot[circleId][round + 1] += pot;
            } else {
                _terminalPotDistribution(circleId, round, pot);
            }
        } else {
            // Compute holdback: holdbackBps * (roundsStillOwed * contributionAmount) / 10000
            // roundsStillOwed = rounds AFTER this one (the recipient already received, so they owe rounds remaining)
            uint8 roundsStillOwed = circle.memberCount - round; // last recipient: 0 rounds owed → holdback = 0
            uint256 holdback = (uint256(circle.holdbackBps) * uint256(roundsStillOwed) * circle.contributionAmount) / 10000;
            if (holdback > pot) holdback = pot;

            uint256 recipientReceives = pot - holdback;
            pendingWithdrawals[recipient] += recipientReceives;
            memberHoldback[circleId][recipient] += holdback;

            if (pot > 0) emit RoundPayout(circleId, round, recipient, recipientReceives);
            if (holdback > 0) emit HoldbackLocked(circleId, recipient, holdback);
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
        // pendingWithdrawals is in 6-decimal units; convert to native 18-decimal for transfer
        (bool ok,) = payable(msg.sender).call{value: amount * NATIVE_SCALE}("");
        if (!ok) revert NothingToWithdraw(); // reuse error; transfer failure is the only failure mode
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

    function getMemberHoldback(uint256 circleId, address member) external view returns (uint256) {
        _requireValidCircle(circleId);
        return memberHoldback[circleId][member];
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

    function getMemberReputation(address member) external view returns (uint256 paid, uint256 missed, uint256 completed) {
        return (totalRoundsPaid[member], totalRoundsMissed[member], totalCirclesCompleted[member]);
    }

    function _join(uint256 circleId, address member) internal {
        Circle storage circle = circles[circleId];
        _requireValidCircle(circleId);
        if (isMember[circleId][member]) revert AlreadyMember();
        if (circle.members.length >= circle.memberCount) revert CircleFull();
        if (circle.status != CircleStatus.PENDING) revert CircleNotPending();
        if (block.timestamp >= circleCreatedAt[circleId] + PENDING_EXPIRY) revert CircleExpired();

        if (circle.collateralAmount > 0) {
            if (msg.value != circle.collateralAmount * NATIVE_SCALE) revert IncorrectPayment();
            memberDeposit[circleId][member] = circle.collateralAmount;
        } else {
            if (msg.value != 0) revert IncorrectPayment();
        }

        uint256 index = circle.members.length;
        circle.members.push(member);
        circle.payoutRecipients.push(member);
        circle.defaulted.push(false);
        isMember[circleId][member] = true;
        memberIndex[circleId][member] = index;
        payoutIndex[circleId][member] = index; // same as memberIndex at join time

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
        address roundRecipient = circle.payoutRecipients[round - 1];

        for (uint256 i = 0; i < mLen; i++) {
            address member = circle.members[i];
            if (isDefaulted[circleId][member]) continue;
            if (roundPaid[circleId][round][member]) continue;
            if (member == roundRecipient) continue; // recipient is never slashed for missing their own round

            // Mark defaulter and increment reputation counter
            totalRoundsMissed[member]++;

            uint256 slash = circle.contributionAmount;
            uint256 hb = memberHoldback[circleId][member];
            uint256 dep = memberDeposit[circleId][member];

            uint256 fromHoldback = 0;
            uint256 fromDeposit = 0;

            if (hb >= slash) {
                fromHoldback = slash;
            } else {
                fromHoldback = hb;
                uint256 remaining = slash - fromHoldback;
                fromDeposit = remaining <= dep ? remaining : dep;
            }

            if (fromHoldback > 0) {
                memberHoldback[circleId][member] -= fromHoldback;
                emit HoldbackSlashed(circleId, member, fromHoldback, roundRecipient);
            }
            if (fromDeposit > 0) {
                memberDeposit[circleId][member] -= fromDeposit;
                emit CollateralSlashed(circleId, member, fromDeposit);
            }

            additionalPot += fromHoldback + fromDeposit;

            // Permanently exclude only when both holdback and deposit are exhausted
            if (memberHoldback[circleId][member] == 0 && memberDeposit[circleId][member] == 0) {
                isDefaulted[circleId][member] = true;
                circle.defaulted[memberIndex[circleId][member]] = true;
                emit MemberDefaulted(circleId, member, round);
            }
        }
    }

    function _endCircleAndRefund(uint256 circleId) internal {
        Circle storage circle = circles[circleId];
        circle.status = CircleStatus.ENDED;
        circle.roundDeadline = 0;

        uint256 len = circle.members.length;
        for (uint256 i = 0; i < len; i++) {
            address member = circle.members[i];
            uint256 toRefund = memberHoldback[circleId][member] + memberDeposit[circleId][member];
            if (toRefund > 0) {
                memberHoldback[circleId][member] = 0;
                memberDeposit[circleId][member] = 0;
                pendingWithdrawals[member] += toRefund;
                emit CollateralRefunded(circleId, member, toRefund);
            }
            // Increment circlesCompleted for non-permanently-defaulted members
            if (!isDefaulted[circleId][member]) {
                totalCirclesCompleted[member]++;
            }
        }

        emit CircleEnded(circleId);
    }

    function _terminalPotDistribution(uint256 circleId, uint8 round, uint256 pot) private {
        if (pot == 0) return;
        Circle storage circle = circles[circleId];
        uint256 mLen = circle.members.length;

        // Try contributors first
        uint256 count = 0;
        for (uint256 i = 0; i < mLen; i++) {
            if (roundPaid[circleId][round][circle.members[i]]) count++;
        }
        if (count > 0) {
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
            return;
        }

        // No contributors — try non-defaulted members
        uint256 eligible = 0;
        for (uint256 i = 0; i < mLen; i++) {
            if (!isDefaulted[circleId][circle.members[i]]) eligible++;
        }
        if (eligible > 0) {
            uint256 share = pot / eligible;
            uint256 rem = pot % eligible;
            bool first = true;
            for (uint256 i = 0; i < mLen; i++) {
                address m = circle.members[i];
                if (isDefaulted[circleId][m]) continue;
                uint256 amt = share + (first ? rem : 0);
                first = false;
                pendingWithdrawals[m] += amt;
            }
            return;
        }

        // All defaulted — last-resort sink: circle creator
        pendingWithdrawals[circle.creator] += pot;
    }

    function getCircleCreatedAt(uint256 circleId) external view returns (uint256) {
        _requireValidCircle(circleId);
        return circleCreatedAt[circleId];
    }

    function isPendingExpired(uint256 circleId) external view returns (bool) {
        _requireValidCircle(circleId);
        Circle storage circle = circles[circleId];
        if (circle.status != CircleStatus.PENDING) return false;
        return block.timestamp >= circleCreatedAt[circleId] + PENDING_EXPIRY;
    }

    function _requireValidCircle(uint256 circleId) internal view {
        if (circleId == 0 || circleId > circleCount) revert InvalidCircle();
    }
}
