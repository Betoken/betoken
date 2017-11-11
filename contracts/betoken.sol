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
    //Proportion of control people who vote against a proposal have to stake
    uint againstStakeProp;
    mapping(address => bool) userSupportsProposal;
  }

  modifier isChangeMakingTime {
    require(block.timestamp < startTimeOfCycle + timeOfChangeMaking);
    _;
  }

  //Number of decimals used for decimal numbers
  uint decimals;

  // A list of everyone who is participating in the GroupFund
  address[] participants;

  // Maps user address to their initial deposit
  mapping(address => uint) initialDeposit;
  uint totalInitialDeposit;

  //Address of the control token
  address controlTokenAddr;

  // The total amount of funds held by the group
  uint totalFundsInWeis;

  Proposal[] proposals;

  //The start time for the current investment cycle, in seconds since Unix epoch
  uint startTimeOfCycle;

  //Temporal length of each investment cycle, in seconds
  uint timeOfCycle;

  //Temporal length of change making period at start of each cycle, in seconds
  uint timeOfChangeMaking;

  function GroupFund(
    address _controlTokenAddr,
    uint _decimals,
    uint _timeOfCycle,
    uint _timeOfChangeMaking
  )
  {
    controlTokenAddr = _controlTokenAddr;
    decimals = _decimals;
    startTimeOfCycle = 0;
    timeOfCycle = _timeOfCycle;
    timeOfChangeMaking = _timeOfChangeMaking;
  }

  function startNewCycle() {

  }

  function createProposal()
    isChangeMakingTime
  {

  }

  function supportProposal()
    isChangeMakingTime
  {

  }

  function deposit()
    isChangeMakingTime
  {

  }

  function withdraw()
    isChangeMakingTime
  {

  }

  function endChangeMakingTime() {
    require(block.timestamp >= startTimeOfCycle + timeOfChangeMaking);
    require(block.timestamp < startTimeOfCycle + timeOfCycle);

  }

  function calculateAgainstStakeProp(uint proposalId) view {
    uint numFor = 0;
    uint numAgainst = 0;
    for (uint i = 0; i < participants.length; i++) {
      bool isFor = proposals[proposalId].userSupportsProposal[participants[i]];
      if (isFor) {
        numFor++;
      }
    }
    numAgainst = participants.length - numFor;
    //Todo: use control tokens to calculate againstStakeProp
  }

  function() {
    revert();
  }
}
