pragma solidity 0.5.0;

// Compound finance Ether market interface
interface CEther {
  function mint() external payable returns (uint);
  function redeemUnderlying(uint redeemAmount) external returns (uint);
  function borrow(uint borrowAmount) external returns (uint);
  function repayBorrow() external payable returns (uint);

  function balanceOf(address account) external view returns (uint);
  function borrowBalanceCurrent(address account) external view returns (uint);
  function exchangeRateCurrent() external view returns (uint);
}