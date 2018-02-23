pragma solidity ^0.4.18;


import 'zeppelin-solidity/contracts/token/ERC20/DetailedERC20.sol';


/// @title Kyber constants contract
contract Utils {
  DetailedERC20 constant internal ETH_TOKEN_ADDRESS = DetailedERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
  uint  constant internal PRECISION = (10**18);
  uint  constant internal MAX_QTY   = (10**28); // 10B tokens
  uint  constant internal MAX_RATE  = (PRECISION * 10**6); // up to 1M tokens per ETH
  uint  constant internal MAX_DECIMALS = 18;
  uint  constant internal ETH_DECIMALS = 18;
}