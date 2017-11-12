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

  enum CyclePhase { ChangeMaking, ProposalMaking, Waiting, Ended }

  struct Proposal {
    bool isBuy;
    address tokenAddress;
    uint256 tokenPriceInWeis;
    mapping(address => bool) userSupportsProposal;
  }

  modifier isChangeMakingTime {
    require(now < startTimeOfCycle.add(timeOfChangeMaking));
    _;
  }

  modifier isProposalMakingTime {
    require(now >= startTimeOfCycle.add(timeOfChangeMaking));
    require(now < startTimeOfCycle.add(timeOfChangeMaking).add(timeOfProposalMaking));
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

  //Address of the control token
  address public controlTokenAddr;

  address public etherDeltaAddr;

  // The total amount of funds held by the group
  uint256 public totalFundsInWeis;

  //The start time for the current investment cycle, in seconds since Unix epoch
  uint256 public startTimeOfCycle;

  //Temporal length of each investment cycle, in seconds
  uint256 public timeOfCycle;

  //Temporal length of change making period at start of each cycle, in seconds
  uint256 public timeOfChangeMaking;

  //Temporal length of proposal making period at start of each cycle, in seconds
  uint256 public timeOfProposalMaking;

  //Proportion of control people who vote against a proposal have to stake
  uint256 public againstStakeProportion;

  uint256 public maxProposals;

  uint256 public commissionRate;

  bool public isFirstCycle;

  mapping(address => uint256) public balanceOf;

  mapping(uint256 => uint256) public stakedControlOfProposal;

  mapping(uint256 => mapping(address => uint256)) public stakedControlOfProposalOfUser;

  Proposal[] public proposals;
  ControlToken internal cToken;
  EtherDelta internal etherDelta;
  CyclePhase public cyclePhase;

  event CycleStarted(uint256 timestamp);
  event ChangeMakingTimeEnded(uint256 timestamp);
  event ProposalMakingTimeEnded(uint256 timestamp);
  event CycleEnded(uint256 timestamp);

  function GroupFund(
    address _etherDeltaAddr,
    uint256 _decimals,
    uint256 _timeOfCycle,
    uint256 _timeOfChangeMaking,
    uint256 _timeOfProposalMaking,
    uint256 _againstStakeProportion,
    uint256 _maxProposals,
    uint256 _commissionRate
  )
    public
  {
    require(_timeOfChangeMaking.add(_timeOfProposalMaking) <= _timeOfCycle);
    etherDeltaAddr = _etherDeltaAddr;
    decimals = _decimals;
    timeOfCycle = _timeOfCycle;
    timeOfChangeMaking = _timeOfChangeMaking;
    timeOfProposalMaking = _timeOfProposalMaking;
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
    require(cyclePhase == CyclePhase.Ended);
    require(now >= startTimeOfCycle.add(timeOfCycle));

    cyclePhase = CyclePhase.ChangeMaking;

    startTimeOfCycle = now;
    CycleStarted(now);
  }

  function createProposal(
    bool _isBuy,
    address _tokenAddress,
    uint256 _tokenPriceInWeis,
    uint256 _amountInWeis
  )
    public
    isProposalMakingTime
    onlyParticipant
  {
    require(proposals.length < maxProposals);

    proposals.push(Proposal({
      isBuy: _isBuy,
      tokenAddress: _tokenAddress,
      tokenPriceInWeis: _tokenPriceInWeis
    }));

    //Stake control tokens
    uint256 proposalId = proposals.length - 1;
    supportProposal(proposalId, _amountInWeis);
  }

  function supportProposal(uint256 _proposalId, uint256 _amountInWeis)
    public
    isProposalMakingTime
    onlyParticipant
  {
    require(_proposalId < proposals.length);

    //Stake control tokens
    uint256 controlStake = _amountInWeis.mul(cToken.balanceOf(msg.sender)).div(totalFundsInWeis);

    //Collect staked control tokens into GroupFund
    cToken.ownerCollectFrom(msg.sender, controlStake);
    //Update stake data
    stakedControlOfProposal[_proposalId] = stakedControlOfProposal[_proposalId].add(controlStake);
    stakedControlOfProposalOfUser[_proposalId][msg.sender] = stakedControlOfProposalOfUser[_proposalId][msg.sender].add(controlStake);
  }

  function deposit()
    public
    payable
    isChangeMakingTime
  {
    // Add the msg.sender if they are not yet a Participant
    if (!isParticipant[msg.sender]) {
      participants.push(msg.sender);
      isParticipant[msg.sender] = true;
    }

    //Register investment
    balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);

    // Update the total amount in GroupFund account
    totalFundsInWeis = totalFundsInWeis.add(msg.value);

    // On first Cycle:
    if (isFirstCycle) {
      //Give control tokens proportional to investment
      cToken.mint(msg.sender, msg.value);
    }
  }

  function withdraw(uint256 _amountInWeis)
    public
    isChangeMakingTime
    onlyParticipant
  {
    require(!isFirstCycle);

    totalFundsInWeis = totalFundsInWeis.sub(_amountInWeis);
    balanceOf[msg.sender] = balanceOf[msg.sender].sub(_amountInWeis);

    msg.sender.transfer(_amountInWeis);
  }

  function endChangeMakingTime() public {
    require(cyclePhase == CyclePhase.ChangeMaking);
    require(now >= startTimeOfCycle.add(timeOfChangeMaking));

    cyclePhase = CyclePhase.ProposalMaking;

    ChangeMakingTimeEnded(now);
  }

  function endProposalMakingTime() public {
    require(cyclePhase == CyclePhase.ProposalMaking);
    require(now >= startTimeOfCycle.add(timeOfChangeMaking).add(timeOfProposalMaking));

    cyclePhase = CyclePhase.Waiting;

    //Stake against votes
    for (uint256 i = 0; i < participants.length; i = i.add(1)) {
      for (uint256 j = 0; j < proposals.length; j = j.add(1)) {
        address participant = participants[i];
        bool isFor = proposals[j].userSupportsProposal[participant];
        if (!isFor) {
          //Unfair to later proposals
          uint256 stakeAmount = cToken.balanceOf(participant).mul(againstStakeProportion).div(10**decimals);
          cToken.ownerCollectFrom(participant, stakeAmount);
        }
      }
    }

    //Invest in tokens using etherdelta
    for (i = 0; i < proposals.length; i = i.add(1)) {
      uint256 investAmount = totalFundsInWeis.mul(stakedControlOfProposal[i]).div(cToken.totalSupply());
      assert(etherDelta.call.value(investAmount)(bytes4(keccak256("deposit()")))); //Deposit ether

    }

    ProposalMakingTimeEnded(now);
  }

  function endCycle() public {
    require(cyclePhase == CyclePhase.Waiting);
    require(now >= startTimeOfCycle.add(timeOfCycle));

    if (isFirstCycle) {
      cToken.finishMinting();
    }
    cyclePhase = CyclePhase.Ended;
    isFirstCycle = false;

    //Sell all invested tokens

    //Distribute staked control tokens

    //Distribute funds
    uint256 totalCommission = commissionRate.mul(this.balance).div(10**decimals);

    for (uint256 i = 0; i < participants.length; i = i.add(1)) {
      address participant = participants[i];
      uint256 newBalance = this.balance.sub(totalCommission).mul(balanceOf[participant]).div(totalFundsInWeis);
      //Add commission
      newBalance = newBalance.add(totalCommission.mul(cToken.balanceOf(participant)).div(cToken.totalSupply()));
      balanceOf[participant] = newBalance;
    }

    //Reset data
    totalFundsInWeis = this.balance;
    delete proposals;

    CycleEnded(now);
  }

  function addControlTokenReceipientAsParticipant(address _receipient) public {
    require(msg.sender == controlTokenAddr);
    isParticipant[_receipient] = true;
    participants.push(_receipient);
  }

  function() public {
    revert();
  }
}

//Proportional to Wei
contract ControlToken is MintableToken {
  using SafeMath for uint256;

  event OwnerCollectFrom(address _from, uint256 _value);

  function transfer(address _to, uint256 _value) public returns(bool) {
    require(_to != address(0));
    require(_value <= balances[msg.sender]);

    //Add receipient as a participant if not already a participant
    GroupFund g = GroupFund(owner);
    if (!g.isParticipant(_to)) {
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
    GroupFund g = GroupFund(owner);
    if (!g.isParticipant(_to)) {
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
