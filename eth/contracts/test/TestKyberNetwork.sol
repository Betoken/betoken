pragma solidity ^0.4.25;

import "../interfaces/KyberNetwork.sol";
import "../Utils.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract TestKyberNetwork is KyberNetwork, Utils, Ownable {
  mapping(address => uint256) public priceInDAI;

  constructor(address[] _tokens, uint256[] _pricesInDAI) public {
    for (uint256 i = 0; i < _tokens.length; i = i.add(1)) {
      priceInDAI[_tokens[i]] = _pricesInDAI[i];
    }
  }

  function setTokenPrice(address _token, uint256 _priceInDAI) public onlyOwner {
    priceInDAI[_token] = _priceInDAI;
  }

  function setAllTokenPrices(address[] _tokens, uint256[] _pricesInDAI) public onlyOwner {
    for (uint256 i = 0; i < _tokens.length; i = i.add(1)) {
      priceInDAI[_tokens[i]] = _pricesInDAI[i];
    }
  }

  function tradeWithHint(
    ERC20Detailed src,
    uint srcAmount,
    ERC20Detailed dest,
    address destAddress,
    uint maxDestAmount,
    uint minConversionRate,
    address walletId,
    bytes hint
  )
    external
    payable
    returns(uint)
  {
    uint256 destAmount = srcAmount.mul(priceInDAI[address(src)]).mul(10**getDecimals(dest)).div(priceInDAI[address(dest)].mul(10**getDecimals(src)));
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
