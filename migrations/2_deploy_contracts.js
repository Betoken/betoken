var GroupFund = artifacts.require("GroupFund");

module.exports = function(deployer) {
  deployer.deploy(
    GroupFund,
    "0x228344536a03c0910fb8be9c2755c1a0ba6f89e1", //Ethdelta address
    18, //decimals
    30 * 24 * 3600, //timeOfCycle
    2 * 24 * 3600, //timeOfChangeMaking
    2 * 24 * 3600, //timeOfProposalMaking
    0.01 * Math.pow(10, 18), //againstStakeProportion
    20, //maxProposals
    0.01 * Math.pow(10, 18), //commissionRate
    3600 / 20, //orderExpirationTimeInBlocks
    0.01 * Math.pow(10, 18) //oraclizeFeeProportion
  );
};
