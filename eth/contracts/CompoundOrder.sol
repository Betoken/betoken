pragma solidity ^0.4.25;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./Utils.sol";
import "./interfaces/WETH.sol";

contract CompoundOrder is Ownable, Utils {
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
  address public tokenAddr;
  bool public isSold;
  bool public orderType; // True for shorting, false for longing

  // Contract instances
  ERC20Detailed internal token;

  constructor(
    address _tokenAddr,
    uint256 _cycleNumber,
    uint256 _stake,
    uint256 _collateralAmountInDAI,
    uint256 _loanAmountInDAI,
    bool _orderType
  ) internal isValidToken(_tokenAddr) {
    // Initialize details of short order
    require(_tokenAddr != DAI_ADDR);
    require(_stake > 0 && _collateralAmountInDAI > 0 && _loanAmountInDAI > 0); // Validate inputs
    stake = _stake;
    collateralAmountInDAI = _collateralAmountInDAI;
    loanAmountInDAI = _loanAmountInDAI;
    cycleNumber = _cycleNumber;
    tokenAddr = _tokenAddr;
    orderType = _orderType;
    token = ERC20Detailed(_tokenAddr);
  }
  
  function executeOrder(uint256 _minPrice, uint256 _maxPrice) public;

  function sellOrder(uint256 _minPrice, uint256 _maxPrice) public returns (uint256 _inputAmount, uint256 _outputAmount);

  function repayLoan(uint256 _repayAmountInDAI) public;

  function getCurrentLiquidityInDAI() public view returns (bool _isNegative, uint256 _amount) {
    int256 liquidityInETH = compound.getAccountLiquidity(this);
    if (liquidityInETH >= 0) {
      return (false, __tokenToDAI(WETH_ADDR, uint256(liquidityInETH)));
    } else {
      require(-liquidityInETH > 0); // Prevent overflow
      return (true, __tokenToDAI(WETH_ADDR, uint256(-liquidityInETH)));
    }
  }

  function getCurrentProfitInDAI() public view returns (bool _isNegative, uint256 _amount);

  function __sellDAIForToken(uint256 _daiAmount) internal returns (uint256 _actualDAIAmount, uint256 _actualTokenAmount) {
    if (tokenAddr == WETH_ADDR) {
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

  function __sellTokenForDAI(uint256 _tokenAmount) internal returns (uint256 _actualDAIAmount, uint256 _actualTokenAmount) {
    if (tokenAddr == WETH_ADDR) {
      // Handle WETH (not on Kyber)
      // Unwrap WETH into ETH
      WETH weth = WETH(WETH_ADDR);
      weth.withdraw(_tokenAmount);
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