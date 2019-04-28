pragma solidity 0.5.0;

// Compound finance comptroller
interface Comptroller {
    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);
    function getAccountLiquidity(address account) external view returns (uint, uint, uint);
}