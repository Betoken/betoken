BetokenFund = artifacts.require "BetokenFund"
ControlToken = artifacts.require "ControlToken"
ShareToken = artifacts.require "ShareToken"

module.exports = (deployer, network, accounts) ->
  deployer.then () ->
    if network == "development" || network == "rinkeby"
      # Testnet Migration

      config = require "../deployment_configs/testnet.json"
      TestKyberNetwork = artifacts.require "TestKyberNetwork"
      TestToken = artifacts.require "TestToken"
      TestTokenFactory = artifacts.require "TestTokenFactory"
      PRECISION = 1e18

      # deploy TestToken factory
      await deployer.deploy(TestTokenFactory)
      TokenFactory = await TestTokenFactory.deployed()

      # create TestDAI
      testDAIAddr = (await TokenFactory.newToken("DAI Stable Coin", "DAI", 18)).logs[0].args.addr
      TestDAI = TestToken.at(testDAIAddr)

      # create TestTokens
      tokens = require "../deployment_configs/kn_tokens.json"
      tokenAddrs = []
      for token in tokens
        tokenAddrs.push((await TokenFactory.newToken(token.name, token.symbol, token.decimals)).logs[0].args.addr)
      tokenAddrs.push(TestDAI.address)
      tokenPrices = (1000 * PRECISION for i in [1..tokens.length]).concat([PRECISION])

      # deploy TestKyberNetwork
      await deployer.deploy(TestKyberNetwork, tokenAddrs, tokenPrices)

      # mint tokens for KN
      for token in tokenAddrs
        await TestToken.at(token).mint(TestKyberNetwork.address, 1e11 * PRECISION) # one trillion

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