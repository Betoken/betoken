pragma solidity ^0.4.25;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./Utils.sol";
import "./interfaces/WETH.sol";

contract ShortOrder is Ownable, Utils {
  modifier isInitialized {
    require(stake > 0 && collateralAmountInDAI > 0 && loanAmountInDAI > 0); // Ensure order is initialized
    _;
  }

  // Constants
  uint256 internal constant NEGLIGIBLE_DEBT = 10 ** 14; // we don't care about debts below 10^-4 DAI (0.1 cent)
  uint256 internal constant MAX_REPAY_STEPS = 3; // Max number of times we attempt to repay remaining debt

  // Instance variables
  uint256 public stake;
  uint256 public collateralAmountInDAI;
  uint256 public loanAmountInDAI;
  uint256 public cycleNumber;
  address public shortingToken;
  bool public isSold;

  // Contract instances
  ERC20Detailed internal token;

  constructor(
    address _shortingToken,
    uint256 _cycleNumber,
    uint256 _stake,
    uint256 _collateralAmountInDAI,
    uint256 _loanAmountInDAI
  ) public isValidToken(_shortingToken) {
    // Initialize details of short order
    require(_shortingToken != DAI_ADDR);
    require(_stake > 0 && _collateralAmountInDAI > 0 && _loanAmountInDAI > 0); // Validate inputs
    stake = _stake;
    collateralAmountInDAI = _collateralAmountInDAI;
    loanAmountInDAI = _loanAmountInDAI;
    cycleNumber = _cycleNumber;
    shortingToken = _shortingToken;
    token = ERC20Detailed(_shortingToken);
  }
  
  function executeOrder(uint256 _minPrice, uint256 _maxPrice) public onlyOwner isValidToken(shortingToken) {
    // Ensure shortingToken's price is between _minPrice and _maxPrice
    uint256 tokenPrice = compound.assetPrices(shortingToken); // Get the shorting token's price in ETH
    require(tokenPrice > 0); // Ensure asset exists on Compound
    tokenPrice = __tokenToDAI(shortingToken, tokenPrice); // Convert token price to be in DAI
    require(tokenPrice >= _minPrice && tokenPrice <= _maxPrice); // Ensure price is within range

    // Get funds in DAI from BetokenFund
    require(dai.transferFrom(owner(), this, collateralAmountInDAI)); // Transfer DAI from BetokenFund
    require(dai.approve(COMPOUND_ADDR, 0)); // Clear DAI allowance of Compound
    require(dai.approve(COMPOUND_ADDR, collateralAmountInDAI)); // Approve DAI transfer to Compound

    // Get loan from Compound in shortingToken
    uint256 loanAmountInToken = __daiToToken(shortingToken, loanAmountInDAI);
    require(compound.supply(DAI_ADDR, collateralAmountInDAI) == 0); // Transfer DAI into Compound as supply
    require(compound.borrow(shortingToken, loanAmountInToken) == 0);// Take out loan
    require(compound.getAccountLiquidity(this) > 0); // Ensure account liquidity is positive

    // Convert loaned tokens to DAI
    (uint256 actualDAIAmount, uint256 actualTokenAmount) = __sellLongingTokenForDAI(loamAmountInToken);
    loanAmountInDAI = actualDAIAmount; // Change loan amount to actual DAI received

    // Repay leftover tokens to avoid complications
    if (token.balanceOf(this) > 0) {
      uint256 repayAmount = token.balanceOf(this);
      require(token.approve(COMPOUND_ADDR, 0));
      require(token.approve(COMPOUND_ADDR, repayAmount));
      require(compound.repayBorrow(shortingToken, repayAmount) == 0);
    }
  }

  function sellOrder(uint256 _minPrice, uint256 _maxPrice) 
    public 
    onlyOwner 
    isValidToken(shortingToken) 
    isInitialized 
    returns (uint256 _inputAmount, uint256 _outputAmount) 
  {
    require(isSold == false);
    isSold = true;

    // Ensure price is within range provided by user
    uint256 tokenPrice = compound.assetPrices(shortingToken); // Get the shorting token's price in ETH
    tokenPrice = __tokenToDAI(shortingToken, tokenPrice); // Convert token price to be in DAI
    require(tokenPrice >= _minPrice && tokenPrice <= _maxPrice); // Ensure price is within range

    // Siphon remaining collateral by repaying x DAI and getting back 1.5x DAI collateral
    // Repeat to ensure debt is exhausted
    for (uint256 i = 0; i < MAX_REPAY_STEPS; i = i.add(1)) {
      uint256 currentDebt = __tokenToDAI(shortingToken, compound.getBorrowBalance(this, shortingToken));
      if (currentDebt <= NEGLIGIBLE_DEBT) {
        // Current debt negligible, exit
        break;
      }

      // Determine amount to be repayed this step
      uint256 currentBalance = dai.balanceOf(this);
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
      require(compound.withdraw(DAI_ADDR, uint256(-1)) == 0);
    }

    // Send DAI back to BetokenFund and return
    _inputAmount = collateralAmountInDAI;
    _outputAmount = dai.balanceOf(this);
    require(dai.transfer(owner(), dai.balanceOf(this)));
  }

  // Allows manager to repay loan to avoid liquidation
  function repayLoan(uint256 _repayAmountInDAI) public onlyOwner isValidToken(shortingToken) isInitialized {
    // Convert DAI to shorting token
    (,uint256 actualTokenAmount) = __sellDAIForLongingToken(_repayAmountInDAI);

    // Repay loan to Compound
    require(token.approve(COMPOUND_ADDR, 0));
    require(token.approve(COMPOUND_ADDR, actualTokenAmount));
    require(compound.repayBorrow(shortingToken, actualTokenAmount) == 0);
  }

  function getCurrentLiquidityInDAI() public view returns (bool _isNegative, uint256 _amount) {
    int256 liquidityInETH = compound.getAccountLiquidity(this);
    if (liquidityInETH >= 0) {
      return (false, __tokenToDAI(WETH_ADDR, uint256(liquidityInETH)));
    } else {
      require(-liquidityInETH > 0); // Prevent overflow
      return (true, __tokenToDAI(WETH_ADDR, uint256(-liquidityInETH)));
    }
  }

  function getCurrentProfitInDAI() public view returns (bool _isNegative, uint256 _amount) {
    uint256 borrowBalance = __tokenToDAI(shortingToken, compound.getBorrowBalance(this, shortingToken));
    if (loanAmountInDAI >= borrowBalance) {
      return (false, loanAmountInDAI.sub(borrowBalance));
    } else {
      return (true, borrowBalance.sub(loanAmountInDAI));
    }
  }

  function __sellDAIForLongingToken(uint256 _daiAmount) internal returns (uint256 _actualDAIAmount, uint256 _actualTokenAmount) {
    if (longingToken == WETH_ADDR) {
      // Handle WETH (not on Kyber)
      (,, _actualTokenAmount, _actualDAIAmount) = __kyberTrade(dai, _daiAmount, ETH_TOKEN_ADDRESS); // Sell DAI for ETH on Kyber
      // Wrap ETH into WETH
      WETH weth = WETH(WETH_ADDR);
      weth.deposit.value(_actualTokenAmount)();
    } else {
      (,, _actualTokenAmount, _actualDAIAmount) = __kyberTrade(dai, _daiAmount, token); // Sell DAI for tokens on Kyber
    }
    require(_actualDAIAmount > 0 && _actualTokenAmount > 0); // Validate return values
  }

  function __sellLongingTokenForDAI(uint256 _tokenAmount) internal returns (uint256 _actualDAIAmount, uint256 _actualTokenAmount) {
    if (shortingToken == WETH_ADDR) {
      // Handle WETH (not on Kyber)
      // Unwrap WETH into ETH
      WETH weth = WETH(WETH_ADDR);
      weth.withdraw(loanAmountInToken);
      (,, _actualDAIAmount, _actualTokenAmount) = __kyberTrade(ETH_TOKEN_ADDRESS, _tokenAmount, dai); // Sell ETH for DAI on Kyber
    } else {
      (,, _actualDAIAmount, _actualTokenAmount) = __kyberTrade(token, _tokenAmount, dai); // Sell tokens for DAI on Kyber
    }
    require(_actualDAIAmount > 0 && _actualTokenAmount > 0); // Validate return values
  }

  // Convert a DAI amount to the amount of a given token that's of equal value
  function __daiToToken(address _token, uint256 _daiAmount) internal view returns (uint256) {
    return _daiAmount.mul(compound.assetPrices(DAI_ADDR)).div(compound.assetPrices(_token));
  }

  // Convert a token amount to the amount of DAI that's of equal value
  function __tokenToDAI(address _token, uint256 _tokenAmount) internal view returns (uint256) {
    return _tokenAmount.mul(compound.assetPrices(_token)).div(compound.assetPrices(DAI_ADDR));
  }
}