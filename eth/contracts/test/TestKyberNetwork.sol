pragma solidity 0.5.13;

import "../interfaces/KyberNetwork.sol";
import "../Utils.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract TestKyberNetwork is KyberNetwork, Utils(address(0), address(0), address(0)), Ownable {
  mapping(address => uint256) public priceInDAI;

  constructor(address[] memory _tokens, uint256[] memory _pricesInDAI) public {
    for (uint256 i = 0; i < _tokens.length; i = i.add(1)) {
      priceInDAI[_tokens[i]] = _pricesInDAI[i];
    }
  }

  function setTokenPrice(address _token, uint256 _priceInDAI) public onlyOwner {
    priceInDAI[_token] = _priceInDAI;
  }

  function setAllTokenPrices(address[] memory _tokens, uint256[] memory _pricesInDAI) public onlyOwner {
    for (uint256 i = 0; i < _tokens.length; i = i.add(1)) {
      priceInDAI[_tokens[i]] = _pricesInDAI[i];
    }
  }

  function getExpectedRate(ERC20Detailed src, ERC20Detailed dest, uint /*srcQty*/) external view returns (uint expectedRate, uint slippageRate) 
  {
    uint256 result = priceInDAI[address(src)].mul(10**getDecimals(dest)).mul(PRECISION).div(priceInDAI[address(dest)].mul(10**getDecimals(src)));
    return (result, result);
  }

  function tradeWithHint(
    ERC20Detailed src,
    uint srcAmount,
    ERC20Detailed dest,
    address payable destAddress,
    uint maxDestAmount,
    uint /*minConversionRate*/,
    address /*walletId*/,
    bytes calldata /*hint*/
  )
    external
    payable
    returns(uint)
  {
    require(calcDestAmount(src, srcAmount, dest) <= maxDestAmount);

    if (address(src) == address(ETH_TOKEN_ADDRESS)) {
      require(srcAmount == msg.value);
    } else {
      require(src.transferFrom(msg.sender, address(this), srcAmount));
    }

    if (address(dest) == address(ETH_TOKEN_ADDRESS)) {
      destAddress.transfer(calcDestAmount(src, srcAmount, dest));
    } else {
      require(dest.transfer(destAddress, calcDestAmount(src, srcAmount, dest)));
    }
    return calcDestAmount(src, srcAmount, dest);
  }

  function calcDestAmount(
    ERC20Detailed src,
    uint srcAmount,
    ERC20Detailed dest
  ) internal view returns (uint destAmount) {
    return srcAmount.mul(priceInDAI[address(src)]).mul(10**getDecimals(dest)).div(priceInDAI[address(dest)].mul(10**getDecimals(src)));
  }

  function() external payable {}
}
