pragma solidity 0.5.0;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../interfaces/CEther.sol";
import "../interfaces/Comptroller.sol";

contract TestCEther is CEther {
  using SafeMath for uint;

  uint public constant PRECISION = 10 ** 18;

  uint public reserveFactorMantissa = 2 * PRECISION / 3;
  uint public exchangeRateCurrent = PRECISION;

  mapping(address => uint) public balanceOf;
  mapping(address => uint) public borrowBalanceCurrent;

  Comptroller public COMPTROLLER;

  constructor(address _comptrollerAddr) public {
    COMPTROLLER = Comptroller(_comptrollerAddr);
  }

  function mint() external payable returns (uint) {
    balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);
    return 0;
  }

  function redeemUnderlying(uint redeemAmount) external returns (uint) {
    balanceOf[msg.sender] = balanceOf[msg.sender].sub(redeemAmount);

    msg.sender.transfer(redeemAmount);

    // check if there's still enough liquidity
    (,,uint shortfall) = COMPTROLLER.getAccountLiquidity(msg.sender);
    require(shortfall == 0);

    return 0;
  }
  
  function borrow(uint amount) external returns (uint) {
    // add to borrow balance
    borrowBalanceCurrent[msg.sender] = borrowBalanceCurrent[msg.sender].add(amount);

    // transfer asset
    msg.sender.transfer(amount);

    // check if there's still enough liquidity
    (,,uint shortfall) = COMPTROLLER.getAccountLiquidity(msg.sender);
    require(shortfall == 0);

    return 0;
  }
  
  function repayBorrow() external payable returns (uint) {
    borrowBalanceCurrent[msg.sender] = borrowBalanceCurrent[msg.sender].sub(msg.value);
    return 0;
  }

  function() external payable {}
}