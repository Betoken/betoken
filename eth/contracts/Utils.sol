pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/token/ERC20/DetailedERC20.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';

/**
 * @title The smart contract for useful utility functions and constants.
 * @author Zefram Lou (Zebang Liu)
 */
contract Utils {
  using SafeMath for uint256;

  DetailedERC20 constant internal ETH_TOKEN_ADDRESS = DetailedERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
  uint  constant internal PRECISION = (10**18);
  uint  constant internal MAX_QTY   = (10**28); // 10B tokens
  uint  constant internal ETH_DECIMALS = 18;

  /**
   * @notice Calculates the invert of a fixed-point decimal with precision PRECISION
   * @param x the fixed-point decimal to be inverted
   */
  function invert(uint256 x) internal pure returns(uint256) {
    return PRECISION.mul(PRECISION).div(x);
  }

  function getDecimals(DetailedERC20 _token) internal view returns(uint256) {
    if (address(_token) == address(ETH_TOKEN_ADDRESS)) {
      return uint256(ETH_DECIMALS);
    }
    return uint256(_token.decimals());
  }

  function getBalance(DetailedERC20 _token, address _addr) internal view returns(uint256) {
    if (address(_token) == address(ETH_TOKEN_ADDRESS)) {
      return _addr.balance;
    }
    return uint256(_token.balanceOf(_addr));
  }
}