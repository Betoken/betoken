pragma solidity ^0.4.25;

interface WETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
}