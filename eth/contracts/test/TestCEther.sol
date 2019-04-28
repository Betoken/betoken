pragma solidity 0.5.0;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../interfaces/CEther.sol";
import "../interfaces/Comptroller.sol";

contract TestCEther is CEther {
  using SafeMath for uint;

  uint public constant PRECISION = 10 ** 18;

  uint public _reserveFactorMantissa = 2 * PRECISION / 3;
  uint public _exchangeRateCurrent = PRECISION;

  mapping(address => uint) public _balanceOf;
  mapping(address => uint) public _borrowBalanceCurrent;

  Comptroller public COMPTROLLER;

  constructor(address _comptrollerAddr) public {
    COMPTROLLER = Comptroller(_comptrollerAddr);
  }

  function mint() external payable returns (uint) {
    _balanceOf[msg.sender] = _balanceOf[msg.sender].add(msg.value);
    return 0;
  }

  function redeemUnderlying(uint redeemAmount) external returns (uint) {
    _balanceOf[msg.sender] = _balanceOf[msg.sender].sub(redeemAmount);

    msg.sender.transfer(redeemAmount);

    return 0;
  }
  
  function borrow(uint amount) external returns (uint) {
    // add to borrow balance
    _borrowBalanceCurrent[msg.sender] = _borrowBalanceCurrent[msg.sender].add(amount);

    // transfer asset
    msg.sender.transfer(amount);

    return 0;
  }
  
  function repayBorrow() external payable returns (uint) {
    _borrowBalanceCurrent[msg.sender] = _borrowBalanceCurrent[msg.sender].sub(msg.value);
    return 0;
  }

  function balanceOf(address account) external view returns (uint) { return _balanceOf[account]; }
  function borrowBalanceCurrent(address account) external view returns (uint) { return _borrowBalanceCurrent[account]; }
  function reserveFactorMantissa() external view returns (uint) { return _reserveFactorMantissa; }
  function exchangeRateCurrent() external view returns (uint) { return _exchangeRateCurrent; }

  function() external payable {}
}