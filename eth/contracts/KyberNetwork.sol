pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/token/ERC20/DetailedERC20.sol';

contract KyberNetwork {
  function trade(
    DetailedERC20 src,
    uint srcAmount,
    DetailedERC20 dest,
    address destAddress,
    uint maxDestAmount,
    uint minConversionRate,
    address walletId
  )
    public
    payable
    returns(uint);

  function findBestRate(DetailedERC20 src, DetailedERC20 dest, uint srcQty) public view returns(uint, uint);

  function getExpectedRate(DetailedERC20 src, DetailedERC20 dest, uint srcQty) public view returns (uint expectedRate, uint slippageRate);
}
