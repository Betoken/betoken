pragma solidity 0.5.0;

import "./BetokenFund.sol";

contract BetokenProxy {
  address payable public betokenFundAddress;

  constructor(address payable _fundAddr) public {
    betokenFundAddress = _fundAddr;
  }

  function updateBetokenFundAddress() public {
    require(msg.sender == betokenFundAddress, "Sender not BetokenFund");
    address payable nextVersion = BetokenFund(betokenFundAddress).nextVersion();
    require(nextVersion != address(0), "Next version can't be empty");
    betokenFundAddress = nextVersion;
  }
}