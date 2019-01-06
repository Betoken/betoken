pragma solidity ^0.4.25;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./Utils.sol";
import "./interfaces/Compound.sol";
import "./interfaces/WETH.sol";

contract ShortOrder is Ownable, Utils {
  modifier isInitialized {
    require(collateralAmountInDAI > 0 && loanAmountInDAI > 0); // Ensure order is initialized
    _;
  }

  uint256 public collateralAmountInDAI;
  uint256 public loanAmountInDAI;
  address public shortingToken;
  
  // Initialize details of short order and execute
  function executeOrder(uint256 _collateralAmountInDAI, uint256 _loanAmountInDAI, address _shortingToken) public onlyOwner isValidToken(_shortingToken) {
    // Initialize details of short order
    require(_collateralAmountInDAI > 0 && _loanAmountInDAI > 0); // Validate inputs
    collateralAmountInDAI = _collateralAmountInDAI;
    loanAmountInDAI = _loanAmountInDAI;
    shortingToken = _shortingToken;

    // Initialize needed variables
    ERC20Detailed dai = ERC20Detailed(DAI_ADDR);
    ERC20Detailed token = ERC20Detailed(_shortingToken);
    Compound compound = Compound(COMPOUND_ADDR);
    uint256 loanAmountInToken = __daiToToken(_shortingToken, _loanAmountInDAI);

    // Get loan from Compound in shortingToken
    require(compound.assetPrices(_shortingToken) > 0);
    require(dai.transferFrom(owner(), this, _collateralAmountInDAI)); // Transfer DAI from BetokenFund
    require(dai.approve(COMPOUND_ADDR, 0)); // Clear DAI allowance of Compound
    require(dai.approve(COMPOUND_ADDR, _collateralAmountInDAI)); // Approve DAI transfer to Compound
    require(compound.supply(DAI_ADDR, _collateralAmountInDAI) == 0); // Transfer DAI into Compound as supply
    require(compound.borrow(_shortingToken, loanAmountInToken) == 0);// Take out loan
    require(compound.getAccountLiquidity(this) > 0); // Ensure account liquidity is positive

    // Convert loaned tokens to DAI
    uint256 actualDAIAmount;
    uint256 actualTokenAmount;
    // Handle WETH (not on Kyber)
    if (_shortingToken == WETH_ADDR) {
      // Unwrap WETH into ETH
      WETH weth = WETH(WETH_ADDR);
      weth.withdraw(loanAmountInToken);
      (,, actualDAIAmount, actualTokenAmount) = __kyberTrade(ETH_TOKEN_ADDRESS, loanAmountInToken, dai); // Sell ETH for DAI on Kyber
    } else {
      (,, actualDAIAmount, actualTokenAmount) = __kyberTrade(token, loanAmountInToken, dai); // Sell tokens for DAI on Kyber
    }
    require(actualDAIAmount > 0 && actualTokenAmount > 0); // Validate return values
    loanAmountInDAI = actualDAIAmount; // Change loan amount to actual DAI received
    // Repay leftover tokens to avoid complications
    if (actualTokenAmount < loanAmountInToken) {
      uint256 repayAmount = loanAmountInToken.sub(actualTokenAmount);
      require(token.approve(COMPOUND_ADDR, 0));
      require(token.approve(COMPOUND_ADDR, repayAmount));
      require(compound.repayBorrow(_shortingToken, repayAmount));
    }
  }

  function sellOrder() public onlyOwner isValidToken(shortingToken) isInitialized {
    
    
  }

  function repayLoan() public onlyOwner isValidToken(shortingToken) isInitialized {

  }

  function getCurrentLiquidityInDAI() public view returns (bool _isNegative, uint256 _amount) {
    Compound compound = Compound(COMPOUND_ADDR);
    int256 liquidityInETH = compound.getAccountLiquidity(this);
    if (liquidityInETH >= 0) {
      return (false, __tokenToDAI(WETH_ADDR, uint256(liquidityInETH)));
    } else {
      require(-liquidityInETH > 0); // Prevent overflow
      return (true, __tokenToDAI(WETH_ADDR, uint256(-liquidityInETH)));
    }
  }

  function getCurrentProfitInDAI() public view returns (bool _isNegative, uint256 _amount) {
    Compound compound = Compound(COMPOUND_ADDR);
    uint256 borrowBalance = __tokenToDAI(shortingToken, compound.getBorrowBalance(this, shortingToken));
    if (loanAmountInDAI >= borrowBalance) {
      return (false, loanAmountInDAI.sub(borrowBalance));
    } else {
      return (true, borrowBalance.sub(loanAmountInDAI));
    }
  }

  // Convert a DAI amount to the amount of a given token that's of equal value
  function __daiToToken(address _token, uint256 _daiAmount) internal view returns (uint256) {
    Compound compound = Compound(COMPOUND_ADDR);
    return _daiAmount.mul(compound.assetPrices(DAI_ADDR)).div(compound.assetPrices(_token));
  }

  // Convert a token amount to the amount of DAI that's of equal value
  function __tokenToDAI(address _token, uint256 _tokenAmount) internal view returns (uint256) {
    Compound compound = Compound(COMPOUND_ADDR);
    return _tokenAmount.mul(compound.assetPrices(_token)).div(compound.assetPrices(DAI_ADDR));
  }
}