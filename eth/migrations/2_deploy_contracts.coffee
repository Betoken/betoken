BetokenFund = artifacts.require "BetokenFund"
ControlToken = artifacts.require "ControlToken"

config = require "../deployment_configs/testnet.json"

module.exports = (deployer, network, accounts) ->
  deployer.deploy([[
    BetokenFund,
    config.kyberAddress, #KyberNetwork address
    accounts[0], #developerFeeAccount
    config.timeOfChangeMaking,#2 * 24 * 3600, #timeOfChangeMaking
    config.timeOfProposalMaking,#2 * 24 * 3600, #timeOfProposalMaking
    config.timeOfWaiting, #timeOfWaiting
    config.minStakeProportion, #minStakeProportion
    config.maxProposals, #maxProposals
    config.commissionRate, #commissionRate
    config.developerFeeProportion, #developerFeeProportion
    config.maxProposalsPerMember, #maxProposalsPerMember
    0 #cycleNumber
  ], [ControlToken]]).then(
    () ->
      return ControlToken.deployed().then(
        (instance) ->
          instance.transferOwnership(BetokenFund.address)
      )
  ).then(
    () ->
      return BetokenFund.deployed().then(
        (instance) ->
          instance.initializeSubcontracts(ControlToken.address)
      )
  )

