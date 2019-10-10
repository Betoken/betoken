pragma solidity 0.5.12;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../interfaces/Comptroller.sol";
import "../interfaces/PriceOracle.sol";
import "../interfaces/CERC20.sol";
import "../interfaces/CEther.sol";
import "../Utils.sol";

contract CompoundOrder is Utils(address(0), address(0)), Ownable {
  // Constants
  uint256 internal constant NEGLIGIBLE_DEBT = 10 ** 14; // we don't care about debts below 10^-4 DAI (0.1 cent)
  uint256 internal constant MAX_REPAY_STEPS = 3; // Max number of times we attempt to repay remaining debt
  uint256 internal constant DEFAULT_LIQUIDITY_SLIPPAGE = 10 ** 12; // 1e-6 slippage for redeeming liquidity when selling order
  uint256 internal constant FALLBACK_LIQUIDITY_SLIPPAGE = 10 ** 15; // 0.1% slippage for redeeming liquidity when selling order
  uint256 internal constant MAX_LIQUIDITY_SLIPPAGE = 10 ** 17; // 10% max slippage for redeeming liquidity when selling order

  // Contract instances
  Comptroller public COMPTROLLER; // The Compound comptroller
  PriceOracle public ORACLE; // The Compound price oracle
  CERC20 public CDAI; // The Compound DAI market token
  address public CETH_ADDR;

  // Instance variables
  uint256 public stake;
  uint256 public collateralAmountInDAI;
  uint256 public loanAmountInDAI;
  uint256 public cycleNumber;
  uint256 public buyTime; // Timestamp for order execution
  uint256 public outputAmount; // Records the total output DAI after order is sold
  address public compoundTokenAddr;
  bool public isSold;
  bool public orderType; // True for shorting, false for longing
  bool internal initialized;


  constructor() public {}

  function init(
    address _compoundTokenAddr,
    uint256 _cycleNumber,
    uint256 _stake,
    uint256 _collateralAmountInDAI,
    uint256 _loanAmountInDAI,
    bool _orderType,
    address _daiAddr,
    address payable _kyberAddr,
    address _comptrollerAddr,
    address _priceOracleAddr,
    address _cDAIAddr,
    address _cETHAddr
  ) public {
    require(!initialized);
    initialized = true;
    
    // Initialize details of order
    require(_compoundTokenAddr != _cDAIAddr);
    require(_stake > 0 && _collateralAmountInDAI > 0 && _loanAmountInDAI > 0); // Validate inputs
    stake = _stake;
    collateralAmountInDAI = _collateralAmountInDAI;
    loanAmountInDAI = _loanAmountInDAI;
    cycleNumber = _cycleNumber;
    compoundTokenAddr = _compoundTokenAddr;
    orderType = _orderType;

    COMPTROLLER = Comptroller(_comptrollerAddr);
    ORACLE = PriceOracle(_priceOracleAddr);
    CDAI = CERC20(_cDAIAddr);
    CETH_ADDR = _cETHAddr;
    DAI_ADDR = _daiAddr;
    KYBER_ADDR = _kyberAddr;
    dai = ERC20Detailed(_daiAddr);
    kyber = KyberNetwork(_kyberAddr);

    // transfer ownership to msg.sender
    _transferOwnership(msg.sender);
  }

  /**
   * @notice Executes the Compound order
   * @param _minPrice the minimum token price
   * @param _maxPrice the maximum token price
   */
  function executeOrder(uint256 _minPrice, uint256 _maxPrice) public;

  /**
   * @notice Sells the Compound order and returns assets to BetokenFund
   * @param _minPrice the minimum token price
   * @param _maxPrice the maximum token price
   */
  function sellOrder(uint256 _minPrice, uint256 _maxPrice) public returns (uint256 _inputAmount, uint256 _outputAmount);

  /**
   * @notice Repays the loans taken out to prevent the collateral ratio from dropping below threshold
   * @param _repayAmountInDAI the amount to repay, in DAI
   */
  function repayLoan(uint256 _repayAmountInDAI) public;

  function getMarketCollateralFactor() public view returns (uint256);

  function getCurrentCollateralInDAI() public returns (uint256 _amount);

  function getCurrentBorrowInDAI() public returns (uint256 _amount);

  function getCurrentCashInDAI() public view returns (uint256 _amount);

  /**
   * @notice Calculates the current profit in DAI
   * @return the profit amount
   */
  function getCurrentProfitInDAI() public returns (bool _isNegative, uint256 _amount) {
    uint256 l;
    uint256 r;
    if (isSold) {
      l = outputAmount;
      r = collateralAmountInDAI;
    } else {
      uint256 cash = getCurrentCashInDAI();
      uint256 supply = getCurrentCollateralInDAI();
      uint256 borrow = getCurrentBorrowInDAI();
      if (cash >= borrow) {
        l = supply.add(cash);
        r = borrow.add(collateralAmountInDAI);
      } else {
        l = supply;
        r = borrow.sub(cash).mul(PRECISION).div(getMarketCollateralFactor()).add(collateralAmountInDAI);
      }
    }
    
    if (l >= r) {
      return (false, l.sub(r));
    } else {
      return (true, r.sub(l));
    }
  }

  /**
   * @notice Calculates the current collateral ratio on Compound, using 18 decimals
   * @return the collateral ratio
   */
  function getCurrentCollateralRatioInDAI() public returns (uint256 _amount) {
    uint256 supply = getCurrentCollateralInDAI();
    uint256 borrow = getCurrentBorrowInDAI();
    if (borrow == 0) {
      return uint256(-1);
    }
    return supply.mul(PRECISION).div(borrow);
  }

  /**
   * @notice Calculates the current liquidity (supply - collateral) on the Compound platform
   * @return the liquidity
   */
  function getCurrentLiquidityInDAI() public returns (bool _isNegative, uint256 _amount) {
    uint256 supply = getCurrentCollateralInDAI();
    uint256 borrow = getCurrentBorrowInDAI().mul(PRECISION).div(getMarketCollateralFactor());
    if (supply >= borrow) {
      return (false, supply.sub(borrow));
    } else {
      return (true, borrow.sub(supply));
    }
  }

  function __sellDAIForToken(uint256 _daiAmount) internal returns (uint256 _actualDAIAmount, uint256 _actualTokenAmount) {
    ERC20Detailed t = __underlyingToken(compoundTokenAddr);
    (,, _actualTokenAmount, _actualDAIAmount) = __kyberTrade(dai, _daiAmount, t); // Sell DAI for tokens on Kyber
    require(_actualDAIAmount > 0 && _actualTokenAmount > 0); // Validate return values
  }

  function __sellTokenForDAI(uint256 _tokenAmount) internal returns (uint256 _actualDAIAmount, uint256 _actualTokenAmount) {
    ERC20Detailed t = __underlyingToken(compoundTokenAddr);
    (,, _actualDAIAmount, _actualTokenAmount) = __kyberTrade(t, _tokenAmount, dai); // Sell tokens for DAI on Kyber
    require(_actualDAIAmount > 0 && _actualTokenAmount > 0); // Validate return values
  }

  // Convert a DAI amount to the amount of a given token that's of equal value
  function __daiToToken(address _cToken, uint256 _daiAmount) internal view returns (uint256) {
    if (_cToken == CETH_ADDR) {
      // token is ETH
      return _daiAmount.mul(ORACLE.getPrice(DAI_ADDR)).div(PRECISION);
    }
    ERC20Detailed t = __underlyingToken(_cToken);
    return _daiAmount.mul(ORACLE.getPrice(DAI_ADDR)).mul(10 ** getDecimals(t)).div(ORACLE.getPrice(address(t)).mul(PRECISION));
  }

  // Convert a compound token amount to the amount of DAI that's of equal value
  function __tokenToDAI(address _cToken, uint256 _tokenAmount) internal view returns (uint256) {
    if (_cToken == CETH_ADDR) {
      // token is ETH
      return _tokenAmount.mul(PRECISION).div(ORACLE.getPrice(DAI_ADDR));
    }
    ERC20Detailed t = __underlyingToken(_cToken);
    return _tokenAmount.mul(ORACLE.getPrice(address(t))).mul(PRECISION).div(ORACLE.getPrice(DAI_ADDR).mul(10 ** uint256(t.decimals())));
  }

  function __underlyingToken(address _cToken) internal view returns (ERC20Detailed) {
    if (_cToken == CETH_ADDR) {
      // ETH
      return ETH_TOKEN_ADDRESS;
    }
    CERC20 ct = CERC20(_cToken);
    address underlyingToken = ct.underlying();
    ERC20Detailed t = ERC20Detailed(underlyingToken);
    return t;
  }

  function() external payable {}
}