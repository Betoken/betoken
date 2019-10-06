pragma solidity 0.5.12;

interface BetokenProxyInterface {
  function betokenFundAddress() external view returns (address payable);
  function updateBetokenFundAddress() external;
}