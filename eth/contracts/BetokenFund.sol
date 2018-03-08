pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/math/Math.sol';
import 'zeppelin-solidity/contracts/lifecycle/Pausable.sol';
import './ControlToken.sol';
import './KyberNetwork.sol';
import './Utils.sol';

/**
 * The main contract of the Betoken hedge fund
 */
contract BetokenFund is Pausable, Utils {
  using SafeMath for uint256;

  enum CyclePhase { ChangeMaking, ProposalMaking, Waiting, Selling, Finalized }

  struct Proposal {
    address tokenAddress;
    uint256 buyPriceInWeis;
    uint256 sellPriceInWeis;
    uint256 numFor;
    uint256 numAgainst;
    bool isSold;
  }

  /**
   * Executes function only during the given cycle phase.
   * @param phase the cycle phase during which the function may be called
   */
  modifier during(CyclePhase phase) {
    require(cyclePhase == phase);
    _;
  }

  /**
   * Executes function only when msg.sender is a participant of the fund.
   */
  modifier onlyParticipant {
    require(isParticipant[msg.sender]);
    _;
  }

  modifier rewardCaller {
    cToken.mint(msg.sender, functionCallReward);
    _;
  }

  //Address of the control token contract.
  address public controlTokenAddr;

  //Address of the KyberNetwork contract
  address public kyberAddr;

  //The creator of the BetokenFund contract. Only used in initializeSubcontracts().
  address public creator;

  //Address to which the developer fees will be paid.
  address public developerFeeAccount;

  //The number of the current investment cycle.
  uint256 public cycleNumber;

  //10^{decimals} used for representing fixed point numbers with {decimals} decimals.
  uint256 public PRECISION;

  //The amount of funds held by the fund.
  uint256 public totalFundsInWeis;

  //The start time for the current investment cycle phase, in seconds since Unix epoch.
  uint256 public startTimeOfCyclePhase;

  //Temporal length of change making period at start of each cycle, in seconds.
  uint256 public timeOfChangeMaking;

  //Temporal length of proposal making period at start of each cycle, in seconds.
  uint256 public timeOfProposalMaking;

  //Temporal length of waiting period, in seconds.
  uint256 public timeOfWaiting;

  //Minimum proportion of Kairo balance people have to stake in support of a proposal. Fixed point decimal.
  uint256 public minStakeProportion;

  //The maximum number of proposals each cycle.
  uint256 public maxProposals;

  //The proportion of the fund that gets distributed to Kairo holders every cycle. Fixed point decimal.
  uint256 public commissionRate;

  //The proportion of contract balance that goes the the devs every cycle. Fixed point decimal.
  uint256 public developerFeeProportion;

  //The max number of proposals each member can create.
  uint256 public maxProposalsPerMember;

  //Number of proposals already made in this cycle. Excludes deleted proposals.
  uint256 public numProposals;

  //Total Kairo staked in support of proposals this cycle.
  uint256 public cycleTotalForStake;

  //Amount of Kairo rewarded to the user who calls a phase transition/proposal handling function
  uint256 public functionCallReward;

  //Flag for whether the contract has been initialized with subcontracts' addresses.
  bool public initialized;

  //Flag for whether emergency withdrawing is allowed.
  bool public allowEmergencyWithdraw;

  //Returns true for an address if it's in the participants array, false otherwise.
  mapping(address => bool) public isParticipant;

  //Returns the amount participant staked into all proposals in the current cycle.
  mapping(address => uint256) public userStakedProposalCount;

  //Mapping from a participant's address to their Ether balance, in weis.
  mapping(address => uint256) public balanceOf;

  //Mapping from Proposal to total amount of Control Tokens being staked by supporters.
  mapping(uint256 => uint256) public forStakedControlOfProposal;
  mapping(uint256 => uint256) public againstStakedControlOfProposal;

  //Records the number of proposals a user has created in the current cycle. Canceling support does not decrease this number.
  mapping(address => uint256) public createdProposalCount;

  //mapping(proposalId => mapping(participantAddress => stakedTokensInWeis))
  mapping(uint256 => mapping(address => uint256)) public forStakedControlOfProposalOfUser;
  mapping(uint256 => mapping(address => uint256)) public againstStakedControlOfProposalOfUser;

  //Mapping to check if a proposal for a token has already been made.
  mapping(address => bool) public isTokenAlreadyProposed;

  //A list of everyone who is participating in the fund.
  address[] public participants;

  //List of proposals in the current cycle.
  Proposal[] public proposals;

  //The current cycle phase.
  CyclePhase public cyclePhase;

  //Contract instances
  ControlToken internal cToken;
  KyberNetwork internal kyber;

  event CycleStarted(uint256 _cycleNumber, uint256 _timestamp);
  event Deposit(uint256 _cycleNumber, address _sender, uint256 _amountInWeis, uint256 _timestamp);
  event Withdraw(uint256 _cycleNumber, address _sender, uint256 _amountInWeis, uint256 _timestamp);
  event ChangeMakingTimeEnded(uint256 _cycleNumber, uint256 _timestamp);

  event NewProposal(uint256 _cycleNumber, uint256 _id, address _tokenAddress, uint256 _stakeInWeis);
  event StakedProposal(uint256 _cycleNumber, uint256 _id, uint256 _stakeInWeis, bool _support);
  event ProposalMakingTimeEnded(uint256 _cycleNumber, uint256 _timestamp);

  event WaitingPhaseEnded(uint256 _cycleNumber, uint256 _timestamp);

  event AssetSold(uint256 _cycleNumber, uint256 _proposalId);
  event SellingPhaseEnded(uint256 _cycleNumber, uint256 _timestamp);

  event ROI(uint256 _cycleNumber, uint256 _beforeTotalFunds, uint256 _afterTotalFunds);
  event CommissionPaid(uint256 _cycleNumber, uint256 _totalCommissionInWeis);
  event CycleFinalized(uint256 _cycleNumber, uint256 _timestamp);

  /**
   * Contract initialization functions
   */

  //Constructor
  function BetokenFund(
    address _kyberAddr,
    address _developerFeeAccount,
    uint256 _timeOfChangeMaking,
    uint256 _timeOfProposalMaking,
    uint256 _timeOfWaiting,
    uint256 _minStakeProportion,
    uint256 _maxProposals,
    uint256 _commissionRate,
    uint256 _developerFeeProportion,
    uint256 _maxProposalsPerMember,
    uint256 _cycleNumber,
    uint256 _functionCallReward
  )
    public
  {
    require(_minStakeProportion < 10**18);
    require(_commissionRate.add(_developerFeeProportion) < 10**18);

    kyberAddr = _kyberAddr;
    developerFeeAccount = _developerFeeAccount;
    timeOfChangeMaking = _timeOfChangeMaking;
    timeOfProposalMaking = _timeOfProposalMaking;
    timeOfWaiting = _timeOfWaiting;
    minStakeProportion = _minStakeProportion;
    maxProposals = _maxProposals;
    commissionRate = _commissionRate;
    developerFeeProportion = _developerFeeProportion;
    maxProposalsPerMember = _maxProposalsPerMember;
    startTimeOfCyclePhase = 0;
    cyclePhase = CyclePhase.Finalized;
    creator = msg.sender;
    numProposals = 0;
    cycleNumber = _cycleNumber;
    functionCallReward = _functionCallReward;
    kyber = KyberNetwork(_kyberAddr);
    allowEmergencyWithdraw = false;
  }

  /**
   * Initializes the list of participants. Used during contract upgrades.
   * @param _participants the list of participant addresses
   */
  function initializeParticipants(address[] _participants) public {
    require(msg.sender == creator);
    require (!initialized);

    participants = _participants;
    for (uint i = 0; i < _participants.length; i++) {
      isParticipant[_participants[i]] = true;
    }
  }

  /**
   * Initializes the address of the ControlToken contract.
   * @param _cTokenAddr address of ControlToken contract
   */
  function initializeSubcontracts(address _cTokenAddr) public {
    require(msg.sender == creator);
    require(!initialized);

    initialized = true;

    controlTokenAddr = _cTokenAddr;

    cToken = ControlToken(controlTokenAddr);
  }

  /**
   * Getters
   */

  /**
   * Returns the length of the participants array.
   * @return length of participants array
   */
  function participantsCount() public view returns(uint256 _count) {
    return participants.length;
  }

  /**
   * Returns the length of the proposals array.
   * @return length of proposals array
   */
  function proposalsCount() public view returns(uint256 _count) {
    return proposals.length;
  }

  /**
   * Meta functions
   */

  /**
   * Emergency functions
   */

  /**
   * In case the fund is invested in tokens, sell all tokens.
   */
  function emergencyDumpAllTokens() onlyOwner whenPaused public {
    for (uint256 i = 0; i < proposals.length; i = i.add(1)) {
      emergencyDumpToken(i);
    }
  }

  function emergencyDumpToken(uint256 _proposalId) onlyOwner whenPaused public {
    if (__proposalIsValid(i)) { //Ensure proposal isn't a deleted one
      __handleInvestment(i, false);
    }
  }

  /**
   * In case the fund is invested in tokens, return all staked Kairos.
   */
  function emergencyReturnAllStakes() onlyOwner whenPaused public {
    for (uint256 i = 0; i < proposals.length; i = i.add(1)) {
      emergencyReturnStakes(i);
    }
  }

  function emergencyReturnStakes(uint256 _proposalId) onlyOwner whenPaused public {
    if (__proposalIsValid(_proposalId)) {
      __returnStakes(_proposalId);
    }
  }

  /**
   * In case the fund is invested in tokens, redistribute balance after selling all tokens.
   */
  function emergencyRedistBalances() onlyOwner whenPaused public {
    for (uint256 i = 0; i < participants.length; i = i.add(1)) {
      address participant = participants[i];
      uint256 newBalance = 0;
      if (totalFundsInWeis > 0) {
        newBalance = newBalance.add(this.balance.mul(balanceOf[participant]).div(totalFundsInWeis));
      }
      balanceOf[participant] = newBalance;
    }
    totalFundsInWeis = this.balance;
  }

  function setAllowEmergencyWithdraw(bool _val) onlyOwner whenPaused public {
    allowEmergencyWithdraw = _val;
  }

  /**
   * Function for withdrawing all funds in times of emergency. Only callable when fund is paused.
   */
  function emergencyWithdraw()
    public
    onlyParticipant
    whenPaused
  {
    require(allowEmergencyWithdraw);
    uint256 amountInWeis = balanceOf[msg.sender];

    //Subtract from account
    totalFundsInWeis = totalFundsInWeis.sub(amountInWeis);
    balanceOf[msg.sender] = 0;

    //Transfer
    msg.sender.transfer(amountInWeis);

    //Emit event
    Withdraw(cycleNumber, msg.sender, amountInWeis, now);
  }

  /**
   * Parameter setters
   */

  /**
   * Changes the address of the KyberNetwork contract used in the contract. Only callable by owner.
   * @param _newAddr new address of KyberNetwork contract
   */
  function changeKyberNetworkAddress(address _newAddr) public onlyOwner whenPaused {
    require(_newAddr != address(0));
    kyberAddr = _newAddr;
    kyber = KyberNetwork(_newAddr);
  }

  /**
   * Changes the address to which the developer fees will be sent. Only callable by owner.
   * @param _newAddr new developer fee address
   */
  function changeDeveloperFeeAccount(address _newAddr) public onlyOwner {
    require(_newAddr != address(0));
    developerFeeAccount = _newAddr;
  }

  /**
   * Changes the proportion of fund balance sent to the developers each cycle. May only decrease. Only callable by owner.
   * @param _newProp the new proportion, fixed point decimal
   */
  function changeDeveloperFeeProportion(uint256 _newProp) public onlyOwner {
    require(_newProp < developerFeeProportion);
    developerFeeProportion = _newProp;
  }

  /**
   * Changes the proportion of fund balance given to Kairo holders each cycle. Only callable by owner.
   * @param _newProp the new proportion, fixed point decimal
   */
  function changeCommissionRate(uint256 _newProp) public onlyOwner {
    commissionRate = _newProp;
  }

  /**
   * Changes the owner of the ControlToken contract.
   * @param  _newOwner the new owner address
   */
  function changeControlTokenOwner(address _newOwner) public onlyOwner whenPaused {
    require(_newOwner != address(0));
    cToken.transferOwnership(_newOwner);
  }

  /**
   * Start cycle functions
   */

  /**
   * Starts a new investment cycle.
   */
  function startNewCycle() public during(CyclePhase.Finalized) whenNotPaused rewardCaller {
    require(initialized);

    //Update values
    cyclePhase = CyclePhase.ChangeMaking;
    startTimeOfCyclePhase = now;
    cycleNumber = cycleNumber.add(1);

    //Reset data
    for (uint256 i = 0; i < participants.length; i = i.add(1)) {
      __resetMemberData(participants[i]);
    }
    for (i = 0; i < proposals.length; i = i.add(1)) {
      __resetProposalData(i);
    }
    delete proposals;
    delete numProposals;
    delete cycleTotalForStake;

    //Emit event
    CycleStarted(cycleNumber, now);
  }

  /**
   * Resets cycle specific data for a given participant.
   * @param _addr the participant whose data will be reset
   */
  function __resetMemberData(address _addr) internal {
    delete createdProposalCount[_addr];
    delete userStakedProposalCount[_addr];

    //Remove the associated corresponding control staked for/against  each proposal
    for (uint256 i = 0; i < proposals.length; i = i.add(1)) {
      delete forStakedControlOfProposalOfUser[i][_addr];
      delete againstStakedControlOfProposalOfUser[i][_addr];
    }
  }

  /**
   * Resets cycle specific data for a give proposal
   * @param _proposalId ID of proposal whose data will be reset
   */
  function __resetProposalData(uint256 _proposalId) internal {
    delete isTokenAlreadyProposed[proposals[_proposalId].tokenAddress];
    delete forStakedControlOfProposal[_proposalId];
    delete againstStakedControlOfProposal[_proposalId];
  }

  /**
   * ChangeMakingTime functions
   */

  /**
   * Deposit Ether into the fund.
   */
  function deposit()
    public
    payable
    during(CyclePhase.ChangeMaking)
    whenNotPaused
  {
    //If caller is not a participant, add them to the participants list
    if (!isParticipant[msg.sender]) {
      participants.push(msg.sender);
      isParticipant[msg.sender] = true;
    }

    //Register investment
    balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);
    totalFundsInWeis = totalFundsInWeis.add(msg.value);

    //Deposits during all cycles will grant you Kairo in the testnet alpha
    //Uncomment in mainnet version
    //if (cycleNumber == 1) {
      //Give control tokens proportional to investment
      cToken.mint(msg.sender, msg.value);
    //}

    //Emit event
    Deposit(cycleNumber, msg.sender, msg.value, now);
  }

  /**
   * Withdraws a certain amount of Ether from the user's account. Cannot be called during the first cycle.
   * @param _amountInWeis amount of Ether to be withdrawn
   */
  function withdraw(uint256 _amountInWeis)
    public
    during(CyclePhase.ChangeMaking)
    onlyParticipant
    whenNotPaused
  {
    require(cycleNumber != 1);

    //Subtract from account
    totalFundsInWeis = totalFundsInWeis.sub(_amountInWeis);
    balanceOf[msg.sender] = balanceOf[msg.sender].sub(_amountInWeis);

    //Transfer Ether to user
    msg.sender.transfer(_amountInWeis);

    //Emit event
    Withdraw(cycleNumber, msg.sender, _amountInWeis, now);
  }

  /**
   * Ends the ChangeMaking phase.
   */
  function endChangeMakingTime() public during(CyclePhase.ChangeMaking) whenNotPaused rewardCaller {
    require(now >= startTimeOfCyclePhase.add(timeOfChangeMaking));

    startTimeOfCyclePhase = now;
    cyclePhase = CyclePhase.ProposalMaking;

    ChangeMakingTimeEnded(cycleNumber, now);
  }

  /**
   * ProposalMakingTime functions
   */

  /**
   * Creates a new investment proposal for an ERC20 token.
   * @param _tokenAddress address of the ERC20 token contract
   * @param _stakeInWeis amount of Kairos to be staked in support of the proposal
   */
  function createProposal(
    address _tokenAddress,
    uint256 _stakeInWeis
  )
    public
    during(CyclePhase.ProposalMaking)
    onlyParticipant
    whenNotPaused
  {
    require(numProposals < maxProposals);
    require(!isTokenAlreadyProposed[_tokenAddress]);
    require(createdProposalCount[msg.sender] < maxProposalsPerMember);

    //Add proposal to list
    proposals.push(Proposal({
      tokenAddress: _tokenAddress,
      buyPriceInWeis: 0,
      sellPriceInWeis: 0,
      numFor: 0,
      numAgainst: 0,
      isSold: false
    }));

    //Update values about proposal
    isTokenAlreadyProposed[_tokenAddress] = true;
    createdProposalCount[msg.sender] = createdProposalCount[msg.sender].add(1);
    numProposals = numProposals.add(1);

    //Stake control tokens
    uint256 proposalId = proposals.length - 1;
    stakeProposal(proposalId, _stakeInWeis, true);

    //Emit event
    NewProposal(cycleNumber, proposalId, _tokenAddress, _stakeInWeis);
  }

  /**
   * Stakes for or against an investment proposal.
   * @param _proposalId ID of the proposal the user wants to support
   * @param _stakeInWeis amount of Kairo to be staked in support of the proposal
   */
  function stakeProposal(uint256 _proposalId, uint256 _stakeInWeis, bool _support)
    public
    during(CyclePhase.ProposalMaking)
    onlyParticipant
    whenNotPaused
  {
    require(_proposalId < proposals.length); //Valid ID
    require(isTokenAlreadyProposed[proposals[_proposalId].tokenAddress]); //Non-empty proposal

    /**
     * Stake Kairos
     */
    //Ensure stake is larger than the minimum proportion of Kairo balance
    require(_stakeInWeis.mul(PRECISION) >= minStakeProportion.mul(cToken.balanceOf(msg.sender)));
    require(_stakeInWeis > 0); //Ensure positive stake amount

    //Collect Kairos as stake
    cToken.ownerCollectFrom(msg.sender, _stakeInWeis);

    //Update stake data
    if (_support && againstStakedControlOfProposalOfUser[_proposalId][msg.sender] == 0) {
      //Support proposal, hasn't staked against it
      if (forStakedControlOfProposalOfUser[_proposalId][msg.sender] == 0) {
        proposals[_proposalId].numFor = proposals[_proposalId].numFor.add(1);
      }
      forStakedControlOfProposal[_proposalId] = forStakedControlOfProposal[_proposalId].add(_stakeInWeis);
      forStakedControlOfProposalOfUser[_proposalId][msg.sender] = forStakedControlOfProposalOfUser[_proposalId][msg.sender].add(_stakeInWeis);
      cycleTotalForStake = cycleTotalForStake.add(_stakeInWeis);
    } else if (!_support && forStakedControlOfProposalOfUser[_proposalId][msg.sender] == 0) {
      //Against proposal, hasn't staked for it
      if (againstStakedControlOfProposalOfUser[_proposalId][msg.sender] == 0) {
        proposals[_proposalId].numAgainst = proposals[_proposalId].numAgainst.add(1);
      }
      againstStakedControlOfProposal[_proposalId] = againstStakedControlOfProposal[_proposalId].add(_stakeInWeis);
      againstStakedControlOfProposalOfUser[_proposalId][msg.sender] = againstStakedControlOfProposalOfUser[_proposalId][msg.sender].add(_stakeInWeis);
    } else {
      revert();
    }
    userStakedProposalCount[msg.sender] = userStakedProposalCount[msg.sender].add(1);

    //Emit event
    StakedProposal(cycleNumber, _proposalId, _stakeInWeis, _support);
  }

  /**
   * Cancels staking in a proposal.
   * @param _proposalId ID of the proposal
   */
  function cancelProposalStake(uint256 _proposalId)
    public
    during(CyclePhase.ProposalMaking)
    onlyParticipant
    whenNotPaused
  {
    require(_proposalId < proposals.length); //Valid ID
    require(proposals[_proposalId].numFor > 0); //Non-empty proposal

    //Remove stake data
    uint256 forStake = forStakedControlOfProposalOfUser[_proposalId][msg.sender];
    uint256 againstStake = againstStakedControlOfProposalOfUser[_proposalId][msg.sender];
    uint256 stake = forStake.add(againstStake);
    if (forStake > 0) {
      forStakedControlOfProposal[_proposalId] = forStakedControlOfProposal[_proposalId].sub(stake);
      cycleTotalForStake = cycleTotalForStake.sub(stake);
      proposals[_proposalId].numFor = proposals[_proposalId].numFor.sub(1);
    } else if (againstStake > 0) {
      againstStakedControlOfProposal[_proposalId] = againstStakedControlOfProposal[_proposalId].sub(stake);
      proposals[_proposalId].numAgainst = proposals[_proposalId].numAgainst.sub(1);
    } else {
      return;
    }
    userStakedProposalCount[msg.sender] = userStakedProposalCount[msg.sender].sub(1);

    delete forStakedControlOfProposalOfUser[_proposalId][msg.sender];
    delete againstStakedControlOfProposalOfUser[_proposalId][msg.sender];

    //Return stake
    cToken.transfer(msg.sender, stake);

    //Delete proposal if necessary
    if (proposals[_proposalId].numFor == 0) {
      __returnStakes(_proposalId);
      __resetProposalData(_proposalId);
      numProposals = numProposals.sub(1);
      delete proposals[_proposalId];
    }
  }

  /**
   * Ends the ProposalMaking phase.
   */
  function endProposalMakingTime()
    public
    during(CyclePhase.ProposalMaking)
    rewardCaller
    whenNotPaused
  {
    require(now >= startTimeOfCyclePhase.add(timeOfProposalMaking));

    startTimeOfCyclePhase = now;
    cyclePhase = CyclePhase.Waiting;

    __penalizeNonparticipation();

    ProposalMakingTimeEnded(cycleNumber, now);
  }

  /**
   * Penalizes non-participation by burning a proportion of Kairo balance.
   */
  function __penalizeNonparticipation() internal {
    for (uint256 i = 0; i < participants.length; i = i.add(1)) {
      address participant = participants[i];
      uint256 kairoBalance = cToken.balanceOf(participant);
      if (userStakedProposalCount[participant] == 0 && kairoBalance > 0) {
        uint256 decreaseAmount = kairoBalance.mul(minStakeProportion).div(PRECISION);
        cToken.ownerBurn(participant, decreaseAmount);
      }
    }
  }

  /**
   * Waiting phase functions
   */

  /**
   * Called by user to buy the assets of a proposal
   * @param _proposalId the ID of the proposal
   */
  function executeProposal(uint256 _proposalId)
    public
    during(CyclePhase.Waiting)
    whenNotPaused
    rewardCaller
  {
    require(__proposalIsValid(_proposalId));
    require(proposals[_proposalId].buyPriceInWeis == 0);
    __handleInvestment(_proposalId, true);
  }

  function endWaitingPhase()
    public
    during(CyclePhase.Waiting)
    whenNotPaused
    rewardCaller
  {
    require(now >= startTimeOfCyclePhase.add(timeOfWaiting));

    startTimeOfCyclePhase = now;
    cyclePhase = CyclePhase.Selling;

    WaitingPhaseEnded(cycleNumber, now);
  }

  /**
   * Selling phase functions
   */

  /**
   * Called by user to sell the assets a proposal invested in
   * @param _proposalId the ID of the proposal
   */
  function sellProposalAsset(uint256 _proposalId)
    public
    during(CyclePhase.Selling)
    whenNotPaused
    rewardCaller
  {
    require(__proposalIsValid(_proposalId));
    require(proposals[_proposalId].buyPriceInWeis > 0);
    __handleInvestment(_proposalId, false);
    __settleBets(_proposalId);
    proposals[_proposalId].isSold = true;
  }

  /**
   * Finalize the cycle by redistributing user balances and settling investment proposals.
   */
  function finalizeCycle() public during(CyclePhase.Selling) whenNotPaused rewardCaller {
    require(proposalsAreSold());

    //Update cycle values
    startTimeOfCyclePhase = now;
    cyclePhase = CyclePhase.Finalized;

    //Burn any Kairo left in BetokenFund's account
    cToken.burnOwnerBalance();

    //Distribute funds
    __distributeFundsAfterCycleEnd();

    //Emit event
    CycleFinalized(cycleNumber, now);
  }

  /**
   * Returns true if the tokens proposals have invested in have all been sold.
   */
  function proposalsAreSold() public view returns (bool) {
    for (uint256 i = 0; i < proposals.length; i = i.add(1)) {
      if (__proposalIsValid(i) && !proposals[i].isSold && proposals[i].buyPriceInWeis > 0) {
        return false;
      }
    }
    return true;
  }

  /**
   * Internal use functions
   */

  function __proposalIsValid(uint256 _proposalId) internal view returns (bool) {
    return proposals[_proposalId].numFor > 0;
  }

  function __addControlTokenReceipientAsParticipant(address _receipient) public {
    require(msg.sender == controlTokenAddr);
    isParticipant[_receipient] = true;
    participants.push(_receipient);
  }

  /**
   * Returns all stakes of a proposal
   * @param _proposalId ID of the proposal
   */
  function __returnStakes(uint256 _proposalId) internal {
    for (uint256 j = 0; j < participants.length; j = j.add(1)) {
      address participant = participants[j];
      uint256 stake = forStakedControlOfProposalOfUser[_proposalId][participant].add(againstStakedControlOfProposalOfUser[_proposalId][participant]);
      if (stake != 0) {
        cToken.transfer(participant, stake);
      }
    }
  }

  /**
   * Settles an investment proposal in terms of profitability.
   * @param _proposalId ID of the proposal
   */
  function __settleBets(uint256 _proposalId) internal {
    Proposal storage prop = proposals[_proposalId];

    uint256 forMultiplier = prop.sellPriceInWeis.mul(PRECISION).div(prop.buyPriceInWeis);
    uint256 againstMultiplier = 0;
    if (prop.sellPriceInWeis < prop.buyPriceInWeis.mul(2)) {
      againstMultiplier = prop.buyPriceInWeis.mul(2).sub(prop.sellPriceInWeis).mul(PRECISION).div(prop.buyPriceInWeis);
    }

    for (uint256 j = 0; j < participants.length; j = j.add(1)) {
      address participant = participants[j];
      uint256 stake = 0;
      if (forStakedControlOfProposalOfUser[_proposalId][participant] > 0) {
        //User supports proposal
        stake = forStakedControlOfProposalOfUser[_proposalId][participant];
        //Mint instead of transfer. Ensures that there are always enough tokens.
        //Extra will be burnt right after so no problem there.
        cToken.mint(participant, stake.mul(forMultiplier).div(PRECISION));
      } else if (againstStakedControlOfProposalOfUser[_proposalId][participant] > 0) {
        //User is against proposal
        stake = againstStakedControlOfProposalOfUser[_proposalId][participant];
        //Mint instead of transfer. Ensures that there are always enough tokens.
        //Extra will be burnt right after so no problem there.
        cToken.mint(participant, stake.mul(againstMultiplier).div(PRECISION));
      }
    }
  }

  /**
   * Distributes the funds accourding to previously held proportions. Pays commission to Kairo holders,
   * and developer fees to developers.
   */
  function __distributeFundsAfterCycleEnd() internal {
    uint256 profit = 0;
    if (this.balance > totalFundsInWeis) {
      profit = this.balance - totalFundsInWeis;
    }
    uint256 totalCommission = commissionRate.mul(profit).div(PRECISION);
    uint256 devFee = developerFeeProportion.mul(this.balance).div(PRECISION);
    uint256 newTotalRegularFunds = this.balance.sub(totalCommission).sub(devFee);

    //Distributes funds to participants
    for (uint256 i = 0; i < participants.length; i = i.add(1)) {
      address participant = participants[i];
      uint256 newBalance = 0;
      //Add share
      if (totalFundsInWeis > 0) {
        newBalance = newBalance.add(newTotalRegularFunds.mul(balanceOf[participant]).div(totalFundsInWeis));
      }
      //Add commission
      //Adding a check for nonzero Kairo supply here makes Truffle go apeshit. Edge case anyways, so whatevs.
      if (cToken.totalSupply() > 0) {
        newBalance = newBalance.add(totalCommission.mul(cToken.balanceOf(participant)).div(cToken.totalSupply()));
      }
      //Update balance
      balanceOf[participant] = newBalance;
    }

    //Update values
    uint256 newTotalFunds = newTotalRegularFunds.add(totalCommission);
    ROI(cycleNumber, totalFundsInWeis, newTotalFunds);
    totalFundsInWeis = newTotalFunds;

    //Transfer fees
    developerFeeAccount.transfer(devFee);

    //Emit event
    CommissionPaid(cycleNumber, totalCommission);
  }

  function __handleInvestment(uint256 _proposalId, bool _buy) internal {
    uint256 srcAmount;
    uint256 actualDestAmount;
    uint256 actualRate;
    address destAddr = proposals[_proposalId].tokenAddress;
    DetailedERC20 destToken = DetailedERC20(destAddr);

    if (_buy) {
      //Make buy orders

      //Calculate investment amount
      srcAmount = totalFundsInWeis.mul(forStakedControlOfProposal[_proposalId]).div(cycleTotalForStake);

      uint256 beforeBalance = this.balance;

      //Do trade
      actualDestAmount = kyber.trade.value(srcAmount)(
        ETH_TOKEN_ADDRESS,
        srcAmount,
        destToken,
        address(this),
        MAX_QTY,
        1,
        address(this)
      );

      //Record buy price
      require(actualDestAmount > 0);
      actualRate = beforeBalance.sub(this.balance).mul(PRECISION).div(actualDestAmount);
      proposals[_proposalId].buyPriceInWeis = actualRate;
    } else {
      //Make sell orders

      //Get sell amount
      srcAmount = destToken.balanceOf(address(this));

      //Do trade
      destToken.approve(kyberAddr, srcAmount);
      actualDestAmount = kyber.trade(
        destToken,
        srcAmount,
        ETH_TOKEN_ADDRESS,
        address(this),
        MAX_QTY,
        1,
        address(this)
      );
      destToken.approve(kyberAddr, 0);

      //Record sell price
      require(srcAmount > destToken.balanceOf(address(this)));
      actualRate = actualDestAmount.mul(PRECISION).div(srcAmount.sub(destToken.balanceOf(address(this))));
      proposals[_proposalId].sellPriceInWeis = actualRate;
    }
  }

  function() public payable {
    if (msg.sender != kyberAddr) {
      revert();
    }
  }
}