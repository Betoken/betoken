pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ReentrancyGuard.sol";
import "./tokens/minime/MiniMeToken.sol";
import "./KyberNetwork.sol";
import "./Utils.sol";
import "./BetokenProxy.sol";

/**
 * @title The main smart contract of the Betoken hedge fund.
 * @author Zefram Lou (Zebang Liu)
 */
contract BetokenFund is Ownable, Utils, ReentrancyGuard, TokenController {
  using SafeMath for uint256;

  enum CyclePhase { DepositWithdraw, MakeDecisions, RedeemCommission }

  struct Investment {
    address tokenAddress;
    uint256 cycleNumber;
    uint256 stake;
    uint256 tokenAmount;
    uint256 buyPrice;
    uint256 sellPrice;
    bool isSold;
  }

  /**
   * @notice Executes function only during the given cycle phase.
   * @param phase the cycle phase during which the function may be called
   */
  modifier during(CyclePhase phase) {
    require(cyclePhase == phase);
    _;
  }

  /**
   * @notice Checks if `token` is a valid token.
   * @param token the token's address
   */
  modifier isValidToken(address token) {
    if (token != address(ETH_TOKEN_ADDRESS)) {
      DetailedERC20 _token = DetailedERC20(token);
      require(_token.totalSupply() > 0);
      require(_token.decimals() >= MIN_DECIMALS);
    }
    _;
  }

  /**
   * @notice Checks if the fund is ready for upgrading to the next version
   */
  modifier readyForUpgrade {
    require(cycleNumber == cycleOfUpgrade.add(1));
    require(nextVersion != address(0));
    require(now > startTimeOfCyclePhase.add(phaseLengths[uint(CyclePhase.DepositWithdraw)]));
    _;
  }

  // Address of the control token contract.
  address public controlTokenAddr;

  // Address of the share token contract.
  address public shareTokenAddr;

  // Address of the KyberNetwork contract
  address public kyberAddr;

  // Address of the BetokenProxy contract
  address public proxyAddr;

  // Address to which the developer fees will be paid.
  address public developerFeeAccount;

  // Address of the DAI stable-coin contract.
  address public daiAddr;

  // Address of the previous version of BetokenFund.
  address public previousVersion;

  // Address of the next version of BetokenFund.
  address public nextVersion;

  // The number of the current investment cycle.
  uint256 public cycleNumber;

  // The amount of funds held by the fund.
  uint256 public totalFundsInDAI;

  // The start time for the current investment cycle phase, in seconds since Unix epoch.
  uint256 public startTimeOfCyclePhase;

  // The proportion of the fund that gets distributed to Kairo holders every cycle. Fixed point decimal.
  uint256 public commissionRate;

  // The proportion of contract balance that gets distributed to Kairo holders every cycle. Fixed point decimal.
  uint256 public assetFeeRate;

  // The proportion of contract balance that goes the the devs every cycle. Fixed point decimal.
  uint256 public developerFeeRate;

  // The proportion of funds that goes the the devs during withdrawals. Fixed point decimal.
  uint256 public exitFeeRate;

  // Amount of Kairo rewarded to the user who calls a phase transition/investment handling function
  uint256 public functionCallReward;

  // Total amount of commission unclaimed by managers
  uint256 public totalCommissionLeft;

  // Stores the lengths of each cycle phase in seconds.
  uint256[3] phaseLengths;

  // The last cycle where a user redeemed commission.
  mapping(address => uint256) public lastCommissionRedemption;

  // List of investments in the current cycle.
  mapping(address => Investment[]) public userInvestments;

  // Total commission to be paid in a certain cycle
  mapping(uint256 => uint256) public totalCommissionOfCycle;

  // The block number at which the RedeemCommission phase started for the given cycle
  mapping(uint256 => uint256) public commissionPhaseStartBlock;

  // Upgrade related variables
  uint256 public cycleOfUpgrade; // Cycle when the contract is upgraded
  uint256 public upgradeQuorum;
  uint256 public nextVersionQuorum;

  mapping(uint256 => mapping(address => bool)) public hasSignaledUpgrade;
  mapping(uint256 => uint256) public votesSignalingUpgrade;
  mapping(uint256 => uint256) public totalUpgradeVotes;

  mapping(uint256 => mapping(address => bool)) public hasVotedOnNextVersion;
  mapping(uint256 => mapping(address => uint256)) public votesForNextVersion;
  mapping(uint256 => uint256) public totalNextVersionVotes;


  // The current cycle phase.
  CyclePhase public cyclePhase;

  // Contract instances
  MiniMeToken internal cToken;
  MiniMeToken internal sToken;
  KyberNetwork internal kyber;
  DetailedERC20 internal dai;
  BetokenProxy internal proxy;

  event ChangedPhase(uint256 indexed _cycleNumber, uint256 indexed _newPhase, uint256 _timestamp);

  event Deposit(uint256 indexed _cycleNumber, address indexed _sender, address _tokenAddress, uint256 _tokenAmount, uint256 _daiAmount, uint256 _timestamp);
  event Withdraw(uint256 indexed _cycleNumber, address indexed _sender, address _tokenAddress, uint256 _tokenAmount, uint256 daiAmount, uint256 _timestamp);

  event CreatedInvestment(uint256 indexed _cycleNumber, address indexed _sender, uint256 _id, address _tokenAddress, uint256 _stakeInWeis, uint256 _buyPrice, uint256 _costDAIAmount);
  event SoldInvestment(uint256 indexed _cycleNumber, address indexed _sender, uint256 _investmentId, uint256 _receivedKairos, uint256 _sellPrice, uint256 _earnedDAIAmount);

  event ROI(uint256 indexed _cycleNumber, uint256 _beforeTotalFunds, uint256 _afterTotalFunds);
  event CommissionPaid(uint256 indexed _cycleNumber, address indexed _sender, uint256 _commission);
  event TotalCommissionPaid(uint256 indexed _cycleNumber, uint256 _totalCommissionInDAI);

  event NewUser(address _user);

  event BeganUpgradeProcess(uint256 indexed _cycleNumber, bool _byCommunity);
  event VotedUpgrade(uint256 indexed _cycleNumber, address indexed _sender, uint256 _voteWeight, bool _support);
  event VotedNextVersion(uint256 indexed _cycleNumber, address indexed _sender, uint256 _voteWeight, address _nextVersion);
  event SetNextVersion(uint256 indexed _cycleNumber, address _nextVersion, bool _byCommunity);

  /**
   * Meta functions
   */

  constructor(
    address _cTokenAddr,
    address _sTokenAddr,
    address _kyberAddr,
    address _daiAddr,
    address _proxyAddr,
    address _developerFeeAccount,
    uint256[3] _phaseLengths,
    uint256 _commissionRate,
    uint256 _assetFeeRate,
    uint256 _developerFeeRate,
    uint256 _exitFeeRate,
    uint256 _functionCallReward,
    uint256 _upgradeQuorum,
    uint256 _nextVersionQuorum,
    address _previousVersion
  )
    public
  {
    require(_commissionRate.add(_developerFeeRate) < 10**18);

    controlTokenAddr = _cTokenAddr;
    shareTokenAddr = _sTokenAddr;
    kyberAddr = _kyberAddr;
    daiAddr = _daiAddr;
    proxyAddr = _proxyAddr;
    cToken = MiniMeToken(_cTokenAddr);
    sToken = MiniMeToken(_sTokenAddr);
    kyber = KyberNetwork(_kyberAddr);
    dai = DetailedERC20(_daiAddr);

    developerFeeAccount = _developerFeeAccount;
    phaseLengths = _phaseLengths;
    commissionRate = _commissionRate;
    assetFeeRate = _assetFeeRate;
    developerFeeRate = _developerFeeRate;
    exitFeeRate = _exitFeeRate;
    cyclePhase = CyclePhase.RedeemCommission;
    functionCallReward = _functionCallReward;
    upgradeQuorum = _upgradeQuorum;
    nextVersionQuorum = _nextVersionQuorum;

    previousVersion = _previousVersion;
  }

  /**
   * Upgrading functions
   */

  function announceNextVersion(address _nextVersion) public onlyOwner during(CyclePhase.DepositWithdraw) {
    require(_nextVersion != address(0));
    require(cycleOfUpgrade == 0);
    nextVersion = _nextVersion;
    cycleOfUpgrade = cycleNumber;

    emit BeganUpgradeProcess(cycleNumber, false);
    emit SetNextVersion(cycleNumber, _nextVersion, false);
  }

  function signalUpgrade(bool _support) public during(CyclePhase.DepositWithdraw) {
    require(hasSignaledUpgrade[cycleNumber][msg.sender] == false);
    hasSignaledUpgrade[cycleNumber][msg.sender] = true;

    // add votes to tally
    uint256 voteWeight = cToken.balanceOfAt(msg.sender, commissionPhaseStartBlock[cycleNumber.sub(1)]);
    totalUpgradeVotes[cycleNumber] = totalUpgradeVotes[cycleNumber].add(voteWeight);
    if (_support) {
        votesSignalingUpgrade[cycleNumber] = votesSignalingUpgrade[cycleNumber].add(voteWeight);
    }

    emit VotedUpgrade(cycleNumber, msg.sender, voteWeight, _support);
  }

  function tallyUpgradeVotes() public during(CyclePhase.MakeDecisions) {
    // check if upgrade is initiated
    if (votesSignalingUpgrade[cycleNumber].mul(2) > totalUpgradeVotes[cycleNumber]
        && totalUpgradeVotes[cycleNumber] > cToken.totalSupplyAt(commissionPhaseStartBlock[cycleNumber.sub(1)]).mul(upgradeQuorum).div(PRECISION)) {
      cycleOfUpgrade = cycleNumber;

      emit BeganUpgradeProcess(cycleNumber, true);
    }
  }

  function voteForNextVersion(address _nextVersion) public during(CyclePhase.MakeDecisions) {
    require(_nextVersion != address(0));
    require(cycleNumber == cycleOfUpgrade);
    require(hasVotedOnNextVersion[cycleNumber][msg.sender] == false);
    hasVotedOnNextVersion[cycleNumber][msg.sender] = true;

    // add votes to tally
    uint256 voteWeight = cToken.balanceOfAt(msg.sender, commissionPhaseStartBlock[cycleNumber.sub(1)]);
    totalNextVersionVotes[cycleNumber] = totalNextVersionVotes[cycleNumber].add(voteWeight);
    votesForNextVersion[cycleNumber][_nextVersion] = votesForNextVersion[cycleNumber][_nextVersion].add(voteWeight);

    emit VotedNextVersion(cycleNumber, msg.sender, voteWeight, _nextVersion);
  }

  function tallyNextVersionVotes(address _nextVersion) public during(CyclePhase.RedeemCommission) {
    // check if vote is passed
    if (votesForNextVersion[cycleNumber][_nextVersion].mul(2) > totalNextVersionVotes[cycleNumber]
        && totalNextVersionVotes[cycleNumber] > cToken.totalSupplyAt(commissionPhaseStartBlock[cycleNumber.sub(1)]).mul(nextVersionQuorum).div(PRECISION)) {
      nextVersion = _nextVersion;

      emit SetNextVersion(cycleNumber, _nextVersion, true);
    }
  }

  function resetUpgrade() public during(CyclePhase.DepositWithdraw) {
    require(nextVersion == address(0));
    require(cycleNumber == cycleOfUpgrade.add(1));

    cycleOfUpgrade = 0;
  }

  function migrateOwnedContractsToNextVersion() public readyForUpgrade {
    cToken.transferOwnership(nextVersion);
    sToken.transferOwnership(nextVersion);
    proxy.updateBetokenFundAddress();
  }

  function transferAssetToNextVersion(address _assetAddress) public readyForUpgrade isValidToken(_assetAddress) {
    if (_assetAddress == address(ETH_TOKEN_ADDRESS)) {
      nextVersion.transfer(address(this).balance);
    } else {
      DetailedERC20 token = DetailedERC20(_assetAddress);
      token.transfer(nextVersion, token.balanceOf(address(this)));
    }
  }

  /**
   * Getters
   */

  /**
   * @notice Returns the length of the user's investments array.
   * @return length of the user's investments array
   */
  function investmentsCount(address _userAddr) public view returns(uint256 _count) {
    return userInvestments[_userAddr].length;
  }

  /**
   * @notice Returns the phaseLengths array.
   * @return the phaseLengths array
   */
  function getPhaseLengths() public view returns(uint256[3] _phaseLengths) {
    return phaseLengths;
  }

  /**
   * Parameter setters
   */

  /**
   * @notice Changes the address to which the developer fees will be sent. Only callable by owner.
   * @param _newAddr the new developer fee address
   */
  function changeDeveloperFeeAccount(address _newAddr) public onlyOwner {
    require(_newAddr != address(0));
    developerFeeAccount = _newAddr;
  }

  /**
   * @notice Changes the proportion of fund balance sent to the developers each cycle. May only decrease. Only callable by owner.
   * @param _newProp the new proportion, fixed point decimal
   */
  function changeDeveloperFeeRate(uint256 _newProp) public onlyOwner {
    require(_newProp < PRECISION);
    require(_newProp < developerFeeRate);
    developerFeeRate = _newProp;
  }

  /**
   * @notice Changes exit fee rate. May only decrease. Only callable by owner.
   * @param _newProp the new proportion, fixed point decimal
   */
  function changeExitFeeRate(uint256 _newProp) public onlyOwner {
    require(_newProp < PRECISION);
    require(_newProp < exitFeeRate);
    exitFeeRate = _newProp;
  }


  /**
   * @notice Moves the fund to the next phase in the investment cycle.
   */
  function nextPhase()
    public
  {
    require(now >= startTimeOfCyclePhase.add(phaseLengths[uint(cyclePhase)]));

    if (cyclePhase == CyclePhase.RedeemCommission) {
      // Start new cycle
      if (cycleNumber == 0) {
        require(msg.sender == owner);
      }

      cycleNumber = cycleNumber.add(1);
    } else if (cyclePhase == CyclePhase.DepositWithdraw) {
      if (cycleOfUpgrade > 0) {
        require(cycleNumber < cycleOfUpgrade.add(1)); // Enforce upgrade
      }
    } else if (cyclePhase == CyclePhase.MakeDecisions) {
      // Burn any Kairo left in BetokenFund's account
      require(cToken.destroyTokens(address(this), cToken.balanceOf(address(this))));

      __distributeFundsAfterCycleEnd();

      commissionPhaseStartBlock[cycleNumber] = block.number;
    }

    cyclePhase = CyclePhase(addmod(uint(cyclePhase), 1, 3));
    startTimeOfCyclePhase = now;

    // Reward caller
    cToken.generateTokens(msg.sender, functionCallReward);

    emit ChangedPhase(cycleNumber, uint(cyclePhase), now);
  }

  /**
   * DepositWithdraw phase functions
   */

   /**
   * @notice Deposit Ether into the fund. Ether will be converted into DAI.
   */
  function depositEther()
    public
    payable
    during(CyclePhase.DepositWithdraw)
    nonReentrant
  {
    // Buy DAI with ETH
    uint256 actualDAIDeposited;
    uint256 actualETHDeposited;
    uint256 beforeETHBalance = getBalance(ETH_TOKEN_ADDRESS, this);
    uint256 beforeDAIBalance = getBalance(dai, this);
    __kyberTrade(ETH_TOKEN_ADDRESS, msg.value, dai);
    actualETHDeposited = beforeETHBalance.sub(getBalance(ETH_TOKEN_ADDRESS, this));
    uint256 leftOverETH = msg.value.sub(actualETHDeposited);
    if (leftOverETH > 0) {
      msg.sender.transfer(leftOverETH);
    }
    actualDAIDeposited = getBalance(dai, this).sub(beforeDAIBalance);

    // Register investment
    if (sToken.totalSupply() == 0 || totalFundsInDAI == 0) {
      sToken.generateTokens(msg.sender, actualDAIDeposited);
    } else {
      sToken.generateTokens(msg.sender, actualDAIDeposited.mul(sToken.totalSupply()).div(totalFundsInDAI));
    }
    totalFundsInDAI = totalFundsInDAI.add(actualDAIDeposited);

    // Emit event
    emit Deposit(cycleNumber, msg.sender, ETH_TOKEN_ADDRESS, actualETHDeposited, actualDAIDeposited, now);
  }

  /**
   * @notice Deposit ERC20 tokens into the fund. Tokens will be converted into DAI.
   * @param _tokenAddr the address of the token to be deposited
   * @param _tokenAmount The amount of tokens to be deposited. May be different from actual deposited amount.
   */
  function depositToken(address _tokenAddr, uint256 _tokenAmount)
    public
    during(CyclePhase.DepositWithdraw)
    isValidToken(_tokenAddr)
    nonReentrant
  {
    require(cycleNumber <= cycleOfUpgrade); // prevent depositing when there's an upgrade
    DetailedERC20 token = DetailedERC20(_tokenAddr);

    require(token.transferFrom(msg.sender, this, _tokenAmount));

    // Convert token into DAI
    uint256 actualDAIDeposited;
    uint256 actualTokenDeposited;
    if (_tokenAddr == daiAddr) {
      actualDAIDeposited = _tokenAmount;
      actualTokenDeposited = _tokenAmount;
    } else {
      // Buy DAI with tokens
      uint256 beforeTokenBalance = getBalance(token, this);
      uint256 beforeDAIBalance = getBalance(dai, this);
      __kyberTrade(token, _tokenAmount, dai);
      actualTokenDeposited = beforeTokenBalance.sub(getBalance(token, this));
      uint256 leftOverTokens = _tokenAmount.sub(actualTokenDeposited);
      if (leftOverTokens > 0) {
        require(token.transfer(msg.sender, leftOverTokens));
      }
      actualDAIDeposited = getBalance(dai, this).sub(beforeDAIBalance);
      require(actualDAIDeposited > 0);
    }

    // Register investment
    if (sToken.totalSupply() == 0 || totalFundsInDAI == 0) {
      sToken.generateTokens(msg.sender, actualDAIDeposited);
    } else {
      sToken.generateTokens(msg.sender, actualDAIDeposited.mul(sToken.totalSupply()).div(totalFundsInDAI));
    }
    totalFundsInDAI = totalFundsInDAI.add(actualDAIDeposited);

    // Emit event
    emit Deposit(cycleNumber, msg.sender, _tokenAddr, actualTokenDeposited, actualDAIDeposited, now);
  }

  /**
   * @notice Withdraws Ether by burning Shares.
   * @param _amountInDAI Amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
   */
  function withdrawEther(uint256 _amountInDAI)
    public
    during(CyclePhase.DepositWithdraw)
    nonReentrant
  {
    // Buy ETH
    uint256 actualETHWithdrawn;
    uint256 actualDAIWithdrawn;
    uint256 beforeETHBalance = getBalance(ETH_TOKEN_ADDRESS, this);
    uint256 beforeDaiBalance = getBalance(dai, this);
    __kyberTrade(dai, _amountInDAI, ETH_TOKEN_ADDRESS);
    actualETHWithdrawn = getBalance(ETH_TOKEN_ADDRESS, this).sub(beforeETHBalance);
    actualDAIWithdrawn = beforeDaiBalance.sub(getBalance(dai, this));
    require(actualDAIWithdrawn > 0);

    // Burn shares
    sToken.destroyTokens(msg.sender, actualDAIWithdrawn.mul(sToken.totalSupply()).div(totalFundsInDAI));
    totalFundsInDAI = totalFundsInDAI.sub(actualDAIWithdrawn);

    // Transfer Ether to user
    if (cycleNumber <= cycleOfUpgrade) {
      // Charge exit fee unless last cycle
      uint256 exitFee = actualETHWithdrawn.mul(exitFeeRate).div(PRECISION);
      developerFeeAccount.transfer(exitFee);
      actualETHWithdrawn = actualETHWithdrawn.sub(exitFee);
    }
    msg.sender.transfer(actualETHWithdrawn);

    // Emit event
    emit Withdraw(cycleNumber, msg.sender, ETH_TOKEN_ADDRESS, actualETHWithdrawn, actualDAIWithdrawn, now);
  }

  /**
   * @notice Withdraws funds by burning Shares, and converts the funds into the specified token using Kyber Network.
   * @param _tokenAddr the address of the token to be withdrawn into the caller's account
   * @param _amountInDAI The amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
   */
  function withdrawToken(address _tokenAddr, uint256 _amountInDAI)
    public
    during(CyclePhase.DepositWithdraw)
    isValidToken(_tokenAddr)
    nonReentrant
  {
    DetailedERC20 token = DetailedERC20(_tokenAddr);

    // Convert DAI into desired tokens
    uint256 actualTokenWithdrawn;
    uint256 actualDAIWithdrawn;
    if (_tokenAddr == daiAddr) {
      actualDAIWithdrawn = _amountInDAI;
      actualTokenWithdrawn = _amountInDAI;
    } else {
      // Buy desired tokens
      uint256 beforeTokenBalance = getBalance(token, this);
      uint256 beforeDaiBalance = getBalance(dai, this);
      __kyberTrade(dai, _amountInDAI, token);
      actualTokenWithdrawn = getBalance(token, this).sub(beforeTokenBalance);
      actualDAIWithdrawn = beforeDaiBalance.sub(getBalance(dai, this));
      require(actualDAIWithdrawn > 0);
    }

    // Burn Shares
    sToken.destroyTokens(msg.sender, actualDAIWithdrawn.mul(sToken.totalSupply()).div(totalFundsInDAI));
    totalFundsInDAI = totalFundsInDAI.sub(actualDAIWithdrawn);

    // Transfer tokens to user
    if (cycleNumber <= cycleOfUpgrade) {
      // Charge exit fee unless last cycle
      uint256 exitFee = actualTokenWithdrawn.mul(exitFeeRate).div(PRECISION);
      token.transfer(developerFeeAccount, exitFee);
      actualTokenWithdrawn = actualTokenWithdrawn.sub(exitFee);
    }
    
    token.transfer(msg.sender, actualTokenWithdrawn);

    // Emit event
    emit Withdraw(cycleNumber, msg.sender, _tokenAddr, actualTokenWithdrawn, actualDAIWithdrawn, now);
  }

  /**
   * MakeDecisions phase functions
   */

  /**
   * @notice Creates a new investment investment for an ERC20 token.
   * @param _tokenAddress address of the ERC20 token contract
   * @param _stake amount of Kairos to be staked in support of the investment
   */
  function createInvestment(
    address _tokenAddress,
    uint256 _stake
  )
    public
    during(CyclePhase.MakeDecisions)
    isValidToken(_tokenAddress)
    nonReentrant
  {
    DetailedERC20 token = DetailedERC20(_tokenAddress);

    // Collect stake
    require(cToken.generateTokens(address(this), _stake));
    require(cToken.destroyTokens(msg.sender, _stake));

    // Add investment to list
    userInvestments[msg.sender].push(Investment({
      tokenAddress: _tokenAddress,
      cycleNumber: cycleNumber,
      stake: _stake,
      tokenAmount: 0,
      buyPrice: 0,
      sellPrice: 0,
      isSold: false
    }));

    // Invest
    uint256 beforeTokenAmount = getBalance(token, this);
    uint256 beforeDAIBalance = getBalance(dai, this);
    uint256 investmentId = investmentsCount(msg.sender).sub(1);
    __handleInvestment(investmentId, true);
    userInvestments[msg.sender][investmentId].tokenAmount = getBalance(token, this).sub(beforeTokenAmount);

    // Emit event
    emit CreatedInvestment(cycleNumber, msg.sender, investmentsCount(msg.sender).sub(1), _tokenAddress, _stake, userInvestments[msg.sender][investmentId].buyPrice, beforeDAIBalance.sub(getBalance(dai, this)));
  }

  /**
   * @notice Called by user to sell the assets an investment invested in. Returns the staked Kairo plus rewards/penalties.
   * @param _investmentId the ID of the investment
   */
  function sellInvestmentAsset(uint256 _investmentId)
    public
    during(CyclePhase.MakeDecisions)
    nonReentrant
  {
    Investment storage investment = userInvestments[msg.sender][_investmentId];
    require(investment.buyPrice > 0);
    require(investment.cycleNumber == cycleNumber);
    require(!investment.isSold);

    investment.isSold = true;

    // Sell asset
    uint256 beforeDAIBalance = getBalance(dai, this);
    __handleInvestment(_investmentId, false);

    // Return Kairo
    uint256 multiplier = investment.sellPrice.mul(PRECISION).div(investment.buyPrice);
    uint256 receiveKairoAmount = investment.stake.mul(multiplier).div(PRECISION);
    if (receiveKairoAmount > investment.stake) {
      cToken.transfer(msg.sender, investment.stake);
      cToken.generateTokens(msg.sender, receiveKairoAmount.sub(investment.stake));
    } else {
      cToken.transfer(msg.sender, receiveKairoAmount);
      require(cToken.destroyTokens(address(this), investment.stake.sub(receiveKairoAmount)));
    }

    // Emit event
    emit SoldInvestment(cycleNumber, msg.sender, _investmentId, receiveKairoAmount, investment.sellPrice, getBalance(dai, this).sub(beforeDAIBalance));
  }

  /**
   * RedeemCommission phase functions
   */

  /**
   * @notice Redeems commission.
   */
  function redeemCommission()
    public
    during(CyclePhase.RedeemCommission)
    nonReentrant
  {
    require(lastCommissionRedemption[msg.sender] < cycleNumber);
    uint256 commission = 0;
    for (uint256 cycle = lastCommissionRedemption[msg.sender].add(1); cycle <= cycleNumber; cycle = cycle.add(1)) {
      commission = commission.add(totalCommissionOfCycle[cycle].mul(cToken.balanceOfAt(msg.sender, commissionPhaseStartBlock[cycle]))
          .div(cToken.totalSupplyAt(commissionPhaseStartBlock[cycle])));
    }

    lastCommissionRedemption[msg.sender] = cycleNumber;
    totalCommissionLeft = totalCommissionLeft.sub(commission);
    delete userInvestments[msg.sender];

    dai.transfer(msg.sender, commission);

    emit CommissionPaid(cycleNumber, msg.sender, commission);
  }

  /**
   * @notice Redeems commission in shares.
   */
  function redeemCommissionInShares()
    public
    during(CyclePhase.RedeemCommission)
    nonReentrant
  {
    require(lastCommissionRedemption[msg.sender] < cycleNumber);
    uint256 commission = 0;
    for (uint256 cycle = lastCommissionRedemption[msg.sender].add(1); cycle <= cycleNumber; cycle = cycle.add(1)) {
      commission = commission.add(totalCommissionOfCycle[cycle].mul(cToken.balanceOfAt(msg.sender, commissionPhaseStartBlock[cycle]))
          .div(cToken.totalSupplyAt(commissionPhaseStartBlock[cycle])));
    }

    lastCommissionRedemption[msg.sender] = cycleNumber;
    totalCommissionLeft = totalCommissionLeft.sub(commission);

    sToken.generateTokens(msg.sender, commission.mul(sToken.totalSupply()).div(totalFundsInDAI));
    totalFundsInDAI = totalFundsInDAI.add(commission);

    delete userInvestments[msg.sender];

    // Emit event
    emit Deposit(cycleNumber, msg.sender, daiAddr, commission, commission, now);
    emit CommissionPaid(cycleNumber, msg.sender, commission);
  }

  /**
   * @notice Sells tokens left over due to manager not selling or KyberNetwork not having enough demand. Callable by anyone.
   * @param _tokenAddr address of the token to be sold
   */
  function sellLeftoverToken(address _tokenAddr)
    public
    during(CyclePhase.RedeemCommission)
    isValidToken(_tokenAddr)
    nonReentrant
  {
    uint256 beforeBalance = getBalance(dai, this);
    DetailedERC20 token = DetailedERC20(_tokenAddr);
    __kyberTrade(token, getBalance(token, this), dai);
    totalFundsInDAI = totalFundsInDAI.add(getBalance(dai, this).sub(beforeBalance));
  }

  /**
   * Internal use functions
   */

  // MiniMe TokenController functions, not used right now
  /**
   * @notice Called when `_owner` sends ether to the MiniMe Token contract
   * @param _owner The address that sent the ether to create tokens
   * @return True if the ether is accepted, false if it throws
   */
  function proxyPayment(address _owner) public payable returns(bool) {
    return false;
  }

  /**
   * @notice Notifies the controller about a token transfer allowing the
   *  controller to react if desired
   * @param _from The origin of the transfer
   * @param _to The destination of the transfer
   * @param _amount The amount of the transfer
   * @return False if the controller does not authorize the transfer
   */
  function onTransfer(address _from, address _to, uint _amount) public returns(bool) {
    return true;
  }

  /// @notice Notifies the controller about an approval allowing the
  ///  controller to react if desired
  /// @param _owner The address that calls `approve()`
  /// @param _spender The spender in the `approve()` call
  /// @param _amount The amount in the `approve()` call
  /// @return False if the controller does not authorize the approval
  function onApprove(address _owner, address _spender, uint _amount) public
      returns(bool) {
    return true;
  }

  /**
   * @notice Update fund statistics, and pay developer fees.
   */
  function __distributeFundsAfterCycleEnd() internal {
    uint256 profit = 0;
    if (getBalance(dai, this) > totalFundsInDAI) {
      profit = getBalance(dai, this).sub(totalFundsInDAI);
    }
    totalCommissionOfCycle[cycleNumber] = commissionRate.mul(profit).add(assetFeeRate.mul(getBalance(dai, this))).div(PRECISION);
    totalCommissionLeft = totalCommissionLeft.add(totalCommissionOfCycle[cycleNumber]);
    uint256 devFee = developerFeeRate.mul(getBalance(dai, this)).div(PRECISION);
    uint256 newTotalFunds = getBalance(dai, this).sub(totalCommissionLeft).sub(devFee);

    // Update values
    emit ROI(cycleNumber, totalFundsInDAI, newTotalFunds);
    totalFundsInDAI = newTotalFunds;

    // Transfer fees
    dai.transfer(developerFeeAccount, devFee);

    // Emit event
    emit TotalCommissionPaid(cycleNumber, totalCommissionOfCycle[cycleNumber]);
  }

  function __handleInvestment(uint256 _investmentId, bool _buy) internal {
    Investment storage investment = userInvestments[msg.sender][_investmentId];
    uint256 srcAmount;
    uint256 dInS;
    uint256 sInD;
    if (_buy) {
      srcAmount = totalFundsInDAI.mul(investment.stake).div(cToken.totalSupply());
    } else {
      srcAmount = investment.tokenAmount;
    }
    DetailedERC20 token = DetailedERC20(investment.tokenAddress);
    if (_buy) {
      (dInS, sInD) = __kyberTrade(dai, srcAmount, token);
      investment.buyPrice = dInS;
    } else {
      (dInS, sInD) = __kyberTrade(token, srcAmount, dai);
      investment.sellPrice = sInD;
    }
  }

  /**
   * @notice Wrapper function for doing token conversion on Kyber Network
   * @param _srcToken the token to convert from
   * @param _srcAmount the amount of tokens to be converted
   * @param _destToken the destination token
   * @return _destPriceInSrc the price of the destination token, in terms of source tokens
   */
  function __kyberTrade(DetailedERC20 _srcToken, uint256 _srcAmount, DetailedERC20 _destToken) internal returns(uint256 _destPriceInSrc, uint256 _srcPriceInDest) {
    require(_srcToken != _destToken);
    uint256 actualDestAmount;
    uint256 beforeSrcBalance = getBalance(_srcToken, this);
    uint256 msgValue;

    if (_srcToken != ETH_TOKEN_ADDRESS) {
      msgValue = 0;
      _srcToken.approve(kyberAddr, 0);
      _srcToken.approve(kyberAddr, _srcAmount);
    } else {
      msgValue = _srcAmount;
    }
    actualDestAmount = kyber.trade.value(msgValue)(
      _srcToken,
      _srcAmount,
      _destToken,
      this,
      MAX_QTY,
      1,
      0
    );
    require(actualDestAmount > 0);
    if (_srcToken != ETH_TOKEN_ADDRESS) {
      _srcToken.approve(kyberAddr, 0);
    }

    uint256 actualSrcAmount = beforeSrcBalance.sub(getBalance(_srcToken, this));
    _destPriceInSrc = calcRateFromQty(actualDestAmount, actualSrcAmount, getDecimals(_destToken), getDecimals(_srcToken));
    _srcPriceInDest = calcRateFromQty(actualSrcAmount, actualDestAmount, getDecimals(_srcToken), getDecimals(_destToken));
  }

  function() public payable {
    if (msg.sender != kyberAddr || msg.sender != previousVersion) {
      revert();
    }
  }
}