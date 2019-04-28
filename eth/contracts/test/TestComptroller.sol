pragma solidity 0.5.0;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../interfaces/Comptroller.sol";
import "../interfaces/PriceOracle.sol";
import "../interfaces/CERC20.sol";

contract TestComptroller is Comptroller {
  using SafeMath for uint;

  mapping(address => address[]) public getAssetsIn;

  constructor() public {}

  function enterMarkets(address[] calldata cTokens) external returns (uint[] memory) {
    for (uint256 i = 0; i < cTokens.length; i = i.add(1)) {
      getAssetsIn[msg.sender].push(cTokens[i]);
    }
  }
}