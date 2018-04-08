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
  uint  constant internal MAX_RATE  = (PRECISION * 10**6); // up to 1M tokens per ETH
  uint  constant internal MAX_DECIMALS = 18;
  uint  constant internal ETH_DECIMALS = 18;

  /**
   * @notice Calculates the invert of a fixed-point decimal with precision PRECISION
   * @param x the fixed-point decimal to be inverted
   */
  function invert(uint256 x) internal pure returns(uint256) {
    return PRECISION.mul(PRECISION).div(x);
  }
}