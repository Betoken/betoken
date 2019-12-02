pragma solidity 0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../interfaces/PriceOracle.sol";
import "../interfaces/CERC20.sol";

contract TestPriceOracle is PriceOracle, Ownable {
  using SafeMath for uint;

  uint public constant PRECISION = 10 ** 18;
  address public CETH_ADDR;

  mapping(address => uint256) public priceInDAI;

  constructor(address[] memory _tokens, uint256[] memory _pricesInDAI, address _cETH) public {
    for (uint256 i = 0; i < _tokens.length; i = i.add(1)) {
      priceInDAI[_tokens[i]] = _pricesInDAI[i];
    }
    CETH_ADDR = _cETH;
  }

  function setTokenPrice(address _token, uint256 _priceInDAI) public onlyOwner {
    priceInDAI[_token] = _priceInDAI;
  }

  function getUnderlyingPrice(address cToken) external view returns (uint) {
    return priceInDAI[cToken].mul(PRECISION).div(priceInDAI[CETH_ADDR]);
  }
}