var GroupFund = artifacts.require("GroupFund");
var ControlToken = artifacts.require("ControlToken");
var OraclizeHandler = artifacts.require("OraclizeHandler");

module.exports = function(deployer) {
  var etherDeltaAddress = "0x4e10d1807608994489355d873edb6dc09b151776";
  deployer.deploy([[
    GroupFund,
    etherDeltaAddress, //Ethdelta address
    18, //decimals
    1800,//30 * 24 * 3600, //timeOfCycle
    600,//2 * 24 * 3600, //timeOfChangeMaking
    600,//2 * 24 * 3600, //timeOfProposalMaking
    0.01 * Math.pow(10, 18), //againstStakeProportion
    20, //maxProposals
    0.01 * Math.pow(10, 18), //commissionRate
    30,//3600 / 20, //orderExpirationTimeInBlocks
    0.01 * Math.pow(10, 18) //oraclizeFeeProportion
  ], [ControlToken]]).then(
    () => {
      return deployer.deploy(OraclizeHandler, ControlToken.address, etherDeltaAddress);
    }
  ).then(
    () => {
      return ControlToken.deployed().then(
        (instance) => {
          instance.transferOwnership(GroupFund.address);
        }
      );
    }
  ).then(
    () => {
      return OraclizeHandler.deployed().then(
        (instance) => {
          instance.transferOwnership(GroupFund.address);
        }
      );
    }
  ).then(
    () => {
      return GroupFund.deployed().then(
        (instance) => {
          instance.initializeSubcontracts(ControlToken.address, OraclizeHandler.address);
        }
      );
    }
  );
};
