pragma solidity 0.5.13;

import "./BetokenStorage.sol";
import "./interfaces/PositionToken.sol";
import "./derivatives/CompoundOrderFactory.sol";

/**
 * @title Part of the functions for BetokenFund
 * @author Zefram Lou (Zebang Liu)
 */
contract BetokenLogic is BetokenStorage, Utils(address(0), address(0), address(0)) {
  /**
   * @notice Executes function only during the given cycle phase.
   * @param phase the cycle phase during which the function may be called
   */
  modifier during(CyclePhase phase) {
    require(cyclePhase == phase);
    if (cyclePhase == CyclePhase.Intermission) {
      require(isInitialized);
    }
    _;
  }

  /**
   * @notice Returns the length of the user's investments array.
   * @return length of the user's investments array
   */
  function investmentsCount(address _userAddr) public view returns(uint256 _count) {
    return userInvestments[_userAddr].length;
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
    require(cycleNumber.sub(lastActiveCycle(_deadman)) > INACTIVE_THRESHOLD);
    require(cToken.destroyTokens(_deadman, cToken.balanceOf(_deadman)));
  }

  /**
   * @notice Creates a new investment for an ERC20 token. Backwards compatible.
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
  {
    bytes memory nil;
    createInvestmentV2(
      _tokenAddress,
      _stake,
      _minPrice,
      _maxPrice,
      nil,
      true
    );
  }

  /**
   * @notice Called by user to sell the assets an investment invested in. Returns the staked Kairo plus rewards/penalties to the user.
   *         The user can sell only part of the investment by changing _tokenAmount. Backwards compatible.
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
  {
    bytes memory nil;
    sellInvestmentAssetV2(
      _investmentId,
      _tokenAmount,
      _minPrice,
      _maxPrice,
      nil,
      true
    );
  }

  /**
   * @notice Creates a new investment for an ERC20 token.
   * @param _tokenAddress address of the ERC20 token contract
   * @param _stake amount of Kairos to be staked in support of the investment
   * @param _minPrice the minimum price for the trade
   * @param _maxPrice the maximum price for the trade
   * @param _calldata calldata for dex.ag trading
   * @param _useKyber true for Kyber Network, false for dex.ag
   */
  function createInvestmentV2(
    address _tokenAddress,
    uint256 _stake,
    uint256 _minPrice,
    uint256 _maxPrice,
    bytes memory _calldata,
    bool _useKyber
  )
    public
    during(CyclePhase.Manage)
    nonReentrant
    isValidToken(_tokenAddress)
  {
    require(_minPrice <= _maxPrice);
    require(_stake > 0);
    require(isKyberToken[_tokenAddress] || isPositionToken[_tokenAddress]);

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
      buyTime: now,
      buyCostInDAI: 0,
      isSold: false
    }));

    // Invest
    uint256 investmentId = investmentsCount(msg.sender).sub(1);
    __handleInvestment(investmentId, _minPrice, _maxPrice, true, _calldata, _useKyber);

    // Update last active cycle
    _lastActiveCycle[msg.sender] = cycleNumber;

    // Emit event
    __emitCreatedInvestmentEvent(investmentId);
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
  function sellInvestmentAssetV2(
    uint256 _investmentId,
    uint256 _tokenAmount,
    uint256 _minPrice,
    uint256 _maxPrice,
    bytes memory _calldata,
    bool _useKyber
  )
    public
    during(CyclePhase.Manage)
    nonReentrant
  {
    Investment storage investment = userInvestments[msg.sender][_investmentId];
    require(investment.buyPrice > 0 && investment.cycleNumber == cycleNumber && !investment.isSold);
    require(_tokenAmount > 0 && _tokenAmount <= investment.tokenAmount);
    require(_minPrice <= _maxPrice);

    // Create new investment for leftover tokens
    bool isPartialSell = false;
    uint256 stakeOfSoldTokens = investment.stake.mul(_tokenAmount).div(investment.tokenAmount);
    if (_tokenAmount != investment.tokenAmount) {
      isPartialSell = true;

      __createInvestmentForLeftovers(_investmentId, _tokenAmount);
    }
    
    // Update investment info
    investment.isSold = true;

    // Sell asset
    (uint256 actualDestAmount, uint256 actualSrcAmount) = __handleInvestment(_investmentId, _minPrice, _maxPrice, false, _calldata, _useKyber);
    if (isPartialSell) {
      // If only part of _tokenAmount was successfully sold, put the unsold tokens in the new investment
      userInvestments[msg.sender][investmentsCount(msg.sender).sub(1)].tokenAmount = userInvestments[msg.sender][investmentsCount(msg.sender).sub(1)].tokenAmount.add(_tokenAmount.sub(actualSrcAmount));
    }

    // Return staked Kairo
    uint256 receiveKairoAmount = getReceiveKairoAmount(stakeOfSoldTokens, investment.sellPrice, investment.buyPrice);
    __returnStake(receiveKairoAmount, stakeOfSoldTokens);

    // Record risk taken in investment
    __recordRisk(investment.stake, investment.buyTime);

    // Update total funds
    totalFundsInDAI = totalFundsInDAI.sub(investment.buyCostInDAI).add(actualDestAmount);
    
    // Emit event
    if (isPartialSell) {
      __emitCreatedInvestmentEvent(investmentsCount(msg.sender).sub(1));
    }
    __emitSoldInvestmentEvent(_investmentId, receiveKairoAmount, actualDestAmount);
  }

  function __emitSoldInvestmentEvent(uint256 _investmentId, uint256 _receiveKairoAmount, uint256 _actualDestAmount) internal {
    Investment storage investment = userInvestments[msg.sender][_investmentId];
    emit SoldInvestment(cycleNumber, msg.sender, _investmentId, investment.tokenAddress, _receiveKairoAmount, investment.sellPrice, _actualDestAmount);
  }

  function __createInvestmentForLeftovers(uint256 _investmentId, uint256 _tokenAmount) internal {
    Investment storage investment = userInvestments[msg.sender][_investmentId];

    uint256 stakeOfSoldTokens = investment.stake.mul(_tokenAmount).div(investment.tokenAmount);

    // calculate the part of original DAI cost attributed to the sold tokens
    uint256 soldBuyCostInDAI = investment.buyCostInDAI.mul(_tokenAmount).div(investment.tokenAmount);

    userInvestments[msg.sender].push(Investment({
      tokenAddress: investment.tokenAddress,
      cycleNumber: cycleNumber,
      stake: investment.stake.sub(stakeOfSoldTokens),
      tokenAmount: investment.tokenAmount.sub(_tokenAmount),
      buyPrice: investment.buyPrice,
      sellPrice: 0,
      buyTime: investment.buyTime,
      buyCostInDAI: investment.buyCostInDAI.sub(soldBuyCostInDAI),
      isSold: false
    }));

    // update the investment object being sold
    investment.tokenAmount = _tokenAmount;
    investment.stake = stakeOfSoldTokens;
    investment.buyCostInDAI = soldBuyCostInDAI;
  }

  function __emitCreatedInvestmentEvent(uint256 _id) internal {
    Investment storage investment = userInvestments[msg.sender][_id];
    emit CreatedInvestment(
      cycleNumber, msg.sender, _id,
      investment.tokenAddress, investment.stake, investment.buyPrice,
      investment.buyCostInDAI, investment.tokenAmount);
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
    during(CyclePhase.Manage)
    nonReentrant
    isValidToken(_tokenAddress)
  {
    require(_minPrice <= _maxPrice);
    require(_stake > 0);
    require(isCompoundToken[_tokenAddress]);

    // Collect stake
    require(cToken.generateTokens(address(this), _stake));
    require(cToken.destroyTokens(msg.sender, _stake));

    // Create compound order and execute
    uint256 collateralAmountInDAI = totalFundsInDAI.mul(_stake).div(cToken.totalSupply());
    CompoundOrder order = __createCompoundOrder(_orderType, _tokenAddress, _stake, collateralAmountInDAI);
    dai.safeApprove(address(order), 0);
    dai.safeApprove(address(order), collateralAmountInDAI);
    order.executeOrder(_minPrice, _maxPrice);

    // Add order to list
    userCompoundOrders[msg.sender].push(address(order));

    // Update last active cycle
    _lastActiveCycle[msg.sender] = cycleNumber;

    // Emit event
    emit CreatedCompoundOrder(cycleNumber, msg.sender, userCompoundOrders[msg.sender].length - 1, address(order), _orderType, _tokenAddress, _stake, collateralAmountInDAI);
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
    // Load order info
    require(userCompoundOrders[msg.sender][_orderId] != address(0));
    CompoundOrder order = CompoundOrder(userCompoundOrders[msg.sender][_orderId]);
    require(order.isSold() == false && order.cycleNumber() == cycleNumber);

    // Sell order
    (uint256 inputAmount, uint256 outputAmount) = order.sellOrder(_minPrice, _maxPrice);

    // Return staked Kairo
    uint256 stake = order.stake();
    uint256 receiveKairoAmount = getReceiveKairoAmount(stake, outputAmount, inputAmount);
    __returnStake(receiveKairoAmount, stake);

    // Record risk taken
    __recordRisk(stake, order.buyTime());

    // Update total funds
    totalFundsInDAI = totalFundsInDAI.sub(inputAmount).add(outputAmount);

    // Emit event
    emit SoldCompoundOrder(cycleNumber, msg.sender, userCompoundOrders[msg.sender].length - 1, address(order), order.orderType(), order.compoundTokenAddr(), receiveKairoAmount, outputAmount);
  }

  /**
   * @notice Repys debt for a Compound order to prevent the collateral ratio from dropping below threshold.
   * @param _orderId the ID of the Compound order
   * @param _repayAmountInDAI amount of DAI to use for repaying debt
   */
  function repayCompoundOrder(uint256 _orderId, uint256 _repayAmountInDAI) public during(CyclePhase.Manage) nonReentrant {
    // Load order info
    require(userCompoundOrders[msg.sender][_orderId] != address(0));
    CompoundOrder order = CompoundOrder(userCompoundOrders[msg.sender][_orderId]);
    require(order.isSold() == false && order.cycleNumber() == cycleNumber);

    // Repay loan
    order.repayLoan(_repayAmountInDAI);

    // Emit event
    emit RepaidCompoundOrder(cycleNumber, msg.sender, userCompoundOrders[msg.sender].length - 1, address(order), _repayAmountInDAI);
  }

  function getReceiveKairoAmount(uint256 stake, uint256 output, uint256 input) public pure returns(uint256 _amount) {
    if (output >= input) {
      // positive ROI, simply return stake * (1 + ROI)
      return stake.mul(output).div(input);
    } else {
      // negative ROI
      uint256 absROI = input.sub(output).mul(PRECISION).div(input);
      if (absROI <= ROI_PUNISH_THRESHOLD) {
        // ROI better than -10%, no punishment
        return stake.mul(output).div(input);
      } else if (absROI > ROI_PUNISH_THRESHOLD && absROI < ROI_BURN_THRESHOLD) {
        // ROI between -10% and -25%, punish
        // return stake * (1 + roiWithPunishment) = stake * (1 + (-(6 * absROI - 0.5)))
        return stake.mul(PRECISION.sub(ROI_PUNISH_SLOPE.mul(absROI).sub(ROI_PUNISH_NEG_BIAS))).div(PRECISION);
      } else {
        // ROI greater than 25%, burn all stake
        return 0;
      }
    }
  }

  /**
   * @notice Returns the commission balance of `_manager`
   * @return the commission balance and the received penalty, denoted in DAI
   */
  function commissionBalanceOf(address _manager) public view returns (uint256 _commission, uint256 _penalty) {
    if (lastCommissionRedemption(_manager) >= cycleNumber) { return (0, 0); }
    uint256 cycle = lastCommissionRedemption(_manager) > 0 ? lastCommissionRedemption(_manager) : 1;
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
    if (hasRedeemedCommissionForCycle(_manager, _cycle)) { return (0, 0); }
    // take risk into account
    uint256 baseKairoBalance = cToken.balanceOfAt(_manager, managePhaseEndBlock(_cycle.sub(1)));
    uint256 baseStake = baseKairoBalance == 0 ? baseRiskStakeFallback(_manager) : baseKairoBalance;
    if (baseKairoBalance == 0 && baseRiskStakeFallback(_manager) == 0) { return (0, 0); }
    uint256 riskTakenProportion = riskTakenInCycle(_manager, _cycle).mul(PRECISION).div(baseStake.mul(MIN_RISK_TIME)); // risk / threshold
    riskTakenProportion = riskTakenProportion > PRECISION ? PRECISION : riskTakenProportion; // max proportion is 1

    uint256 fullCommission = totalCommissionOfCycle(_cycle).mul(cToken.balanceOfAt(_manager, managePhaseEndBlock(_cycle)))
      .div(cToken.totalSupplyAt(managePhaseEndBlock(_cycle)));

    _commission = fullCommission.mul(riskTakenProportion).div(PRECISION);
    _penalty = fullCommission.sub(_commission);
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
      dai.safeTransfer(msg.sender, commission);
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
      dai.safeTransfer(msg.sender, commission);
    }
  }

  /**
   * @notice Handles and investment by doing the necessary trades using __kyberTrade() or Fulcrum trading
   * @param _investmentId the ID of the investment to be handled
   * @param _minPrice the minimum price for the trade
   * @param _maxPrice the maximum price for the trade
   * @param _buy whether to buy or sell the given investment
   * @param _calldata calldata for dex.ag trading
   * @param _useKyber true for Kyber Network, false for dex.ag
   */
  function __handleInvestment(uint256 _investmentId, uint256 _minPrice, uint256 _maxPrice, bool _buy, bytes memory _calldata, bool _useKyber)
    public
    returns (uint256 _actualDestAmount, uint256 _actualSrcAmount)
  {
    Investment storage investment = userInvestments[msg.sender][_investmentId];
    address token = investment.tokenAddress;
    if (isPositionToken[token]) {
      // Fulcrum trading
      PositionToken pToken = PositionToken(token);
      uint256 beforeBalance;
      if (_buy) {
        _actualSrcAmount = totalFundsInDAI.mul(investment.stake).div(cToken.totalSupply());
        dai.safeApprove(token, 0);
        dai.safeApprove(token, _actualSrcAmount);
        beforeBalance = pToken.balanceOf(address(this));
        pToken.mintWithToken(address(this), DAI_ADDR, _actualSrcAmount, 0);
        _actualDestAmount = pToken.balanceOf(address(this)).sub(beforeBalance);
        require(_actualDestAmount > 0);
        dai.safeApprove(token, 0);

        investment.buyPrice = calcRateFromQty(_actualDestAmount, _actualSrcAmount, pToken.decimals(), dai.decimals()); // price of pToken in DAI
        require(_minPrice <= investment.buyPrice && investment.buyPrice <= _maxPrice);

        investment.tokenAmount = _actualDestAmount;
        investment.buyCostInDAI = _actualSrcAmount;
      } else {
        _actualSrcAmount = investment.tokenAmount;
        beforeBalance = dai.balanceOf(address(this));
        pToken.burnToToken(address(this), DAI_ADDR, _actualSrcAmount, 0);
        _actualDestAmount = dai.balanceOf(address(this)).sub(beforeBalance);

        investment.sellPrice = calcRateFromQty(_actualSrcAmount, _actualDestAmount, pToken.decimals(), dai.decimals()); // price of pToken in DAI
        require(_minPrice <= investment.sellPrice && investment.sellPrice <= _maxPrice);
      }
    } else {
      // Basic trading
      uint256 dInS; // price of dest token denominated in src token
      uint256 sInD; // price of src token denominated in dest token
      if (_buy) {
        if (_useKyber) {
          (dInS, sInD, _actualDestAmount, _actualSrcAmount) = __kyberTrade(dai, totalFundsInDAI.mul(investment.stake).div(cToken.totalSupply()), ERC20Detailed(token));
        } else {
          // dex.ag trading
          (dInS, sInD, _actualDestAmount, _actualSrcAmount) = __dexagTrade(dai, totalFundsInDAI.mul(investment.stake).div(cToken.totalSupply()), ERC20Detailed(token), _calldata);
        }
        require(_minPrice <= dInS && dInS <= _maxPrice);
        investment.buyPrice = dInS;
        investment.tokenAmount = _actualDestAmount;
        investment.buyCostInDAI = _actualSrcAmount;
      } else {
        if (_useKyber) {
          (dInS, sInD, _actualDestAmount, _actualSrcAmount) = __kyberTrade(ERC20Detailed(token), investment.tokenAmount, dai);
        } else {
          (dInS, sInD, _actualDestAmount, _actualSrcAmount) = __dexagTrade(ERC20Detailed(token), investment.tokenAmount, dai, _calldata);
        }
        
        require(_minPrice <= sInD && sInD <= _maxPrice);
        investment.sellPrice = sInD;
      }
    }
  }

  /**
   * @notice Separated from createCompoundOrder() to avoid stack too deep error
   */
  function __createCompoundOrder(
    bool _orderType, // True for shorting, false for longing
    address _tokenAddress,
    uint256 _stake,
    uint256 _collateralAmountInDAI
  ) internal returns (CompoundOrder) {
    CompoundOrderFactory factory = CompoundOrderFactory(compoundFactoryAddr);
    uint256 loanAmountInDAI = _collateralAmountInDAI.mul(COLLATERAL_RATIO_MODIFIER).div(PRECISION).mul(factory.getMarketCollateralFactor(_tokenAddress)).div(PRECISION);
    CompoundOrder order = factory.createOrder(
      _tokenAddress,
      cycleNumber,
      _stake,
      _collateralAmountInDAI,
      loanAmountInDAI,
      _orderType
    );
    return order;
  }

  /**
   * @notice Returns stake to manager after investment is sold, including reward/penalty based on performance
   */
  function __returnStake(uint256 _receiveKairoAmount, uint256 _stake) internal {
    require(cToken.destroyTokens(address(this), _stake));
    require(cToken.generateTokens(msg.sender, _receiveKairoAmount));
  }

  /**
   * @notice Records risk taken in a trade based on stake and time of investment
   */
  function __recordRisk(uint256 _stake, uint256 _buyTime) internal {
    _riskTakenInCycle[msg.sender][cycleNumber] = riskTakenInCycle(msg.sender, cycleNumber).add(_stake.mul(now.sub(_buyTime)));
  }

  /**
   * @notice Redeems the commission for all previous cycles. Updates the related variables.
   * @return the amount of commission to be redeemed
   */
  function __redeemCommission() internal returns (uint256 _commission) {
    require(lastCommissionRedemption(msg.sender) < cycleNumber);

    uint256 penalty; // penalty received for not taking enough risk
    (_commission, penalty) = commissionBalanceOf(msg.sender);

    // record the redemption to prevent double-redemption
    for (uint256 i = lastCommissionRedemption(msg.sender); i < cycleNumber; i = i.add(1)) {
      _hasRedeemedCommissionForCycle[msg.sender][i] = true;
    }
    _lastCommissionRedemption[msg.sender] = cycleNumber;

    // record the decrease in commission pool
    totalCommissionLeft = totalCommissionLeft.sub(_commission);
    // include commission penalty to this cycle's total commission pool
    _totalCommissionOfCycle[cycleNumber] = totalCommissionOfCycle(cycleNumber).add(penalty);
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
    require(!hasRedeemedCommissionForCycle(msg.sender, _cycle));

    uint256 penalty; // penalty received for not taking enough risk
    (_commission, penalty) = commissionOfAt(msg.sender, _cycle);

    _hasRedeemedCommissionForCycle[msg.sender][_cycle] = true;

    // record the decrease in commission pool
    totalCommissionLeft = totalCommissionLeft.sub(_commission);
    // include commission penalty to this cycle's total commission pool
    _totalCommissionOfCycle[cycleNumber] = totalCommissionOfCycle(cycleNumber).add(penalty);
    // clear investment arrays to save space
    delete userInvestments[msg.sender];
    delete userCompoundOrders[msg.sender];

    emit CommissionPaid(_cycle, msg.sender, _commission);
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
}