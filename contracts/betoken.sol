pragma solidity ^0.4.18;

// Importing stuff
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

  // The 4 different phases the GroupFund could be in
  enum CyclePhase { ChangeMaking, ProposalMaking, Waiting, Ended }

  // The Proposal structure
  struct Proposal {
    bool isBuy;
    address tokenAddress;
    uint256 tokenPriceInWeis;

    // Maps participant addresses to whether or not they support the proposal
    mapping(address => bool) userSupportsProposal;
  }

  // Requires time elapsed to be greater than timeOfChangeMaking
  modifier isChangeMakingTime {
    require(now < startTimeOfCycle.add(timeOfChangeMaking));
    _;
  }

  // Requires time elapsed to be between timeOfChangeMaking and the end of
  // timeOfProposalMaking
  modifier isProposalMakingTime {
    require(now >= startTimeOfCycle.add(timeOfChangeMaking));
    require(now < startTimeOfCycle.add(timeOfChangeMaking).add(timeOfProposalMaking));
    _;
  }

  // Checks if the message sender is participant
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
    require(cyclePhase == Ended);
    require(now >= startTimeOfCycle.add(timeOfCycle));

    cyclePhase = ChangeMaking;

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
    require(_amountInWeis <= totalFundsInWeis);

    proposals.push(Proposal({
      isBuy: _isBuy,
      tokenAddress: _tokenAddress,
      tokenPriceInWeis: _tokenPriceInWeis
    }));

    //Stake control tokens
    uint256 proposalId = proposals.length - 1;
    supportProposal(proposalId, _amountInWeis);
  }

  function supportProposal(uint256 proposalId, uint256 _amountInWeis)
    public
    isProposalMakingTime
    onlyParticipant
  {
    require(proposalId < proposals.length);
    require(_amountInWeis <= totalFundsInWeis);

    //Stake control tokens
    uint256 controlStake = _amountInWeis.mul(cToken.balanceOf(msg.sender)).div(totalFundsInWeis);
    //Collect staked control tokens
    cToken.ownerCollectFrom(msg.sender, controlStake);
    //Update stake data
    stakedControlOfProposal[proposalId] = stakedControlOfProposal[proposalId].add(controlStake);
    stakedControlOfProposalOfUser[proposalId][msg.sender] = stakedControlOfProposalOfUser[proposalId][msg.sender].add(controlStake);
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
    totalFundsInWeis = totalFundsInWeis.add(msg.value);

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
    balanceOf[msg.sender] = balanceOf[msg.sender].sub(amountInWeis);

    msg.sender.transfer(amountInWeis);
  }

  function endChangeMakingTime() public {
    require(cyclePhase == ChangeMaking);
    require(now >= startTimeOfCycle.add(timeOfChangeMaking));
    require(now < startTimeOfCycle.add(timeOfCycle));

    cyclePhase = ProposalMaking;

    ChangeMakingTimeEnded(now);
  }

  function endProposalMakingTime() public {
    require(cyclePhase == ProposalMaking);

    cyclePhase = Waiting;

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

    //Invest in tokens using etherdelta
    for (i = 0; i < proposals.length; i = i.add(1)) {
      uint256 investAmount = totalFundsInWeis.mul(stakedControlOfProposal[i]).div(cToken.totalSupply());
      assert(etherDelta.call.value(investAmount)(bytes4(keccak256("deposit()"))); //Deposit ether

    }

    ProposalMakingTimeEnded(now);
  }

  function endCycle() public {
    require(cyclePhase == Waiting);
    require(now >= startTimeOfCycle.add(timeOfCycle));

    if (isFirstCycle) {
      cToken.finishMinting();
    }
    cyclePhase = Ended;
    isFirstCycle = false;

    //Sell all invested tokens

    totalFundsInWeis = this.balance;

    //Distribute staked control tokens

    //Distribute funds
    uint256 totalCommission = commissionRate.mul(totalFundsInWeis).div(10**decimals);

    for (uint256 i = 0; i < participants.length; i = i.add(1)) {
      address participant = participants[i];
      uint256 newBalance = totalFundsInWeis.sub(totalCommission).mul(initialDeposit[participant]).div(totalInitialDeposit);
      //Add commission
      newBalance = newBalance.add(totalCommission.mul(cToken.balanceOf(participant)).div(cToken.totalSupply()));
      balanceOf[participant] = newBalance;
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
    return amount.mul(initialDeposit[user]).div(balanceOf[user]);
  }?

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
