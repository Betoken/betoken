pragma solidity ^0.4.23;

import './TestToken.sol';

contract TestTokenFactory {
  mapping(bytes32 => address) private createdTokens;

  event CreatedToken(string symbol, address addr);

  function newToken(string name, string symbol, uint8 decimals) public returns(address) {
    TestToken token = new TestToken(name, symbol, decimals);
    token.transferOwnership(msg.sender);
    createdTokens[keccak256(symbol)] = address(token);
    emit CreatedToken(symbol, address(token));
    return address(token);
  }

  function getToken(string symbol) public view returns(address) {
    return createdTokens[keccak256(symbol)];
  }
}
