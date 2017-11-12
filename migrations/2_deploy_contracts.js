var GroupFund = artifacts.require("GroupFund");

module.exports = function(deployer) {
  deployer.deploy(
    GroupFund,
    "0x8d12A197cB00D4747a1fe03395095ce2A5CC6819", //Ethdelta address
    18, //decimals
    30 * 24 * 3600, //timeOfCycle
    2 * 24 * 3600, //timeOfChangeMaking
    2 * 24 * 3600, //timeOfProposalMaking
    0.01 * Math.pow(10, 18), //againstStakeProportion
    20, //maxProposals
    0.01 * Math.pow(10, 18) //commissionRate
  );
};
