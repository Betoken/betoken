pragma solidity 0.5.8;

import "./BetokenStorage.sol";
import "./derivatives/CompoundOrderFactory.sol";

/**
 * @title The main smart contract of the Betoken hedge fund.
 * @author Zefram Lou (Zebang Liu)
 */
contract BetokenFund is BetokenStorage, Utils, TokenController {
  /**
   * @notice Executes function only during the given cycle phase.
   * @param phase the cycle phase during which the function may be called
   */
  modifier during(CyclePhase phase) {
    require(cyclePhase == phase);
    _;
  }

  /**
   * @notice Passes if the fund is ready for migrating to the next version
   */
  modifier readyForUpgradeMigration {
    require(hasFinalizedNextVersion == true);
    require(now > startTimeOfCyclePhase.add(phaseLengths[uint(CyclePhase.Intermission)]));
    _;
  }

  /**
   * @notice Passes if the fund has not finalized the next smart contract to upgrade to
   */
  modifier notReadyForUpgrade {
    require(hasFinalizedNextVersion == false);
    _;
  }

  /**
   * Meta functions
   */

  constructor(
    address payable _kroAddr,
    address payable _sTokenAddr,
    address payable _devFundingAccount,
    uint256[2] memory _phaseLengths,
    uint256 _devFundingRate,
    address payable _previousVersion,
    address _daiAddr,
    address payable _kyberAddr,
    address _compoundFactoryAddr,
    address _betokenLogic
  )
    public
    Utils(_daiAddr, _kyberAddr)
  {
    controlTokenAddr = _kroAddr;
    shareTokenAddr = _sTokenAddr;
    devFundingAccount = _devFundingAccount;
    phaseLengths = _phaseLengths;
    devFundingRate = _devFundingRate;
    cyclePhase = CyclePhase.Manage;
    compoundFactoryAddr = _compoundFactoryAddr;
    betokenLogic = _betokenLogic;
    previousVersion = _previousVersion;

    cToken = IMiniMeToken(_kroAddr);
    sToken = IMiniMeToken(_sTokenAddr);
  }

  function initTokenListings(
    address[] memory _kyberTokens,
    address[] memory _compoundTokens,
    address[] memory _positionTokens
  )
    public
    onlyOwner
  {
    // May only initialize once
    require(!hasInitializedTokenListings);
    hasInitializedTokenListings = true;

    uint256 i;
    for (i = 0; i < _kyberTokens.length; i = i.add(1)) {
      isKyberToken[_kyberTokens[i]] = true;
    }

    for (i = 0; i < _compoundTokens.length; i = i.add(1)) {
      isCompoundToken[_compoundTokens[i]] = true;
    }

    for (i = 0; i < _positionTokens.length; i = i.add(1)) {
      isPositionToken[_positionTokens[i]] = true;
    }
  }

  /**
   * @notice Used during deployment to set the BetokenProxy contract address.
   * @param _proxyAddr the proxy's address
   */
  function setProxy(address payable _proxyAddr) public onlyOwner {
    require(_proxyAddr != address(0));
    require(proxyAddr == address(0));
    proxyAddr = _proxyAddr;
    proxy = BetokenProxyInterface(_proxyAddr);
  }

  /**
   * Upgrading functions
   */

  /**
   * @notice Allows the developer to propose a candidate smart contract for the fund to upgrade to.
   *          The developer may change the candidate during the Intermission phase.
   * @param _candidate the address of the candidate smart contract
   * @return True if successfully changed candidate, false otherwise.
   */
  function developerInitiateUpgrade(address payable _candidate) public during(CyclePhase.Intermission) onlyOwner notReadyForUpgrade returns (bool _success) {
    (bool success, bytes memory result) = betokenLogic.delegatecall(abi.encodeWithSelector(this.developerInitiateUpgrade.selector, _candidate));
    if (!success) { return false; }
    return abi.decode(result, (bool));
  }

  /**
   * @notice Allows a manager to signal their support of initiating an upgrade. They can change their signal before the end of the Intermission phase.
   *          Managers who oppose initiating an upgrade don't need to call this function, unless they origianlly signalled in support.
   *          Signals are reset every cycle.
   * @param _inSupport True if the manager supports initiating upgrade, false if the manager opposes it.
   * @return True if successfully changed signal, false if no changes were made.
   */
  function signalUpgrade(bool _inSupport) public during(CyclePhase.Intermission) notReadyForUpgrade returns (bool _success) {
    (bool success, bytes memory result) = betokenLogic.delegatecall(abi.encodeWithSelector(this.signalUpgrade.selector, _inSupport));
    if (!success) { return false; }
    return abi.decode(result, (bool));
  }

  /**
   * @notice Allows manager to propose a candidate smart contract for the fund to upgrade to. Among the managers who have proposed a candidate,
   *          the manager with the most voting weight's candidate will be used in the vote. Ties are broken in favor of the larger address.
   *          The proposer may change the candidate they support during the Propose subchunk in their chunk.
   * @param _chunkNumber the chunk for which the sender is proposing the candidate
   * @param _candidate the address of the candidate smart contract
   * @return True if successfully proposed/changed candidate, false otherwise.
   */
  function proposeCandidate(uint256 _chunkNumber, address payable _candidate) public during(CyclePhase.Manage) notReadyForUpgrade returns (bool _success) {
    (bool success, bytes memory result) = betokenLogic.delegatecall(abi.encodeWithSelector(this.proposeCandidate.selector, _chunkNumber, _candidate));
    if (!success) { return false; }
    return abi.decode(result, (bool));
  }

  /**
   * @notice Allows a manager to vote for or against a candidate smart contract the fund will upgrade to. The manager may change their vote during
   *          the Vote subchunk. A manager who has been a proposer may not vote.
   * @param _inSupport True if the manager supports initiating upgrade, false if the manager opposes it.
   * @return True if successfully changed vote, false otherwise.
   */
  function voteOnCandidate(uint256 _chunkNumber, bool _inSupport) public during(CyclePhase.Manage) notReadyForUpgrade returns (bool _success) {
    (bool success, bytes memory result) = betokenLogic.delegatecall(abi.encodeWithSelector(this.voteOnCandidate.selector, _chunkNumber, _inSupport));
    if (!success) { return false; }
    return abi.decode(result, (bool));
  }

  /**
   * @notice Performs the necessary state changes after a successful vote
   * @param _chunkNumber the chunk number of the successful vote
   * @return True if successful, false otherwise
   */
  function finalizeSuccessfulVote(uint256 _chunkNumber) public during(CyclePhase.Manage) notReadyForUpgrade returns (bool _success) {
    (bool success, bytes memory result) = betokenLogic.delegatecall(abi.encodeWithSelector(this.finalizeSuccessfulVote.selector, _chunkNumber));
    if (!success) { return false; }
    return abi.decode(result, (bool));
  }

  /**
   * @notice Transfers ownership of Kairo & Share token contracts to the next version. Also updates BetokenFund's
   *         address in BetokenProxy.
   */
  function migrateOwnedContractsToNextVersion() public nonReentrant readyForUpgradeMigration {
    cToken.transferOwnership(nextVersion);
    sToken.transferOwnership(nextVersion);
    proxy.updateBetokenFundAddress();
  }

  /**
   * @notice Transfers assets to the next version.
   * @param _assetAddress the address of the asset to be transferred. Use ETH_TOKEN_ADDRESS to transfer Ether.
   */
  function transferAssetToNextVersion(address _assetAddress) public nonReentrant readyForUpgradeMigration isValidToken(_assetAddress) {
    if (_assetAddress == address(ETH_TOKEN_ADDRESS)) {
      nextVersion.transfer(address(this).balance);
    } else {
      ERC20Detailed token = ERC20Detailed(_assetAddress);
      require(token.transfer(nextVersion, token.balanceOf(address(this))));
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
   * @notice Returns the length of the user's compound orders array.
   * @return length of the user's compound orders array
   */
  function compoundOrdersCount(address _userAddr) public view returns(uint256 _count) {
    return userCompoundOrders[_userAddr].length;
  }

  /**
   * @notice Returns the phaseLengths array.
   * @return the phaseLengths array
   */
  function getPhaseLengths() public view returns(uint256[2] memory _phaseLengths) {
    return phaseLengths;
  }

  /**
   * @notice Returns the commission balance of `_manager`
   * @return the commission balance and the received penalty, denoted in DAI
   */
  function commissionBalanceOf(address _manager) public view returns (uint256 _commission, uint256 _penalty) {
    if (lastCommissionRedemption[_manager] >= cycleNumber) { return (0, 0); }
    uint256 cycle = lastCommissionRedemption[_manager] > 0 ? lastCommissionRedemption[_manager] : 1;
    uint256 cycleCommission;
    uint256 cyclePenalty;
    for (; cycle < cycleNumber; cycle = cycle.add(1)) {
      (cycleCommission, cyclePenalty) = commissionOfAt(_manager, cycle);
      _commission = _commission.add(cycleCommission);
      _penalty = _penalty.add(cyclePenalty);
    }
  }

  /**
   * @notice Returns the commission amount received by `_manager` in the `_cycle`th cycle
   * @return the commission amount and the received penalty, denoted in DAI
   */
  function commissionOfAt(address _manager, uint256 _cycle) public view returns (uint256 _commission, uint256 _penalty) {
    if (hasRedeemedCommissionForCycle[_manager][_cycle]) { return (0, 0); }
    // take risk into account
    uint256 baseKairoBalance = cToken.balanceOfAt(_manager, managePhaseEndBlock[_cycle.sub(1)]);
    uint256 baseStake = baseKairoBalance == 0 ? baseRiskStakeFallback[_manager] : baseKairoBalance;
    if (baseKairoBalance == 0 && baseRiskStakeFallback[_manager] == 0) { return (0, 0); }
    uint256 riskTakenProportion = riskTakenInCycle[_manager][_cycle].mul(PRECISION).div(baseStake.mul(MIN_RISK_TIME)); // risk / threshold
    riskTakenProportion = riskTakenProportion > PRECISION ? PRECISION : riskTakenProportion; // max proportion is 1

    uint256 fullCommission = totalCommissionOfCycle[_cycle].mul(cToken.balanceOfAt(_manager, managePhaseEndBlock[_cycle]))
      .div(cToken.totalSupplyAt(managePhaseEndBlock[_cycle]));

    _commission = fullCommission.mul(riskTakenProportion).div(PRECISION);
    _penalty = fullCommission.sub(_commission);
  }

  /**
   * Parameter setters
   */

  /**
   * @notice Changes the address to which the developer fees will be sent. Only callable by owner.
   * @param _newAddr the new developer fee address
   */
  function changeDeveloperFeeAccount(address payable _newAddr) public onlyOwner {
    require(_newAddr != address(0) && _newAddr != address(this));
    devFundingAccount = _newAddr;
  }

  /**
   * @notice Changes the proportion of fund balance sent to the developers each cycle. May only decrease. Only callable by owner.
   * @param _newProp the new proportion, fixed point decimal
   */
  function changeDeveloperFeeRate(uint256 _newProp) public onlyOwner {
    require(_newProp < PRECISION);
    require(_newProp < devFundingRate);
    devFundingRate = _newProp;
  }

  /**
   * @notice Allows managers to invest in a token. Only callable by owner.
   * @param _token address of the token to be listed
   */
  function listKyberToken(address _token) public onlyOwner {
    isKyberToken[_token] = true;
  }

  /**
   * @notice Moves the fund to the next phase in the investment cycle.
   */
  function nextPhase()
    public
  {
    (bool success,) = betokenLogic.delegatecall(abi.encodeWithSelector(this.nextPhase.selector));
    if (!success) { revert(); }
  }


  /**
   * Manager registration
   */

  /**
   * @notice Registers `msg.sender` as a manager, using DAI as payment. The more one pays, the more Kairo one gets.
   *         There's a max Kairo amount that can be bought, and excess payment will be sent back to sender.
   * @param _donationInDAI the amount of DAI to be used for registration
   */
  function registerWithDAI(uint256 _donationInDAI) public nonReentrant {
    (bool success,) = betokenLogic.delegatecall(abi.encodeWithSelector(this.registerWithDAI.selector, _donationInDAI));
    if (!success) { revert(); }
  }

  /**
   * @notice Registers `msg.sender` as a manager, using ETH as payment. The more one pays, the more Kairo one gets.
   *         There's a max Kairo amount that can be bought, and excess payment will be sent back to sender.
   */
  function registerWithETH() public payable nonReentrant {
    (bool success,) = betokenLogic.delegatecall(abi.encodeWithSelector(this.registerWithETH.selector));
    if (!success) { revert(); }
  }

  /**
   * @notice Registers `msg.sender` as a manager, using tokens as payment. The more one pays, the more Kairo one gets.
   *         There's a max Kairo amount that can be bought, and excess payment will be sent back to sender.
   * @param _token the token to be used for payment
   * @param _donationInTokens the amount of tokens to be used for registration, should use the token's native decimals
   */
  function registerWithToken(address _token, uint256 _donationInTokens) public nonReentrant {
    (bool success,) = betokenLogic.delegatecall(abi.encodeWithSelector(this.registerWithToken.selector, _token, _donationInTokens));
    if (!success) { revert(); }
  }


  /**
   * Intermission phase functions
   */

   /**
   * @notice Deposit Ether into the fund. Ether will be converted into DAI.
   */
  function depositEther()
    public
    payable
    during(CyclePhase.Intermission)
    nonReentrant
    notReadyForUpgrade
  {
    // Buy DAI with ETH
    uint256 actualDAIDeposited;
    uint256 actualETHDeposited;
    (,, actualDAIDeposited, actualETHDeposited) = __kyberTrade(ETH_TOKEN_ADDRESS, msg.value, dai);

    // Send back leftover ETH
    uint256 leftOverETH = msg.value.sub(actualETHDeposited);
    if (leftOverETH > 0) {
      msg.sender.transfer(leftOverETH);
    }

    // Register investment
    __deposit(actualDAIDeposited);

    // Emit event
    emit Deposit(cycleNumber, msg.sender, address(ETH_TOKEN_ADDRESS), actualETHDeposited, actualDAIDeposited, now);
  }

  /**
   * @notice Deposit DAI Stablecoin into the fund.
   * @param _daiAmount The amount of DAI to be deposited. May be different from actual deposited amount.
   */
  function depositDAI(uint256 _daiAmount)
    public
    during(CyclePhase.Intermission)
    nonReentrant
    notReadyForUpgrade
  {
    require(dai.transferFrom(msg.sender, address(this), _daiAmount));

    // Register investment
    __deposit(_daiAmount);

    // Emit event
    emit Deposit(cycleNumber, msg.sender, DAI_ADDR, _daiAmount, _daiAmount, now);
  }

  /**
   * @notice Deposit ERC20 tokens into the fund. Tokens will be converted into DAI.
   * @param _tokenAddr the address of the token to be deposited
   * @param _tokenAmount The amount of tokens to be deposited. May be different from actual deposited amount.
   */
  function depositToken(address _tokenAddr, uint256 _tokenAmount)
    public
    nonReentrant
    during(CyclePhase.Intermission)
    isValidToken(_tokenAddr)  
    notReadyForUpgrade
  {
    require(_tokenAddr != DAI_ADDR && _tokenAddr != address(ETH_TOKEN_ADDRESS));

    ERC20Detailed token = ERC20Detailed(_tokenAddr);

    require(token.transferFrom(msg.sender, address(this), _tokenAmount));

    // Convert token into DAI
    uint256 actualDAIDeposited;
    uint256 actualTokenDeposited;
    (,, actualDAIDeposited, actualTokenDeposited) = __kyberTrade(token, _tokenAmount, dai);

    // Give back leftover tokens
    uint256 leftOverTokens = _tokenAmount.sub(actualTokenDeposited);
    if (leftOverTokens > 0) {
      require(token.transfer(msg.sender, leftOverTokens));
    }

    // Register investment
    __deposit(actualDAIDeposited);

    // Emit event
    emit Deposit(cycleNumber, msg.sender, _tokenAddr, actualTokenDeposited, actualDAIDeposited, now);
  }


  /**
   * @notice Withdraws Ether by burning Shares.
   * @param _amountInDAI Amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
   */
  function withdrawEther(uint256 _amountInDAI)
    public
    during(CyclePhase.Intermission)
    nonReentrant
  {
    // Buy ETH
    uint256 actualETHWithdrawn;
    uint256 actualDAIWithdrawn;
    (,, actualETHWithdrawn, actualDAIWithdrawn) = __kyberTrade(dai, _amountInDAI, ETH_TOKEN_ADDRESS);

    __withdraw(actualDAIWithdrawn);

    // Transfer Ether to user
    msg.sender.transfer(actualETHWithdrawn);

    // Emit event
    emit Withdraw(cycleNumber, msg.sender, address(ETH_TOKEN_ADDRESS), actualETHWithdrawn, actualDAIWithdrawn, now);
  }

  /**
   * @notice Withdraws Ether by burning Shares.
   * @param _amountInDAI Amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
   */
  function withdrawDAI(uint256 _amountInDAI)
    public
    during(CyclePhase.Intermission)
    nonReentrant
  {
    __withdraw(_amountInDAI);

    // Transfer DAI to user
    require(dai.transfer(msg.sender, _amountInDAI));

    // Emit event
    emit Withdraw(cycleNumber, msg.sender, DAI_ADDR, _amountInDAI, _amountInDAI, now);
  }

  /**
   * @notice Withdraws funds by burning Shares, and converts the funds into the specified token using Kyber Network.
   * @param _tokenAddr the address of the token to be withdrawn into the caller's account
   * @param _amountInDAI The amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
   */
  function withdrawToken(address _tokenAddr, uint256 _amountInDAI)
    public
    nonReentrant
    during(CyclePhase.Intermission)
    isValidToken(_tokenAddr)
  {
    require(_tokenAddr != DAI_ADDR && _tokenAddr != address(ETH_TOKEN_ADDRESS));

    ERC20Detailed token = ERC20Detailed(_tokenAddr);

    // Convert DAI into desired tokens
    uint256 actualTokenWithdrawn;
    uint256 actualDAIWithdrawn;
    (,, actualTokenWithdrawn, actualDAIWithdrawn) = __kyberTrade(dai, _amountInDAI, token);

    __withdraw(actualDAIWithdrawn);

    // Transfer tokens to user
    require(token.transfer(msg.sender, actualTokenWithdrawn));

    // Emit event
    emit Withdraw(cycleNumber, msg.sender, _tokenAddr, actualTokenWithdrawn, actualDAIWithdrawn, now);
  }

  /**
   * @notice Redeems commission.
   */
  function redeemCommission(bool _inShares)
    public
    during(CyclePhase.Intermission)
    nonReentrant
  {
    uint256 commission = __redeemCommission();

    if (_inShares) {
      // Deposit commission into fund
      __deposit(commission);

      // Emit deposit event
      emit Deposit(cycleNumber, msg.sender, DAI_ADDR, commission, commission, now);
    } else {
      // Transfer the commission in DAI
      require(dai.transfer(msg.sender, commission));
    }
  }

  /**
   * @notice Redeems commission for a particular cycle.
   * @param _inShares true to redeem in Betoken Shares, false to redeem in DAI
   * @param _cycle the cycle for which the commission will be redeemed.
   *        Commissions for a cycle will be redeemed during the Intermission phase of the next cycle, so _cycle must < cycleNumber.
   */
  function redeemCommissionForCycle(bool _inShares, uint256 _cycle)
    public
    during(CyclePhase.Intermission)
    nonReentrant
  {
    require(_cycle < cycleNumber);

    uint256 commission = __redeemCommissionForCycle(_cycle);

    if (_inShares) {
      // Deposit commission into fund
      __deposit(commission);

      // Emit deposit event
      emit Deposit(cycleNumber, msg.sender, DAI_ADDR, commission, commission, now);
    } else {
      // Transfer the commission in DAI
      require(dai.transfer(msg.sender, commission));
    }
  }

  /**
   * @notice Sells tokens left over due to manager not selling or KyberNetwork not having enough volume. Callable by anyone. Money goes to developer.
   * @param _tokenAddr address of the token to be sold
   */
  function sellLeftoverToken(address _tokenAddr)
    public
    nonReentrant
    during(CyclePhase.Intermission)
    isValidToken(_tokenAddr)
  {
    ERC20Detailed token = ERC20Detailed(_tokenAddr);
    (,,uint256 actualDAIReceived,) = __kyberTrade(token, getBalance(token, address(this)), dai);
    totalFundsInDAI = totalFundsInDAI.add(actualDAIReceived);
  }

  /**
   * @notice Sells CompoundOrder left over due to manager not selling or KyberNetwork not having enough volume. Callable by anyone. Money goes to developer.
   * @param _orderAddress address of the CompoundOrder to be sold
   */
  function sellLeftoverCompoundOrder(address payable _orderAddress)
    public
    nonReentrant
    during(CyclePhase.Intermission)
  {
    // Load order info
    require(_orderAddress != address(0));
    CompoundOrder order = CompoundOrder(_orderAddress);
    require(order.isSold() == false && order.cycleNumber() < cycleNumber);

    // Sell short order
    // Not using outputAmount returned by order.sellOrder() because _orderAddress could point to a malicious contract
    uint256 beforeDAIBalance = dai.balanceOf(address(this));
    order.sellOrder(0, MAX_QTY);
    uint256 actualDAIReceived = dai.balanceOf(address(this)).sub(beforeDAIBalance);

    totalFundsInDAI = totalFundsInDAI.add(actualDAIReceived);
  }

  /**
   * @notice Burns the Kairo balance of a manager who has been inactive for a certain number of cycles
   * @param _deadman the manager whose Kairo balance will be burned
   */
  function burnDeadman(address _deadman)
    public
    nonReentrant
    during(CyclePhase.Intermission)
  {
    require(_deadman != address(this));
    require(cycleNumber.sub(lastActiveCycle[_deadman]) >= INACTIVE_THRESHOLD);
    require(cToken.destroyTokens(_deadman, cToken.balanceOf(_deadman)));
  }

  /**
   * Manage phase functions
   */

  /**
   * @notice Creates a new investment for an ERC20 token.
   * @param _tokenAddress address of the ERC20 token contract
   * @param _stake amount of Kairos to be staked in support of the investment
   * @param _minPrice the minimum price for the trade
   * @param _maxPrice the maximum price for the trade
   */
  function createInvestment(
    address _tokenAddress,
    uint256 _stake,
    uint256 _minPrice,
    uint256 _maxPrice
  )
    public
    nonReentrant
    isValidToken(_tokenAddress)
    during(CyclePhase.Manage)
  {
    (bool success,) = betokenLogic.delegatecall(abi.encodeWithSelector(this.createInvestment.selector, _tokenAddress, _stake, _minPrice, _maxPrice));
    if (!success) { revert(); }
  }

  /**
   * @notice Called by user to sell the assets an investment invested in. Returns the staked Kairo plus rewards/penalties to the user.
   *         The user can sell only part of the investment by changing _tokenAmount.
   * @dev When selling only part of an investment, the old investment would be "fully" sold and a new investment would be created with
   *   the original buy price and however much tokens that are not sold.
   * @param _investmentId the ID of the investment
   * @param _tokenAmount the amount of tokens to be sold.
   * @param _minPrice the minimum price for the trade
   * @param _maxPrice the maximum price for the trade
   */
  function sellInvestmentAsset(
    uint256 _investmentId,
    uint256 _tokenAmount,
    uint256 _minPrice,
    uint256 _maxPrice
  )
    public
    during(CyclePhase.Manage)
    nonReentrant
  {
    (bool success,) = betokenLogic.delegatecall(abi.encodeWithSelector(this.sellInvestmentAsset.selector, _investmentId, _tokenAmount, _minPrice, _maxPrice));
    if (!success) { revert(); }
  }

  /**
   * @notice Creates a new Compound order to either short or leverage long a token.
   * @param _orderType true for a short order, false for a levarage long order
   * @param _tokenAddress address of the Compound token to be traded
   * @param _stake amount of Kairos to be staked
   * @param _minPrice the minimum token price for the trade
   * @param _maxPrice the maximum token price for the trade
   */
  function createCompoundOrder(
    bool _orderType,
    address _tokenAddress,
    uint256 _stake,
    uint256 _minPrice,
    uint256 _maxPrice
  )
    public
    nonReentrant
    during(CyclePhase.Manage)
    isValidToken(_tokenAddress)
  {
    (bool success,) = betokenLogic.delegatecall(abi.encodeWithSelector(this.createCompoundOrder.selector, _orderType, _tokenAddress, _stake, _minPrice, _maxPrice));
    if (!success) { revert(); }
  }

  /**
   * @notice Sells a compound order
   * @param _orderId the ID of the order to be sold (index in userCompoundOrders[msg.sender])
   * @param _minPrice the minimum token price for the trade
   * @param _maxPrice the maximum token price for the trade
   */
  function sellCompoundOrder(
    uint256 _orderId,
    uint256 _minPrice,
    uint256 _maxPrice
  )
    public
    during(CyclePhase.Manage)
    nonReentrant
  {
    (bool success,) = betokenLogic.delegatecall(abi.encodeWithSelector(this.sellCompoundOrder.selector, _orderId, _minPrice, _maxPrice));
    if (!success) { revert(); }
  }

  /**
   * @notice Repys debt for a Compound order to prevent the collateral ratio from dropping below threshold.
   * @param _orderId the ID of the Compound order
   * @param _repayAmountInDAI amount of DAI to use for repaying debt
   */
  function repayCompoundOrder(uint256 _orderId, uint256 _repayAmountInDAI) public during(CyclePhase.Manage) nonReentrant {
    (bool success,) = betokenLogic.delegatecall(abi.encodeWithSelector(this.repayCompoundOrder.selector, _orderId, _repayAmountInDAI));
    if (!success) { revert(); }
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

  /**
   * @notice Notifies the controller about an approval allowing the
   *  controller to react if desired
   * @param _owner The address that calls `approve()`
   * @param _spender The spender in the `approve()` call
   * @param _amount The amount in the `approve()` call
   * @return False if the controller does not authorize the approval
   */
  function onApprove(address _owner, address _spender, uint _amount) public
      returns(bool) {
    return true;
  }

  /**
   * @notice Handles deposits by minting Betoken Shares & updating total funds.
   * @param _depositDAIAmount The amount of the deposit in DAI
   */
  function __deposit(uint256 _depositDAIAmount) internal {
    // Register investment and give shares
    if (sToken.totalSupply() == 0 || totalFundsInDAI == 0) {
      require(sToken.generateTokens(msg.sender, _depositDAIAmount));
    } else {
      require(sToken.generateTokens(msg.sender, _depositDAIAmount.mul(sToken.totalSupply()).div(totalFundsInDAI)));
    }
    totalFundsInDAI = totalFundsInDAI.add(_depositDAIAmount);
  }

  /**
   * @notice Handles deposits by burning Betoken Shares & updating total funds.
   * @param _withdrawDAIAmount The amount of the withdrawal in DAI
   */
  function __withdraw(uint256 _withdrawDAIAmount) internal {
    // Burn Shares
    require(sToken.destroyTokens(msg.sender, _withdrawDAIAmount.mul(sToken.totalSupply()).div(totalFundsInDAI)));
    totalFundsInDAI = totalFundsInDAI.sub(_withdrawDAIAmount);
  }

  /**
   * @notice Redeems the commission for all previous cycles. Updates the related variables.
   * @return the amount of commission to be redeemed
   */
  function __redeemCommission() internal returns (uint256 _commission) {
    require(lastCommissionRedemption[msg.sender] < cycleNumber);

    uint256 penalty; // penalty received for not taking enough risk
    (_commission, penalty) = commissionBalanceOf(msg.sender);

    // record the redemption to prevent double-redemption
    for (uint256 i = lastCommissionRedemption[msg.sender]; i < cycleNumber; i = i.add(1)) {
      hasRedeemedCommissionForCycle[msg.sender][i] = true;
    }
    lastCommissionRedemption[msg.sender] = cycleNumber;

    // record the decrease in commission pool
    totalCommissionLeft = totalCommissionLeft.sub(_commission);
    // include commission penalty to this cycle's total commission pool
    totalCommissionOfCycle[cycleNumber] = totalCommissionOfCycle[cycleNumber].add(penalty);
    // clear investment arrays to save space
    delete userInvestments[msg.sender];
    delete userCompoundOrders[msg.sender];

    emit CommissionPaid(cycleNumber, msg.sender, _commission);
  }

  /**
   * @notice Redeems commission for a particular cycle. Updates the related variables.
   * @param _cycle the cycle for which the commission will be redeemed
   * @return the amount of commission to be redeemed
   */
  function __redeemCommissionForCycle(uint256 _cycle) internal returns (uint256 _commission) {
    require(!hasRedeemedCommissionForCycle[msg.sender][_cycle]);

    uint256 penalty; // penalty received for not taking enough risk
    (_commission, penalty) = commissionOfAt(msg.sender, _cycle);

    hasRedeemedCommissionForCycle[msg.sender][_cycle] = true;

    // record the decrease in commission pool
    totalCommissionLeft = totalCommissionLeft.sub(_commission);
    // include commission penalty to this cycle's total commission pool
    totalCommissionOfCycle[cycleNumber] = totalCommissionOfCycle[cycleNumber].add(penalty);
    // clear investment arrays to save space
    delete userInvestments[msg.sender];
    delete userCompoundOrders[msg.sender];

    emit CommissionPaid(_cycle, msg.sender, _commission);
  }

  function() external payable {}
}