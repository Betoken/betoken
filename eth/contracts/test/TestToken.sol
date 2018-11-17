pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";

/**
 * @title An ERC20 token used for testing.
 * @author Zefram Lou (Zebang Liu)
 */
contract TestToken is ERC20Mintable, ERC20Detailed {
  constructor(string name, string symbol, uint8 decimals)
    public
    ERC20Detailed(name, symbol, decimals)
  {}
}
