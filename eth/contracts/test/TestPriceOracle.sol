pragma solidity 0.5.8;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../interfaces/PriceOracle.sol";
import "../interfaces/CERC20.sol";

contract TestPriceOracle is PriceOracle, Ownable {
  using SafeMath for uint;

  address internal constant ETH_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  uint public constant PRECISION = 10 ** 18;
  
  mapping(address => uint256) public priceInDAI;

  constructor(address[] memory _tokens, uint256[] memory _pricesInDAI) public {
    for (uint256 i = 0; i < _tokens.length; i = i.add(1)) {
      priceInDAI[_tokens[i]] = _pricesInDAI[i];
    }
  }

  function setTokenPrice(address _token, uint256 _priceInDAI) public onlyOwner {
    priceInDAI[_token] = _priceInDAI;
  }

  function getUnderlyingPrice(address CToken) external view returns (uint) {
    address underlying = CERC20(CToken).underlying();
    return this.assetPrices(underlying);
  }

  function assetPrices(address asset) external view returns (uint) {
    return priceInDAI[asset].mul(PRECISION).div(priceInDAI[ETH_TOKEN_ADDRESS]);
  }
}