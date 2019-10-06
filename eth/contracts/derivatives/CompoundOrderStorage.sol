pragma solidity 0.5.12;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../interfaces/Comptroller.sol";
import "../interfaces/PriceOracle.sol";
import "../interfaces/CERC20.sol";

contract CompoundOrderStorage is Ownable {
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
  uint256 public outputAmount; // Records the total output DAI after order is sold
  address public compoundTokenAddr;
  bool public isSold;
  bool public orderType; // True for shorting, false for longing

  // The contract containing the code to be executed
  address public logicContract;
}