pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

/**
 * @title The smart contract for useful utility functions and constants.
 * @author Zefram Lou (Zebang Liu)
 */
contract Utils {
  using SafeMath for uint256;

  ERC20Detailed constant internal ETH_TOKEN_ADDRESS = ERC20Detailed(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
  uint  constant internal PRECISION = (10**18);
  uint  constant internal MAX_QTY   = (10**28); // 10B tokens
  uint  constant internal ETH_DECIMALS = 18;
  uint  constant internal MAX_DECIMALS = 18;
  uint  constant internal MIN_DECIMALS = 11;

  function getDecimals(ERC20Detailed _token) internal view returns(uint256) {
    if (address(_token) == address(ETH_TOKEN_ADDRESS)) {
      return uint256(ETH_DECIMALS);
    }
    return uint256(_token.decimals());
  }

  function getBalance(ERC20Detailed _token, address _addr) internal view returns(uint256) {
    if (address(_token) == address(ETH_TOKEN_ADDRESS)) {
      return _addr.balance;
    }
    return uint256(_token.balanceOf(_addr));
  }

  function calcRateFromQty(uint srcAmount, uint destAmount, uint srcDecimals, uint dstDecimals)
        internal pure returns(uint)
  {
    require(srcAmount <= MAX_QTY);
    require(destAmount <= MAX_QTY);

    if (dstDecimals >= srcDecimals) {
      require((dstDecimals - srcDecimals) <= MAX_DECIMALS);
      return (destAmount * PRECISION / ((10 ** (dstDecimals - srcDecimals)) * srcAmount));
    } else {
      require((srcDecimals - dstDecimals) <= MAX_DECIMALS);
      return (destAmount * PRECISION * (10 ** (srcDecimals - dstDecimals)) / srcAmount);
    }
  }
}