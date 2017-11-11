pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/token/Mintable.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';

// The main contract that keeps track of:
// - Who is in the fund
// - How much the fund has
// - Each person's Share
// - Each person's Control
contract GroupFund {
  using SafeMath for uint256;

  struct Proposal {
    bool isBuy;
    address tokenAddress;
    uint256 amount;
    //Proportion of control people who vote against a proposal have to stake
    uint256 againstStakeProp;
    mapping(address => bool) userSupportsProposal;
  }

  modifier isChangeMakingTime {
    require(now < startTimeOfCycle.add(timeOfChangeMaking));
    _;
  }

  modifier onlyParticipant {
    require(isParticipant[msg.sender]);
    _;
  }

  //Number of decimals used for decimal numbers
  uint256 decimals;

  // A list of everyone who is participating in the GroupFund
  address[] participants;
  mapping(address => bool) isParticipant;

  // Maps user address to their initial deposit
  mapping(address => uint256) initialDeposit;
  uint256 totalInitialDeposit;

  //Address of the control token
  address controlTokenAddr;

  // The total amount of funds held by the group
  uint256 totalFundsInWeis;

  //The start time for the current investment cycle, in seconds since Unix epoch
  uint256 startTimeOfCycle;

  //Temporal length of each investment cycle, in seconds
  uint256 timeOfCycle;

  //Temporal length of change making period at start of each cycle, in seconds
  uint256 timeOfChangeMaking;

  //Indicates whether the cycle has started and is not past ending time
  bool cycleIsActive;

  bool changeMakingTimeHasEnded;

  mapping(address => uint256) balanceOf;

  mapping(uint256 => uint256) stakedControlOfProposal;

  mapping(uint256 => mapping(address => uint256)) stakedControlOfUserOfProposal;

  Proposal[] proposals;
  ControlToken cToken;

  event CycleStarted(uint256 timestamp);
  event ChangeMakingTimeEnded(uint256 timestamp);
  event CycleEnded(uint256 timestamp);

  function GroupFund(
    uint256 _decimals,
    uint256 _timeOfCycle,
    uint256 _timeOfChangeMaking
  )
  {
    decimals = _decimals;
    startTimeOfCycle = 0;
    timeOfCycle = _timeOfCycle;
    timeOfChangeMaking = _timeOfChangeMaking;

    //Create control token contract
    cToken = new ControlToken();
    controlTokenAddr = cToken;
  }

  function startNewCycle() {
    require(!cycleIsActive);
    require(now >= startTimeOfCycle.add(timeOfCycle));

    cycleIsActive = true;
    changeMakingTimeHasEnded = false;

    startTimeOfCycle = now;
    CycleStarted(now);
  }

  function createProposal(
    bool _isBuy,
    address _tokenAddress,
    uint256 _amount
  )
    isChangeMakingTime
    onlyParticipant
  {
    //require(amount <= controlOf(msg.sender));
    proposals.push({
      isBuy: _isBuy,
      tokenAddress: _tokenAddress,
      amount: _amount,
      againstStakeProp: calculateAgainstStakeProp()
    });
  }

  function supportProposal(uint256 proposalId, uint256 controlStake)
    isChangeMakingTime
    onlyParticipant
  {
    require(controlStake <= cToken.balanceOf(msg.sender));

    //Stake control tokens
    stakedControlOfProposal[proposalId] = stakedControlOfProposal[proposalId].add(controlStake);
    stakedControlOfUserOfProposal[proposalId][msg.sender] = stakedControlOfUserOfProposal[proposalId][msg.sender].add(controlStake);
    cToken.ownerCollectFrom(msg.sender, controlStake);

    //Make investment
  }

  function deposit()
    payable
    isChangeMakingTime
  {
    if (!isParticipant[msg.sender]) {
      participants.push(msg.sender);
      isParticipant[msg.sender] = true;
    }

    //Register investment
    initialDeposit[msg.sender] = initialDeposit[msg.sender].add(msg.value);
    totalInitialDeposit = totalInitialDeposit.add(msg.value);
    balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);

    //Give control tokens proportional to investment
    cToken.mint(msg.sender, msg.value);
  }

  function withdraw(uint256 amountInWeis)
    isChangeMakingTime
    onlyParticipant
  {
    require(msg.sender.balance + amount >= msg.sender.balance);

    balanceOf[msg.sender] = balanceOf[msg.sender].sub(amountInWeis);

    msg.sender.transfer(amount);
  }

  function endChangeMakingTime() {
    require(!changeMakingTimeHasEnded);
    require(now >= startTimeOfCycle.add(timeOfChangeMaking));
    require(now < startTimeOfCycle.add(timeOfCycle));

    changeMakingTimeHasEnded = true;

    //Do stuff

    ChangeMakingTimeEnded(now);
  }

  function endCycle() {
    require(cycleIsActive);
    require(now >= startTimeOfCycle.add(timeOfCycle));

    cycleIsActive = false;

    //Distribute staked control tokens

    //Sell all invested tokens

  }

  function calculateAgainstStakeProp(uint256 proposalId)
    view
    returns(uint256 againstStakeProp)
  {
    uint256 numFor = 0;
    uint256 numAgainst = 0;
    uint256 forStakedControl = 0;
    uint256 againstTotalControl = 0;

    //Calculate numFor, numAgainst, againstTotalControl, forStakedControl
    for (uint256 i = 0; i < participants.length; i = i.add(1)) {
      address participant = participants[i];
      bool isFor = proposals[proposalId].userSupportsProposal[participant];
      if (isFor) {
        numFor = numFor.add(1);
      } else {
        againstTotalControl = againstTotalControl.add(cToken.balanceOf(participant));
      }
    }
    forStakedControl = stakedControlOfProposal[proposalId];
    numAgainst = participants.length.sub(numFor);

    return numFor.mul(forStakedControl).mul(10**decimals).div(numAgainst.mul(againstTotalControl));
  }

  function() {
    revert();
  }
}

//Proportional to Wei
contract ControlToken is MintableToken {
  using SafeMath for uint256;

  function ownerCollectFrom(address _from, uint256 _value) public onlyOwner {
    require(_from != address(0));
    require(_value <= balances[_from]);

    // SafeMath.sub will throw if there is not enough balance.
    balances[_from] = balances[_from].sub(_value);
    balances[msg.sender] = balances[msg.sender].add(_value);
  }
}
