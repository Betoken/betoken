BetokenFund = artifacts.require "BetokenFund"
ControlToken = artifacts.require "ControlToken"
OraclizeHandler = artifacts.require "OraclizeHandler"

config = require "../deployment_configs/testnet.json"

module.exports = (deployer, network, accounts) ->
  deployer.deploy([[
    BetokenFund,
    config.etherDeltaAddress, #Ethdelta address
    accounts[0], #developerFeeAccount
    config.precision, #precision
    config.timeOfChangeMaking,#2 * 24 * 3600, #timeOfChangeMaking
    config.timeOfProposalMaking,#2 * 24 * 3600, #timeOfProposalMaking
    config.timeOfWaiting, #timeOfWaiting
    config.timeOfSellOrderWaiting, #timeOfSellOrderWaiting
    config.minStakeProportion, #minStakeProportion
    config.maxProposals, #maxProposals
    config.commissionRate, #commissionRate
    config.orderExpirationTimeInBlocks,#3600 / 20, #orderExpirationTimeInBlocks
    config.developerFeeProportion, #developerFeeProportion
    config.maxProposalsPerMember #maxProposalsPerMember
  ], [ControlToken]]).then(
    () ->
      return deployer.deploy(
        OraclizeHandler,
        ControlToken.address,
        config.etherDeltaAddress,
        "json(https:#min-api.cryptocompare.com/data/price?fsym=",
        "&tsyms=ETH).ETH"
      )
  ).then(
    () ->
      return ControlToken.deployed().then(
        (instance) ->
          instance.transferOwnership(BetokenFund.address)
      )
  ).then(
    () ->
      return OraclizeHandler.deployed().then(
        (instance) ->
          instance.transferOwnership(BetokenFund.address)
      )
  ).then(
    () ->
      return BetokenFund.deployed().then(
        (instance) ->
          instance.initializeSubcontracts(ControlToken.address, OraclizeHandler.address)
      )
  )

