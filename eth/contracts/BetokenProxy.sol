pragma solidity 0.5.0;

import "./BetokenFund.sol";

contract BetokenProxy {
  address public betokenFundAddress;
  BetokenFund internal betokenFund;

  constructor(address payable _fundAddr) public {
    betokenFundAddress = _fundAddr;
    betokenFund = BetokenFund(_fundAddr);
  }

  function updateBetokenFundAddress() public {
    require(msg.sender == betokenFundAddress, "Sender not BetokenFund");
    address payable nextVersion = betokenFund.nextVersion();
    require(nextVersion != address(0), "Next version can't be empty");
    betokenFundAddress = nextVersion;
    betokenFund = BetokenFund(nextVersion);
  }

  function() external payable {
    address target = betokenFundAddress;
    bytes memory data = msg.data;
    assembly {
      let result := delegatecall(gas, target, add(data, 0x20), mload(data), 0, 0)
      let size := returndatasize
      let ptr := mload(0x40)
      returndatacopy(ptr, 0, size)
      switch result
      case 0 { revert(ptr, size) }
      default { return(ptr, size) }
    }
  }
}