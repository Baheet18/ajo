// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Tests are split into:
//   AjoCircle.Base.t.sol     — shared abstract base (setUp, actors, helpers)
//   AjoCircle.Core.t.sol     — createCircle / join / contribute / payout / cancel / fuzz
//   AjoCircle.Holdback.t.sol — holdback mechanics, friends mode, defaulters, reputation, invariants
