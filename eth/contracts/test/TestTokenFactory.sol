pragma solidity ^0.4.24;

import "./TestToken.sol";

contract TestTokenFactory {
  mapping(bytes32 => address) private createdTokens;

  event CreatedToken(string symbol, address addr);

  function newToken(string name, string symbol, uint8 decimals) public returns(address) {
    bytes32 symbolHash = keccak256(abi.encodePacked(symbol));
    require(createdTokens[symbolHash] == address(0));
    
    TestToken token = new TestToken(name, symbol, decimals);
    token.transferOwnership(msg.sender);
    createdTokens[symbolHash] = address(token);
    emit CreatedToken(symbol, address(token));
    return address(token);
  }

  function getToken(string symbol) public view returns(address) {
    return createdTokens[keccak256(abi.encodePacked(symbol))];
  }
}
