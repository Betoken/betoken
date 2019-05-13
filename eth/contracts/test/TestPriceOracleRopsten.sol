pragma solidity 0.5.0;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../interfaces/PriceOracle.sol";
import "../interfaces/CERC20.sol";
import "../interfaces/KyberNetwork.sol";

contract TestPriceOracleRopsten is PriceOracle {
  using SafeMath for uint;

  address internal constant KYBER_ADDR = 0x818E6FECD516Ecc3849DAf6845e3EC868087B755;
  ERC20Detailed internal constant ETH_TOKEN_ADDRESS = ERC20Detailed(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
  
  constructor() public {}

  function getUnderlyingPrice(address CToken) external view returns (uint) {
    address underlying = CERC20(CToken).underlying();
    return this.assetPrices(underlying);
  }

  function assetPrices(address asset) external view returns (uint) {
    ERC20Detailed token = ERC20Detailed(asset);
    uint256 decimals = uint256(token.decimals());
    // srcAmount is 1 token
    (, uint256 rate) = KyberNetwork(KYBER_ADDR).getExpectedRate(ERC20Detailed(asset), ETH_TOKEN_ADDRESS, 10 ** decimals);
    return rate;
  }
}