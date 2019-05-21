pragma solidity 0.5.0;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../Utils.sol";
import "../interfaces/Comptroller.sol";
import "../interfaces/PriceOracle.sol";
import "../interfaces/CERC20.sol";

contract CompoundOrder is Ownable, Utils {
  // Constants
  uint256 internal constant NEGLIGIBLE_DEBT = 10 ** 14; // we don't care about debts below 10^-4 DAI (0.1 cent)
  uint256 internal constant MAX_REPAY_STEPS = 3; // Max number of times we attempt to repay remaining debt

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
  address public compoundTokenAddr;
  bool public isSold;
  bool public orderType; // True for shorting, false for longing

  // The contract containing the code to be executed
  address public logicContract;

  constructor(
    address _compoundTokenAddr,
    uint256 _cycleNumber,
    uint256 _stake,
    uint256 _collateralAmountInDAI,
    uint256 _loanAmountInDAI,
    bool _orderType,
    address _logicContract,
    address _daiAddr,
    address payable _kyberAddr,
    address _comptrollerAddr,
    address _priceOracleAddr,
    address _cDAIAddr,
    address _cETHAddr
  ) public Utils(_daiAddr, _kyberAddr)  {
    // Initialize details of short order
    require(_compoundTokenAddr != _cDAIAddr);
    require(_stake > 0 && _collateralAmountInDAI > 0 && _loanAmountInDAI > 0); // Validate inputs
    stake = _stake;
    collateralAmountInDAI = _collateralAmountInDAI;
    loanAmountInDAI = _loanAmountInDAI;
    cycleNumber = _cycleNumber;
    compoundTokenAddr = _compoundTokenAddr;
    orderType = _orderType;
    logicContract = _logicContract;

    COMPTROLLER = Comptroller(_comptrollerAddr);
    ORACLE = PriceOracle(_priceOracleAddr);
    CDAI = CERC20(_cDAIAddr);
    CETH_ADDR = _cETHAddr;
  }
  
  /**
   * @notice Executes the Compound order
   * @param _minPrice the minimum token price
   * @param _maxPrice the maximum token price
   */
  function executeOrder(uint256 _minPrice, uint256 _maxPrice) public {
    (bool success,) = logicContract.delegatecall(abi.encodeWithSelector(this.executeOrder.selector, _minPrice, _maxPrice));
    if (!success) { revert(); }
  }

  /**
   * @notice Sells the Compound order and returns assets to BetokenFund
   * @param _minPrice the minimum token price
   * @param _maxPrice the maximum token price
   */
  function sellOrder(uint256 _minPrice, uint256 _maxPrice) public returns (uint256 _inputAmount, uint256 _outputAmount) {
    (bool success, bytes memory result) = logicContract.delegatecall(abi.encodeWithSelector(this.sellOrder.selector, _minPrice, _maxPrice));
    if (!success) { revert(); }
    return abi.decode(result, (uint256, uint256));
  }

  /**
   * @notice Repays the loans taken out to prevent the collateral ratio from dropping below threshold
   * @param _repayAmountInDAI the amount to repay, in DAI
   */
  function repayLoan(uint256 _repayAmountInDAI) public {
    (bool success,) = logicContract.delegatecall(abi.encodeWithSelector(this.repayLoan.selector, _repayAmountInDAI));
    if (!success) { revert(); }
  }

  /**
   * @notice Calculates the current liquidity (supply - collateral) on the Compound platform
   * @return the liquidity
   */
  function getCurrentLiquidityInDAI() public returns (bool _isNegative, uint256 _amount) {
    (bool success, bytes memory result) = logicContract.delegatecall(abi.encodeWithSelector(this.getCurrentLiquidityInDAI.selector));
    if (!success) { revert(); }
    return abi.decode(result, (bool, uint256));
  }

  /**
   * @notice Calculates the current collateral ratio on Compound, using 18 decimals
   * @return the collateral ratio
   */
  function getCurrentCollateralRatioInDAI() public returns (uint256 _amount) {
    (bool success, bytes memory result) = logicContract.delegatecall(abi.encodeWithSelector(this.getCurrentCollateralRatioInDAI.selector));
    if (!success) { revert(); }
    return abi.decode(result, (uint256));
  }

  /**
   * @notice Calculates the current profit in DAI
   * @return the profit amount
   */
  function getCurrentProfitInDAI() public returns (bool _isNegative, uint256 _amount) {
    (bool success, bytes memory result) = logicContract.delegatecall(abi.encodeWithSelector(this.getCurrentProfitInDAI.selector));
    if (!success) { revert(); }
    return abi.decode(result, (bool, uint256));
  }

  function() external payable {}
}