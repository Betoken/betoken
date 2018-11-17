pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";

/**
 * @title The interface for the Kyber Network smart contract
 * @author Zefram Lou (Zebang Liu)
 */
interface KyberNetwork {
  function maxGasPrice() public view returns(uint);
  function getUserCapInWei(address user) public view returns(uint);
  function getUserCapInTokenWei(address user, ERC20Detailed token) public view returns(uint);
  function enabled() public view returns(bool);
  function info(bytes32 id) public view returns(uint);

  function getExpectedRate(ERC20Detailed src, ERC20Detailed dest, uint srcQty) public view
      returns (uint expectedRate, uint slippageRate);

  function tradeWithHint(ERC20Detailed src, uint srcAmount, ERC20Detailed dest, address destAddress, uint maxDestAmount,
      uint minConversionRate, address walletId, bytes hint) public payable returns(uint);
}
