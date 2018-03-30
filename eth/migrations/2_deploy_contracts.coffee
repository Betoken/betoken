BetokenFund = artifacts.require "BetokenFund"
ControlToken = artifacts.require "ControlToken"
ShareToken = artifacts.require "ShareToken"

config = require "../deployment_configs/testnet.json"

module.exports = (deployer, network, accounts) ->
  deployer.deploy([ControlToken, ShareToken]).then(
    () ->
      deployer.deploy(
        BetokenFund,
        ControlToken.deployed().address,
        ShareToken.deployed().address,
        config.kyberAddress,
        accounts[0], #developerFeeAccount
        config.timeOfChangeMaking,
        config.timeOfProposalMaking,
        config.timeOfWaiting,
        config.timeOfFinalizing,
        config.commissionRate,
        config.developerFeeProportion,
        0,
        config.functionCallReward,
        config.controlTokenInflation,
        config.aumThreshold
      )
  ).then(
    () ->
      return ControlToken.deployed().then(
        (instance) ->
          instance.transferOwnership(BetokenFund.address)
      )
  ).then(
    () ->
      return ShareToken.deployed().then(
        (instance) ->
          instance.transferOwnership(BetokenFund.address)
      )
  )

