pragma solidity ^0.4.24;

import 'zeppelin-solidity/contracts/token/ERC20/MintableToken.sol';
import 'zeppelin-solidity/contracts/token/ERC20/DetailedERC20.sol';

/**
 * @title An ERC20 token used for testing.
 * @author Zefram Lou (Zebang Liu)
 */
contract TestToken is MintableToken, DetailedERC20 {
  constructor(string name, string symbol, uint8 decimals)
    public
    DetailedERC20(name, symbol, decimals)
  {}
}
