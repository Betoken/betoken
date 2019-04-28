pragma solidity 0.5.0;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";
import "../interfaces/CERC20.sol";
import "../interfaces/Comptroller.sol";

contract TestCERC20 is CERC20 {
  using SafeMath for uint;

  uint public constant PRECISION = 10 ** 18;
  uint public constant MAX_UINT = 2 ** 256 - 1;

  address public underlying;
  uint public reserveFactorMantissa = 2 * PRECISION / 3;
  uint public exchangeRateCurrent = PRECISION;

  mapping(address => uint) public balanceOf;
  mapping(address => uint) public borrowBalanceCurrent;

  Comptroller public COMPTROLLER;

  constructor(address _underlying, address _comptrollerAddr) public {
    underlying = _underlying;
    COMPTROLLER = Comptroller(_comptrollerAddr);
  }

  function mint(uint mintAmount) external returns (uint) {
    ERC20Detailed token = ERC20Detailed(underlying);
    require(token.transferFrom(msg.sender, address(this), mintAmount));

    balanceOf[msg.sender] = balanceOf[msg.sender].add(mintAmount);
    
    return 0;
  }

  function redeemUnderlying(uint redeemAmount) external returns (uint) {
    balanceOf[msg.sender] = balanceOf[msg.sender].sub(redeemAmount);

    ERC20Detailed token = ERC20Detailed(underlying);
    require(token.transfer(msg.sender, redeemAmount));

    // check if there's still enough liquidity
    (,,uint shortfall) = COMPTROLLER.getAccountLiquidity(msg.sender);
    require(shortfall == 0);

    return 0;
  }
  
  function borrow(uint amount) external returns (uint) {
    // add to borrow balance
    borrowBalanceCurrent[msg.sender] = borrowBalanceCurrent[msg.sender].add(amount);

    // transfer asset
    ERC20Detailed token = ERC20Detailed(underlying);
    require(token.transfer(msg.sender, amount));

    // check if there's still enough liquidity
    (,,uint shortfall) = COMPTROLLER.getAccountLiquidity(msg.sender);
    require(shortfall == 0);

    return 0;
  }
  
  function repayBorrow(uint amount) external returns (uint) {
    // accept repayment
    ERC20Detailed token = ERC20Detailed(underlying);
    uint256 repayAmount = amount == MAX_UINT ? borrowBalanceCurrent[msg.sender] : amount;
    require(token.transferFrom(msg.sender, address(this), repayAmount));

    // subtract from borrow balance
    borrowBalanceCurrent[msg.sender] = borrowBalanceCurrent[msg.sender].sub(repayAmount);

    return 0;
  }
}