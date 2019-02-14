BetokenFund = artifacts.require "BetokenFund"
BetokenProxy = artifacts.require "BetokenProxy"
MiniMeToken = artifacts.require "MiniMeToken"
MiniMeTokenFactory = artifacts.require "MiniMeTokenFactory"
TestKyberNetwork = artifacts.require "TestKyberNetwork"
TestToken = artifacts.require "TestToken"
TestTokenFactory = artifacts.require "TestTokenFactory"
TestCompound = artifacts.require "TestCompound"
CompoundOrder = artifacts.require "CompoundOrder"

BigNumber = require "bignumber.js"

epsilon = 1e-4

ZERO_ADDR = "0x0000000000000000000000000000000000000000"
PRECISION = 1e18
SHORT_LEVERAGE = -0.5
LONG_LEVERAGE = 1.5

bnToString = (bn) -> BigNumber(bn).toFixed(0)

PRECISION = 1e18
OMG_PRICE = 1000 * PRECISION
ETH_PRICE = 10000 * PRECISION
DAI_PRICE = PRECISION
EXIT_FEE = 0.03
PHASE_LENGTHS = (require "../deployment_configs/testnet.json").phaseLengths
DAY = 86400

timeTravel = (time) ->
  return new Promise((resolve, reject) -> 
    web3.currentProvider.send({
      jsonrpc: "2.0"
      method: "evm_increaseTime"
      params: [time] # 86400 is num seconds in day
      id: new Date().getTime()
    }, (err, result) ->
      if err
        return reject(err)
      return resolve(result)
    );
  )

FUND = (cycle, phase, account) ->
  fund = await BetokenFund.deployed()
  curr_cycle = BigNumber(await fund.cycleNumber.call()).toNumber()
  curr_phase = BigNumber(await fund.cyclePhase.call()).toNumber()
  while curr_cycle < cycle || curr_phase < phase
    await timeTravel(PHASE_LENGTHS[curr_phase])
    await fund.nextPhase({from: account})
    curr_cycle = BigNumber(await fund.cycleNumber.call()).toNumber()
    curr_phase = BigNumber(await fund.cyclePhase.call()).toNumber()
  return fund

DAI = (fund) ->
  daiAddr = await fund.DAI_ADDR.call()
  return TestToken.at(daiAddr)

KN = (fund) ->
  kyberAddr = await fund.KYBER_ADDR.call()
  return TestKyberNetwork.at(kyberAddr)

TK = (symbol) ->
  factory = await TestTokenFactory.deployed()
  addr = await factory.getToken.call(symbol)
  return TestToken.at(addr)

ST = (fund) ->
  shareTokenAddr = await fund.shareTokenAddr.call()
  return MiniMeToken.at(shareTokenAddr)

KRO = (fund) ->
  kroAddr = await fund.controlTokenAddr.call()
  return MiniMeToken.at(kroAddr)

CPD = () ->
  return TestCompound.deployed()

CO = (fund, account, id) ->
  orderAddr = await fund.userCompoundOrders.call(account, id)
  return CompoundOrder.at(orderAddr)

epsilon_equal = (curr, prev) ->
  BigNumber(curr).minus(prev).div(prev).abs().lt(epsilon)

calcRegisterPayAmount = (fund, kroAmount, tokenPrice) ->
  kairoPrice = BigNumber await fund.kairoPrice.call()
  return kroAmount * kairoPrice / tokenPrice

contract("first_cycle", (accounts) ->
  owner = accounts[0]
  account = accounts[1]

  it("start_cycle", () ->
    this.fund = await FUND(1, 0, owner)

    # check phase
    cyclePhase = +await this.fund.cyclePhase.call()
    assert.equal(cyclePhase, 0, "cycle phase didn't change after cycle start")

    # check cycle number
    cycleNumber = +await this.fund.cycleNumber.call()
    assert.equal(cycleNumber, 1, "cycle number didn't change after cycle start")
  )

  it("register_accounts", () ->
    kro = await KRO(this.fund)
    dai = await DAI(this.fund)
    token = await TK("OMG")
    account2 = accounts[2]
    account3 = accounts[3]

    amount = 10 * PRECISION

    # register account[1] using ETH
    await this.fund.registerWithETH({from: account, value: await calcRegisterPayAmount(this.fund, amount, ETH_PRICE)})

    # mint DAI for account[2]
    daiAmount = bnToString(await calcRegisterPayAmount(this.fund, amount, DAI_PRICE))
    await dai.mint(account2, daiAmount, {from: owner})

    # register account[2]
    await dai.approve(this.fund.address, daiAmount, {from: account2})
    await this.fund.registerWithDAI(daiAmount, {from: account2})

    # mint OMG tokens for account[3]
    omgAmount = bnToString(await calcRegisterPayAmount(this.fund, amount, OMG_PRICE))
    await token.mint(account3, omgAmount, {from: owner})

    # register account[3]
    await token.approve(this.fund.address, omgAmount, {from: account3})
    await this.fund.registerWithToken(token.address, omgAmount, {from: account3})

    # check Kairo balances
    assert(epsilon_equal(amount, await kro.balanceOf.call(account)), "account 1 Kairo amount incorrect")
    assert(epsilon_equal(amount, await kro.balanceOf.call(account2)), "account 2 Kairo amount incorrect")
    assert(epsilon_equal(amount, await kro.balanceOf.call(account3)), "account 3 Kairo amount incorrect")
  )

  it("deposit_dai", () ->
    dai = await DAI(this.fund)
    st = await ST(this.fund)
    account2 = accounts[2]

    # give DAI to user
    amount = 1 * PRECISION
    await dai.mint(account2, bnToString(amount), {from: owner})

    # deposit DAI
    fundBalance = BigNumber await this.fund.totalFundsInDAI.call()
    prevDAIBlnce = BigNumber await dai.balanceOf.call(account2)
    prevShareBlnce = BigNumber await st.balanceOf.call(account2)
    await dai.approve(this.fund.address, bnToString(amount), {from: account2})
    await this.fund.depositDAI(bnToString(amount), {from: account2})
    await dai.approve(this.fund.address, 0, {from: account2})

    # check fund balance
    newFundBalance = BigNumber(await this.fund.totalFundsInDAI.call())
    assert.equal(newFundBalance.minus(fundBalance).toNumber(), amount, "fund balance increase incorrect")

    # check dai balance
    daiBlnce = BigNumber(await dai.balanceOf.call(account2))
    assert.equal(prevDAIBlnce.minus(daiBlnce).toNumber(), amount, "DAI balance decrease incorrect")

    # check shares
    shareBlnce = BigNumber(await st.balanceOf.call(account2))
    assert.equal(shareBlnce.minus(prevShareBlnce).toNumber(), amount, "received share amount incorrect")
  )

  it("deposit_token", () ->
    token = await TK("OMG")
    st = await ST(this.fund)

    # mint token for user
    amount = 1000 * PRECISION
    await token.mint(account, bnToString(amount), {from: owner})

    # deposit token
    fundBalance = BigNumber await this.fund.totalFundsInDAI.call()
    prevTokenBlnce = BigNumber await token.balanceOf.call(account)
    prevShareBlnce = BigNumber await st.balanceOf.call(account)
    await token.approve(this.fund.address, bnToString(amount), {from: account})
    await this.fund.depositToken(token.address, bnToString(amount), {from: account})
    await token.approve(this.fund.address, 0, {from: account})

    # check shares
    shareBlnce = BigNumber(await st.balanceOf.call(account))
    assert.equal(shareBlnce.minus(prevShareBlnce).toNumber(), Math.round(amount * OMG_PRICE / PRECISION), "received share amount incorrect")

    # check fund balance
    newFundBalance = BigNumber(await this.fund.totalFundsInDAI.call())
    assert.equal(newFundBalance.minus(fundBalance).toNumber(), Math.round(amount * OMG_PRICE / PRECISION), "fund balance increase incorrect")

    # check token balance
    tokenBlnce = BigNumber(await token.balanceOf.call(account))
    assert.equal(prevTokenBlnce.minus(tokenBlnce).toNumber(), amount, "token balance decrease incorrect")
  )

  it("withdraw_dai", () ->
    dai = await DAI(this.fund)
    st = await ST(this.fund)

    # withdraw dai
    amount = 0.1 * PRECISION
    prevShareBlnce = BigNumber await st.balanceOf.call(account)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    prevDAIBlnce = BigNumber await dai.balanceOf.call(account)
    await this.fund.withdrawDAI(bnToString(amount), {from: account})

    # check shares
    shareBlnce = BigNumber await st.balanceOf.call(account)
    assert.equal(prevShareBlnce.minus(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.minus(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check dai balance
    daiBlnce = BigNumber await dai.balanceOf.call(account)
    assert.equal(daiBlnce.minus(prevDAIBlnce).toNumber(), amount * (1 - EXIT_FEE), "DAI balance increase incorrect")
  )

  it("withdraw_token", () ->
    token = await TK("OMG")
    st = await ST(this.fund)

    # withdraw token
    amount = 1 * PRECISION

    prevShareBlnce = BigNumber await st.balanceOf.call(account)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    prevTokenBlnce = BigNumber await token.balanceOf.call(account)
    await this.fund.withdrawToken(token.address, bnToString(amount), {from: account})

    # check shares
    shareBlnce = BigNumber await st.balanceOf.call(account)
    assert.equal(prevShareBlnce.minus(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.minus(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check token balance
    tokenBlnce = BigNumber await token.balanceOf.call(account)
    assert.equal(tokenBlnce.minus(prevTokenBlnce).toNumber(), Math.round(amount * (1 - EXIT_FEE) * PRECISION / OMG_PRICE), "DAI balance increase incorrect")
  )

  it("phase_0_to_1", () ->
    await timeTravel(PHASE_LENGTHS[0])
    await this.fund.nextPhase({from: owner})

    # check phase
    cyclePhase = +await this.fund.cyclePhase.call()
    assert.equal(cyclePhase, 1, "cycle phase didn't change")

    # check cycle number
    cycleNumber = +await this.fund.cycleNumber.call()
    assert.equal(cycleNumber, 1, "cycle number didn't change")
  )

  it("create_investment", () ->
    kro = await KRO(this.fund)
    token = await TK("OMG")
    MAX_PRICE = bnToString(OMG_PRICE * 2)
    fund = this.fund

    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundTokenBlnce = BigNumber await token.balanceOf(this.fund.address)

    # buy token
    amount = 10 * PRECISION
    await this.fund.createInvestment(token.address, bnToString(amount), 0, MAX_PRICE, {from: account})

    # check KRO balance
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert.equal(prevKROBlnce.minus(kroBlnce).toNumber(), amount, "Kairo balance decrease incorrect")

    # check fund token balance
    fundDAIBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    kroTotalSupply = BigNumber await kro.totalSupply.call()
    fundTokenBlnce = BigNumber await token.balanceOf(fund.address)
    assert.equal(fundTokenBlnce.minus(prevFundTokenBlnce).toNumber(), Math.floor(fundDAIBlnce.times(PRECISION).div(kroTotalSupply).times(amount).div(OMG_PRICE).toNumber()), "token balance increase incorrect")

    # create investment for account2
    account2 = accounts[2]
    await this.fund.createInvestment(token.address, bnToString(amount), 0, MAX_PRICE, {from: account2})
  )

  it("sell_investment", () ->
    kro = await KRO(this.fund)
    token = await TK("OMG")
    MAX_PRICE = bnToString(OMG_PRICE * 2)

    # wait for 3 days to sell investment for accounts[1]
    await timeTravel(3 * DAY)

    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundTokenBlnce = BigNumber await token.balanceOf(this.fund.address)

    # sell investment
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account, 0)).tokenAmount)
    await this.fund.sellInvestmentAsset(0, bnToString(tokenAmount), 0, MAX_PRICE, {from: account})

    # check KRO balance
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    stake = BigNumber((await this.fund.userInvestments.call(account, 0)).stake)
    assert(epsilon_equal(stake, kroBlnce.minus(prevKROBlnce)), "received Kairo amount incorrect")

    # check fund token balance
    fundTokenBlnce = BigNumber await token.balanceOf(this.fund.address)
    assert(epsilon_equal(tokenAmount, prevFundTokenBlnce.minus(fundTokenBlnce)), "fund token balance changed")

    # wait for 6 more days to sell investment for account2
    account2 = accounts[2]
    await timeTravel(6 * DAY)
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account2, 0)).tokenAmount)
    await this.fund.sellInvestmentAsset(0, bnToString(tokenAmount.div(2)), 0, MAX_PRICE, {from: account2})
    await this.fund.sellInvestmentAsset(1, bnToString(tokenAmount.div(2)), 0, MAX_PRICE, {from: account2})
  )

  it("create_compound_orders", () ->
    kro = await KRO(this.fund)
    token = await TK("OMG")
    dai = await DAI(this.fund)
    MAX_PRICE = bnToString(OMG_PRICE * 2)
    fund = this.fund

    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundDAIBlnce = BigNumber await dai.balanceOf.call(this.fund.address)

    # create short order
    amount = 1 * PRECISION
    await this.fund.createCompoundOrder(true, token.address, bnToString(amount), 0, MAX_PRICE, {from: account})
    shortOrder = await CO(this.fund, account, 0)

    # check KRO balance
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert.equal(prevKROBlnce.minus(kroBlnce).toNumber(), amount, "Kairo balance decrease incorrect")

    # check fund token balance
    fundDAIBlnce = BigNumber await dai.balanceOf.call(this.fund.address)
    kroTotalSupply = BigNumber await kro.totalSupply.call()
    assert.equal(prevFundDAIBlnce.minus(fundDAIBlnce).toNumber(), await shortOrder.collateralAmountInDAI.call(), "DAI balance decrease incorrect")

    # create long order for account2
    account2 = accounts[2]
    await this.fund.createCompoundOrder(false, token.address, bnToString(amount), 0, MAX_PRICE, {from: account2})
  )

  it("sell_compound_orders", () ->
    kro = await KRO(this.fund)
    token = await TK("OMG")
    dai = await DAI(this.fund)
    MAX_PRICE = bnToString(OMG_PRICE * 2)
    account2 = accounts[2]


    # SHORT ORDER SELLING
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundDAIBlnce = BigNumber await dai.balanceOf.call(this.fund.address)

    # sell short order
    shortOrder = await CO(this.fund, account, 0)
    await this.fund.sellCompoundOrder(0, 0, MAX_PRICE, {from: account})

    # check KRO balance
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    stake = BigNumber await shortOrder.stake.call()
    assert(epsilon_equal(stake, kroBlnce.minus(prevKROBlnce)), "account received Kairo amount incorrect")

    # check fund DAI balance
    fundDAIBlnce = BigNumber await dai.balanceOf.call(this.fund.address)
    assert(epsilon_equal(await shortOrder.collateralAmountInDAI.call(), fundDAIBlnce.minus(prevFundDAIBlnce)), "short order returned incorrect DAI amount")


    # LONG ORDER SELLING
    prevKROBlnce = BigNumber await kro.balanceOf.call(account2)
    prevFundDAIBlnce = BigNumber await dai.balanceOf.call(this.fund.address)

    # sell account2's long order
    longOrder = await CO(this.fund, account2, 0)
    await this.fund.sellCompoundOrder(0, 0, MAX_PRICE, {from: account2})

    # check KRO balance
    kroBlnce = BigNumber await kro.balanceOf.call(account2)
    stake = BigNumber await longOrder.stake.call()
    assert(epsilon_equal(stake, kroBlnce.minus(prevKROBlnce)), "account2 received Kairo amount incorrect")

    # check fund DAI balance
    fundDAIBlnce = BigNumber await dai.balanceOf.call(this.fund.address)
    assert(epsilon_equal(await longOrder.collateralAmountInDAI.call(), fundDAIBlnce.minus(prevFundDAIBlnce)), "long order returned incorrect DAI amount")
  )

  it("next_cycle", () ->
    await timeTravel(18 * DAY) # spent 9 days on sell_investment tests
    await this.fund.nextPhase({from: owner})

    # check phase
    cyclePhase = +await this.fund.cyclePhase.call()
    assert.equal(cyclePhase, 0, "cycle phase didn't change")

    # check cycle number
    cycleNumber = +await this.fund.cycleNumber.call()
    assert.equal(cycleNumber, 2, "cycle number didn't change")
  )

  it("redeem_commission", () ->
    dai = await DAI(this.fund)

    prevDAIBlnce = BigNumber await dai.balanceOf.call(account)

    # get commission amount
    commissionAmount = await this.fund.commissionBalanceOf.call(account)

    # redeem commission
    await this.fund.redeemCommission({from: account})

    # check DAI balance
    daiBlnce = BigNumber await dai.balanceOf.call(account)
    assert(epsilon_equal(daiBlnce.minus(prevDAIBlnce), commissionAmount._commission), "didn't receive correct commission")

    # check penalty
    # only invested full kro balance for 3 days out of 9, so penalty / commission = 2
    assert(epsilon_equal(BigNumber(commissionAmount._penalty).div(commissionAmount._commission), 2), "penalty amount incorrect")
  )

  it("redeem_commission_in_shares", () ->
    st = await ST(this.fund)
    account2 = accounts[2]

    prevShareBlnce = BigNumber await st.balanceOf.call(account2)

    # get commission amount
    commissionAmount = await this.fund.commissionBalanceOf.call(account2)

    # redeem commission
    await this.fund.redeemCommissionInShares({from: account2})

    # check Share balance
    shareBlnce = BigNumber await st.balanceOf.call(account2)
    assert(shareBlnce.minus(prevShareBlnce).gt(0), "didn't receive corrent commission")

    # check penalty
    # staked for 9 days, penalty should be 0
    assert(BigNumber(commissionAmount._penalty).eq(0), "penalty amount incorrect")
  )

  it("next_phase", () ->
    await timeTravel(PHASE_LENGTHS[0])
    await this.fund.nextPhase({from: owner})
  )
)

contract("price_changes", (accounts) ->
  owner = accounts[0]
  account = accounts[1]

  it("prep_work", () ->
    this.fund = await FUND(1, 0, owner) # Starts in Intermission phase
    dai = await DAI(this.fund)

    kroAmount = 10 * PRECISION
    await this.fund.registerWithETH({from: account, value: await calcRegisterPayAmount(this.fund, kroAmount, ETH_PRICE)})

    amount = 10 * PRECISION
    await dai.mint(account, bnToString(amount), {from: owner}) # Mint DAI
    await dai.approve(this.fund.address, bnToString(amount), {from: account}) # Approve transfer
    await this.fund.depositDAI(bnToString(amount), {from: account}) # Deposit for account

    await timeTravel(PHASE_LENGTHS[0])
    await this.fund.nextPhase({from: owner}) # Go to Manage phase
  )

  it("raise_asset_price", () ->
    kn = await KN(this.fund)
    kro = await KRO(this.fund)
    omg = await TK("OMG")
    cpd = await CPD()
    MAX_PRICE = bnToString(OMG_PRICE * 2)

    # reset asset price
    await kn.setTokenPrice(omg.address, bnToString(OMG_PRICE), {from: owner})
    await cpd.setTokenPrice(omg.address, bnToString(OMG_PRICE), {from: owner})

    # invest in asset
    stake = 0.1 * PRECISION
    investmentId = 0
    await this.fund.createInvestment(omg.address, bnToString(stake), 0, MAX_PRICE, {from: account})

    # create short order
    shortId = 0
    await this.fund.createCompoundOrder(true, omg.address, bnToString(stake), 0, MAX_PRICE, {from: account})
    # create long order
    longId = 1
    await this.fund.createCompoundOrder(false, omg.address, bnToString(stake), 0, MAX_PRICE, {from: account})

    # raise asset price by 20%
    delta = 0.2
    newPrice = OMG_PRICE * (1 + delta)
    await kn.setTokenPrice(omg.address, bnToString(newPrice), {from: owner})
    await cpd.setTokenPrice(omg.address, bnToString(newPrice), {from: owner})

    # sell asset
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account, investmentId)).tokenAmount)
    await this.fund.sellInvestmentAsset(investmentId, tokenAmount, 0, MAX_PRICE, {from: account})

    # check KRO reward
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), 1 + delta), "investment KRO reward incorrect")

    # sell short order
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    await this.fund.sellCompoundOrder(shortId, 0, MAX_PRICE, {from: account})

    # check KRO penalty
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), 1 + delta * SHORT_LEVERAGE), "short KRO penalty incorrect")

    # sell long order
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    await this.fund.sellCompoundOrder(longId, 0, MAX_PRICE, {from: account})

    # check KRO reward
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), 1 + delta * LONG_LEVERAGE), "long KRO reward incorrect")
  )

  it("lower_asset_price", () ->
    kn = await KN(this.fund)
    kro = await KRO(this.fund)
    omg = await TK("OMG")
    cpd = await CPD()
    MAX_PRICE = bnToString(OMG_PRICE * 2)

    # reset asset price
    await kn.setTokenPrice(omg.address, bnToString(OMG_PRICE), {from: owner})
    await cpd.setTokenPrice(omg.address, bnToString(OMG_PRICE), {from: owner})

    # invest in asset
    stake = 0.1 * PRECISION
    investmentId = 1
    await this.fund.createInvestment(omg.address, bnToString(stake), 0, MAX_PRICE, {from: account})

    # create short order
    shortId = 2
    await this.fund.createCompoundOrder(true, omg.address, bnToString(stake), 0, MAX_PRICE, {from: account})
    # create long order
    longId = 3
    await this.fund.createCompoundOrder(false, omg.address, bnToString(stake), 0, MAX_PRICE, {from: account})

    # lower asset price by 20%
    delta = -0.2
    newPrice = OMG_PRICE * (1 + delta)
    await kn.setTokenPrice(omg.address, bnToString(newPrice), {from: owner})
    await cpd.setTokenPrice(omg.address, bnToString(newPrice), {from: owner})

    # sell asset
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account, investmentId)).tokenAmount)
    await this.fund.sellInvestmentAsset(investmentId, tokenAmount, 0, MAX_PRICE, {from: account})

    # check KRO penalty
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), 1 + delta), "investment KRO penalty incorrect")

    # sell short order
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    await this.fund.sellCompoundOrder(shortId, 0, MAX_PRICE, {from: account})

    # check KRO reward
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), 1 + delta * SHORT_LEVERAGE), "short KRO reward incorrect")

    # sell long order
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    await this.fund.sellCompoundOrder(longId, 0, MAX_PRICE, {from: account})

    # check KRO penalty
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), 1 + delta * LONG_LEVERAGE), "long KRO penalty incorrect")
  )

  it("lower_asset_price_to_0", () ->
    kn = await KN(this.fund)
    kro = await KRO(this.fund)
    omg = await TK("OMG")
    cpd = await CPD()
    MAX_PRICE = bnToString(OMG_PRICE * 2)

    # reset asset price
    await kn.setTokenPrice(omg.address, bnToString(OMG_PRICE), {from: owner})
    await cpd.setTokenPrice(omg.address, bnToString(OMG_PRICE), {from: owner})

    # invest in asset
    stake = 0.1 * PRECISION
    investmentId = 2
    await this.fund.createInvestment(omg.address, bnToString(stake), 0, MAX_PRICE, {from: account})

    # lower asset price by 99.99%
    delta = -0.9999
    newPrice = OMG_PRICE * (1 + delta)
    await kn.setTokenPrice(omg.address, bnToString(newPrice), {from: owner})
    await cpd.setTokenPrice(omg.address, bnToString(newPrice), {from: owner})

    # sell asset
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account, investmentId)).tokenAmount)
    await this.fund.sellInvestmentAsset(investmentId, tokenAmount, 0, MAX_PRICE, {from: account})

    # check KRO penalty
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), 1 + delta), "investment KRO penalty incorrect")
  )
)

contract("param_setters", (accounts) ->
  owner = accounts[0]

  it("prep_work", () ->
    this.fund = await FUND(1, 0, owner) # Starts in Intermission phase
  )

  it("decrease_only_proportion_setters", () ->
    # changeDeveloperFeeRate()
    devFeeRate = BigNumber await this.fund.developerFeeRate.call()
    # valid
    await this.fund.changeDeveloperFeeRate(devFeeRate.idiv(2), {from: owner})
    assert.equal(BigNumber(await this.fund.developerFeeRate.call()).toNumber(), devFeeRate.idiv(2).toNumber(), "changeDeveloperFeeRate() faulty")
    # invalid -- >= 1
    try
      await this.fund.changeDeveloperFeeRate(BigNumber(PRECISION), {from: owner})
      assert.fail("changeDeveloperFeeRate() accepted >=1 rate")
    # invalid -- larger than current value
    try
      await this.fund.changeDeveloperFeeRate(devFeeRate, {from: owner})
      assert.fail("changeDeveloperFeeRate() accepted >= current rate")

    # changeExitFeeRate()
    exitFeeRate = BigNumber await this.fund.exitFeeRate.call()
    # valid
    await this.fund.changeExitFeeRate(exitFeeRate.idiv(2), {from: owner})
    assert.equal(BigNumber(await this.fund.exitFeeRate.call()).toNumber(), exitFeeRate.idiv(2).toNumber(), "changeExitFeeRate() faulty")
    # invalid -- >= 1
    try
      await this.fund.changeExitFeeRate(BigNumber(PRECISION), {from: owner})
      assert.fail("changeExitFeeRate() accepted >=1 rate")
    # invalid -- larger than current value
    try
      await this.fund.changeExitFeeRate(exitFeeRate, {from: owner})
      assert.fail("changeExitFeeRate() accepted >= current rate")
  )

  it("address_setters", () ->
    newAddr = "0xdd974D5C2e2928deA5F71b9825b8b646686BD200"
    kro = await KRO(this.fund)

    # changeDeveloperFeeAccount()
    # valid address
    await this.fund.changeDeveloperFeeAccount(newAddr, {from: owner})
    assert.equal(await this.fund.developerFeeAccount.call(), newAddr, "changeDeveloperFeeAccount() faulty")
    # invalid address
    try
      await this.fund.changeDeveloperFeeAccount(ZERO_ADDR, {from: owner})
      assert.fail("changeDeveloperFeeAccount() accepted zero address")
  )
)

contract("community_initiated_upgrade", (accounts) ->
  owner = accounts[0]
  kroAmounts = [3 * PRECISION, 10 * PRECISION, 20 * PRECISION, 5 * PRECISION]
  depositAmount = 10 * PRECISION

  it("prep_work", () ->
    this.fund = await FUND(1, 0, owner) # Starts in Intermission phase
    dai = await DAI(this.fund)

    # register managers
    for i in [1..3]
      await this.fund.registerWithETH({from: accounts[i], value: await calcRegisterPayAmount(this.fund, kroAmounts[i], ETH_PRICE)})

    # deposit funds
    for i in [1..3]
      await dai.mint(accounts[i], bnToString(depositAmount), {from: owner}) # Mint DAI
      await dai.approve(this.fund.address, bnToString(depositAmount), {from: accounts[i]}) # Approve transfer
      await this.fund.depositDAI(bnToString(depositAmount), {from: accounts[i]}) # Deposit for account

    # move to the 4th cycle (due to the cooldown period after deployment)
    this.fund = await FUND(4, 0, owner)
  )

  it("approve_upgrade_initiation", () ->
    # check voting weights
    for i in [1..3]
      votingWeight = BigNumber(await this.fund.getVotingWeight.call(accounts[i])).div(PRECISION).toNumber()
      assert.equal(votingWeight, kroAmounts[i] / PRECISION, "account #{i} voting weight incorrect")

    # signal upgrade
    # 2 / 3 Kairo signals in support
    await this.fund.signalUpgrade(true, {from: accounts[1]})
    await this.fund.signalUpgrade(true, {from: accounts[2]})
    # 1 / 3 Kairo signals against
    # not necessary, just making sure it doesn't change anything
    await this.fund.signalUpgrade(false, {from: accounts[3]})
    
    # next phase
    this.fund = await FUND(4, 1, owner)

    # check if upgrade voting is active
    assert(await this.fund.upgradeVotingActive.call(), "upgrade voting not active")
  )

  it("make_first_proposal", () ->
    chunkNum = 1

    # wait till chunk 1
    await timeTravel(3 * DAY)

    # account 1 propose account 1 as candidate
    await this.fund.proposeCandidate(chunkNum, accounts[1], {from: accounts[1]})

    # account 2 propose current contract as candidate
    await this.fund.proposeCandidate(chunkNum, this.fund.address, {from: accounts[2]})

    # account 3 unsuccessfully challeng candidate
    assert(await this.fund.proposeCandidate.call(chunkNum, accounts[3], {from: accounts[3]}) == false, "account3 successfully challenged candidate")

    # wait till second subchunk
    await timeTravel(1 * DAY)

    # check candidate
    candidate = await this.fund.candidates.call(chunkNum - 1)
    assert.equal(candidate, this.fund.address, "candidate incorrect")
  )

  it("reject_first_proposal", () ->
    chunkNum = 1

    # account 1 and owner support proporal, account 3 rejects it
    await this.fund.voteOnCandidate(chunkNum, true, {from: accounts[1]})
    await this.fund.voteOnCandidate(chunkNum, true, {from: owner})
    await this.fund.voteOnCandidate(chunkNum, false, {from: accounts[3]})

    # wait till next chunk
    # the 10 is just to make sure it actually goes to the next chunk
    # instead of some weird border condition
    await timeTravel(2 * DAY + 10)

    # ensure vote can't be finalized
    assert((await this.fund.finalizeSuccessfulVote.call(chunkNum)) == false, "unsuccessful vote finalized")
  )

  it("make_second_proposal", () ->
    chunkNum = 2

    # account 1 propose account 1 as candidate
    # using accounts[1] here instead of creating a new BetokenFund
    # because I'm lazy
    await this.fund.proposeCandidate(chunkNum, accounts[1], {from: accounts[1]})

    # wait till second subchunk
    await timeTravel(1 * DAY)

    # check candidate
    candidate = await this.fund.candidates.call(chunkNum - 1)
    assert.equal(candidate, accounts[1], "candidate incorrect")
  )

  it("accept_second_proposal", () ->
    chunkNum = 2

    # account 3 and owner support proporal
    await this.fund.voteOnCandidate(chunkNum, true, {from: owner})
    await this.fund.voteOnCandidate(chunkNum, true, {from: accounts[3]})

    # wait till next chunk
    await timeTravel(2 * DAY)

    # finalize successful vote
    await this.fund.finalizeSuccessfulVote(chunkNum, {from: accounts[2]})

    # go to next cycle
    this.fund = await FUND(5, 0, owner)

    # check if next version is finalized
    assert(await this.fund.hasFinalizedNextVersion.call(), "next version not finalized")
    # check if the next version is accounts[1]
    assert.equal(await this.fund.nextVersion.call(), accounts[1], "next version incorrect")
  )

  it("migrate_to_next_version", () ->
    dai = await DAI(this.fund)

    # let account[3] withdraw their deposit
    await this.fund.withdrawDAI(bnToString(depositAmount * 0.75), {from: accounts[3]})

    # jump to end of intermission
    await timeTravel(3 * DAY + 10)

    # migrate
    await this.fund.migrateOwnedContractsToNextVersion({from: accounts[2]})
    await this.fund.transferAssetToNextVersion(dai.address, {from: accounts[1]})

    # check balances
    assert(BigNumber(await dai.balanceOf(accounts[1])).toNumber() >= depositAmount * 2.2, "didn't transfer assets to account[1]")

    # check BetokenProxy
    proxy = await BetokenProxy.deployed()
    assert.equal(await proxy.betokenFundAddress.call(), accounts[1], "BetokenFund address incorrect in BetokenProxy")
  )
)

contract("developer_initiated_upgrade", (accounts) ->
  owner = accounts[0]
  kroAmounts = [3 * PRECISION, 10 * PRECISION, 20 * PRECISION, 5 * PRECISION]
  depositAmount = 10 * PRECISION

  it("prep_work", () ->
    this.fund = await FUND(1, 0, owner) # Starts in Intermission phase
    dai = await DAI(this.fund)

    # register managers
    for i in [1..3]
      await this.fund.registerWithETH({from: accounts[i], value: await calcRegisterPayAmount(this.fund, kroAmounts[i], ETH_PRICE)})

    # deposit funds
    for i in [1..3]
      await dai.mint(accounts[i], bnToString(depositAmount), {from: owner}) # Mint DAI
      await dai.approve(this.fund.address, bnToString(depositAmount), {from: accounts[i]}) # Approve transfer
      await this.fund.depositDAI(bnToString(depositAmount), {from: accounts[i]}) # Deposit for account

    # move to the 4th cycle (due to the cooldown period after deployment)
    this.fund = await FUND(4, 0, owner)
  )

  it("initiate_upgrade", () ->
    await this.fund.developerInitiateUpgrade(accounts[1], {from: owner})
    assert.equal(await this.fund.nextVersion.call(), accounts[1], "next version not set")

    # next phase
    this.fund = await FUND(4, 1, owner)

    # check if upgrade voting is active
    assert(await this.fund.upgradeVotingActive.call(), "upgrade voting not active")

    # jump to the next cycle to finalize next version
    this.fund = await FUND(5, 0, owner)

    # ensure next version is finalized
    assert(await this.fund.hasFinalizedNextVersion.call(), "next version not finalized")
  )

  it("migrate_to_next_version", () ->
    dai = await DAI(this.fund)

    # let account[3] withdraw their deposit
    await this.fund.withdrawDAI(bnToString(depositAmount * 0.75), {from: accounts[3]})

    # jump to end of intermission
    await timeTravel(3 * DAY + 10)

    # migrate
    await this.fund.migrateOwnedContractsToNextVersion({from: accounts[2]})
    await this.fund.transferAssetToNextVersion(dai.address, {from: accounts[1]})

    # check balances
    assert(BigNumber(await dai.balanceOf(accounts[1])).toNumber() >= depositAmount * 2.2, "didn't transfer assets to account[1]")

    # check BetokenProxy
    proxy = await BetokenProxy.deployed()
    assert.equal(await proxy.betokenFundAddress.call(), accounts[1], "BetokenFund address incorrect in BetokenProxy")
  )
)

contract("community_overrides_developer_upgrade", (accounts) ->
  owner = accounts[0]
  kroAmounts = [3 * PRECISION, 10 * PRECISION, 20 * PRECISION, 5 * PRECISION]
  depositAmount = 10 * PRECISION

  it("prep_work", () ->
    this.fund = await FUND(1, 0, owner) # Starts in Intermission phase
    dai = await DAI(this.fund)

    # register managers
    for i in [1..3]
      await this.fund.registerWithETH({from: accounts[i], value: await calcRegisterPayAmount(this.fund, kroAmounts[i], ETH_PRICE)})

    # deposit funds
    for i in [1..3]
      await dai.mint(accounts[i], bnToString(depositAmount), {from: owner}) # Mint DAI
      await dai.approve(this.fund.address, bnToString(depositAmount), {from: accounts[i]}) # Approve transfer
      await this.fund.depositDAI(bnToString(depositAmount), {from: accounts[i]}) # Deposit for account

    # move to the 4th cycle (due to the cooldown period after deployment)
    this.fund = await FUND(4, 0, owner)
  )

  it("initiate_upgrade", () ->
    await this.fund.developerInitiateUpgrade(accounts[3], {from: owner})
    assert.equal(await this.fund.nextVersion.call(), accounts[3], "next version not set")

    # next phase
    this.fund = await FUND(4, 1, owner)

    # check if upgrade voting is active
    assert(await this.fund.upgradeVotingActive.call(), "upgrade voting not active")
  )

  it("make_first_proposal", () ->
    chunkNum = 1

    # wait till chunk 1
    await timeTravel(3 * DAY)

    # account 1 propose account 1 as candidate
    await this.fund.proposeCandidate(chunkNum, accounts[1], {from: accounts[1]})

    # account 2 propose current contract as candidate
    await this.fund.proposeCandidate(chunkNum, this.fund.address, {from: accounts[2]})

    # account 3 unsuccessfully challeng candidate
    assert(await this.fund.proposeCandidate.call(chunkNum, accounts[3], {from: accounts[3]}) == false, "account3 successfully challenged candidate")

    # wait till second subchunk
    await timeTravel(1 * DAY)

    # check candidate
    candidate = await this.fund.candidates.call(chunkNum - 1)
    assert.equal(candidate, this.fund.address, "candidate incorrect")
  )

  it("reject_first_proposal", () ->
    chunkNum = 1

    # account 1 and owner support proporal, account 3 rejects it
    await this.fund.voteOnCandidate(chunkNum, true, {from: accounts[1]})
    await this.fund.voteOnCandidate(chunkNum, true, {from: owner})
    await this.fund.voteOnCandidate(chunkNum, false, {from: accounts[3]})

    # wait till next chunk
    # the 10 is just to make sure it actually goes to the next chunk
    # instead of some weird border condition
    await timeTravel(2 * DAY + 10)

    # ensure vote can't be finalized
    assert((await this.fund.finalizeSuccessfulVote.call(chunkNum)) == false, "unsuccessful vote finalized")
  )

  it("make_second_proposal", () ->
    chunkNum = 2

    # account 1 propose account 1 as candidate
    # using accounts[1] here instead of creating a new BetokenFund
    # because I'm lazy
    await this.fund.proposeCandidate(chunkNum, accounts[1], {from: accounts[1]})

    # wait till second subchunk
    await timeTravel(1 * DAY)

    # check candidate
    candidate = await this.fund.candidates.call(chunkNum - 1)
    assert.equal(candidate, accounts[1], "candidate incorrect")
  )

  it("accept_second_proposal", () ->
    chunkNum = 2

    # account 3 and owner support proporal
    await this.fund.voteOnCandidate(chunkNum, true, {from: owner})
    await this.fund.voteOnCandidate(chunkNum, true, {from: accounts[3]})

    # wait till next chunk
    await timeTravel(2 * DAY)

    # finalize successful vote
    await this.fund.finalizeSuccessfulVote(chunkNum, {from: accounts[2]})

    # go to next cycle
    this.fund = await FUND(5, 0, owner)

    # check if next version is finalized
    assert(await this.fund.hasFinalizedNextVersion.call(), "next version not finalized")
    # check if the next version is accounts[1]
    assert.equal(await this.fund.nextVersion.call(), accounts[1], "next version incorrect")
  )

  it("migrate_to_next_version", () ->
    dai = await DAI(this.fund)

    # let account[3] withdraw their deposit
    await this.fund.withdrawDAI(bnToString(depositAmount * 0.75), {from: accounts[3]})

    # jump to end of intermission
    await timeTravel(3 * DAY + 10)

    # migrate
    await this.fund.migrateOwnedContractsToNextVersion({from: accounts[2]})
    await this.fund.transferAssetToNextVersion(dai.address, {from: accounts[1]})

    # check balances
    assert(BigNumber(await dai.balanceOf(accounts[1])).toNumber() >= depositAmount * 2.2, "didn't transfer assets to account[1]")

    # check BetokenProxy
    proxy = await BetokenProxy.deployed()
    assert.equal(await proxy.betokenFundAddress.call(), accounts[1], "BetokenFund address incorrect in BetokenProxy")
  )
)