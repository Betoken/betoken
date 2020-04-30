BetokenFund = artifacts.require "BetokenFund"
BetokenProxy = artifacts.require "BetokenProxy"
MiniMeToken = artifacts.require "MiniMeToken"
MiniMeTokenFactory = artifacts.require "MiniMeTokenFactory"
LongCERC20Order = artifacts.require "LongCERC20Order"
ShortCERC20Order = artifacts.require "ShortCERC20Order"
LongCEtherOrder = artifacts.require "LongCEtherOrder"
ShortCEtherOrder = artifacts.require "ShortCEtherOrder"
CompoundOrderFactory = artifacts.require "CompoundOrderFactory"
BetokenLogic = artifacts.require "BetokenLogic"
BetokenLogic2 = artifacts.require "BetokenLogic2"

BigNumber = require "bignumber.js"

ZERO_ADDR = "0x0000000000000000000000000000000000000000"
ETH_ADDR = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
PRECISION = 1e18

bnToString = (bn) -> BigNumber(bn).toFixed(0)

module.exports = (deployer, network, accounts) ->
  deployer.then () ->
    switch network
      when "development", "develop"
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
        tokenPrices = (bnToString(10 * PRECISION) for i in [1..tokensInfo.length]).concat([bnToString(PRECISION), bnToString(20 * PRECISION)])
  
        # deploy TestKyberNetwork
        await deployer.deploy(TestKyberNetwork, tokenAddrs, tokenPrices)

        # send ETH to TestKyberNetwork
        await web3.eth.sendTransaction({from: accounts[0], to: TestKyberNetwork.address, value: 1 * PRECISION})

        # deploy Test Compound suite of contracts

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

        # deploy TestPriceOracle
        await deployer.deploy(TestPriceOracle, tokenAddrs, tokenPrices, TestCEther.address)


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
            ZERO_ADDR, 0, "Kairo", 18, "KRO", false)).logs[0].args.addr
        shareTokenAddr = (await minimeFactory.createCloneToken(
            ZERO_ADDR, 0, "Betoken Shares", 18, "BTKS", true)).logs[0].args.addr
        ControlToken = await MiniMeToken.at(controlTokenAddr)
        ShareToken = await MiniMeToken.at(shareTokenAddr)
        
        # deploy ShortCERC20Order
        await deployer.deploy(ShortCERC20Order)
        await (await ShortCERC20Order.deployed()).renounceOwnership()

        # deploy ShortCEtherOrder
        await deployer.deploy(ShortCEtherOrder)
        await (await ShortCEtherOrder.deployed()).renounceOwnership()

        # deploy LongCERC20Order
        await deployer.deploy(LongCERC20Order)
        await (await LongCERC20Order.deployed()).renounceOwnership()

        # deploy LongCEtherOrder
        await deployer.deploy(LongCEtherOrder)
        await (await LongCEtherOrder.deployed()).renounceOwnership()

        # deploy CompoundOrderFactory
        await deployer.deploy(
          CompoundOrderFactory,
          ShortCERC20Order.address,
          ShortCEtherOrder.address,
          LongCERC20Order.address,
          LongCEtherOrder.address,
          TestDAI.address,
          TestKyberNetwork.address,
          TestComptroller.address,
          TestPriceOracle.address,
          compoundTokens[TestDAI.address],
          TestCEther.address
        )

        # deploy BetokenLogic
        await deployer.deploy(BetokenLogic)
        await deployer.deploy(BetokenLogic2)

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
          BetokenLogic2.address,
          1,
          ZERO_ADDR
        )
        betokenFund = await BetokenFund.deployed()
        await betokenFund.initTokenListings(
          tokenAddrs[0..tokenAddrs.length - 3].concat([ETH_ADDR]),
          compoundTokensArray,
          []
        )

        # deploy BetokenProxy contract
        await deployer.deploy(
          BetokenProxy,
          BetokenFund.address
        )

        # set proxy address in BetokenFund
        await betokenFund.setProxy(BetokenProxy.address)

        await ControlToken.transferOwnership(betokenFund.address)
        await ShareToken.transferOwnership(betokenFund.address)

        await betokenFund.nextPhase()

      when "mainnet"
        # Mainnet Migration
        config = require "../deployment_configs/mainnet.json"

        PRECISION = 1e18

        KYBER_TOKENS = config.KYBER_TOKENS.map((x) -> web3.utils.toChecksumAddress(x))

        # deploy ShortCERC20Order
        await deployer.deploy(ShortCERC20Order, {gas: 3.4e6})
        ShortCERC20OrderContract = await ShortCERC20Order.deployed()
        await ShortCERC20OrderContract.init(
          config.COMPOUND_CETH_ADDR,
          1,
          1,
          1,
          1,
          true,
          config.DAI_ADDR,
          config.KYBER_ADDR,
          config.COMPOUND_COMPTROLLER_ADDR,
          config.COMPOUND_ORACLE_ADDR,
          config.COMPOUND_CDAI_ADDR,
          config.COMPOUND_CETH_ADDR,
          {gas: 5e5}
        )
        await ShortCERC20OrderContract.renounceOwnership({gas: 4e5})

        # deploy ShortCEtherOrder
        await deployer.deploy(ShortCEtherOrder, {gas: 3.5e6})
        ShortCEtherOrderContract = await ShortCEtherOrder.deployed()
        await ShortCEtherOrderContract.init(
          config.COMPOUND_CETH_ADDR,
          1,
          1,
          1,
          1,
          true,
          config.DAI_ADDR,
          config.KYBER_ADDR,
          config.COMPOUND_COMPTROLLER_ADDR,
          config.COMPOUND_ORACLE_ADDR,
          config.COMPOUND_CDAI_ADDR,
          config.COMPOUND_CETH_ADDR,
          {gas: 5e5}
        )
        await ShortCEtherOrderContract.renounceOwnership({gas: 4e5})

        # deploy LongCERC20Order
        await deployer.deploy(LongCERC20Order, {gas: 3.5e6})
        LongCERC20OrderContract = await LongCERC20Order.deployed()
        await LongCERC20OrderContract.init(
          config.COMPOUND_CETH_ADDR,
          1,
          1,
          1,
          1,
          false,
          config.DAI_ADDR,
          config.KYBER_ADDR,
          config.COMPOUND_COMPTROLLER_ADDR,
          config.COMPOUND_ORACLE_ADDR,
          config.COMPOUND_CDAI_ADDR,
          config.COMPOUND_CETH_ADDR,
          {gas: 5e5}
        )
        await LongCERC20OrderContract.renounceOwnership({gas: 4e5})

        # deploy LongCEtherOrder
        await deployer.deploy(LongCEtherOrder, {gas: 3.3e6})
        LongCEtherOrderContract = await LongCEtherOrder.deployed()
        await LongCEtherOrderContract.init(
          config.COMPOUND_CETH_ADDR,
          1,
          1,
          1,
          1,
          false,
          config.DAI_ADDR,
          config.KYBER_ADDR,
          config.COMPOUND_COMPTROLLER_ADDR,
          config.COMPOUND_ORACLE_ADDR,
          config.COMPOUND_CDAI_ADDR,
          config.COMPOUND_CETH_ADDR,
          {gas: 5e5}
        )
        await LongCEtherOrderContract.renounceOwnership({gas: 4e5})

        # deploy CompoundOrderFactory
        await deployer.deploy(
          CompoundOrderFactory,
          ShortCERC20OrderContract.address,
          ShortCEtherOrderContract.address,
          LongCERC20OrderContract.address,
          LongCEtherOrderContract.address,
          config.DAI_ADDR,
          config.KYBER_ADDR,
          config.COMPOUND_COMPTROLLER_ADDR,
          config.COMPOUND_ORACLE_ADDR,
          config.COMPOUND_CDAI_ADDR,
          config.COMPOUND_CETH_ADDR
          {gas: 8e5}
        )

        # deploy BetokenLogic
        await deployer.deploy(BetokenLogic, {gas: 6.5e6})
        await deployer.deploy(BetokenLogic2, {gas: 6.7e6})

        ###minimeFactory = await MiniMeTokenFactory.at('0xa72f38629585cEa5Fe9d17E5ebBdbffb5A2fEC8a')
        controlTokenAddr = (await minimeFactory.createCloneToken(
            config.KAIRO_ADDR, 8995570, "Test Kairo", 18, "Test-KRO", false, {gas: 3e6})).logs[0].args.addr
        shareTokenAddr = (await minimeFactory.createCloneToken(
            config.SHARES_ADDR, 8995570, "Test Betoken Shares", 18, "Test-BTKS", true, {gas: 3e6})).logs[0].args.addr
        ControlToken = await MiniMeToken.at(controlTokenAddr)
        ShareToken = await MiniMeToken.at(shareTokenAddr)###

        # deploy BetokenFund contract
        await deployer.deploy(
          BetokenFund,
          config.KAIRO_ADDR,
          config.SHARES_ADDR,
          config.DEVELOPER_ACCOUNT,
          config.phaseLengths,
          bnToString(config.devFundingRate),
          config.PREV_VERSION,
          config.DAI_ADDR,
          config.KYBER_ADDR,
          CompoundOrderFactory.address,
          BetokenLogic.address,
          BetokenLogic2.address,
          config.START_CYCLE_NUM,
          config.DEXAG_ADDR,
          {gas: 6e6}
        )
        betokenFund = await BetokenFund.deployed()

       ### console.log "Transferring Kairo ownership to BetokenFund..."
        await ControlToken.transferOwnership(betokenFund.address, {gas: 4e5})

        console.log "Transferring BetokenShares ownership to BetokenFund..."
        await ShareToken.transferOwnership(betokenFund.address, {gas: 4e5})###

        console.log "Initializing token listings..."
        await betokenFund.initTokenListings(
          config.KYBER_TOKENS,
          config.COMPOUND_CTOKENS,
          config.FULCRUM_PTOKENS,
          {gas: 2.72e6}
        )

        # set proxy address in BetokenFund
        console.log "Setting proxy address..."
        await betokenFund.setProxy(config.PROXY_ADDR, {gas: 4e5})

        # transfer fund ownership to developer multisig
        console.log "Transferring BetokenFund ownership..."
        await betokenFund.transferOwnership(config.DEVELOPER_ACCOUNT, {gas: 4e5})