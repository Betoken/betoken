BetokenFund = artifacts.require "BetokenFund"
ControlToken = artifacts.require "ControlToken"
ShareToken = artifacts.require "ShareToken"

config = require "../deployment_configs/testnet.json"

module.exports = (deployer, network, accounts) ->
  deployer.deploy([ControlToken, ShareToken]).then(
    () ->
      deployer.deploy(
        BetokenFund,
        ControlToken.address,
        ShareToken.address,
        config.kyberAddress,
        accounts[0], #developerFeeAccount
        config.phaseLengths,
        config.commissionRate,
        config.developerFeeProportion,
        config.functionCallReward,
        "0x0"
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

