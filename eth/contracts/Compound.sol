pragma solidity ^0.4.25;

interface Compound {
    function supply(address asset, uint amount) external returns (uint);
    function withdraw(address asset, uint requestedAmount) external returns (uint);
    function borrow(address asset, uint amount) external returns (uint);
    function repayBorrow(address asset, uint amount) external returns (uint);
    function getAccountLiquidity(address account) view external returns (int);
    function getSupplyBalance(address account, address asset) view external returns (uint);
    function getBorrowBalance(address account, address asset) view external returns (uint);
    function liquidateBorrow(address targetAccount, address assetBorrow, address assetCollateral, uint requestedAmountClose) external returns (uint);
    function assetPrices(address asset) external view returns (uint);
}