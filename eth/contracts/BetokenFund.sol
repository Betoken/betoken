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

  enum CyclePhase { DepositWithdraw, MakeDecisions, RedeemCommission }

  struct Investment {
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

  // Address of the control token contract.
  address public controlTokenAddr;

  // Address of the share token contract.
  address public shareTokenAddr;

  // Address of the KyberNetwork contract
  address public kyberAddr;

  // Address to which the developer fees will be paid.
  address public developerFeeAccount;

  // Address of the DAI stable-coin contract.
  address public daiAddr;

  // The number of the current investment cycle.
  uint256 public cycleNumber;

  // The amount of funds held by the fund.
  uint256 public totalFundsInWeis;

  // The start time for the current investment cycle phase, in seconds since Unix epoch.
  uint256 public startTimeOfCyclePhase;

  // The proportion of the fund that gets distributed to Kairo holders every cycle. Fixed point decimal.
  uint256 public commissionRate;

  // The proportion of contract balance that goes the the devs every cycle. Fixed point decimal.
  uint256 public developerFeeProportion;

  // Amount of Kairo rewarded to the user who calls a phase transition/investment handling function
  uint256 public functionCallReward;

  // Amount of commission to be paid out this cycle
  uint256 public totalCommission;

  // The AUM (Asset Under Management) threshold for progressing to MakeDecisionsTime in the first cycle.
  uint256 public aumThresholdInWeis;

  // Flag for whether emergency withdrawing is allowed.
  bool public allowEmergencyWithdraw;

  uint256[3] phaseLengths;

  // The last cycle where a user redeemed commission.
  mapping(address => uint256) public lastCommissionRedemption;

  // List of investments in the current cycle.
  mapping(address => Investment[]) public userInvestments;

  // Records if a token is a stable coin. Users can't make investments with stable coins.
  mapping(address => bool) public isStableCoin;

  // Records if a token's contract maliciously treats the BetokenFund differently when calling transfer(), transferFrom(), or approve().
  mapping(address => bool) public isMaliciousCoin;

  // The current cycle phase.
  CyclePhase public cyclePhase;

  // Contract instances
  ControlToken internal cToken;
  ShareToken internal sToken;
  KyberNetwork internal kyber;
  DetailedERC20 internal dai;

  event ChangedPhase(uint256 indexed _cycleNumber, uint256 indexed _newPhase, uint256 _timestamp);

  event Deposit(uint256 indexed _cycleNumber, address indexed _sender, address _tokenAddress, uint256 _amount, uint256 _timestamp);
  event Withdraw(uint256 indexed _cycleNumber, address indexed _sender, address _tokenAddress, uint256 _amount, uint256 _timestamp);

  event CreatedInvestment(uint256 indexed _cycleNumber, address indexed _sender, uint256 _id, address _tokenAddress, uint256 _stakeInWeis);
  event SoldInvestment(uint256 indexed _cycleNumber, address indexed _sender, uint256 _investmentId, uint256 _receivedKairos);

  event ROI(uint256 indexed _cycleNumber, uint256 _beforeTotalFunds, uint256 _afterTotalFunds);
  event CommissionPaid(uint256 indexed _cycleNumber, address indexed _sender, uint256 _commission);
  event TotalCommissionPaid(uint256 indexed _cycleNumber, uint256 _totalCommissionInWeis);

  /**
   * Contract initialization functions
   */

  // Constructor
  function BetokenFund(
    address _cTokenAddr,
    address _sTokenAddr,
    address _kyberAddr,
    address _daiAddr,
    address _developerFeeAccount,
    uint256 _cycleNumber,
    uint256 _aumThresholdInWeis,
    uint256[3] _phaseLengths,
    uint256 _commissionRate,
    uint256 _developerFeeProportion,
    uint256 _functionCallReward,
    address[] _stableCoins
  )
    public
  {
    require(_commissionRate.add(_developerFeeProportion) < 10**18);

    controlTokenAddr = _cTokenAddr;
    shareTokenAddr = _sTokenAddr;
    kyberAddr = _kyberAddr;
    daiAddr = _daiAddr;
    cToken = ControlToken(_cTokenAddr);
    sToken = ShareToken(_sTokenAddr);
    kyber = KyberNetwork(_kyberAddr);

    developerFeeAccount = _developerFeeAccount;
    phaseLengths = _phaseLengths;
    commissionRate = _commissionRate;
    developerFeeProportion = _developerFeeProportion;
    startTimeOfCyclePhase = 0;
    cyclePhase = CyclePhase.RedeemCommission;
    cycleNumber = _cycleNumber;
    functionCallReward = _functionCallReward;
    aumThresholdInWeis = _aumThresholdInWeis;
    allowEmergencyWithdraw = false;

    for (uint256 i = 0; i < _stableCoins.length; i = i.add(1)) {
      isStableCoin[_stableCoins[i]] = true;
    }
  }

  /**
   * Getters
   */

  /**
   * Returns the length of the investments array.
   * @return length of investments array
   */
  function investmentsCount(address _userAddr) public view returns(uint256 _count) {
    return userInvestments[_userAddr].length;
  }

  function investments(address _userAddr) public view returns(Investment[] _investments) {
    return userInvestments[_userAddr];
  }

  function getPhaseLengths() public view returns(uint256[3] _phaseLengths) {
    return phaseLengths;
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
    during(CyclePhase.RedeemCommission)
    whenPaused
  {
    __transactToken(_tokenAddr, ERC20(_tokenAddr).balanceOf(this), false);
  }

  /**
   * @dev Return staked Kairos for a investment under emergency situations.
   */
  function emergencyRedeemStake(uint256 _investmentId) whenPaused public {
    require(allowEmergencyWithdraw);
    Investment storage investment = userInvestments[msg.sender][_investmentId];
    require(investment.cycleNumber == cycleNumber);
    uint256 stake = investment.stake;
    require(stake > 0);
    delete investment.stake;
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
    Withdraw(cycleNumber, msg.sender, ETH_TOKEN_ADDRESS, amountInWeis, now);
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

  function changeDAIAddress(address _newAddr) public onlyOwner whenPaused {
    require(_newAddr != address(0));
    daiAddr = _newAddr;
    dai = DetailedERC20(_newAddr);
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

  function changeCallReward(uint256 _newVal) public onlyOwner {
    functionCallReward = _newVal;
  }

  function changePhaseLengths(uint256[3] _newVal) public onlyOwner {
    phaseLengths = _newVal;
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

  function addStableCoin(address _stableCoin) public onlyOwner whenPaused {
    require(_stableCoin != address(0));
    isStableCoin[_stableCoin] = true;
  }

  function setMaliciousCoinStatus(address _coin, bool _status) public onlyOwner whenPaused {
    require(_coin != address(0));
    isMaliciousCoin[_coin] = _status;
  }


  /**
   * @dev Moves the fund to the next phase in the investment cycle.
   */
  function nextPhase()
    public
    whenNotPaused
  {
    require(now >= startTimeOfCyclePhase.add(phaseLengths[uint(cyclePhase)]));

    if (cyclePhase == CyclePhase.RedeemCommission) {
      // Start new cycle
      cycleNumber = cycleNumber.add(1);

      if (cToken.paused()) {
        cToken.unpause();
      }
    } else if (cyclePhase == CyclePhase.DepositWithdraw) {
      // End DepositWithdraw phase
      if (cycleNumber == 1) {
        require(totalFundsInWeis >= aumThresholdInWeis);
      }
    } else if (cyclePhase == CyclePhase.MakeDecisions) {
      // Burn any Kairo left in BetokenFund's account
      require(cToken.burnOwnerBalance());

      cToken.pause();
      __distributeFundsAfterCycleEnd();
    }

    cyclePhase = CyclePhase(addmod(uint(cyclePhase), 1, 5));
    startTimeOfCyclePhase = now;

    // Reward caller
    cToken.mint(msg.sender, functionCallReward);

    ChangedPhase(cycleNumber, uint(cyclePhase), now);
  }

  /**
   * DepositWithdraw phase functions
   */

  /**
   * @dev Deposit Ether into the fund.
   */
  function deposit()
    public
    payable
    during(CyclePhase.DepositWithdraw)
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
    Deposit(cycleNumber, msg.sender, ETH_TOKEN_ADDRESS, msg.value, now);
  }

  function depositToken(address _tokenAddr, uint256 _tokenAmount)
    public
    during(CyclePhase.DepositWithdraw)
    whenNotPaused
  {
    require(_tokenAddr != address(ETH_TOKEN_ADDRESS));
    DetailedERC20 token = DetailedERC20(_tokenAddr);
    require(token.totalSupply() > 0);

    require(token.transferFrom(msg.sender, this, _tokenAmount));

    uint256 beforeTokenBalance = token.balanceOf(this);
    uint256 beforeEthBalance = this.balance;
    __transactToken(_tokenAddr, _tokenAmount, false);
    uint256 actualTokenAmount = beforeTokenBalance - token.balanceOf(this);
    uint256 leftOverTokens = _tokenAmount - actualTokenAmount;
    if (leftOverTokens > 0) {
      require(token.transfer(msg.sender, leftOverTokens));
    }

    uint256 depositInWeis = this.balance - beforeEthBalance;
    require(depositInWeis > 0);

    // Register investment
    if (cycleNumber == 1) {
      sToken.mint(msg.sender, depositInWeis);
    } else {
      sToken.mint(msg.sender, depositInWeis.mul(sToken.totalSupply()).div(totalFundsInWeis));
    }
    totalFundsInWeis = totalFundsInWeis.add(depositInWeis);

    // Give control tokens proportional to investment
    // Uncomment if statement if not test version
    // if (cycleNumber == 1) {
    cToken.mint(msg.sender, depositInWeis);
    // }

    // Emit event
    Deposit(cycleNumber, msg.sender, _tokenAddr, actualTokenAmount, now);
  }

  /**
   * @dev Withdraws a certain amount of Ether from the user's account. Cannot be called during the first cycle.
   * @param _amountInWeis amount of Ether to be withdrawn
   */
  function withdraw(uint256 _amountInWeis)
    public
    during(CyclePhase.DepositWithdraw)
    whenNotPaused
  {
    require(cycleNumber != 1);

    // Subtract from account
    sToken.ownerBurn(msg.sender, _amountInWeis.mul(sToken.totalSupply()).div(totalFundsInWeis));
    totalFundsInWeis = totalFundsInWeis.sub(_amountInWeis);

    // Transfer Ether to user
    msg.sender.transfer(_amountInWeis);

    // Emit event
    Withdraw(cycleNumber, msg.sender, ETH_TOKEN_ADDRESS, _amountInWeis, now);
  }

  function withdrawToken(address _tokenAddr, uint256 _amountInWeis)
    public
    during(CyclePhase.DepositWithdraw)
    whenNotPaused
  {
    require(cycleNumber != 1);
    require(_tokenAddr != address(ETH_TOKEN_ADDRESS));

    DetailedERC20 token = DetailedERC20(_tokenAddr);
    require(token.totalSupply() > 0);

    // Buy desired tokens
    uint256 beforeTokenBalance = token.balanceOf(this);
    uint256 beforeEthBalance = this.balance;
    __transactToken(_tokenAddr, _amountInWeis, true);
    uint256 actualTokenAmount = token.balanceOf(this) - beforeTokenBalance;

    // Subtract from account
    uint256 actualAmountInWeis = beforeEthBalance - this.balance;
    require(actualAmountInWeis > 0);
    sToken.ownerBurn(msg.sender, actualAmountInWeis.mul(sToken.totalSupply()).div(totalFundsInWeis));
    totalFundsInWeis = totalFundsInWeis.sub(actualAmountInWeis);

    // Transfer tokens
    token.transfer(msg.sender, actualTokenAmount);

    // Emit event
    Withdraw(cycleNumber, msg.sender, _tokenAddr, actualTokenAmount, now);
  }

  /**
   * MakeDecisions phase functions
   */

  /**
   * @dev Creates a new investment investment for an ERC20 token.
   * @param _tokenAddress address of the ERC20 token contract
   * @param _stakeInWeis amount of Kairos to be staked in support of the investment
   */
  function createInvestment(
    address _tokenAddress,
    uint256 _stakeInWeis
  )
    public
    during(CyclePhase.MakeDecisions)
    whenNotPaused
  {
    // Check if token is valid
    DetailedERC20 token = DetailedERC20(_tokenAddress);
    require(token.totalSupply() > 0);
    require(!isStableCoin[_tokenAddress]);

    // Collect stake
    require(cToken.ownerCollectFrom(msg.sender, _stakeInWeis));

    // Add investment to list
    userInvestments[msg.sender].push(Investment({
      tokenAddress: _tokenAddress,
      cycleNumber: cycleNumber,
      stake: _stakeInWeis,
      tokenAmount: 0,
      buyPriceInWeis: 0,
      sellPriceInWeis: 0,
      isSold: false
    }));

    // Invest
    uint256 beforeTokenAmount = token.balanceOf(this);
    uint256 investmentId = investmentsCount(msg.sender) - 1;
    __handleInvestment(investmentId, true);
    userInvestments[msg.sender][investmentId].tokenAmount = token.balanceOf(this) - beforeTokenAmount;

    // Emit event
    CreatedInvestment(cycleNumber, msg.sender, investmentsCount(msg.sender) - 1, _tokenAddress, _stakeInWeis);
  }

  /**
   * @dev Called by user to sell the assets a investment invested in. Returns the staked Kairo plus rewards.
   * @param _investmentId the ID of the investment
   */
  function sellInvestmentAsset(uint256 _investmentId)
    public
    during(CyclePhase.MakeDecisions)
    whenNotPaused
  {
    Investment storage investment = userInvestments[msg.sender][_investmentId];
    require(investment.buyPriceInWeis > 0);
    require(investment.cycleNumber == cycleNumber);
    require(!investment.isSold);

    __handleInvestment(_investmentId, false);
    investment.isSold = true;

    uint256 multiplier = investment.sellPriceInWeis.mul(PRECISION).div(investment.buyPriceInWeis);
    uint256 receiveKairoAmount = investment.stake.mul(multiplier).div(PRECISION);
    if (receiveKairoAmount > investment.stake) {
      cToken.transfer(msg.sender, investment.stake);
      cToken.mint(msg.sender, receiveKairoAmount.sub(investment.stake));
    } else {
      cToken.transfer(msg.sender, receiveKairoAmount);
      require(cToken.burnOwnerTokens(investment.stake.sub(receiveKairoAmount)));
    }

    SoldInvestment(cycleNumber, msg.sender, _investmentId, receiveKairoAmount);
  }

  /**
   * RedeemCommission phase functions
   */

  /**
   * @dev Redeems commission.
   */
  function redeemCommission()
    public
    during(CyclePhase.RedeemCommission)
    whenNotPaused
  {
    require(lastCommissionRedemption[msg.sender] < cycleNumber);
    lastCommissionRedemption[msg.sender] = cycleNumber;
    uint256 commission = totalCommission.mul(cToken.balanceOf(msg.sender)).div(cToken.totalSupply());
    msg.sender.transfer(commission);

    delete userInvestments[msg.sender];

    CommissionPaid(cycleNumber, msg.sender, commission);
  }

  /**
   * @dev Sells tokens left over due to manager not selling or KyberNetwork not having enough demand.
   * @param _tokenAddr address of the token to be sold
   */
  function sellLeftoverToken(address _tokenAddr)
    public
    during(CyclePhase.RedeemCommission)
    whenNotPaused
  {
    uint256 beforeBalance = this.balance;
    __transactToken(_tokenAddr, ERC20(_tokenAddr).balanceOf(this), false);
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

  function __handleInvestment(uint256 _investmentId, bool _buy) internal {
    Investment storage investment = userInvestments[msg.sender][_investmentId];
    uint256 srcAmount;
    if (_buy) {
      srcAmount = totalFundsInWeis.mul(investment.stake).div(cToken.totalSupply());
    } else {
      srcAmount = investment.tokenAmount;
    }
    uint256 actualRate = __transactToken(investment.tokenAddress, srcAmount, _buy);
    if (_buy) {
      investment.buyPriceInWeis = actualRate;
    } else {
      investment.sellPriceInWeis = actualRate;
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
        this,
        MAX_QTY,
        1,
        0
      );

      // Record buy price
      require(actualDestAmount > 0);
      _actualRate = beforeBalance.sub(this.balance).mul(PRECISION).mul(10**uint256(destToken.decimals())).div(actualDestAmount.mul(10**18));
    } else {
      // Make sell orders

      beforeBalance = destToken.balanceOf(this);

      // Do trade
      destToken.approve(kyberAddr, 0);
      destToken.approve(kyberAddr, _srcAmount);
      actualDestAmount = kyber.trade(
        destToken,
        _srcAmount,
        ETH_TOKEN_ADDRESS,
        this,
        MAX_QTY,
        1,
        0
      );
      destToken.approve(kyberAddr, 0);

      // Record sell price
      require(beforeBalance > destToken.balanceOf(this));
      _actualRate = actualDestAmount.mul(PRECISION).mul(10**18).div(beforeBalance.sub(destToken.balanceOf(this)).mul(10**uint256(destToken.decimals())));
    }
  }

  function() public payable {
    if (msg.sender != kyberAddr) {
      revert();
    }
  }
}