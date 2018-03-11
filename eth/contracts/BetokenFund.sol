pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/math/Math.sol';
import 'zeppelin-solidity/contracts/lifecycle/Pausable.sol';
import './ControlToken.sol';
import './ShareToken.sol';
import './KyberNetwork.sol';
import './Utils.sol';

/**
 * The main contract of the Betoken hedge fund
 */
contract BetokenFund is Pausable, Utils {
  using SafeMath for uint256;

  enum CyclePhase { ChangeMaking, Waiting, Finalizing, Finalized }

  struct Proposal {
    address tokenAddress;
    uint256 buyPriceInWeis;
    uint256 sellPriceInWeis;
    uint256 numFor;
    uint256 numAgainst;
    bool isSold;
  }

  /**
   * @dev Executes function only during the given cycle phase.
   * @param phase the cycle phase during which the function may be called
   */
  modifier during(CyclePhase phase) {
    require(cyclePhase == phase);
    _;
  }

  modifier rewardCaller {
    cToken.mint(msg.sender, functionCallReward);
    _;
  }

  //Address of the control token contract.
  address public controlTokenAddr;

  //Address of the share token contract.
  address public shareTokenAddr;

  //Address of the KyberNetwork contract
  address public kyberAddr;

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

  //Temporal length of waiting period, in seconds.
  uint256 public timeOfWaiting;

  uint256 public timeOfFinalizing;

  uint256 public timeBetweenCycles;

  //Minimum proportion of Kairo balance people have to stake in support of a proposal. Fixed point decimal.
  uint256 public minStakeProportion;

  //The proportion of the fund that gets distributed to Kairo holders every cycle. Fixed point decimal.
  uint256 public commissionRate;

  //The proportion of contract balance that goes the the devs every cycle. Fixed point decimal.
  uint256 public developerFeeProportion;

  //Total Kairo staked in support of proposals this cycle.
  uint256 public cycleTotalForStake;

  //Amount of Kairo rewarded to the user who calls a phase transition/proposal handling function
  uint256 public functionCallReward;

  //Amount of commission to be paid out this cycle
  uint256 public totalCommission;

  //Flag for whether emergency withdrawing is allowed.
  bool public allowEmergencyWithdraw;

  //Mapping from Proposal to total amount of Control Tokens being staked by supporters.
  mapping(uint256 => uint256) public forStakedControlOfProposal;
  mapping(uint256 => uint256) public againstStakedControlOfProposal;

  //mapping(proposalId => mapping(participantAddress => stakedTokensInWeis))
  mapping(uint256 => mapping(address => uint256)) public forStakedControlOfProposalOfUser;
  mapping(uint256 => mapping(address => uint256)) public againstStakedControlOfProposalOfUser;

  //Mapping to check if a proposal for a token has already been made.
  mapping(address => bool) public isTokenAlreadyProposed;

  //The last cycle where a user redeemed commission.
  mapping(address => uint256) public lastCommissionRedemption;

  //List of proposals in the current cycle.
  Proposal[] public proposals;

  //The current cycle phase.
  CyclePhase public cyclePhase;

  //Contract instances
  ControlToken internal cToken;
  ShareToken internal sToken;
  KyberNetwork internal kyber;

  event CycleStarted(uint256 _cycleNumber, uint256 _timestamp);
  event Deposit(uint256 _cycleNumber, address _sender, uint256 _amountInWeis, uint256 _timestamp);
  event Withdraw(uint256 _cycleNumber, address _sender, uint256 _amountInWeis, uint256 _timestamp);
  event NewProposal(uint256 _cycleNumber, uint256 _id, address _tokenAddress, uint256 _stakeInWeis);
  event StakedProposal(uint256 _cycleNumber, uint256 _id, uint256 _stakeInWeis, bool _support);
  event ChangeMakingTimeEnded(uint256 _cycleNumber, uint256 _timestamp);

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
    address _cTokenAddr,
    address _sTokenAddr,
    address _kyberAddr,
    address _developerFeeAccount,
    uint256 _timeOfChangeMaking,
    uint256 _timeOfWaiting,
    uint256 _timeOfFinalizing,
    uint256 _timeBetweenCycles,
    uint256 _minStakeProportion,
    uint256 _commissionRate,
    uint256 _developerFeeProportion,
    uint256 _cycleNumber,
    uint256 _functionCallReward
  )
    public
  {
    require(_minStakeProportion < 10**18);
    require(_commissionRate.add(_developerFeeProportion) < 10**18);

    controlTokenAddr = _cTokenAddr;
    shareTokenAddr = _sTokenAddr;
    kyberAddr = _kyberAddr;
    cToken = ControlToken(_cTokenAddr);
    sToken = ShareToken(_sTokenAddr);
    kyber = KyberNetwork(_kyberAddr);

    developerFeeAccount = _developerFeeAccount;
    timeOfChangeMaking = _timeOfChangeMaking;
    timeOfWaiting = _timeOfWaiting;
    timeOfFinalizing = _timeOfFinalizing;
    timeBetweenCycles = _timeBetweenCycles;
    minStakeProportion = _minStakeProportion;
    commissionRate = _commissionRate;
    developerFeeProportion = _developerFeeProportion;
    startTimeOfCyclePhase = 0;
    cyclePhase = CyclePhase.Finalized;
    cycleNumber = _cycleNumber;
    functionCallReward = _functionCallReward;
    allowEmergencyWithdraw = false;
  }

  /**
   * Getters
   */

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
   * @dev In case the fund is invested in tokens, sell all tokens.
   */
  function emergencyDumpAllTokens() onlyOwner whenPaused public {
    for (uint256 i = 0; i < proposals.length; i = i.add(1)) {
      emergencyDumpToken(i);
    }
  }

  function emergencyDumpToken(uint256 _proposalId) onlyOwner whenPaused public {
    if (__proposalIsValid(_proposalId)) { //Ensure proposal isn't a deleted one
      __handleInvestment(_proposalId, false);
    }
  }

  /**
   * @dev Return staked Kairos for a proposal under emergency situations.
   */
  function emergencyRedeemStake(uint256 _proposalId) whenPaused public {
    require(allowEmergencyWithdraw);
    uint256 stake = forStakedControlOfProposalOfUser[_proposalId][msg.sender].add(againstStakedControlOfProposalOfUser[_proposalId][msg.sender]);
    forStakedControlOfProposalOfUser[_proposalId][msg.sender] = 0;
    againstStakedControlOfProposalOfUser[_proposalId][msg.sender] = 0;
    cToken.transfer(msg.sender, stake);
  }

  /**
   * @dev Update current fund balance
   */
  function emergencyRedistBalances() onlyOwner whenPaused public {
    totalFundsInWeis = this.balance;
  }

  function setAllowEmergencyWithdraw(bool _val) onlyOwner whenPaused public {
    allowEmergencyWithdraw = _val;
  }

  /**
   * @dev Function for withdrawing all funds in times of emergency. Only callable when fund is paused.
   */
  function emergencyWithdraw()
    public
    whenPaused
  {
    require(allowEmergencyWithdraw);

    uint256 amountInWeis = sToken.balanceOf(msg.sender).mul(totalFundsInWeis).div(sToken.totalSupply());
    sToken.ownerBurn(msg.sender, sToken.balanceOf(msg.sender));
    totalFundsInWeis = totalFundsInWeis.sub(amountInWeis);

    //Transfer
    msg.sender.transfer(amountInWeis);

    //Emit event
    Withdraw(cycleNumber, msg.sender, amountInWeis, now);
  }

  /**
   * Parameter setters
   */

  /**
   * @dev Changes the address of the KyberNetwork contract used in the contract. Only callable by owner.
   * @param _newAddr new address of KyberNetwork contract
   */
  function changeKyberNetworkAddress(address _newAddr) public onlyOwner whenPaused {
    require(_newAddr != address(0));
    kyberAddr = _newAddr;
    kyber = KyberNetwork(_newAddr);
  }

  /**
   * @dev Changes the address to which the developer fees will be sent. Only callable by owner.
   * @param _newAddr new developer fee address
   */
  function changeDeveloperFeeAccount(address _newAddr) public onlyOwner {
    require(_newAddr != address(0));
    developerFeeAccount = _newAddr;
  }

  /**
   * @dev Changes the proportion of fund balance sent to the developers each cycle. May only decrease. Only callable by owner.
   * @param _newProp the new proportion, fixed point decimal
   */
  function changeDeveloperFeeProportion(uint256 _newProp) public onlyOwner {
    require(_newProp < developerFeeProportion);
    developerFeeProportion = _newProp;
  }

  /**
   * @dev Changes the proportion of fund balance given to Kairo holders each cycle. Only callable by owner.
   * @param _newProp the new proportion, fixed point decimal
   */
  function changeCommissionRate(uint256 _newProp) public onlyOwner {
    commissionRate = _newProp;
  }

  /**
   * @dev Changes the owner of the ControlToken contract.
   * @param  _newOwner the new owner address
   */
  function changeControlTokenOwner(address _newOwner) public onlyOwner whenPaused {
    require(_newOwner != address(0));
    cToken.transferOwnership(_newOwner);
  }

  /**
   * @dev Changes the owner of the ShareToken contract.
   * @param  _newOwner the new owner address
   */
  function changeShareTokenOwner(address _newOwner) public onlyOwner whenPaused {
    require(_newOwner != address(0));
    sToken.transferOwnership(_newOwner);
  }

  /**
   * Start cycle functions
   */

  /**
   * @dev Starts a new investment cycle.
   */
  function startNewCycle() public during(CyclePhase.Finalized) whenNotPaused rewardCaller {
    require(now >= startTimeOfCyclePhase.add(timeBetweenCycles));

    //Update values
    cyclePhase = CyclePhase.ChangeMaking;
    startTimeOfCyclePhase = now;
    cycleNumber = cycleNumber.add(1);

    if (cToken.paused()) {
      cToken.unpause();
    }

    //Reset data
    for (uint256 i = 0; i < proposals.length; i = i.add(1)) {
      __resetProposalData(i);
    }
    delete proposals;
    delete cycleTotalForStake;

    //Emit event
    CycleStarted(cycleNumber, now);
  }

  /**
   * @dev Resets cycle specific data for a give proposal
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
   * @dev Deposit Ether into the fund.
   */
  function deposit()
    public
    payable
    during(CyclePhase.ChangeMaking)
    whenNotPaused
  {
    //Register investment
    if (cycleNumber == 1) {
      sToken.mint(msg.sender, msg.value);
    } else {
      sToken.mint(msg.sender, msg.value.mul(sToken.totalSupply()).div(totalFundsInWeis));
    }
    totalFundsInWeis = totalFundsInWeis.add(msg.value);

    //Give control tokens proportional to investment
    //Uncomment if statement if not test version
    //if (cycleNumber == 1) {
      cToken.mint(msg.sender, msg.value);
    //}

    //Emit event
    Deposit(cycleNumber, msg.sender, msg.value, now);
  }

  /**
   * @dev Withdraws a certain amount of Ether from the user's account. Cannot be called during the first cycle.
   * @param _amountInWeis amount of Ether to be withdrawn
   */
  function withdraw(uint256 _amountInWeis)
    public
    during(CyclePhase.ChangeMaking)
    whenNotPaused
  {
    require(cycleNumber != 1);

    //Subtract from account
    sToken.ownerBurn(msg.sender, _amountInWeis.mul(sToken.totalSupply()).div(totalFundsInWeis));
    totalFundsInWeis = totalFundsInWeis.sub(_amountInWeis);

    //Transfer Ether to user
    msg.sender.transfer(_amountInWeis);

    //Emit event
    Withdraw(cycleNumber, msg.sender, _amountInWeis, now);
  }

  /**
   * @dev Creates a new investment proposal for an ERC20 token.
   * @param _tokenAddress address of the ERC20 token contract
   * @param _stakeInWeis amount of Kairos to be staked in support of the proposal
   */
  function createProposal(
    address _tokenAddress,
    uint256 _stakeInWeis
  )
    public
    during(CyclePhase.ChangeMaking)
    whenNotPaused
  {
    require(!isTokenAlreadyProposed[_tokenAddress]);

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

    //Stake control tokens
    uint256 proposalId = proposals.length - 1;
    stakeProposal(proposalId, _stakeInWeis, true);

    //Emit event
    NewProposal(cycleNumber, proposalId, _tokenAddress, _stakeInWeis);
  }

  /**
   * @dev Stakes for or against an investment proposal.
   * @param _proposalId ID of the proposal the user wants to support
   * @param _stakeInWeis amount of Kairo to be staked in support of the proposal
   */
  function stakeProposal(uint256 _proposalId, uint256 _stakeInWeis, bool _support)
    public
    during(CyclePhase.ChangeMaking)
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

    //Emit event
    StakedProposal(cycleNumber, _proposalId, _stakeInWeis, _support);
  }

  /**
   * @dev Cancels staking in a proposal.
   * @param _proposalId ID of the proposal
   */
  function cancelProposalStake(uint256 _proposalId)
    public
    during(CyclePhase.ChangeMaking)
    whenNotPaused
  {
    require(_proposalId < proposals.length); //Valid ID
    require(__proposalIsValid(_proposalId)); //Non-empty proposal

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

    delete forStakedControlOfProposalOfUser[_proposalId][msg.sender];
    delete againstStakedControlOfProposalOfUser[_proposalId][msg.sender];

    //Return stake
    cToken.transfer(msg.sender, stake);

    //Delete proposal if necessary
    if (proposals[_proposalId].numFor == 0) {
      //TODO return stakes
      __resetProposalData(_proposalId);
      delete proposals[_proposalId];
    }
  }

  /**
   * @dev Ends the ChangeMaking phase.
   */
  function endChangeMakingTime() public during(CyclePhase.ChangeMaking) whenNotPaused rewardCaller {
    require(now >= startTimeOfCyclePhase.add(timeOfChangeMaking));

    startTimeOfCyclePhase = now;
    cyclePhase = CyclePhase.Waiting;

    ChangeMakingTimeEnded(cycleNumber, now);
  }

  /**
   * Waiting phase functions
   */

  /**
   * @dev Called by user to buy the assets of a proposal
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
    cyclePhase = CyclePhase.Finalizing;

    WaitingPhaseEnded(cycleNumber, now);
  }

  /**
   * Finalizing phase functions
   */

  /**
   * @dev Called by user to sell the assets a proposal invested in
   * @param _proposalId the ID of the proposal
   */
  function sellProposalAsset(uint256 _proposalId)
    public
    during(CyclePhase.Finalizing)
    whenNotPaused
    rewardCaller
  {
    require(__proposalIsValid(_proposalId));
    require(proposals[_proposalId].buyPriceInWeis > 0);
    __handleInvestment(_proposalId, false);
    proposals[_proposalId].isSold = true;
  }

  /**
   * @dev Redeems the Kairo stake and reward for a particular proposal
   * @param _proposalId the ID of the proposal
   */
  function redeemKairos(uint256 _proposalId)
    public
    during(CyclePhase.Finalizing)
    whenNotPaused
  {
    Proposal storage prop = proposals[_proposalId];
    require(prop.isSold);

    uint256 forMultiplier = prop.sellPriceInWeis.mul(PRECISION).div(prop.buyPriceInWeis);
    uint256 againstMultiplier = 0;
    if (prop.sellPriceInWeis < prop.buyPriceInWeis.mul(2)) {
      againstMultiplier = prop.buyPriceInWeis.mul(2).sub(prop.sellPriceInWeis).mul(PRECISION).div(prop.buyPriceInWeis);
    }

    uint256 stake = 0;
    if (forStakedControlOfProposalOfUser[_proposalId][msg.sender] > 0) {
      //User supports proposal
      stake = forStakedControlOfProposalOfUser[_proposalId][msg.sender];
      //Mint instead of transfer. Ensures that there are always enough tokens.
      //Extra will be burnt right after so no problem there.
      cToken.mint(msg.sender, stake.mul(forMultiplier).div(PRECISION));
      delete forStakedControlOfProposalOfUser[_proposalId][msg.sender];
    } else if (againstStakedControlOfProposalOfUser[_proposalId][msg.sender] > 0) {
      //User is against proposal
      stake = againstStakedControlOfProposalOfUser[_proposalId][msg.sender];
      //Mint instead of transfer. Ensures that there are always enough tokens.
      //Extra will be burnt right after so no problem there.
      cToken.mint(msg.sender, stake.mul(againstMultiplier).div(PRECISION));
      delete againstStakedControlOfProposalOfUser[_proposalId][msg.sender];
    }
  }

  /**
   * @dev Finalize the cycle by redistributing user balances and settling investment proposals.
   */
  function finalizeCycle() public during(CyclePhase.Finalizing) whenNotPaused rewardCaller {
    require(now >= startTimeOfCyclePhase.add(timeOfFinalizing));

    //Update cycle values
    startTimeOfCyclePhase = now;
    cyclePhase = CyclePhase.Finalized;

    //Burn any Kairo left in BetokenFund's account
    cToken.burnOwnerBalance();

    cToken.pause();

    //Distribute funds
    __distributeFundsAfterCycleEnd();

    //Emit event
    CycleFinalized(cycleNumber, now);
  }

  /**
   * Finalized phase functions
   */

  function redeemCommission()
    public
    during(CyclePhase.Finalized)
    whenNotPaused
  {
    require(lastCommissionRedemption[msg.sender] < cycleNumber);
    lastCommissionRedemption[msg.sender] = cycleNumber;
    msg.sender.transfer(totalCommission.mul(cToken.balanceOf(msg.sender)).div(cToken.totalSupply()));
  }

  /**
   * Internal use functions
   */

  function __proposalIsValid(uint256 _proposalId) internal view returns (bool) {
    return proposals[_proposalId].numFor > 0;
  }

  /**
   * @dev Distributes the funds accourding to previously held proportions. Pays commission to Kairo holders,
   * and developer fees to developers.
   */
  function __distributeFundsAfterCycleEnd() internal {
    uint256 profit = 0;
    if (this.balance > totalFundsInWeis) {
      profit = this.balance - totalFundsInWeis;
    }
    totalCommission = commissionRate.mul(profit).div(PRECISION);
    uint256 devFee = developerFeeProportion.mul(this.balance).div(PRECISION);
    uint256 newTotalFunds = this.balance.sub(totalCommission).sub(devFee);

    //Update values
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