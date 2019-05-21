pragma solidity 0.5.8;

// Compound finance's price oracle
interface PriceOracle {
  function getUnderlyingPrice(address CToken) external view returns (uint);
  function assetPrices(address Asset) external view returns (uint);
}