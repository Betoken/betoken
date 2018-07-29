BetokenFund = artifacts.require "BetokenFund"
MiniMeToken = artifacts.require "MiniMeToken"
MiniMeTokenFactory = artifacts.require "MiniMeTokenFactory"

module.exports = (deployer, network, accounts) ->
  deployer.then () ->
    switch network
      when "development"
        # Local testnet migration

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

        # mint DAI for owner
        await TestDAI.mint(accounts[0], 1e7 * PRECISION) # ten million

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
          await TestToken.at(token).mint(TestKyberNetwork.address, 1e12 * PRECISION) # one trillion tokens

        # deploy Kairo and Betoken Shares contracts
        await deployer.deploy(MiniMeTokenFactory)
        minimeFactory = await MiniMeTokenFactory.deployed()
        ControlToken = MiniMeToken.at((await minimeFactory.createCloneToken(
            "0x0", 0, "Kairo", 18, "KRO", true)).logs[0].args.addr)
        ShareToken = MiniMeToken.at((await minimeFactory.createCloneToken(
            "0x0", 0, "Betoken Shares", 18, "BTKS", true)).logs[0].args.addr)

        await ControlToken.generateTokens(accounts[1], 1e4 * PRECISION)
        await ControlToken.generateTokens(accounts[2], 1e4 * PRECISION)

        # deploy BetokenFund contract
        await deployer.deploy(
          BetokenFund,
          ControlToken.address,
          ShareToken.address,
          TestKyberNetwork.address,
          TestDAI.address,
          TestTokenFactory.address,
          accounts[0], #developerFeeAccount
          config.phaseLengths,
          config.commissionRate,
          config.assetFeeRate
          config.developerFeeRate,
          config.exitFeeRate,
          config.functionCallReward,
          "0x0"
        )

        await ControlToken.transferOwnership(BetokenFund.address)
        await ShareToken.transferOwnership(BetokenFund.address)

      when "rinkeby"
        # Rinkeby Migration
        config = require "../deployment_configs/rinkeby_beta.json"

        TestKyberNetwork = artifacts.require "TestKyberNetwork"
        TestToken = artifacts.require "TestToken"
        TestTokenFactory = artifacts.require "TestTokenFactory"
        PRECISION = 1e18

        HD_WALLET = "0x45755b7876F0b67BE1BBdB700Bc0118A930A3cb8"

        # deploy TestToken factory
        await deployer.deploy(TestTokenFactory)
        TokenFactory = await TestTokenFactory.deployed()

        # create TestDAI
        testDAIAddr = (await TokenFactory.newToken("DAI Stable Coin", "DAI", 18)).logs[0].args.addr
        TestDAI = TestToken.at(testDAIAddr)

        # mint DAI for owner
        await TestDAI.mint(accounts[0], 1e7 * PRECISION) # ten million

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
          await TestToken.at(token).mint(TestKyberNetwork.address, 1e12 * PRECISION) # one trillion tokens
          await TestToken.at(token).finishMinting(); # stop minting

        # deploy Kairo and Betoken Shares contracts
        await deployer.deploy(MiniMeTokenFactory)
        minimeFactory = await MiniMeTokenFactory.deployed()
        ControlToken = MiniMeToken.at((await minimeFactory.createCloneToken(
            "0x0", 0, "Kairo", 18, "KRO", true)).logs[0].args.addr)
        ShareToken = MiniMeToken.at((await minimeFactory.createCloneToken(
            "0x0", 0, "Betoken Shares", 18, "BTKS", true)).logs[0].args.addr)

        # deploy BetokenFund contract
        await deployer.deploy(
          BetokenFund,
          ControlToken.address,
          ShareToken.address,
          TestKyberNetwork.address,
          TestDAI.address,
          TestTokenFactory.address,
          accounts[0], #developerFeeAccount
          config.phaseLengths,
          config.commissionRate,
          config.assetFeeRate
          config.developerFeeRate,
          config.exitFeeRate,
          config.functionCallReward,
          "0x0"
        )

        await ControlToken.transferOwnership(BetokenFund.address)
        await ShareToken.transferOwnership(BetokenFund.address)

        fund = await BetokenFund.deployed()
        await fund.transferOwnership(HD_WALLET)
