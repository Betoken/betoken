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
  uint256 public decimals;

  // A list of everyone who is participating in the GroupFund
  address[] public participants;
  mapping(address => bool) public isParticipant;

  // Maps user address to their initial deposit
  mapping(address => uint256) public initialDeposit;
  uint256 public totalInitialDeposit;

  //Address of the control token
  address public controlTokenAddr;

  // The total amount of funds held by the group
  uint256 public totalFundsInWeis;

  uint256 public totalFundsAtStartOfCycleInWeis;

  //The start time for the current investment cycle, in seconds since Unix epoch
  uint256 public startTimeOfCycle;

  //Temporal length of each investment cycle, in seconds
  uint256 public timeOfCycle;

  //Temporal length of change making period at start of each cycle, in seconds
  uint256 public timeOfChangeMaking;

  //Indicates whether the cycle has started and is not past ending time
  bool public cycleIsActive;

  bool public changeMakingTimeHasEnded;

  bool public isFirstCycle;

  mapping(address => uint256) public balanceOf;

  mapping(uint256 => uint256) public stakedControlOfProposal;

  mapping(uint256 => mapping(address => uint256)) public stakedControlOfProposalOfUser;

  Proposal[] public proposals;
  ControlToken public cToken;

  event CycleStarted(uint256 timestamp);
  event ChangeMakingTimeEnded(uint256 timestamp);
  event CycleEnded(uint256 timestamp);

  function GroupFund(
    uint256 _decimals,
    uint256 _timeOfCycle,
    uint256 _timeOfChangeMaking
  )
    public
  {
    decimals = _decimals;
    startTimeOfCycle = 0;
    timeOfCycle = _timeOfCycle;
    timeOfChangeMaking = _timeOfChangeMaking;
    isFirstCycle = true;

    //Create control token contract
    cToken = new ControlToken();
    controlTokenAddr = cToken;
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
    //require(_amount <= cToken.balanceOf(msg.sender));
    proposals.push({
      isBuy: _isBuy,
      tokenAddress: _tokenAddress,
      amount: _amount,
      againstStakeProp: calculateAgainstStakeProp()
    });
  }

  function supportProposal(uint256 proposalId, uint256 controlStake)
    public
    isChangeMakingTime
    onlyParticipant
  {
    require(controlStake <= cToken.balanceOf(msg.sender));

    //Stake control tokens
    stakedControlOfProposal[proposalId] = stakedControlOfProposal[proposalId].add(controlStake);
    stakedControlOfProposalOfUser[proposalId][msg.sender] = stakedControlOfProposalOfUser[proposalId][msg.sender].add(controlStake);
    cToken.ownerCollectFrom(msg.sender, controlStake);

    //Make investment
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
    balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);

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
    require(msg.sender.balance + amount >= msg.sender.balance);

    balanceOf[msg.sender] = balanceOf[msg.sender].sub(amountInWeis);

    msg.sender.transfer(amount);
  }

  function endChangeMakingTime() {
    require(!changeMakingTimeHasEnded);
    require(now >= startTimeOfCycle.add(timeOfChangeMaking));
    require(now < startTimeOfCycle.add(timeOfCycle));

    changeMakingTimeHasEnded = true;

    //Stake against votes

    ChangeMakingTimeEnded(now);
  }

  function endCycle() public {
    require(cycleIsActive);
    require(now >= startTimeOfCycle.add(timeOfCycle));

    cycleIsActive = false;
    isFirstCycle = false;

    //Distribute staked control tokens

    //Sell all invested tokens

    //totalFundsInWeis = this.balance;
    //totalFundsAtStartOfCycleInWeis = this.balance;

    //Distribute ether balance

    //Distribute commission
  }

  function addControlTokenReceipientAsParticipant(address receipient) public {
    require(msg.sender == controlTokenAddr);
    if (!isParticipant[receipient]) {
      isParticipant[receipient] = true;
      participants.push(receipient);
    }
  }

  function calculateAgainstStakeProp(uint256 proposalId)
    public
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
        if (cToken.balanceOf(participant) != 0) {
          numAgainst = numAgainst.add(1);
          againstTotalControl = againstTotalControl.add(cToken.balanceOf(participant));
        }
      }
    }
    forStakedControl = stakedControlOfProposal[proposalId];

    return numFor.mul(forStakedControl).mul(10**decimals).div(numAgainst.mul(againstTotalControl));
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
