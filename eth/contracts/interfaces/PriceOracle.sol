pragma solidity 0.5.12;

// Compound finance's price oracle
interface PriceOracle {
  function getPrice(address asset) external view returns (uint);
}