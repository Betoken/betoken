BetokenFund = artifacts.require "BetokenFund"
ControlToken = artifacts.require "ControlToken"
ShareToken = artifacts.require "ShareToken"

module.exports = (deployer, network, accounts) ->
  deployer.then () ->
    if network == "development" || network == "rinkeby"
      # Testnet Migration

      config = require "../deployment_configs/testnet.json"
      ETH_TOKEN_ADDRESS = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
      TestKyberNetwork = artifacts.require "TestKyberNetwork"
      TestToken = artifacts.require "TestToken"

      #TestAsset = await deployer.deploy(TestToken, "Test Asset", "AST", 1)
      await deployer.deploy(TestToken, "DAI Stable Coin", "DAI", 18)
      TestDAI = await TestToken.deployed()
      await deployer.deploy(TestKyberNetwork, [TestDAI.address, ETH_TOKEN_ADDRESS], [1, 600])
      await deployer.deploy([ControlToken, ShareToken])
      await deployer.deploy(
        BetokenFund,
        ControlToken.address,
        ShareToken.address,
        TestKyberNetwork.address,
        TestDAI.address,
        accounts[0], #developerFeeAccount
        config.phaseLengths,
        config.commissionRate,
        config.assetFeeRate
        config.developerFeeRate,
        config.exitFeeRate,
        config.functionCallReward,
        "0x0"
      )

      controlToken = await ControlToken.deployed()
      shareToken = await ShareToken.deployed()
      controlToken.transferOwnership(BetokenFund.address)
      shareToken.transferOwnership(BetokenFund.address)


