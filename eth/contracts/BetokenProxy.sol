pragma solidity 0.5.12;

import "./BetokenFund.sol";

contract BetokenProxy {
  address payable public betokenFundAddress;

  event UpdatedFundAddress(address payable _newFundAddr);

  constructor(address payable _fundAddr) public {
    betokenFundAddress = _fundAddr;
    emit UpdatedFundAddress(_fundAddr);
  }

  function updateBetokenFundAddress() public {
    require(msg.sender == betokenFundAddress, "Sender not BetokenFund");
    address payable nextVersion = BetokenFund(betokenFundAddress).nextVersion();
    require(nextVersion != address(0), "Next version can't be empty");
    betokenFundAddress = nextVersion;
    emit UpdatedFundAddress(betokenFundAddress);
  }
}