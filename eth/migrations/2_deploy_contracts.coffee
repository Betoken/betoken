BetokenFund = artifacts.require "BetokenFund"
BetokenProxy = artifacts.require "BetokenProxy"
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

      when "mainnet"
        # Mainnet Migration
        config = require "../deployment_configs/mainnet.json"

        PRECISION = 1e18

        KAIRO_ADDR = "0x0532894d50c8f6D51887f89eeF853Cc720D7ffB4"
        KYBER_ADDR = "0x818E6FECD516Ecc3849DAf6845e3EC868087B755"
        DAI_ADDR = "0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359"
        DEVELOPER_ACCOUNT = "0x332d87209f7c8296389c307eae170c2440830a47"

        # deploy Betoken Shares contracts
        await deployer.deploy(MiniMeTokenFactory)
        minimeFactory = await MiniMeTokenFactory.deployed()
        ShareToken = MiniMeToken.at((await minimeFactory.createCloneToken(
            "0x0", 0, "Betoken Shares", 18, "BTKS", true)).logs[0].args.addr)

        # deploy BetokenProxy contract

        # deploy BetokenFund contract
        await deployer.deploy(
          BetokenFund,
          KAIRO_ADDR,
          ShareToken.address,
          KYBER_ADDR,
          DAI_ADDR,
          BetokenProxy.address
          DEVELOPER_ACCOUNT,
          config.phaseLengths,
          config.commissionRate,
          config.assetFeeRate
          config.developerFeeRate,
          config.exitFeeRate,
          config.functionCallReward,
          0,
          0,
          "0x0"
        )

        # transfer ShareToken ownership to BetokenFund
        await ShareToken.transferOwnership(BetokenFund.address)

        # transfer fund ownership to developer
        fund = await BetokenFund.deployed()
        await fund.transferOwnership(DEVELOPER_ACCOUNT)
