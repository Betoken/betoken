pragma solidity ^0.4.18;

// The main contract that keeps track of:
// - Who is in the fund
// - How much the fund has
// - Each person's Share
// - Each person's Control
contract GroupFund {
  // A list of everyone who is participating in the GroupFund
  address[] participants;

  // The proportion a person owns of the totalFunds
  mapping(address => uint) shares;

  // The total amount of funds held by the group
  uint totalFunds;
}
