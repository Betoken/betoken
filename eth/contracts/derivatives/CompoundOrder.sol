pragma solidity 0.5.0;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../Utils.sol";

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
  uint256 public buyTime; // Timestamp for order execution
  address public tokenAddr;
  bool public isSold;
  bool public orderType; // True for shorting, false for longing

  // Contract instances
  ERC20Detailed internal token;

  // The contract containing the code to be executed
  address public logicContract;

  constructor(
    address _tokenAddr,
    uint256 _cycleNumber,
    uint256 _stake,
    uint256 _collateralAmountInDAI,
    uint256 _loanAmountInDAI,
    bool _orderType,
    address _logicContract,
    address payable kro_addr,
    address dai_addr,
    address payable kyber_addr,
    address compound_addr
  ) public Utils(kro_addr, dai_addr, kyber_addr, compound_addr)  {
    // Initialize details of short order
    require(_tokenAddr != DAI_ADDR);
    require(_stake > 0 && _collateralAmountInDAI > 0 && _loanAmountInDAI > 0); // Validate inputs
    stake = _stake;
    collateralAmountInDAI = _collateralAmountInDAI;
    loanAmountInDAI = _loanAmountInDAI;
    cycleNumber = _cycleNumber;
    tokenAddr = _tokenAddr;
    orderType = _orderType;
    logicContract = _logicContract;
    token = ERC20Detailed(_tokenAddr);
  }
  
  function executeOrder(uint256 _minPrice, uint256 _maxPrice) public {
    (bool success,) = logicContract.delegatecall(abi.encodeWithSelector(this.executeOrder.selector, _minPrice, _maxPrice));
    if (!success) { revert(); }
  }

  function sellOrder(uint256 _minPrice, uint256 _maxPrice) public returns (uint256 _inputAmount, uint256 _outputAmount) {
    (bool success,) = logicContract.delegatecall(abi.encodeWithSelector(this.sellOrder.selector, _minPrice, _maxPrice));
    if (!success) { revert(); }
  }

  function repayLoan(uint256 _repayAmountInDAI) public {
    (bool success,) = logicContract.delegatecall(abi.encodeWithSelector(this.repayLoan.selector, _repayAmountInDAI));
    if (!success) { revert(); }
  }

  function getCurrentLiquidityInDAI() public returns (bool _isNegative, uint256 _amount) {
    (bool success, bytes memory result) = logicContract.delegatecall(abi.encodeWithSelector(this.getCurrentLiquidityInDAI.selector));
    if (!success) { revert(); }
    return abi.decode(result, (bool, uint256));
  }

  function getCurrentCollateralRatioInDAI() public returns (uint256 _amount) {
    (bool success, bytes memory result) = logicContract.delegatecall(abi.encodeWithSelector(this.getCurrentCollateralRatioInDAI.selector));
    if (!success) { revert(); }
    return abi.decode(result, (uint256));
  }

  function getCurrentProfitInDAI() public returns (bool _isNegative, uint256 _amount) {
    (bool success, bytes memory result) = logicContract.delegatecall(abi.encodeWithSelector(this.getCurrentProfitInDAI.selector));
    if (!success) { revert(); }
    return abi.decode(result, (bool, uint256));
  }
}