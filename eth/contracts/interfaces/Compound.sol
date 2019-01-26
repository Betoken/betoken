pragma solidity ^0.4.25;

contract Compound {
  uint public collateralRatio;
  function supply(address asset, uint amount) public returns (uint);
  function withdraw(address asset, uint requestedAmount) public returns (uint);
  function borrow(address asset, uint amount) public returns (uint);
  function repayBorrow(address asset, uint amount) public returns (uint);
  function getAccountLiquidity(address account) view public returns (int);
  function getSupplyBalance(address account, address asset) view public returns (uint);
  function getBorrowBalance(address account, address asset) view public returns (uint);
  function assetPrices(address asset) public view returns (uint);
}