pragma solidity 0.5.0;

import "./CompoundOrder.sol";

contract LongOrder is CompoundOrder {
  constructor(
    address _tokenAddr,
    uint256 _cycleNumber,
    uint256 _stake,
    uint256 _collateralAmountInDAI,
    uint256 _loanAmountInDAI
  ) public CompoundOrder(_tokenAddr, _cycleNumber, _stake, _collateralAmountInDAI, _loanAmountInDAI, false) {}

  function executeOrder(uint256 _minPrice, uint256 _maxPrice) public onlyOwner isValidToken(tokenAddr) {
    super.executeOrder(_minPrice, _maxPrice);
    
    // Ensure token's price is between _minPrice and _maxPrice
    uint256 tokenPrice = compound.assetPrices(tokenAddr); // Get the longing token's price in ETH
    require(tokenPrice > 0); // Ensure asset exists on Compound
    tokenPrice = __tokenToDAI(tokenAddr, tokenPrice); // Convert token price to be in DAI
    require(tokenPrice >= _minPrice && tokenPrice <= _maxPrice); // Ensure price is within range

    // Get funds in DAI from BetokenFund
    require(dai.transferFrom(owner(), address(this), collateralAmountInDAI)); // Transfer DAI from BetokenFund
    require(dai.approve(COMPOUND_ADDR, 0)); // Clear DAI allowance of Compound
    require(dai.approve(COMPOUND_ADDR, collateralAmountInDAI)); // Approve DAI transfer to Compound

    // Convert received DAI to longing token
    (,uint256 actualTokenAmount) = __sellDAIForToken(collateralAmountInDAI);

    // Get loan from Compound in DAI
    require(compound.supply(tokenAddr, actualTokenAmount) == 0); // Transfer DAI into Compound as supply
    require(compound.borrow(DAI_ADDR, loanAmountInDAI) == 0);// Take out loan
    require(compound.getAccountLiquidity(address(this)) > 0); // Ensure account liquidity is positive

    // Convert borrowed DAI to longing token
    __sellDAIForToken(loanAmountInDAI);

    // Repay leftover DAI to avoid complications
    if (dai.balanceOf(address(this)) > 0) {
      uint256 repayAmount = dai.balanceOf(address(this));
      require(dai.approve(COMPOUND_ADDR, 0));
      require(dai.approve(COMPOUND_ADDR, repayAmount));
      require(compound.repayBorrow(DAI_ADDR, repayAmount) == 0);
    }
  }

  function sellOrder(uint256 _minPrice, uint256 _maxPrice) 
    public 
    onlyOwner 
    isValidToken(tokenAddr) 
    isInitialized 
    returns (uint256 _inputAmount, uint256 _outputAmount) 
  {
    require(isSold == false);
    isSold = true;

    // Ensure price is within range provided by user
    uint256 tokenPrice = compound.assetPrices(tokenAddr); // Get the longing token's price in ETH
    tokenPrice = __tokenToDAI(tokenAddr, tokenPrice); // Convert token price to be in DAI
    require(tokenPrice >= _minPrice && tokenPrice <= _maxPrice); // Ensure price is within range
    
    // Siphon remaining collateral by repaying x DAI and getting back 1.5x DAI collateral
    // Repeat to ensure debt is exhausted
    for (uint256 i = 0; i < MAX_REPAY_STEPS; i = i.add(1)) {
      uint256 currentDebt = compound.getBorrowBalance(address(this), address(dai));
      if (currentDebt <= NEGLIGIBLE_DEBT) {
        // Current debt negligible, exit
        break;
      }

      // Determine amount to be repayed this step
      uint256 currentBalance = __tokenToDAI(tokenAddr, token.balanceOf(address(this)));
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
      require(compound.withdraw(tokenAddr, uint256(-1)) == 0);
    }

    // Sell all longing token to DAI
    __sellTokenForDAI(token.balanceOf(address(this)));

    // Send DAI back to BetokenFund and return
    _inputAmount = collateralAmountInDAI;
    _outputAmount = dai.balanceOf(address(this));
    require(dai.transfer(owner(), dai.balanceOf(address(this))));
    require(token.transfer(owner(), token.balanceOf(address(this)))); // Send back potential leftover tokens
  }

  // Allows manager to repay loan to avoid liquidation
  function repayLoan(uint256 _repayAmountInDAI) public onlyOwner isValidToken(tokenAddr) isInitialized {
    // Convert longing token to DAI
    uint256 repayAmountInToken = __daiToToken(tokenAddr, _repayAmountInDAI);
    (uint256 actualDAIAmount,) = __sellTokenForDAI(repayAmountInToken);

    // Repay loan to Compound
    require(dai.approve(COMPOUND_ADDR, 0));
    require(dai.approve(COMPOUND_ADDR, actualDAIAmount));
    require(compound.repayBorrow(DAI_ADDR, actualDAIAmount) == 0);
  }

  function getCurrentProfitInDAI() public view returns (bool _isNegative, uint256 _amount) {
    uint256 borrowBalance = compound.getBorrowBalance(address(this), DAI_ADDR);
    if (loanAmountInDAI >= borrowBalance) {
      return (false, loanAmountInDAI.sub(borrowBalance));
    } else {
      return (true, borrowBalance.sub(loanAmountInDAI));
    }
  }

  function getCurrentCollateralRatioInDAI() public view returns (uint256 _amount) {
    uint256 supply = __tokenToDAI(tokenAddr, compound.getSupplyBalance(address(this), tokenAddr));
    uint256 borrow = compound.getBorrowBalance(address(this), DAI_ADDR);
    return supply.mul(PRECISION).div(borrow);
  }
}