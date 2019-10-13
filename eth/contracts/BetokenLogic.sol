pragma solidity 0.5.12;

import "./BetokenStorage.sol";
import "./interfaces/PositionToken.sol";
import "./derivatives/CompoundOrderFactory.sol";

/**
 * @title Part of the functions for BetokenFund
 * @author Zefram Lou (Zebang Liu)
 */
contract BetokenLogic is BetokenStorage, Utils(address(0), address(0)) {
  /**
   * Next phase transition handler
   * @notice Moves the fund to the next phase in the investment cycle.
   */
  function nextPhase()
    public
  {
    require(proxy.betokenFundAddress() == address(this)); // upgrade complete
    require(now >= startTimeOfCyclePhase.add(phaseLengths[uint(cyclePhase)]));

    if (cycleNumber == 0) {
      require(msg.sender == owner());
    }

    if (cyclePhase == CyclePhase.Intermission) {
      require(hasFinalizedNextVersion == false); // Shouldn't progress to next phase if upgrading

      // Check if there is enough signal supporting upgrade
      if (upgradeSignalStrength[cycleNumber] > getTotalVotingWeight().div(2)) {
        upgradeVotingActive = true;
        emit InitiatedUpgrade(cycleNumber);
      }
    } else if (cyclePhase == CyclePhase.Manage) {
      // Burn any Kairo left in BetokenFund's account
      require(cToken.destroyTokens(address(this), cToken.balanceOf(address(this))));

      // Pay out commissions and fees
      uint256 profit = 0;
      if (getBalance(dai, address(this)) > totalFundsInDAI.add(totalCommissionLeft)) {
        profit = getBalance(dai, address(this)).sub(totalFundsInDAI).sub(totalCommissionLeft);
      }
      uint256 commissionThisCycle = COMMISSION_RATE.mul(profit).add(ASSET_FEE_RATE.mul(getBalance(dai, address(this)))).div(PRECISION);
      _totalCommissionOfCycle[cycleNumber] = totalCommissionOfCycle(cycleNumber).add(commissionThisCycle); // account for penalties
      totalCommissionLeft = totalCommissionLeft.add(commissionThisCycle);

      totalFundsInDAI = getBalance(dai, address(this)).sub(totalCommissionLeft);

      // Give the developer Betoken shares inflation funding
      uint256 devFunding = devFundingRate.mul(sToken.totalSupply()).div(PRECISION);
      require(sToken.generateTokens(devFundingAccount, devFunding));

      // Emit event
      emit TotalCommissionPaid(cycleNumber, totalCommissionOfCycle(cycleNumber));

      _managePhaseEndBlock[cycleNumber] = block.number;

      // Clear/update upgrade related data
      if (nextVersion == address(this)) {
        // The developer proposed a candidate, but the managers decide to not upgrade at all
        // Reset upgrade process
        delete nextVersion;
        delete hasFinalizedNextVersion;
      }
      if (nextVersion == address(0)) {
        delete proposers;
        delete candidates;
        delete forVotes;
        delete againstVotes;
        delete upgradeVotingActive;
        delete proposersVotingWeight;
      } else {
        hasFinalizedNextVersion = true;
        emit FinalizedNextVersion(cycleNumber, nextVersion);
      }

      // Start new cycle
      cycleNumber = cycleNumber.add(1);
    }

    cyclePhase = CyclePhase(addmod(uint(cyclePhase), 1, 2));
    startTimeOfCyclePhase = now;

    // Reward caller if they're a manager
    if (cToken.balanceOf(msg.sender) > 0) {
      require(cToken.generateTokens(msg.sender, NEXT_PHASE_REWARD));
    }

    emit ChangedPhase(cycleNumber, uint(cyclePhase), now, totalFundsInDAI);
  }

  /**
   * @notice Returns the length of the user's investments array.
   * @return length of the user's investments array
   */
  function investmentsCount(address _userAddr) public view returns(uint256 _count) {
    return userInvestments[_userAddr].length;
  }

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
    (, uint256 actualSrcAmount) = __handleInvestment(investmentId, _minPrice, _maxPrice, true);

    // Update last active cycle
    _lastActiveCycle[msg.sender] = cycleNumber;

    // Emit event
    emit CreatedInvestment(cycleNumber, msg.sender, investmentId, _tokenAddress, _stake, userInvestments[msg.sender][investmentId].buyPrice, actualSrcAmount, userInvestments[msg.sender][investmentId].tokenAmount);
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
    
    // Update investment info
    investment.isSold = true;

    // Sell asset
    (uint256 actualDestAmount, uint256 actualSrcAmount) = __handleInvestment(_investmentId, _minPrice, _maxPrice, false);
    if (isPartialSell) {
      // If only part of _tokenAmount was successfully sold, put the unsold tokens in the new investment
      userInvestments[msg.sender][investmentsCount(msg.sender).sub(1)].tokenAmount = userInvestments[msg.sender][investmentsCount(msg.sender).sub(1)].tokenAmount.add(_tokenAmount.sub(actualSrcAmount));
    }

    // Return staked Kairo
    uint256 receiveKairoAmount = stakeOfSoldTokens.mul(investment.sellPrice).div(investment.buyPrice);
    __returnStake(receiveKairoAmount, stakeOfSoldTokens);

    // Record risk taken in investment
    __recordRisk(investment.stake, investment.buyTime);

    // Update total funds
    totalFundsInDAI = totalFundsInDAI.sub(investment.buyCostInDAI).add(actualDestAmount);
    
    // Emit event
    if (isPartialSell) {
      Investment storage newInvestment = userInvestments[msg.sender][investmentsCount(msg.sender).sub(1)];
      emit CreatedInvestment(
        cycleNumber, msg.sender, investmentsCount(msg.sender).sub(1),
        newInvestment.tokenAddress, newInvestment.stake, newInvestment.buyPrice,
        newInvestment.buyCostInDAI, newInvestment.tokenAmount);
    }
    emit SoldInvestment(cycleNumber, msg.sender, _investmentId, investment.tokenAddress, receiveKairoAmount, investment.sellPrice, actualDestAmount);
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
  {
    // Load order info
    require(userCompoundOrders[msg.sender][_orderId] != address(0));
    CompoundOrder order = CompoundOrder(userCompoundOrders[msg.sender][_orderId]);
    require(order.isSold() == false && order.cycleNumber() == cycleNumber);

    // Sell order
    (uint256 inputAmount, uint256 outputAmount) = order.sellOrder(_minPrice, _maxPrice);

    // Return staked Kairo
    uint256 stake = order.stake();
    uint256 receiveKairoAmount = order.stake().mul(outputAmount).div(inputAmount);
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
  function repayCompoundOrder(uint256 _orderId, uint256 _repayAmountInDAI) public {
    // Load order info
    require(userCompoundOrders[msg.sender][_orderId] != address(0));
    CompoundOrder order = CompoundOrder(userCompoundOrders[msg.sender][_orderId]);
    require(order.isSold() == false && order.cycleNumber() == cycleNumber);

    // Repay loan
    order.repayLoan(_repayAmountInDAI);

    // Emit event
    emit RepaidCompoundOrder(cycleNumber, msg.sender, userCompoundOrders[msg.sender].length - 1, address(order), _repayAmountInDAI);
  }

  /**
   * @notice Handles and investment by doing the necessary trades using __kyberTrade() or Fulcrum trading
   * @param _investmentId the ID of the investment to be handled
   * @param _minPrice the minimum price for the trade
   * @param _maxPrice the maximum price for the trade
   * @param _buy whether to buy or sell the given investment
   */
  function __handleInvestment(uint256 _investmentId, uint256 _minPrice, uint256 _maxPrice, bool _buy)
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
      // Kyber trading
      uint256 dInS; // price of dest token denominated in src token
      uint256 sInD; // price of src token denominated in dest token
      if (_buy) {
        (dInS, sInD, _actualDestAmount, _actualSrcAmount) = __kyberTrade(dai, totalFundsInDAI.mul(investment.stake).div(cToken.totalSupply()), ERC20Detailed(token));
        require(_minPrice <= dInS && dInS <= _maxPrice);
        investment.buyPrice = dInS;
        investment.tokenAmount = _actualDestAmount;
        investment.buyCostInDAI = _actualSrcAmount;
      } else {
        (dInS, sInD, _actualDestAmount, _actualSrcAmount) = __kyberTrade(ERC20Detailed(token), investment.tokenAmount, dai);
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
}