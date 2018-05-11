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
      TestTokenFactory = artifacts.require "TestTokenFactory"

      # deploy TestToken factory
      await deployer.deploy(TestTokenFactory)
      TokenFactory = await TestTokenFactory.deployed()

      # create TestTokens
      testAssetAddr = (await TokenFactory.newToken("Test Asset", "AST", 11)).logs[0].args.addr
      testDAIAddr = (await TokenFactory.newToken("DAI Stable Coin", "DAI", 18)).logs[0].args.addr
      console.log "Test asset address: " + testAssetAddr
      TestAsset = TestToken.at(testAssetAddr)
      TestDAI = TestToken.at(testDAIAddr)

      # deploy TestKyberNetwork
      await deployer.deploy(TestKyberNetwork, [TestDAI.address, ETH_TOKEN_ADDRESS, TestAsset.address], [1, 600, 1000])
      # mint tokens for KN
      await TestAsset.mint(TestKyberNetwork.address, 1e27)
      await TestDAI.mint(TestKyberNetwork.address, 1e27)

      # deploy Betoken fund contracts
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


