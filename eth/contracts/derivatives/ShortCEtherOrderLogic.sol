pragma solidity 0.5.8;

import "./CompoundOrderLogic.sol";

contract ShortCEtherOrderLogic is CompoundOrderLogic {
  function executeOrder(uint256 _minPrice, uint256 _maxPrice) public onlyOwner isValidToken(compoundTokenAddr) {
    super.executeOrder(_minPrice, _maxPrice);
    
    // Ensure token's price is between _minPrice and _maxPrice
    uint256 tokenPrice = PRECISION; // The price of ETH in ETH is just 1
    tokenPrice = __tokenToDAI(CETH_ADDR, tokenPrice); // Convert token price to be in DAI
    require(tokenPrice >= _minPrice && tokenPrice <= _maxPrice); // Ensure price is within range

    // Get funds in DAI from BetokenFund
    require(dai.transferFrom(owner(), address(this), collateralAmountInDAI)); // Transfer DAI from BetokenFund
    require(dai.approve(address(CDAI), 0)); // Clear DAI allowance of Compound DAI market
    require(dai.approve(address(CDAI), collateralAmountInDAI)); // Approve DAI transfer to Compound DAI market

    // Enter Compound markets
    CEther market = CEther(compoundTokenAddr);
    address[] memory markets = new address[](2);
    markets[0] = compoundTokenAddr;
    markets[1] = address(CDAI);
    uint[] memory errors = COMPTROLLER.enterMarkets(markets);
    require(errors[0] == 0 && errors[1] == 0);

    // Get loan from Compound in tokenAddr
    uint256 loanAmountInToken = __daiToToken(compoundTokenAddr, loanAmountInDAI);
    require(CDAI.mint(collateralAmountInDAI) == 0); // Transfer DAI into Compound as supply
    require(market.borrow(loanAmountInToken) == 0);// Take out loan
    (bool negLiquidity, ) = getCurrentLiquidityInDAI();
    require(!negLiquidity); // Ensure account liquidity is positive

    // Convert loaned tokens to DAI
    (uint256 actualDAIAmount,) = __sellTokenForDAI(loanAmountInToken);
    loanAmountInDAI = actualDAIAmount; // Change loan amount to actual DAI received

    // Repay leftover tokens to avoid complications
    if (address(this).balance > 0) {
      uint256 repayAmount = address(this).balance;
      market.repayBorrow.value(repayAmount)();
    }
  }

  function sellOrder(uint256 _minPrice, uint256 _maxPrice)
    public
    onlyOwner
    returns (uint256 _inputAmount, uint256 _outputAmount)
  {
    require(buyTime > 0); // Ensure the order has been executed
    require(isSold == false);
    isSold = true;

    // Ensure price is within range provided by user
    uint256 tokenPrice = PRECISION; // The price of ETH in ETH is just 1
    tokenPrice = __tokenToDAI(compoundTokenAddr, tokenPrice); // Convert token price to be in DAI
    require(tokenPrice >= _minPrice && tokenPrice <= _maxPrice); // Ensure price is within range

    // Siphon remaining collateral by repaying x DAI and getting back 1.5x DAI collateral
    // Repeat to ensure debt is exhausted
    CEther market = CEther(compoundTokenAddr);
    for (uint256 i = 0; i < MAX_REPAY_STEPS; i = i.add(1)) {
      uint256 currentDebt = getCurrentBorrowInDAI();
      if (currentDebt <= NEGLIGIBLE_DEBT) {
        // Current debt negligible, exit
        break;
      }

      // Determine amount to be repayed this step
      uint256 currentBalance = getCurrentCashInDAI();
      uint256 repayAmount = 0; // amount to be repaid in DAI
      if (currentDebt <= currentBalance) {
        // Has enough money, repay all debt
        repayAmount = currentDebt;
      } else {
        // Doesn't have enough money, repay whatever we can repay
        repayAmount = currentBalance;
      }

      // Repay debt
      repayLoan(repayAmount);

      // Withdraw all available liquidity
      (bool isNeg, uint256 liquidity) = getCurrentLiquidityInDAI();
      if (!isNeg) {
        require(CDAI.redeemUnderlying(liquidity) == 0);
      }
    }

    // Send DAI back to BetokenFund and return
    _inputAmount = collateralAmountInDAI;
    _outputAmount = dai.balanceOf(address(this));
    outputAmount = _outputAmount;
    require(dai.transfer(owner(), dai.balanceOf(address(this))));
  }

  // Allows manager to repay loan to avoid liquidation
  function repayLoan(uint256 _repayAmountInDAI) public onlyOwner {
    require(buyTime > 0); // Ensure the order has been executed

    // Convert DAI to shorting token
    (,uint256 actualTokenAmount) = __sellDAIForToken(_repayAmountInDAI);

    // Check if amount is greater than borrow balance
    CEther market = CEther(compoundTokenAddr);
    uint256 currentDebt = market.borrowBalanceCurrent(address(this));
    if (actualTokenAmount > currentDebt) {
      actualTokenAmount = currentDebt;
    }

    // Repay loan to Compound
    market.repayBorrow.value(actualTokenAmount)();
  }

  function getMarketCollateralFactor() public view returns (uint256) {
    (, uint256 ratio) = COMPTROLLER.markets(address(compoundTokenAddr));
    return ratio;
  }

  function getCurrentCollateralInDAI() public returns (uint256 _amount) {
    uint256 supply = CDAI.balanceOf(address(this)).mul(CDAI.exchangeRateCurrent()).div(PRECISION);
    return supply;
  }

  function getCurrentBorrowInDAI() public returns (uint256 _amount) {
    CEther market = CEther(compoundTokenAddr);
    uint256 borrow = __tokenToDAI(compoundTokenAddr, market.borrowBalanceCurrent(address(this)));
    return borrow;
  }

  function getCurrentCashInDAI() public view returns (uint256 _amount) {
    uint256 cash = getBalance(dai, address(this));
    return cash;
  }
}