pragma solidity ^0.4.9;

contract EtherDelta{
  //the admin address
  address public admin;

  //the account that will receive fees
  address public feeAccount;

  //the address of the AccountLevels contract
  address public accountLevelsAddr;

  //percentage times (1 ether)
  uint public feeMake;

  //percentage times (1 ether)
  uint public feeTake;

  //percentage times (1 ether)
  uint public feeRebate;

  //mapping of token addresses to mapping of account balances (token=0 means Ether)
  mapping (address => mapping (address => uint)) public tokens;

  //mapping of user accounts to mapping of order hashes to booleans (true = submitted by user, equivalent to offchain signature)
  mapping (address => mapping (bytes32 => bool)) public orders;

  //mapping of user accounts to mapping of order hashes to uints (amount of order that has been filled)
  mapping (address => mapping (bytes32 => uint)) public orderFills;

  //****
  // Deposit and withdraw functions:
  //****
  function deposit() public payable;
  function withdraw(uint amount) public;
  function depositToken(address token, uint amount) public;
  function withdrawToken(address token, uint amount) public;

  function balanceOf(address token, address user) public constant returns (uint);

  function order(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce) public;

  function trade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s, uint amount) public;

  function testTrade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s, uint amount, address sender) public constant returns(bool);

  function availableVolume(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s) public constant returns(uint);

  function amountFilled(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s) public constant returns(uint);

  function cancelOrder(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, uint8 v, bytes32 r, bytes32 s) public;
}
