/**
 * AjoCircle contract config.
 * Address is populated after deployment; update AGENTS.md and this file together.
 */

export const AJO_ADDRESS = (import.meta.env.VITE_AJO_ADDRESS ?? '0x0000000000000000000000000000000000000000') as `0x${string}`;

export const AJO_CHAIN_ID = 5042; // Arc Mainnet

export const AJO_DEPLOYED = AJO_ADDRESS !== '0x0000000000000000000000000000000000000000';

export const AJO_ABI = [
  // createCircle (v6: adds holdbackBps)
  {
    "inputs": [
      { "internalType": "string", "name": "name", "type": "string" },
      { "internalType": "uint256", "name": "contributionAmount", "type": "uint256" },
      { "internalType": "uint8", "name": "memberCount", "type": "uint8" },
      { "internalType": "uint256", "name": "roundDuration", "type": "uint256" },
      { "internalType": "uint256", "name": "collateralAmount", "type": "uint256" },
      { "internalType": "uint16", "name": "holdbackBps", "type": "uint16" }
    ],
    "name": "createCircle",
    "outputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "stateMutability": "payable",
    "type": "function"
  },
  // join
  {
    "inputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "name": "join",
    "outputs": [],
    "stateMutability": "payable",
    "type": "function"
  },
  // contribute
  {
    "inputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "name": "contribute",
    "outputs": [],
    "stateMutability": "payable",
    "type": "function"
  },
  // payout
  {
    "inputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "name": "payout",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  // withdraw
  {
    "inputs": [],
    "name": "withdraw",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  // cancelCircle
  {
    "inputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "name": "cancelCircle",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  // leave
  {
    "inputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "name": "leave",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  // setPayoutOrder
  {
    "inputs": [
      { "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "internalType": "address[]", "name": "order", "type": "address[]" }
    ],
    "name": "setPayoutOrder",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  // getCircleCreatedAt
  {
    "inputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "name": "getCircleCreatedAt",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  // isPendingExpired
  {
    "inputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "name": "isPendingExpired",
    "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }],
    "stateMutability": "view",
    "type": "function"
  },
  // circleCount
  {
    "inputs": [],
    "name": "circleCount",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  // getCircle (struct now includes holdbackBps)
  {
    "inputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "name": "getCircle",
    "outputs": [
      {
        "components": [
          { "internalType": "string", "name": "name", "type": "string" },
          { "internalType": "address", "name": "creator", "type": "address" },
          { "internalType": "uint256", "name": "contributionAmount", "type": "uint256" },
          { "internalType": "uint8", "name": "memberCount", "type": "uint8" },
          { "internalType": "uint256", "name": "roundDuration", "type": "uint256" },
          { "internalType": "uint256", "name": "collateralAmount", "type": "uint256" },
          { "internalType": "uint16", "name": "holdbackBps", "type": "uint16" },
          { "internalType": "uint8", "name": "status", "type": "uint8" },
          { "internalType": "uint8", "name": "currentRound", "type": "uint8" },
          { "internalType": "uint256", "name": "roundDeadline", "type": "uint256" },
          { "internalType": "address[]", "name": "members", "type": "address[]" },
          { "internalType": "address[]", "name": "payoutRecipients", "type": "address[]" },
          { "internalType": "bool[]", "name": "defaulted", "type": "bool[]" }
        ],
        "internalType": "struct AjoCircle.Circle",
        "name": "",
        "type": "tuple"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  // getMembers
  {
    "inputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "name": "getMembers",
    "outputs": [{ "internalType": "address[]", "name": "", "type": "address[]" }],
    "stateMutability": "view",
    "type": "function"
  },
  // getPayoutRecipients
  {
    "inputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "name": "getPayoutRecipients",
    "outputs": [{ "internalType": "address[]", "name": "", "type": "address[]" }],
    "stateMutability": "view",
    "type": "function"
  },
  // getCurrentRound
  {
    "inputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "name": "getCurrentRound",
    "outputs": [{ "internalType": "uint8", "name": "", "type": "uint8" }],
    "stateMutability": "view",
    "type": "function"
  },
  // getNextRecipient
  {
    "inputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "name": "getNextRecipient",
    "outputs": [{ "internalType": "address", "name": "", "type": "address" }],
    "stateMutability": "view",
    "type": "function"
  },
  // getRoundPaidStatus
  {
    "inputs": [
      { "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "internalType": "uint8", "name": "round", "type": "uint8" }
    ],
    "name": "getRoundPaidStatus",
    "outputs": [{ "internalType": "bool[]", "name": "paidStatus", "type": "bool[]" }],
    "stateMutability": "view",
    "type": "function"
  },
  // hasMemberPaid
  {
    "inputs": [
      { "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "internalType": "address", "name": "member", "type": "address" }
    ],
    "name": "hasMemberPaid",
    "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }],
    "stateMutability": "view",
    "type": "function"
  },
  // getMemberDefaulted
  {
    "inputs": [
      { "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "internalType": "address", "name": "member", "type": "address" }
    ],
    "name": "getMemberDefaulted",
    "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }],
    "stateMutability": "view",
    "type": "function"
  },
  // getRoundDeadline
  {
    "inputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "name": "getRoundDeadline",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  // getPotSize
  {
    "inputs": [{ "internalType": "uint256", "name": "circleId", "type": "uint256" }],
    "name": "getPotSize",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  // getMemberDeposit
  {
    "inputs": [
      { "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "internalType": "address", "name": "member", "type": "address" }
    ],
    "name": "getMemberDeposit",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  // getMemberHoldback (replaces getMemberBond)
  {
    "inputs": [
      { "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "internalType": "address", "name": "member", "type": "address" }
    ],
    "name": "getMemberHoldback",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  // getMemberReputation
  {
    "inputs": [{ "internalType": "address", "name": "member", "type": "address" }],
    "name": "getMemberReputation",
    "outputs": [
      { "internalType": "uint256", "name": "paid", "type": "uint256" },
      { "internalType": "uint256", "name": "missed", "type": "uint256" },
      { "internalType": "uint256", "name": "completed", "type": "uint256" }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  // pendingWithdrawals
  {
    "inputs": [{ "internalType": "address", "name": "", "type": "address" }],
    "name": "pendingWithdrawals",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  // isMember
  {
    "inputs": [
      { "internalType": "uint256", "name": "", "type": "uint256" },
      { "internalType": "address", "name": "", "type": "address" }
    ],
    "name": "isMember",
    "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }],
    "stateMutability": "view",
    "type": "function"
  },
  // Events
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "indexed": true, "internalType": "address", "name": "creator", "type": "address" },
      { "indexed": false, "internalType": "string", "name": "name", "type": "string" },
      { "indexed": false, "internalType": "uint256", "name": "contributionAmount", "type": "uint256" },
      { "indexed": false, "internalType": "uint8", "name": "memberCount", "type": "uint8" },
      { "indexed": false, "internalType": "uint256", "name": "roundDuration", "type": "uint256" },
      { "indexed": false, "internalType": "uint256", "name": "collateralAmount", "type": "uint256" },
      { "indexed": false, "internalType": "uint16", "name": "holdbackBps", "type": "uint16" }
    ],
    "name": "CircleCreated",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "indexed": true, "internalType": "address", "name": "member", "type": "address" },
      { "indexed": false, "internalType": "uint8", "name": "position", "type": "uint8" }
    ],
    "name": "MemberJoined",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "indexed": false, "internalType": "uint256", "name": "roundDeadline", "type": "uint256" }
    ],
    "name": "CircleStarted",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "indexed": true, "internalType": "uint8", "name": "round", "type": "uint8" },
      { "indexed": true, "internalType": "address", "name": "member", "type": "address" },
      { "indexed": false, "internalType": "uint256", "name": "amount", "type": "uint256" }
    ],
    "name": "ContributionMade",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "indexed": true, "internalType": "uint8", "name": "round", "type": "uint8" },
      { "indexed": true, "internalType": "address", "name": "recipient", "type": "address" },
      { "indexed": false, "internalType": "uint256", "name": "amount", "type": "uint256" }
    ],
    "name": "RoundPayout",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "indexed": true, "internalType": "address", "name": "member", "type": "address" },
      { "indexed": false, "internalType": "uint8", "name": "round", "type": "uint8" }
    ],
    "name": "MemberDefaulted",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "indexed": true, "internalType": "address", "name": "member", "type": "address" },
      { "indexed": false, "internalType": "uint256", "name": "amount", "type": "uint256" }
    ],
    "name": "CollateralSlashed",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "indexed": true, "internalType": "address", "name": "member", "type": "address" },
      { "indexed": false, "internalType": "uint256", "name": "amount", "type": "uint256" }
    ],
    "name": "CollateralRefunded",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "indexed": true, "internalType": "address", "name": "member", "type": "address" },
      { "indexed": false, "internalType": "uint256", "name": "amount", "type": "uint256" }
    ],
    "name": "HoldbackLocked",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "indexed": true, "internalType": "address", "name": "member", "type": "address" },
      { "indexed": false, "internalType": "uint256", "name": "amount", "type": "uint256" }
    ],
    "name": "HoldbackReleased",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "indexed": true, "internalType": "address", "name": "member", "type": "address" },
      { "indexed": false, "internalType": "uint256", "name": "amount", "type": "uint256" },
      { "indexed": false, "internalType": "address", "name": "recipient", "type": "address" }
    ],
    "name": "HoldbackSlashed",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" }
    ],
    "name": "CircleEnded",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "address", "name": "recipient", "type": "address" },
      { "indexed": false, "internalType": "uint256", "name": "amount", "type": "uint256" }
    ],
    "name": "Withdrawn",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" }
    ],
    "name": "CircleCancelled",
    "type": "event"
  },
  // Custom errors
  { "inputs": [], "name": "InvalidCircle",              "type": "error" },
  { "inputs": [], "name": "InvalidContributionAmount",  "type": "error" },
  { "inputs": [], "name": "InvalidMemberCount",         "type": "error" },
  { "inputs": [], "name": "InvalidRoundDuration",       "type": "error" },
  { "inputs": [], "name": "InvalidHoldbackBps",         "type": "error" },
  { "inputs": [], "name": "CircleNotPending",           "type": "error" },
  { "inputs": [], "name": "CircleNotActive",            "type": "error" },
  { "inputs": [], "name": "CircleEndedAlready",         "type": "error" },
  { "inputs": [], "name": "AlreadyMember",              "type": "error" },
  { "inputs": [], "name": "CircleFull",                 "type": "error" },
  { "inputs": [], "name": "NotMember",                  "type": "error" },
  { "inputs": [], "name": "NotCreator",                 "type": "error" },
  { "inputs": [], "name": "AlreadyContributed",         "type": "error" },
  { "inputs": [], "name": "RoundDeadlinePassed",        "type": "error" },
  { "inputs": [], "name": "MemberDefaultedAlready",     "type": "error" },
  { "inputs": [], "name": "ContributionsStillPending",  "type": "error" },
  { "inputs": [], "name": "NothingToWithdraw",          "type": "error" },
  { "inputs": [], "name": "IncorrectPayment",           "type": "error" },
  { "inputs": [], "name": "NotAMember",                 "type": "error" },
  { "inputs": [], "name": "IsCreator",                  "type": "error" },
  { "inputs": [], "name": "CircleExpired",              "type": "error" },
  { "inputs": [], "name": "InvalidOrder",               "type": "error" },
  // MemberLeft event
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "indexed": true, "internalType": "address", "name": "member", "type": "address" }
    ],
    "name": "MemberLeft",
    "type": "event"
  },
  // PayoutOrderSet event
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "circleId", "type": "uint256" },
      { "indexed": false, "internalType": "address[]", "name": "order", "type": "address[]" }
    ],
    "name": "PayoutOrderSet",
    "type": "event"
  }
] as const;

export const USDC_ADDRESS = '0x3600000000000000000000000000000000000000' as const;
export const USDC_ABI = [
  {
    "inputs": [
      { "internalType": "address", "name": "owner", "type": "address" },
      { "internalType": "address", "name": "spender", "type": "address" }
    ],
    "name": "allowance",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      { "internalType": "address", "name": "spender", "type": "address" },
      { "internalType": "uint256", "name": "amount", "type": "uint256" }
    ],
    "name": "approve",
    "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{ "internalType": "address", "name": "account", "type": "address" }],
    "name": "balanceOf",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  }
] as const;
