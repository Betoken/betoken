pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/token/ERC20/MintableToken.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/lifecycle/pausable.sol';
import './etherdelta.sol';
import './oraclizeAPI_0.5.sol';

/**
 * The main contract of the Betoken hedge fund
 */
contract BetokenFund is Pausable {
  using SafeMath for uint256;

  enum CyclePhase { ChangeMaking, ProposalMaking, Waiting, Ended, Finalized }

  struct Proposal {
    address tokenAddress;
    string tokenSymbol;
    uint256 tokenDecimals;
    uint256 buyPriceInWeis;
    uint256 sellPriceInWeis;
    uint256 buyOrderExpirationBlockNum;
    uint256 sellOrderExpirationBlockNum;
    uint256 numFor;
    uint256 numAgainst;
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

  /**
   * Exucutes function only when msg.sender is the fund's OraclizeHandler.
   */
  modifier onlyOraclize {
    require(msg.sender == oraclizeAddr);
    _;
  }

  //Address of the control token contract.
  address public controlTokenAddr;

  //Address of the EtherDelta contract
  address public etherDeltaAddr;

  //Address of the fund's OraclizeHandler contract.
  address public oraclizeAddr;

  //The creator of the BetokenFund contract. Only used in initializeSubcontracts().
  address public creator;

  //Address to which the developer fees will be paid.
  address public developerFeeAccount;

  //The number of the current investment cycle.
  uint256 public cycleNumber;

  //10^{decimals} used for representing fixed point numbers with {decimals} decimals.
  uint256 public tenToDecimals;

  //The amount of funds held by the fund.
  uint256 public totalFundsInWeis;

  //The start time for the current investment cycle phase, in seconds since Unix epoch.
  uint256 public startTimeOfCyclePhase;

  //Temporal length of change making period at start of each cycle, in seconds.
  uint256 public timeOfChangeMaking;

  //Temporal length of proposal making period at start of each cycle, in seconds.
  uint256 public timeOfProposalMaking;

  //Temporal length of waiting period, after which the bets will be settled, in seconds.
  uint256 public timeOfWaiting;

  //The time allotted for waiting for sell orders, in seconds.
  uint256 public timeOfSellOrderWaiting;

  //Minimum proportion of Kairo balance people have to stake in support of a proposal. Fixed point decimal.
  uint256 public minStakeProportion;

  //The maximum number of proposals each cycle.
  uint256 public maxProposals;

  //The proportion of the fund that gets distributed to Kairo holders every cycle. Fixed point decimal.
  uint256 public commissionRate;

  //The expiration time for buy and sell orders made on EtherDelta.
  uint256 public orderExpirationTimeInBlocks;

  //The proportion of contract balance that goes the the devs every cycle. Fixed point decimal.
  uint256 public developerFeeProportion;

  //The max number of proposals each member can create.
  uint256 public maxProposalsPerMember;

  //Number of proposals already made in this cycle. Excludes deleted proposals.
  uint256 public numProposals;

  //Flag for whether the contract has been initialized with subcontracts' addresses.
  bool public initialized;

  //Returns true for an address if it's in the participants array, false otherwise.
  mapping(address => bool) public isParticipant;

  //Mapping from a participant's address to their Ether balance, in weis.
  mapping(address => uint256) public balanceOf;

  //Mapping from Proposal to total amount of Control Tokens being staked by supporters.
  mapping(uint256 => uint256) public forStakedControlOfProposal;

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

  //References to subcontracts and EtherDelta contract.
  ControlToken internal cToken;
  EtherDelta internal etherDelta;
  OraclizeHandler internal oraclize;

  //The current cycle phase.
  CyclePhase public cyclePhase;

  event CycleStarted(uint256 _cycleNumber, uint256 _timestamp);
  event Deposit(uint256 _cycleNumber, address _sender, uint256 _amountInWeis, uint256 _timestamp);
  event Withdraw(uint256 _cycleNumber, address _sender, uint256 _amountInWeis, uint256 _timestamp);
  event ChangeMakingTimeEnded(uint256 _cycleNumber, uint256 _timestamp);
  event NewProposal(uint256 _cycleNumber, uint256 _id, address _tokenAddress, string _tokenSymbol, uint256 _amountInWeis);
  event SupportedProposal(uint256 _cycleNumber, uint256 _id, uint256 _amountInWeis);
  event ProposalMakingTimeEnded(uint256 _cycleNumber, uint256 _timestamp);
  event CycleEnded(uint256 _cycleNumber, uint256 _timestamp);
  event CycleFinalized(uint256 _cycleNumber, uint256 _timestamp);
  event ROI(uint256 _cycleNumber, uint256 _beforeTotalFunds, uint256 _afterTotalFunds);
  event PredictionResult(uint256 _cycleNumber, address _member, bool _success);
  event CommissionPaid(uint256 _cycleNumber, uint256 _totalCommissionInWeis);

  /**
   * Contract initialization functions
   */

  //Constructor
  function BetokenFund(
    address _etherDeltaAddr,
    address _developerFeeAccount,
    uint256 _tenToDecimals,
    uint256 _timeOfChangeMaking,
    uint256 _timeOfProposalMaking,
    uint256 _timeOfWaiting,
    uint256 _timeOfSellOrderWaiting,
    uint256 _minStakeProportion,
    uint256 _maxProposals,
    uint256 _commissionRate,
    uint256 _orderExpirationTimeInBlocks,
    uint256 _developerFeeProportion,
    uint256 _maxProposalsPerMember
  )
    public
  {
    require(_tenToDecimals > 0);
    require(_minStakeProportion < _tenToDecimals);
    require(_commissionRate.add(_developerFeeProportion) < _tenToDecimals);

    etherDeltaAddr = _etherDeltaAddr;
    developerFeeAccount = _developerFeeAccount;
    tenToDecimals = _tenToDecimals;
    timeOfChangeMaking = _timeOfChangeMaking;
    timeOfProposalMaking = _timeOfProposalMaking;
    timeOfWaiting = _timeOfWaiting;
    timeOfSellOrderWaiting = _timeOfSellOrderWaiting;
    minStakeProportion = _minStakeProportion;
    maxProposals = _maxProposals;
    commissionRate = _commissionRate;
    orderExpirationTimeInBlocks = _orderExpirationTimeInBlocks;
    developerFeeProportion = _developerFeeProportion;
    maxProposalsPerMember = _maxProposalsPerMember;
    startTimeOfCyclePhase = 0;
    cyclePhase = CyclePhase.Finalized;
    creator = msg.sender;
    numProposals = 0;
    cycleNumber = 0;
    etherDelta = EtherDelta(etherDeltaAddr);
  }

  /**
   * Initializes the addresses of the ControlToken and OraclizeHandler contracts.
   * @param _cTokenAddr address of ControlToken contract
   * @param _oraclizeAddr address of OraclizeHandler contract
   */
  function initializeSubcontracts(address _cTokenAddr, address _oraclizeAddr) public {
    require(msg.sender == creator);
    require(!initialized);

    initialized = true;

    controlTokenAddr = _cTokenAddr;
    oraclizeAddr = _oraclizeAddr;

    cToken = ControlToken(controlTokenAddr);
    oraclize = OraclizeHandler(oraclizeAddr);
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
   * Changes the address of the EtherDelta contract used in the contract. Only callable by owner.
   * @param _newAddr new address of EtherDelta contract
   */
  function changeEtherDeltaAddress(address _newAddr) public onlyOwner {
    require(_newAddr != address(0));
    etherDeltaAddr = _newAddr;
    etherDelta = EtherDelta(_newAddr);
    oraclize.__changeEtherDeltaAddress(_newAddr);
  }

  /**
   * Changes the address of the OraclizeHandler contract used in the contract. Only callable by owner.
   * @param _newAddr new address of OraclizeHandler contract
   */
  function changeOraclizeAddress(address _newAddr) public onlyOwner {
    require(_newAddr != address(0));
    oraclizeAddr = _newAddr;
    oraclize = OraclizeHandler(_newAddr);
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
   * Sends Ether to the OraclizeHandler contract.
   */
  function topupOraclizeFees() public payable {
    oraclizeAddr.transfer(msg.value);
  }

  function changeOraclizeOwner(address _newOwner) public onlyOwner {
    require(_newOwner != address(0));
    oraclize.transferOwnership(_newOwner);
  }

  function changeControlTokenOwner(address _newOwner) public onlyOwner {
    require(_newOwner != address(0));
    cToken.transferOwnership(_newOwner);
  }

  /**
   * Start cycle functions
   */

  /**
   * Starts a new investment cycle.
   */
  function startNewCycle() public during(CyclePhase.Finalized) whenNotPaused {
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
    oraclize.__deleteTokenSymbolOfProposal();
    delete proposals;
    delete numProposals;

    //Emit event
    CycleStarted(cycleNumber, now);
  }

  /**
   * Resets cycle specific data for a given participant.
   * @param _addr the participant whose data will be reset
   */
  function __resetMemberData(address _addr) internal {
    delete createdProposalCount[_addr];

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

    if (cycleNumber == 1) {
      //Give control tokens proportional to investment
      cToken.mint(msg.sender, msg.value);
    }

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
   * Function for withdrawing all funds in times of emergency. Only callable when fund is paused.
   */
  function emergencyWithdraw()
    public
    onlyParticipant
    whenPaused
  {
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
   * Ends the ChangeMaking phase.
   */
  function endChangeMakingTime() public during(CyclePhase.ChangeMaking) whenNotPaused {
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
   * @param _tokenSymbol  ticker/symbol of the token
   * @param _tokenDecimals number of decimals that the token uses
   * @param _stakeInWeis amount of Kairos to be staked in support of the proposal
   */
  function createProposal(
    address _tokenAddress,
    string _tokenSymbol,
    uint256 _tokenDecimals,
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
      tokenSymbol: _tokenSymbol,
      tokenDecimals: _tokenDecimals,
      buyPriceInWeis: 0,
      sellPriceInWeis: 0,
      numFor: 0,
      numAgainst: 0,
      buyOrderExpirationBlockNum: 0,
      sellOrderExpirationBlockNum: 0
    }));

    //Update values about proposal
    isTokenAlreadyProposed[_tokenAddress] = true;
    oraclize.__pushTokenSymbolOfProposal(_tokenSymbol);
    createdProposalCount[msg.sender] = createdProposalCount[msg.sender].add(1);
    numProposals = numProposals.add(1);

    //Stake control tokens
    uint256 proposalId = proposals.length - 1;
    supportProposal(proposalId, _stakeInWeis);

    //Emit event
    NewProposal(cycleNumber, proposalId, _tokenAddress, _tokenSymbol, _stakeInWeis);
  }

  /**
   * Supports an investment proposal.
   * @param _proposalId ID of the proposal the user wants to support
   * @param _stakeInWeis amount of Kairo to be staked in support of the proposal
   */
  function supportProposal(uint256 _proposalId, uint256 _stakeInWeis)
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
    require(_stakeInWeis.mul(tenToDecimals) >= minStakeProportion.mul(cToken.balanceOf(msg.sender)));
    //Collect Kairos as stake
    cToken.ownerCollectFrom(msg.sender, _stakeInWeis);
    //Update stake data
    if (forStakedControlOfProposalOfUser[_proposalId][msg.sender] == 0) {
      proposals[_proposalId].numFor = proposals[_proposalId].numFor.add(1);
    }
    forStakedControlOfProposal[_proposalId] = forStakedControlOfProposal[_proposalId].add(_stakeInWeis);
    forStakedControlOfProposalOfUser[_proposalId][msg.sender] = forStakedControlOfProposalOfUser[_proposalId][msg.sender].add(_stakeInWeis);

    //Emit event
    SupportedProposal(cycleNumber, _proposalId, _stakeInWeis);
  }

  /**
   * Cancels support of a proposal.
   * @param _proposalId ID of the proposal
   */
  function cancelProposalSupport(uint256 _proposalId)
    public
    during(CyclePhase.ProposalMaking)
    onlyParticipant
    whenNotPaused
  {
    require(_proposalId < proposals.length); //Valid ID
    require(proposals[_proposalId].numFor > 0); //Non-empty proposal

    //Remove stake data
    uint256 stake = forStakedControlOfProposalOfUser[_proposalId][msg.sender];
    delete forStakedControlOfProposalOfUser[_proposalId][msg.sender];
    forStakedControlOfProposal[_proposalId] = forStakedControlOfProposal[_proposalId].sub(stake);

    //Remove support
    proposals[_proposalId].numFor = proposals[_proposalId].numFor.sub(1);

    //Return stake
    cToken.transfer(msg.sender, stake);

    //Delete proposal if necessary
    if (forStakedControlOfProposal[_proposalId] == 0) {
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
    whenNotPaused
  {
    require(now >= startTimeOfCyclePhase.add(timeOfProposalMaking));

    startTimeOfCyclePhase = now;
    cyclePhase = CyclePhase.Waiting;

    __stakeAgainstVotes();
    __makeInvestments();

    ProposalMakingTimeEnded(cycleNumber, now);
  }

  /**
   * Stakes the Kairos of the against side into proposals.
   */
  function __stakeAgainstVotes() internal {
    for (uint256 i = 0; i < proposals.length; i = i.add(1)) {
      if (proposals[i].numFor > 0) { //Ensure proposal isn't a deleted one
        //Calculate total Kairo balance of users against the proposal
        uint256 againstTotalBalance = 0;
        for (uint256 j = 0; j < participants.length; j = j.add(1)) {
          bool isFor = forStakedControlOfProposalOfUser[i][participants[j]] != 0;
          if (!isFor) {
            againstTotalBalance = againstTotalBalance.add(cToken.balanceOf(participants[j]));
          }
        }
        //Calculate the proportion of Kairo each user against the proposal have to stake
        uint256 stakeProportion = tenToDecimals;
        if (forStakedControlOfProposal[i] < againstTotalBalance) {
          stakeProportion = forStakedControlOfProposal[i].mul(tenToDecimals).div(againstTotalBalance);
        } else {
          //Mint new Kairo to fill the gap
          uint256 mintAmount = forStakedControlOfProposal[i] - againstTotalBalance;
          if (mintAmount > 0) {
            cToken.mint(address(this), mintAmount);
          }
        }
        //Collect stakes
        for (j = 0; j < participants.length; j = j.add(1)) {
          address participant = participants[j];
          isFor = forStakedControlOfProposalOfUser[i][participant] != 0;
          uint256 userBalance = cToken.balanceOf(participant);
          if (!isFor && userBalance > 0) {
            uint256 stake = stakeProportion.mul(userBalance).div(tenToDecimals);
            cToken.ownerCollectFrom(participant, stake);
            proposals[i].numAgainst = proposals[i].numAgainst.add(1);
            againstStakedControlOfProposalOfUser[i][participant] = againstStakedControlOfProposalOfUser[i][participant].add(stake);
          }
        }
      }
    }
  }

  /**
   * Turns the investment proposals into EtherDelta orders.
   */
  function __makeInvestments() internal {
    //Invest in tokens using etherdelta
    for (uint256 i = 0; i < proposals.length; i = i.add(1)) {
      if (proposals[i].numFor > 0) { //Ensure proposal isn't a deleted one
        //Deposit ether
        uint256 investAmount = totalFundsInWeis.mul(forStakedControlOfProposal[i]).div(cToken.totalSupply());
        etherDelta.deposit.value(investAmount)();
        oraclize.__grabCurrentPriceFromOraclize(i);
      }
    }
  }

  /**
   * Ends the Waiting phase.
   */
  function endWaitingTime() public during(CyclePhase.Waiting) whenNotPaused {
    require(now >= startTimeOfCyclePhase.add(timeOfWaiting));

    //Update values
    startTimeOfCyclePhase = now;
    cyclePhase = CyclePhase.Ended;

    //Sell all invested tokens
    for (uint256 i = 0; i < proposals.length; i = i.add(1)) {
      if (proposals[i].numFor > 0) { //Ensure proposal isn't a deleted one
        oraclize.__grabCurrentPriceFromOraclize(i);
      }
    }

    //Emit event
    CycleEnded(cycleNumber, now);
  }

  /**
   * Finalize the cycle by redistributing user balances and settling investment proposals.
   */
  function finalizeCycle() public during(CyclePhase.Ended) whenNotPaused {
    require(now >= startTimeOfCyclePhase.add(timeOfSellOrderWaiting));

    //Update cycle values
    startTimeOfCyclePhase = now;
    cyclePhase = CyclePhase.Finalized;

    //Settle investment proposal results
    for (uint256 proposalId = 0; proposalId < proposals.length; proposalId = proposalId.add(1)) {
      if (proposals[proposalId].numFor > 0) { //Ensure proposal isn't a deleted one
        __settleBets(proposalId);
      }
    }
    //Burn any Kairo left in BetokenFund's account
    cToken.burnOwnerBalance();

    //Withdraw from etherdelta
    uint256 balance = etherDelta.tokens(address(0), address(this));
    etherDelta.withdraw(balance);

    //Get all remaining funds from OraclizeHandler
    oraclize.__returnAllFunds();

    //Distribute funds
    __distributeFundsAfterCycleEnd();

    //Emit event
    CycleFinalized(cycleNumber, now);
  }

  /**
   * Settles an investment proposal in terms of profitability.
   * @param _proposalId ID of the proposal
   */
  function __settleBets(uint256 _proposalId) internal {
    Proposal storage prop = proposals[_proposalId];

    //Prevent divide by zero errors
    if (prop.buyPriceInWeis == 0 || cToken.totalSupply() == 0) {
      __returnStakes(_proposalId);
      return;
    }

    uint256 stake;
    uint256 j;
    address participant;
    uint256 investAmount = totalFundsInWeis.mul(forStakedControlOfProposal[_proposalId]).div(cToken.totalSupply());

    //Check if sell order has been partially or completely filled
    if (etherDelta.amountFilled(prop.tokenAddress, investAmount.mul(10**prop.tokenDecimals).div(prop.buyPriceInWeis), address(0), investAmount, prop.sellOrderExpirationBlockNum, _proposalId, address(this), 0, 0, 0) != 0) {
      if (prop.sellPriceInWeis > prop.buyPriceInWeis) {
        //For wins
        for (j = 0; j < participants.length; j = j.add(1)) {
          participant = participants[j];
          stake = forStakedControlOfProposalOfUser[_proposalId][participant];
          if (stake > 0) {
            //Give control tokens
            cToken.transfer(participant, stake.mul(2));
            //Emit event
            PredictionResult(cycleNumber, participant, true);
          } else {
            //Check if participant staked against
            if (againstStakedControlOfProposalOfUser[_proposalId][participant] > 0) {
              //Emit event
              PredictionResult(cycleNumber, participant, false);
            }
          }
        }
      } else {
        //Against wins
        if (prop.numAgainst > 0) {
          for (j = 0; j < participants.length; j = j.add(1)) {
            participant = participants[j];
            stake = againstStakedControlOfProposalOfUser[_proposalId][participant];
            if (stake > 0) {
              //Give control tokens
              cToken.transfer(participant, stake.mul(2));
              //Emit event
              PredictionResult(cycleNumber, participant, true);
            } else {
              //Check if participant staked for
              if (forStakedControlOfProposalOfUser[_proposalId][participant] > 0) {
                //Emit event
                PredictionResult(cycleNumber, participant, false);
              }
            }
          }
        } else {
          //Everyone f'ed up somehow. No point in punishing. Return stakes.
          __returnStakes(_proposalId);
        }
      }
    } else {
      //Buy order failed completely. Give back stakes.
      __returnStakes(_proposalId);
    }
  }

  /**
   * Returns all stakes of a proposal
   * @param _proposalId ID of a proposal
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
   * Distributes the funds accourding to previously held proportions. Pays commission to Kairo holders,
   * developer fees to developers, and oraclize fee to OraclizeHandler.
   */
  function __distributeFundsAfterCycleEnd() internal {
    uint256 totalCommission = commissionRate.mul(this.balance).div(tenToDecimals);
    uint256 devFee = developerFeeProportion.mul(this.balance).div(tenToDecimals);
    uint256 oraclizeFee = oraclize.__oraclizeFee().mul(maxProposals).mul(2);
    uint256 newTotalRegularFunds = this.balance.sub(totalCommission).sub(devFee);
    if (oraclizeFee <= newTotalRegularFunds) {
      newTotalRegularFunds = newTotalRegularFunds.sub(oraclizeFee);
    }

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
      newBalance = newBalance.add(totalCommission.mul(cToken.balanceOf(participant)).div(cToken.totalSupply()));
      //Update balance
      balanceOf[participant] = newBalance;
    }

    //Update values
    uint256 newTotalFunds = newTotalRegularFunds.add(totalCommission);
    ROI(cycleNumber, totalFundsInWeis, newTotalFunds);
    totalFundsInWeis = newTotalFunds;

    //Transfer fees
    developerFeeAccount.transfer(devFee);
    oraclize.transfer(oraclizeFee);

    //Emit event
    CommissionPaid(cycleNumber, totalCommission);
  }

  /**
   * Internal use functions
   */

  function __addControlTokenReceipientAsParticipant(address _receipient) public {
    require(msg.sender == controlTokenAddr);
    isParticipant[_receipient] = true;
    participants.push(_receipient);
  }

  function __makeOrder(address _tokenGet, uint _amountGet, address _tokenGive, uint _amountGive, uint _expires, uint _nonce) public onlyOraclize whenNotPaused {
    etherDelta.order(_tokenGet, _amountGet, _tokenGive, _amountGive, _expires, _nonce);
  }

  function __setBuyPriceAndExpirationBlock(uint256 _proposalId, uint256 _buyPrice, uint256 _expires) public onlyOraclize {
    proposals[_proposalId].buyPriceInWeis = _buyPrice;
    proposals[_proposalId].buyOrderExpirationBlockNum = _expires;
  }

  function __setSellPriceAndExpirationBlock(uint256 _proposalId, uint256 _sellPrice, uint256 _expires) public onlyOraclize {
    proposals[_proposalId].sellPriceInWeis = _sellPrice;
    proposals[_proposalId].sellOrderExpirationBlockNum = _expires;
  }

  function() public payable {
    if (msg.sender != etherDeltaAddr && msg.sender != oraclizeAddr) {
      revert();
    }
  }
}

/**
 * Contract that handles all Oraclize related operations.
 */
contract OraclizeHandler is usingOraclize, Ownable {
  using SafeMath for uint256;

  enum CyclePhase { ChangeMaking, ProposalMaking, Waiting, Ended, Finalized }

  //URL parts used for Oraclize queries.
  string public priceCheckURL1;
  string public priceCheckURL2;
  string public currencySymbol;

  //Addresses of other contracts.
  address public controlTokenAddr;
  address public etherDeltaAddr;

  //mapping(queryHash => proposalId)
  mapping(bytes32 => uint256) public proposalIdOfQuery;

  //References to other contracts.
  BetokenFund internal betokenFund;
  ControlToken internal cToken;
  EtherDelta internal etherDelta;

  //Stores the token symbols of each proposal.
  string[] public tokenSymbolOfProposal;

  function OraclizeHandler(
    address _controlTokenAddr,
    address _etherDeltaAddr,
    string _priceCheckURL1,
    string _priceCheckURL2
  )
    public
  {
    controlTokenAddr = _controlTokenAddr;
    etherDeltaAddr = _etherDeltaAddr;
    cToken = ControlToken(_controlTokenAddr);
    etherDelta = EtherDelta(_etherDeltaAddr);

    priceCheckURL1 = _priceCheckURL1;
    priceCheckURL2 = _priceCheckURL2;
  }

  function __changeEtherDeltaAddress(address _newAddr) public onlyOwner {
    etherDeltaAddr = _newAddr;
    etherDelta = EtherDelta(_newAddr);
  }

  function __pushTokenSymbolOfProposal(string _tokenSymbol) public onlyOwner {
    tokenSymbolOfProposal.push(_tokenSymbol);
  }

  function __deleteTokenSymbolOfProposal() public onlyOwner {
    delete tokenSymbolOfProposal;
  }

  function __returnAllFunds() public onlyOwner {
    owner.transfer(this.balance);
  }

  function __oraclizeFee() public view returns(uint256) {
    return oraclize_getPrice("URL");
  }

  /**
   * Oraclize functions
   */

  /**
   * Queries the price of a proposal's token using Oraclize.
   * @param _proposalId ID of the proposal
   */
  function __grabCurrentPriceFromOraclize(uint _proposalId) public payable onlyOwner {
    require(oraclize_getPrice("URL") <= this.balance);

    betokenFund = BetokenFund(owner);

    //Generate query
    string storage tokenSymbol = tokenSymbolOfProposal[_proposalId];
    string memory urlToQuery = strConcat(priceCheckURL1, tokenSymbol, priceCheckURL2);

    //Call Oraclize to grab the most recent price information
    proposalIdOfQuery[oraclize_query("URL", urlToQuery)] = _proposalId;
  }

  /**
   * Callback function for Oraclize queries.
   * @param _myID query ID
   * @param _result  result of query
   */
  function __callback(bytes32 _myID, string _result) public {
    require(msg.sender == oraclize_cbAddress());
    require(keccak256(_result) != keccak256(""));

    //Update BetokenFund contract in case owner has changed
    betokenFund = BetokenFund(owner);

    //Grab ETH price in Weis
    uint256 priceInWeis = parseInt(_result, 18);

    //Get proposal data
    uint256 proposalId = proposalIdOfQuery[_myID];
    var (tokenAddress, _, decimals,) = betokenFund.proposals(proposalId);

    uint256 investAmount = betokenFund.totalFundsInWeis().mul(betokenFund.forStakedControlOfProposal(proposalId)).div(cToken.totalSupply());
    uint256 expires = block.number.add(betokenFund.orderExpirationTimeInBlocks());
    if (uint(betokenFund.cyclePhase()) == uint(CyclePhase.Waiting)) {
      //Make buy orders
      betokenFund.__setBuyPriceAndExpirationBlock(proposalId, priceInWeis, expires);
      uint256 buyTokenAmount = investAmount.mul(10**decimals).div(priceInWeis);
      betokenFund.__makeOrder(tokenAddress, buyTokenAmount, address(0), investAmount, expires, proposalId);
    } else if (uint(betokenFund.cyclePhase()) == uint(CyclePhase.Ended)) {
      //Make sell orders
      betokenFund.__setSellPriceAndExpirationBlock(proposalId, priceInWeis, expires);
      uint256 sellTokenAmount = etherDelta.tokens(tokenAddress, owner);
      uint256 getWeiAmount = sellTokenAmount.mul(priceInWeis).div(10**decimals);
      betokenFund.__makeOrder(address(0), getWeiAmount, tokenAddress, sellTokenAmount, expires, proposalId);
    }

    //Reset data
    delete proposalIdOfQuery[_myID];
  }

  function() public payable {
    if (msg.sender != owner) {
      revert();
    }
  }
}

/**
 * ERC20 token contract for Kairo.
 */
contract ControlToken is MintableToken {
  using SafeMath for uint256;

  string public constant name = "Kairo";
  string public constant symbol = "KRO";
  uint8 public constant decimals = 18;

  event OwnerCollectFrom(address _from, uint256 _value);

  /**
   * Transfer token for a specified address
   * @param _to The address to transfer to.
   * @param _value The amount to be transferred.
   */
  function transfer(address _to, uint256 _value) public returns(bool) {
    require(_to != address(0));
    require(_value <= balances[msg.sender]);

    //Add receipient as a participant if not already a participant
    addParticipant(_to);

    // SafeMath.sub will throw if there is not enough balance.
    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
    Transfer(msg.sender, _to, _value);
    return true;
  }

  /**
   * Transfer tokens from one address to another
   * @param _from The address which you want to send tokens from
   * @param _to The address which you want to transfer to
   * @param _value the amount of tokens to be transferred
   */
  function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
    require(_to != address(0));
    require(_value <= balances[_from]);
    require(_value <= allowed[_from][msg.sender]);

    //Add receipient as a participant if not already a participant
    addParticipant(_to);

    balances[_from] = balances[_from].sub(_value);
    balances[_to] = balances[_to].add(_value);
    allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
    Transfer(_from, _to, _value);
    return true;
  }

  /**
   * Collects tokens for the owner.
   * @param _from The address which you want to send tokens from
   * @param _value the amount of tokens to be transferred
   * @return true if succeeded, false otherwise
   */
  function ownerCollectFrom(address _from, uint256 _value) public onlyOwner returns(bool) {
    require(_from != address(0));
    require(_value <= balances[_from]);

    // SafeMath.sub will throw if there is not enough balance.
    balances[_from] = balances[_from].sub(_value);
    balances[msg.sender] = balances[msg.sender].add(_value);
    OwnerCollectFrom(_from, _value);
    return true;
  }

  /**
   * Adds an address as a BetokenFund participant.
   * @param  _to the address to be added
   */
  function addParticipant(address _to) internal {
    BetokenFund groupFund = BetokenFund(owner);
    if (!groupFund.isParticipant(_to)) {
      groupFund.__addControlTokenReceipientAsParticipant(_to);
    }
  }

  /**
   * Burns the owner's token balance.
   */
  function burnOwnerBalance() public onlyOwner {
    totalSupply_ = totalSupply_.sub(balances[owner]);
    balances[owner] = 0;
  }

  function() public {
    revert();
  }
}
