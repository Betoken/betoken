pragma solidity 0.5.13;

interface BetokenProxyInterface {
  function betokenFundAddress() external view returns (address payable);
  function updateBetokenFundAddress() external;
}