pragma solidity ^0.4.18;

import '../KyberNetwork.sol';
import '../Utils.sol';

contract TestKyberNetwork is KyberNetwork, Utils {
  mapping(address => uint256) priceInDAI;

  function TestKyberNetwork(address[] _tokens, uint256[] _pricesInDAI) public {
    for (uint256 i = 0; i < _tokens.length; i = i.add(1)) {
      priceInDAI[_tokens[i]] = _pricesInDAI[i];
    }
  }

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
    returns(uint)
  {
    uint256 destAmount = srcAmount.mul(priceInDAI[address(dest)]).div(priceInDAI[address(src)]);
    require(destAmount <= maxDestAmount);

    if (address(src) == address(ETH_TOKEN_ADDRESS)) {
      require(srcAmount == msg.value);
    } else {
      require(src.transferFrom(msg.sender, this, srcAmount));
    }

    if (address(dest) == address(ETH_TOKEN_ADDRESS)) {
      destAddress.transfer(destAmount);
    } else {
      require(dest.transfer(destAddress, destAmount));
    }
    return destAmount;
  }
}
