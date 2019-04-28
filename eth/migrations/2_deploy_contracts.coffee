BetokenFund = artifacts.require "BetokenFund"
BetokenProxy = artifacts.require "BetokenProxy"
MiniMeToken = artifacts.require "MiniMeToken"
MiniMeTokenFactory = artifacts.require "MiniMeTokenFactory"
LongCERC20OrderLogic = artifacts.require "LongCERC20OrderLogic"
ShortCERC20OrderLogic = artifacts.require "ShortCERC20OrderLogic"
LongCEtherOrderLogic = artifacts.require "LongCEtherOrderLogic"
ShortCEtherOrderLogic = artifacts.require "ShortCEtherOrderLogic"
CompoundOrderFactory = artifacts.require "CompoundOrderFactory"
BetokenLogic = artifacts.require "BetokenLogic"

BigNumber = require "bignumber.js"

ZERO_ADDR = "0x0000000000000000000000000000000000000000"
ETH_ADDR = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
WETH_ADDR = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
PRECISION = 1e18

bnToString = (bn) -> BigNumber(bn).toFixed(0)

module.exports = (deployer, network, accounts) ->
  deployer.then () ->
    switch network
      when "development"
        # Local testnet migration
        config = require "../deployment_configs/testnet.json"

        TestKyberNetwork = artifacts.require "TestKyberNetwork"
        TestToken = artifacts.require "TestToken"
        TestTokenFactory = artifacts.require "TestTokenFactory"
        TestPriceOracle = artifacts.require "TestPriceOracle"
        TestComptroller = artifacts.require "TestComptroller"
        TestCERC20 = artifacts.require "TestCERC20"
        TestCEther = artifacts.require "TestCEther"
        TestCERC20Factory = artifacts.require "TestCERC20Factory"

        # deploy TestToken factory
        await deployer.deploy(TestTokenFactory)
        testTokenFactory = await TestTokenFactory.deployed()

        # create TestDAI
        testDAIAddr = (await testTokenFactory.newToken("DAI Stable Coin", "DAI", 18)).logs[0].args.addr
        TestDAI = await TestToken.at(testDAIAddr)
        
        # mint DAI for owner
        await TestDAI.mint(accounts[0], bnToString(1e7 * PRECISION)) # ten million

        # create TestTokens
        tokensInfo = require "../deployment_configs/kn_tokens.json"
        tokenAddrs = []
        for token in tokensInfo
          tokenAddrs.push((await testTokenFactory.newToken(token.name, token.symbol, token.decimals)).logs[0].args.addr)
        tokenAddrs.push(TestDAI.address)
        tokenAddrs.push(ETH_ADDR)
        tokenPrices = (bnToString(1000 * PRECISION) for i in [1..tokensInfo.length]).concat([bnToString(PRECISION), bnToString(10000 * PRECISION)])
  
        # deploy TestKyberNetwork
        await deployer.deploy(TestKyberNetwork, tokenAddrs, tokenPrices)

        # send ETH to TestKyberNetwork
        await web3.eth.sendTransaction({from: accounts[0], to: TestKyberNetwork.address, value: 1 * PRECISION})

        # deploy Test Compound suite of contracts

        # deploy TestPriceOracle
        await deployer.deploy(TestPriceOracle, tokenAddrs, tokenPrices)

        # deploy TestComptroller
        await deployer.deploy(TestComptroller)

        # deploy TestCERC20Factory
        await deployer.deploy(TestCERC20Factory)
        testCERC20Factory = await TestCERC20Factory.deployed()

        # deploy TestCEther
        await deployer.deploy(TestCEther, TestComptroller.address)

        # send ETH to TestCEther
        await web3.eth.sendTransaction({from: accounts[0], to: TestCEther.address, value: 1 * PRECISION})

        # deploy TestCERC20 contracts
        compoundTokens = {}
        for token in tokenAddrs[0..tokenAddrs.length - 2]
          compoundTokens[token] = (await testCERC20Factory.newToken(token, TestComptroller.address)).logs[0].args.cToken


        # mint tokens for KN
        for token in tokenAddrs[0..tokenAddrs.length - 2]
          tokenObj = await TestToken.at(token)
          await tokenObj.mint(TestKyberNetwork.address, bnToString(1e12 * PRECISION)) # one trillion tokens

        # mint tokens for Compound markets
        for token in tokenAddrs[0..tokenAddrs.length - 2]
          tokenObj = await TestToken.at(token)
          await tokenObj.mint(compoundTokens[token], bnToString(1e12 * PRECISION)) # one trillion tokens        

        # deploy Kairo and Betoken Shares contracts
        await deployer.deploy(MiniMeTokenFactory)
        minimeFactory = await MiniMeTokenFactory.deployed()
        controlTokenAddr = (await minimeFactory.createCloneToken(
            ZERO_ADDR, 0, "Kairo", 18, "KRO", true)).logs[0].args.addr
        shareTokenAddr = (await minimeFactory.createCloneToken(
            ZERO_ADDR, 0, "Betoken Shares", 18, "BTKS", true)).logs[0].args.addr
        ControlToken = await MiniMeToken.at(controlTokenAddr)
        ShareToken = await MiniMeToken.at(shareTokenAddr)
        
        # deploy ShortCERC20OrderLogic
        await deployer.deploy(ShortCERC20OrderLogic)

        # deploy ShortCEtherOrderLogic
        await deployer.deploy(ShortCEtherOrderLogic)

        # deploy LongCERC20OrderLogic
        await deployer.deploy(LongCERC20OrderLogic)

        # deploy LongCEtherOrderLogic
        await deployer.deploy(LongCEtherOrderLogic)

        # deploy CompoundOrderFactory
        await deployer.deploy(
          CompoundOrderFactory,
          ShortCERC20OrderLogic.address,
          ShortCEtherOrderLogic.address,
          LongCERC20OrderLogic.address,
          LongCEtherOrderLogic.address,
          TestDAI.address,
          TestKyberNetwork.address,
          TestComptroller.address,
          TestPriceOracle.address,
          compoundTokens[TestDAI.address],
          TestCEther.address
        )

        # deploy BetokenLogic
        await deployer.deploy(BetokenLogic)

        # deploy BetokenFund contract
        compoundTokensArray = (compoundTokens[token] for token in tokenAddrs[0..tokenAddrs.length - 3])
        compoundTokensArray.push(TestCEther.address)
        await deployer.deploy(
          BetokenFund,
          ControlToken.address,
          ShareToken.address,
          accounts[0], #devFundingAccount
          config.phaseLengths,
          bnToString(config.devFundingRate),
          ZERO_ADDR,
          TestDAI.address,
          TestKyberNetwork.address,
          CompoundOrderFactory.address,
          BetokenLogic.address,
          [TestDAI.address]
          compoundTokensArray
        )
        betokenFund = await BetokenFund.deployed()

        # deploy BetokenProxy contract
        await deployer.deploy(
          BetokenProxy,
          BetokenFund.address
        )

        # set proxy address in BetokenFund
        await betokenFund.setProxy(BetokenProxy.address)

        await ControlToken.transferOwnership(betokenFund.address)
        await ShareToken.transferOwnership(betokenFund.address)

      when "mainnet"
        # Mainnet Migration
        config = require "../deployment_configs/mainnet.json"

        PRECISION = 1e18

        KAIRO_ADDR = "0x0532894d50c8f6D51887f89eeF853Cc720D7ffB4"
        KYBER_ADDR = "0x818E6FECD516Ecc3849DAf6845e3EC868087B755"
        DAI_ADDR = "0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359"
        COMPOUND_ADDR = "0x3FDA67f7583380E67ef93072294a7fAc882FD7E7"
        DEVELOPER_ACCOUNT = "0x332d87209f7c8296389c307eae170c2440830a47"
        STABLECOINS = [
          DAI_ADDR,
          "0x0000000000085d4780B73119b644AE5ecd22b376", # TUSD
          "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", # USDC
          "0xdB25f211AB05b1c97D595516F45794528a807ad8", # EURS
          "0xdAC17F958D2ee523a2206206994597C13D831ec7", # USDT
          "0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd", # GUSD
          "0x8E870D67F660D95d5be530380D0eC0bd388289E1", # PAX
          "0x57Ab1E02fEE23774580C119740129eAC7081e9D3", # sUSD
          "0xAbdf147870235FcFC34153828c769A70B3FAe01F" # EURT
        ]

        # deploy Betoken Shares contracts
        await deployer.deploy(MiniMeTokenFactory)
        minimeFactory = await MiniMeTokenFactory.deployed()
        ShareToken = MiniMeToken.at((await minimeFactory.createCloneToken(
            "0x0", 0, "Betoken Shares", 18, "BTKS", true)).logs[0].args.addr)

        # deploy ShortOrderLogic
        await deployer.deploy(ShortOrderLogic)
        
        # deploy LongOrderLogic
        await deployer.deploy(LongOrderLogic)

        # deploy CompoundOrderFactory
        await deployer.deploy(
          CompoundOrderFactory,
          ShortOrderLogic.address,
          LongOrderLogic.address,
          DAI_ADDR,
          KYBER_ADDR,
          COMPOUND_ADDR
        )

        # deploy BetokenLogic
        await deployer.deploy(BetokenLogic)

        # deploy BetokenFund contract
        await deployer.deploy(
          BetokenFund,
          KAIRO_ADDR,
          ShareToken.address,
          DEVELOPER_ACCOUNT
          config.phaseLengths,
          bnToString(config.devFundingRate),
          ZERO_ADDR,
          DAI_ADDR,
          KYBER_ADDR,
          COMPOUND_ADDR,
          CompoundOrderFactory.address,
          BetokenLogic.address
        )

        # deploy BetokenProxy contract
        await deployer.deploy(
          BetokenProxy,
          BetokenFund.address
        )

        # set proxy address in BetokenFund
        await betokenFund.setProxy(BetokenProxy.address)

        # transfer ShareToken ownership to BetokenFund
        await ShareToken.transferOwnership(BetokenFund.address)

        # transfer fund ownership to developer multisig
        fund = await BetokenFund.deployed()
        await fund.transferOwnership(DEVELOPER_ACCOUNT)

        # IMPORTANT: After deployment, need to transfer ownership of Kairo contract to the BetokenFund contract