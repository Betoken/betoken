pragma solidity ^0.4.24;

import 'zeppelin-solidity/contracts/token/ERC20/DetailedERC20.sol';

/**
 * @title The interface for the Kyber Network smart contract
 * @author Zefram Lou (Zebang Liu)
 */
interface KyberNetwork {
  function trade(
    DetailedERC20 src,
    uint srcAmount,
    DetailedERC20 dest,
    address destAddress,
    uint maxDestAmount,
    uint minConversionRate,
    address walletId
  )
    external
    payable
    returns(uint);
}
