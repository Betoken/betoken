pragma solidity 0.5.0;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../Utils.sol";

contract CompoundOrderLogic is Ownable, Utils(address(0), address(0), address(0)) {
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
  uint256 public buyTime; // Timestamp for order execution
  address public tokenAddr;
  bool public isSold;
  bool public orderType; // True for shorting, false for longing

  // Contract instances
  ERC20Detailed internal token;
  
  function executeOrder(uint256 _minPrice, uint256 _maxPrice) public {
    buyTime = now;
  }

  function sellOrder(uint256 _minPrice, uint256 _maxPrice) public returns (uint256 _inputAmount, uint256 _outputAmount);

  function repayLoan(uint256 _repayAmountInDAI) public;

  function getCurrentLiquidityInDAI() public view returns (bool _isNegative, uint256 _amount) {
    int256 liquidityInETH = compound.getAccountLiquidity(address(this));
    if (liquidityInETH >= 0) {
      return (false, __tokenToDAI(WETH_ADDR, uint256(liquidityInETH)));
    } else {
      require(-liquidityInETH > 0); // Prevent overflow
      return (true, __tokenToDAI(WETH_ADDR, uint256(-liquidityInETH)));
    }
  }

  function getCurrentCollateralRatioInDAI() public view returns (uint256 _amount);

  function getCurrentProfitInDAI() public view returns (bool _isNegative, uint256 _amount);

  function __sellDAIForToken(uint256 _daiAmount) internal returns (uint256 _actualDAIAmount, uint256 _actualTokenAmount) {
    (,, _actualTokenAmount, _actualDAIAmount) = __kyberTrade(dai, _daiAmount, token); // Sell DAI for tokens on Kyber
    require(_actualDAIAmount > 0 && _actualTokenAmount > 0); // Validate return values
  }

  function __sellTokenForDAI(uint256 _tokenAmount) internal returns (uint256 _actualDAIAmount, uint256 _actualTokenAmount) {
    (,, _actualDAIAmount, _actualTokenAmount) = __kyberTrade(token, _tokenAmount, dai); // Sell tokens for DAI on Kyber
    require(_actualDAIAmount > 0 && _actualTokenAmount > 0); // Validate return values
  }

  // Convert a DAI amount to the amount of a given token that's of equal value
  function __daiToToken(address _token, uint256 _daiAmount) internal view returns (uint256) {
    ERC20Detailed t = ERC20Detailed(_token);
    return _daiAmount.mul(compound.assetPrices(DAI_ADDR)).mul(10 ** uint256(t.decimals())).div(compound.assetPrices(_token).mul(PRECISION));
  }

  // Convert a token amount to the amount of DAI that's of equal value
  function __tokenToDAI(address _token, uint256 _tokenAmount) internal view returns (uint256) {
    ERC20Detailed t = ERC20Detailed(_token);
    return _tokenAmount.mul(compound.assetPrices(_token)).mul(PRECISION).div(compound.assetPrices(DAI_ADDR).mul(10 ** uint256(t.decimals())));
  }
}