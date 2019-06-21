pragma solidity 0.5.8;

// Compound finance's price oracle
interface PriceOracle {
  function getPrice(address asset) external view returns (uint);
}