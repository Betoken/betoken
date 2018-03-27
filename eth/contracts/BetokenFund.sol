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

  enum CyclePhase { ChangeMaking, ProposalMaking, Waiting, Finalizing, Finalized }

  struct Proposal {
    address tokenAddress;
    uint256 cycleNumber;
    uint256 stake;
    uint256 tokenAmount;
    uint256 buyPriceInWeis;
    uint256 sellPriceInWeis;
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

  // Address of the control token contract.
  address public controlTokenAddr;

  // Address of the share token contract.
  address public shareTokenAddr;

  // Address of the KyberNetwork contract
  address public kyberAddr;

  // Address to which the developer fees will be paid.
  address public developerFeeAccount;

  // The number of the current investment cycle.
  uint256 public cycleNumber;

  // 10^{decimals} used for representing fixed point numbers with {decimals} decimals.
  uint256 public PRECISION;

  // The amount of funds held by the fund.
  uint256 public totalFundsInWeis;

  // The start time for the current investment cycle phase, in seconds since Unix epoch.
  uint256 public startTimeOfCyclePhase;

  // Temporal length of change making period at start of each cycle, in seconds.
  uint256 public timeOfChangeMaking;

  uint256 public timeOfProposalMaking;

  // Temporal length of waiting period, in seconds.
  uint256 public timeOfWaiting;

  uint256 public timeOfFinalizing;

  uint256 public timeBetweenCycles;

  // Minimum proportion of Kairo balance people have to stake in support of a proposal. Fixed point decimal.
  uint256 public minStakeProportion;

  // The proportion of the fund that gets distributed to Kairo holders every cycle. Fixed point decimal.
  uint256 public commissionRate;

  // The proportion of contract balance that goes the the devs every cycle. Fixed point decimal.
  uint256 public developerFeeProportion;

  // Amount of Kairo rewarded to the user who calls a phase transition/proposal handling function
  uint256 public functionCallReward;

  // Amount of commission to be paid out this cycle
  uint256 public totalCommission;

  // Inflation rate of control token (KRO). Fixed point decimal.
  uint256 public controlTokenInflation;

  // The AUM (Asset Under Management) threshold for progressing to ProposalMakingTime in the first cycle.
  uint256 public aumThresholdInWeis;

  // Flag for whether emergency withdrawing is allowed.
  bool public allowEmergencyWithdraw;

  // The last cycle where a user redeemed commission.
  mapping(address => uint256) public lastCommissionRedemption;

  // List of proposals in the current cycle.
  mapping(address => Proposal[]) public userProposals;

  // The current cycle phase.
  CyclePhase public cyclePhase;

  // Contract instances
  ControlToken internal cToken;
  ShareToken internal sToken;
  KyberNetwork internal kyber;

  event CycleStarted(uint256 indexed _cycleNumber, uint256 _timestamp);
  event Deposit(uint256 indexed _cycleNumber, address indexed _sender, uint256 _amountInWeis, uint256 _timestamp);
  event Withdraw(uint256 indexed _cycleNumber, address indexed _sender, uint256 _amountInWeis, uint256 _timestamp);
  event ChangeMakingTimeEnded(uint256 indexed _cycleNumber, uint256 _timestamp);

  event NewProposal(uint256 indexed _cycleNumber, address indexed _sender, uint256 _id, address _tokenAddress, uint256 _stakeInWeis);
  event ProposalMakingTimeEnded(uint256 indexed _cycleNumber, uint256 _timestamp);

  event WaitingPhaseEnded(uint256 indexed _cycleNumber, uint256 _timestamp);

  event ProposalSold(uint256 indexed _cycleNumber, address indexed _sender, uint256 _proposalId, uint256 _receivedKairos);
  event SellingPhaseEnded(uint256 indexed _cycleNumber, uint256 _timestamp);

  event ROI(uint256 indexed _cycleNumber, uint256 _beforeTotalFunds, uint256 _afterTotalFunds);
  event CommissionPaid(uint256 indexed _cycleNumber, address indexed _sender, uint256 _commission);
  event TotalCommissionPaid(uint256 indexed _cycleNumber, uint256 _totalCommissionInWeis);
  event CycleFinalized(uint256 indexed _cycleNumber, uint256 _timestamp);

  /**
   * Contract initialization functions
   */

  // Constructor
  function BetokenFund(
    address _cTokenAddr,
    address _sTokenAddr,
    address _kyberAddr,
    address _developerFeeAccount,
    uint256 _timeOfChangeMaking,
    uint256 _timeOfProposalMaking,
    uint256 _timeOfWaiting,
    uint256 _timeOfFinalizing,
    uint256 _timeBetweenCycles,
    uint256 _minStakeProportion,
    uint256 _commissionRate,
    uint256 _developerFeeProportion,
    uint256 _cycleNumber,
    uint256 _functionCallReward,
    uint256 _controlTokenInflation,
    uint256 _aumThresholdInWeis
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
    timeOfProposalMaking = _timeOfProposalMaking;
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
    controlTokenInflation = _controlTokenInflation;
    aumThresholdInWeis = _aumThresholdInWeis;
    allowEmergencyWithdraw = false;
  }

  /**
   * Getters
   */

  /**
   * Returns the length of the proposals array.
   * @return length of proposals array
   */
  function proposalsCount(address _userAddr) public view returns(uint256 _count) {
    return userProposals[_userAddr].length;
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
  function emergencyDumpToken(address _tokenAddr)
    public
    onlyOwner
    during(CyclePhase.Finalized)
    whenPaused
  {
    __transactToken(_tokenAddr, ERC20(_tokenAddr).balanceOf(address(this)), false);
  }

  /**
   * @dev Return staked Kairos for a proposal under emergency situations.
   */
  function emergencyRedeemStake(uint256 _proposalId) whenPaused public {
    require(allowEmergencyWithdraw);
    Proposal storage prop = userProposals[msg.sender][_proposalId];
    require(prop.cycleNumber == cycleNumber);
    uint256 stake = prop.stake;
    require(stake > 0);
    delete prop.stake;
    cToken.transfer(msg.sender, stake);
  }

  /**
   * @dev Update current fund balance
   */
  function emergencyUpdateBalance() onlyOwner whenPaused public {
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

    // Transfer
    msg.sender.transfer(amountInWeis);

    // Emit event
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
   * @dev Changes the inflation rate of control tokens. Only callable by owner.
   * @param _newVal the new inflation value, fixed point decimal
   */
  function changeControlTokenInflation(uint256 _newVal) public onlyOwner {
    controlTokenInflation = _newVal;
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

    // Update values
    cyclePhase = CyclePhase.ChangeMaking;
    startTimeOfCyclePhase = now;
    cycleNumber = cycleNumber.add(1);

    if (cToken.paused()) {
      cToken.unpause();
    }

    // Emit event
    CycleStarted(cycleNumber, now);
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
    // Register investment
    if (cycleNumber == 1) {
      sToken.mint(msg.sender, msg.value);
    } else {
      sToken.mint(msg.sender, msg.value.mul(sToken.totalSupply()).div(totalFundsInWeis));
    }
    totalFundsInWeis = totalFundsInWeis.add(msg.value);

    // Give control tokens proportional to investment
    // Uncomment if statement if not test version
    // if (cycleNumber == 1) {
      cToken.mint(msg.sender, msg.value);
    // }

    // Emit event
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

    // Subtract from account
    sToken.ownerBurn(msg.sender, _amountInWeis.mul(sToken.totalSupply()).div(totalFundsInWeis));
    totalFundsInWeis = totalFundsInWeis.sub(_amountInWeis);

    // Transfer Ether to user
    msg.sender.transfer(_amountInWeis);

    // Emit event
    Withdraw(cycleNumber, msg.sender, _amountInWeis, now);
  }

  /**
   * @dev Ends the ChangeMaking phase.
   */
  function endChangeMakingTime() public during(CyclePhase.ChangeMaking) whenNotPaused rewardCaller {
    require(now >= startTimeOfCyclePhase.add(timeOfChangeMaking));

    if (cycleNumber == 1) {
      require(totalFundsInWeis >= aumThresholdInWeis);
    }

    startTimeOfCyclePhase = now;
    cyclePhase = CyclePhase.ProposalMaking;

    ChangeMakingTimeEnded(cycleNumber, now);
  }

  /**
   * Proposal Making time functions
   */

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
    during(CyclePhase.ProposalMaking)
    whenNotPaused
  {
    // Check if token is valid
    require(ERC20(_tokenAddress).totalSupply() > 0);

    // Collect stake
    cToken.ownerCollectFrom(msg.sender, _stakeInWeis);

    // Add proposal to list
    userProposals[msg.sender].push(Proposal({
      tokenAddress: _tokenAddress,
      cycleNumber: cycleNumber,
      stake: _stakeInWeis,
      tokenAmount: 0,
      buyPriceInWeis: 0,
      sellPriceInWeis: 0,
      isSold: false
    }));

    // Invest
    __handleInvestment(proposalsCount(msg.sender) - 1, true);

    // Emit event
    NewProposal(cycleNumber, msg.sender, proposalsCount(msg.sender) - 1, _tokenAddress, _stakeInWeis);
  }

  function endProposalMakingTime()
    public
    during(CyclePhase.ProposalMaking)
    whenNotPaused
    rewardCaller
  {
    require(now >= startTimeOfCyclePhase.add(timeOfProposalMaking));

    startTimeOfCyclePhase = now;
    cyclePhase = CyclePhase.Waiting;

    ProposalMakingTimeEnded(cycleNumber, now);
  }

  /**
   * Waiting phase functions
   */

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
  {
    Proposal storage prop = userProposals[msg.sender][_proposalId];
    require(prop.buyPriceInWeis > 0);
    require(prop.cycleNumber == cycleNumber);
    require(!prop.isSold);

    __handleInvestment(_proposalId, false);
    prop.isSold = true;

    uint256 multiplier = prop.sellPriceInWeis.mul(PRECISION).div(prop.buyPriceInWeis).add(controlTokenInflation);
    uint256 receiveKairoAmount = prop.stake.mul(multiplier).div(PRECISION);
    cToken.mint(msg.sender, receiveKairoAmount);

    ProposalSold(cycleNumber, msg.sender, _proposalId, receiveKairoAmount);
  }

  /**
   * @dev Finalize the cycle by redistributing user balances and settling investment proposals.
   */
  function finalizeCycle() public during(CyclePhase.Finalizing) whenNotPaused rewardCaller {
    require(now >= startTimeOfCyclePhase.add(timeOfFinalizing));

    // Update cycle values
    startTimeOfCyclePhase = now;
    cyclePhase = CyclePhase.Finalized;

    // Burn any Kairo left in BetokenFund's account
    cToken.burnOwnerBalance();

    cToken.pause();

    // Distribute funds
    __distributeFundsAfterCycleEnd();

    // Emit event
    CycleFinalized(cycleNumber, now);
  }

  /**
   * Finalized phase functions
   */

  /**
   * @dev Redeems commission.
   */
  function redeemCommission()
    public
    during(CyclePhase.Finalized)
    whenNotPaused
  {
    require(lastCommissionRedemption[msg.sender] < cycleNumber);
    lastCommissionRedemption[msg.sender] = cycleNumber;
    uint256 commission = totalCommission.mul(cToken.balanceOf(msg.sender)).div(cToken.totalSupply());
    msg.sender.transfer(commission);

    // Reset data
    delete userProposals[msg.sender];

    CommissionPaid(cycleNumber, msg.sender, commission);
  }

  /**
   * @dev Sells tokens left over due to manager not selling or KyberNetwork not having enough demand.
   * @param _tokenAddr address of the token to be sold
   */
  function sellLeftoverToken(address _tokenAddr)
    public
    during(CyclePhase.Finalized)
    whenNotPaused
  {
    uint256 beforeBalance = this.balance;
    __transactToken(_tokenAddr, ERC20(_tokenAddr).balanceOf(address(this)), false);
    totalFundsInWeis = totalFundsInWeis.add(this.balance.sub(beforeBalance));
  }

  /**
   * Internal use functions
   */

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

    // Update values
    ROI(cycleNumber, totalFundsInWeis, newTotalFunds);
    totalFundsInWeis = newTotalFunds;

    // Transfer fees
    developerFeeAccount.transfer(devFee);

    // Emit event
    TotalCommissionPaid(cycleNumber, totalCommission);
  }

  function __handleInvestment(uint256 _proposalId, bool _buy) internal {
    Proposal storage prop = userProposals[msg.sender][_proposalId];
    uint256 srcAmount;
    if (_buy) {
      srcAmount = totalFundsInWeis.mul(prop.stake).div(cToken.totalSupply());
    } else {
      srcAmount = prop.tokenAmount;
    }
    uint256 actualRate = __transactToken(prop.tokenAddress, srcAmount, _buy);
    if (_buy) {
      prop.buyPriceInWeis = actualRate;
    } else {
      prop.sellPriceInWeis = actualRate;
    }
  }

  function __transactToken(address _tokenAddr, uint256 _srcAmount, bool _buy) internal returns(uint256 _actualRate) {
    uint256 actualDestAmount;
    uint256 beforeBalance;
    address destAddr = _tokenAddr;
    DetailedERC20 destToken = DetailedERC20(destAddr);

    if (_buy) {
      // Make buy orders

      beforeBalance = this.balance;

      // Do trade
      actualDestAmount = kyber.trade.value(_srcAmount)(
        ETH_TOKEN_ADDRESS,
        _srcAmount,
        destToken,
        address(this),
        MAX_QTY,
        1,
        0
      );

      // Record buy price
      require(actualDestAmount > 0);
      _actualRate = beforeBalance.sub(this.balance).mul(PRECISION).div(actualDestAmount);
    } else {
      // Make sell orders

      beforeBalance = destToken.balanceOf(address(this));

      // Do trade
      destToken.approve(kyberAddr, _srcAmount);
      actualDestAmount = kyber.trade(
        destToken,
        _srcAmount,
        ETH_TOKEN_ADDRESS,
        address(this),
        MAX_QTY,
        1,
        0
      );
      destToken.approve(kyberAddr, 0);

      // Record sell price
      require(beforeBalance > destToken.balanceOf(address(this)));
      _actualRate = actualDestAmount.mul(PRECISION).div(beforeBalance.sub(destToken.balanceOf(address(this))));
    }
  }

  function() public payable {
    if (msg.sender != kyberAddr) {
      revert();
    }
  }
}