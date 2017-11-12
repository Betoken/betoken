pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/token/MintableToken.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import './etherdelta.sol';

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
  uint256 public decimals;

  // A list of everyone who is participating in the GroupFund
  address[] public participants;
  mapping(address => bool) public isParticipant;

  // Maps user address to their initial deposit
  mapping(address => uint256) public initialDeposit;
  uint256 public totalInitialDeposit;

  //Address of the control token
  address public controlTokenAddr;

  address public etherDeltaAddr;

  // The total amount of funds held by the group
  uint256 public totalFundsInWeis;

  uint256 public totalFundsAtStartOfCycleInWeis;

  //The start time for the current investment cycle, in seconds since Unix epoch
  uint256 public startTimeOfCycle;

  //Temporal length of each investment cycle, in seconds
  uint256 public timeOfCycle;

  //Temporal length of change making period at start of each cycle, in seconds
  uint256 public timeOfChangeMaking;

  //Proportion of control people who vote against a proposal have to stake
  uint256 public againstStakeProportion;

  uint256 public maxProposals;

  uint256 public commissionRate;

  //Indicates whether the cycle has started and is not past ending time
  bool public cycleIsActive;

  bool public changeMakingTimeHasEnded;

  bool public isFirstCycle;

  mapping(address => uint256) public balanceOfAtCycleStart;

  mapping(uint256 => uint256) public stakedControlOfProposal;

  mapping(uint256 => mapping(address => uint256)) public stakedControlOfProposalOfUser;

  Proposal[] public proposals;
  ControlToken internal cToken;
  EtherDelta internal etherDelta;

  event CycleStarted(uint256 timestamp);
  event ChangeMakingTimeEnded(uint256 timestamp);
  event CycleEnded(uint256 timestamp);

  function GroupFund(
    address _etherDeltaAddr,
    uint256 _decimals,
    uint256 _timeOfCycle,
    uint256 _timeOfChangeMaking,
    uint256 _againstStakeProportion,
    uint256 _maxProposals,
    uint256 _commissionRate
  )
    public
  {
    etherDeltaAddr = _etherDeltaAddr;
    decimals = _decimals;
    timeOfCycle = _timeOfCycle;
    timeOfChangeMaking = _timeOfChangeMaking;
    againstStakeProportion = _againstStakeProportion;
    maxProposals = _maxProposals;
    commissionRate = _commissionRate;
    startTimeOfCycle = 0;
    isFirstCycle = true;

    //Create control token contract
    cToken = new ControlToken();
    controlTokenAddr = cToken;

    //Initialize etherDelta contract
    etherDelta = EtherDelta(etherDeltaAddr);
  }

  function startNewCycle() public {
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
    public
    isChangeMakingTime
    onlyParticipant
  {
    require(proposals.length < maxProposals);
    require((isFirstCycle && _amount <= initialDeposit[msg.sender])
      || (!isFirstCycle && _amount <= cToken.balanceOf(msg.sender).div(cToken.totalSupply()).mul(totalFundsAtStartOfCycleInWeis)));
    require(_amount <= totalFundsInWeis);

    proposals.push(Proposal({
      isBuy: _isBuy,
      tokenAddress: _tokenAddress,
      amount: _amount
    }));

    //Make investment on etherdelta
  }

  function supportProposal(uint256 proposalId, uint256 controlStake)
    public
    isChangeMakingTime
    onlyParticipant
  {
    require(proposalId < proposals.length);
    require(controlStake <= cToken.balanceOf(msg.sender));

    //Stake control tokens
    stakedControlOfProposal[proposalId] = stakedControlOfProposal[proposalId].add(controlStake);
    stakedControlOfProposalOfUser[proposalId][msg.sender] = stakedControlOfProposalOfUser[proposalId][msg.sender].add(controlStake);
    cToken.ownerCollectFrom(msg.sender, controlStake);

    //Make investment on etherdelta
  }

  function deposit()
    public
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
    balanceOfAtCycleStart[msg.sender] = balanceOfAtCycleStart[msg.sender].add(msg.value);

    if (isFirstCycle) {
      //Give control tokens proportional to investment
      cToken.mint(msg.sender, msg.value);
    }
  }

  function withdraw(uint256 amountInWeis)
    public
    isChangeMakingTime
    onlyParticipant
  {
    require(!isFirstCycle);

    uint256 reduceAmount = amountToReduceInitialDepositBy(msg.sender, amountInWeis);
    initialDeposit[msg.sender] = initialDeposit[msg.sender].sub(reduceAmount);
    totalInitialDeposit = totalInitialDeposit.sub(reduceAmount);
    totalFundsInWeis = totalFundsInWeis.sub(amountInWeis);
    //Todo: check if everything checks out mathematically

    msg.sender.transfer(amountInWeis);
  }

  function endChangeMakingTime() public {
    require(!changeMakingTimeHasEnded);
    require(now >= startTimeOfCycle.add(timeOfChangeMaking));
    require(now < startTimeOfCycle.add(timeOfCycle));

    changeMakingTimeHasEnded = true;

    //Stake against votes
    for (uint256 i = 0; i < participants.length; i = i.add(1)) {
      for (uint256 j = 0; j < proposals.length; j = j.add(1)) {
        address participant = participants[i];
        bool isFor = proposals[j].userSupportsProposal[participant];
        if (!isFor && cToken.balanceOf(participant) > 0) {
          //Unfair to later proposals
          uint256 stakeAmount = cToken.balanceOf(participant).mul(againstStakeProportion).div(decimals);
          cToken.ownerCollectFrom(participant, stakeAmount);
        }
      }
    }

    ChangeMakingTimeEnded(now);
  }

  function endCycle() public {
    require(cycleIsActive);
    require(now >= startTimeOfCycle.add(timeOfCycle));

    if (isFirstCycle) {
      cToken.finishMinting();
    }
    cycleIsActive = false;
    isFirstCycle = false;

    //Sell all invested tokens

    totalFundsInWeis = this.balance;
    totalFundsAtStartOfCycleInWeis = this.balance;

    //Distribute staked control tokens

    //Distribute funds
    uint256 totalCommission = commissionRate.mul(totalFundsInWeis).div(10**decimals);

    for (uint256 i = 0; i < participants.length; i = i.add(1)) {
      address participant = participants[i];
      uint256 newBalance = totalFundsInWeis.sub(totalCommission).mul(initialDeposit[participant]).div(totalInitialDeposit);
      //Add commission
      newBalance = newBalance.add(totalCommission.mul(cToken.balanceOf(participant)).div(cToken.totalSupply()));
      balanceOfAtCycleStart[participant] = newBalance;
    }

    //Reset data
    delete proposals;

    CycleEnded(now);
  }

  function addControlTokenReceipientAsParticipant(address receipient) public {
    require(msg.sender == controlTokenAddr);
    if (!isParticipant[receipient]) {
      isParticipant[receipient] = true;
      participants.push(receipient);
    }
  }

  function amountToReduceInitialDepositBy(address user, uint256 amount) public view returns(uint) {
    return amount.mul(initialDeposit[user]).div(balanceOfAtCycleStart[user]);
  }

  function() public {
    revert();
  }
}

//Proportional to Wei
contract ControlToken is MintableToken {
  using SafeMath for uint256;

  mapping(address => bool) hasOwnedTokens;

  event OwnerCollectFrom(address _from, uint256 value);

  function transfer(address _to, uint256 _value) public returns(bool) {
    require(_to != address(0));
    require(_value <= balances[msg.sender]);

    //Add receipient as a participant if not already a participant
    if (!hasOwnedTokens[_to]) {
      hasOwnedTokens[_to] = true;
      GroupFund g = GroupFund(owner);
      g.addControlTokenReceipientAsParticipant(_to);
    }

    // SafeMath.sub will throw if there is not enough balance.
    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
    Transfer(msg.sender, _to, _value);
    return true;
  }

  function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
    require(_to != address(0));
    require(_value <= balances[_from]);
    require(_value <= allowed[_from][msg.sender]);

    //Add receipient as a participant if not already a participant
    if (!hasOwnedTokens[_to]) {
      hasOwnedTokens[_to] = true;
      GroupFund g = GroupFund(owner);
      g.addControlTokenReceipientAsParticipant(_to);
    }

    balances[_from] = balances[_from].sub(_value);
    balances[_to] = balances[_to].add(_value);
    allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
    Transfer(_from, _to, _value);
    return true;
  }

  function ownerCollectFrom(address _from, uint256 _value) public onlyOwner returns(bool) {
    require(_from != address(0));
    require(_value <= balances[_from]);

    // SafeMath.sub will throw if there is not enough balance.
    balances[_from] = balances[_from].sub(_value);
    balances[msg.sender] = balances[msg.sender].add(_value);
    OwnerCollectFrom(_from, _value);
    return true;
  }
}
