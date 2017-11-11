pragma solidity ^0.4.18;

// The main contract that keeps track of:
// - Who is in the fund
// - How much the fund has
// - Each person's Share
// - Each person's Control
contract GroupFund {
  struct Proposal {
    bool isBuy;
    address tokenAddress;
    uint amount;
  }

  uint decimals;

  // A list of everyone who is participating in the GroupFund
  address[] participants;

  // The proportion a person owns of the totalFunds
  mapping(address => uint) shares;

  //Address of the control token
  address controlTokenAddr;

  // The total amount of funds held by the group
  uint totalFundsInWeis;

  Proposal[] proposals;

  //Proportion of control people who vote against a proposal have to stake
  uint againstStakeProp;

  //Temporal length of each investment cycle
  uint timeOfCycle;

  function GroupFund(uint _decimals, uint _timeOfCycle) {
    decimals = _decimals;
  }

  function() {
    revert();
  }
}
