BetokenFund = artifacts.require "BetokenFund"
ControlToken = artifacts.require "ControlToken"
ShareToken = artifacts.require "ShareToken"
TestKyberNetwork = artifacts.require "TestKyberNetwork"
TestToken = artifacts.require "TestToken"

FUND = (cycle, phase, account) ->
  fund = await BetokenFund.deployed()
  if cycle-1 > 0
    for i in [1..cycle-1]
      for j in [0..2]
        await fund.nextPhase({from: account})
  if phase >= 0
    for i in [0..phase]
      await fund.nextPhase({from: account})
  return fund

DAI = (fund) ->
  daiAddr = await fund.daiAddr.call()
  return TK(daiAddr)

KN = (fund) ->
  kyberAddr = await fund.kyberAddr.call()
  return TestKyberNetwork.at(kyberAddr)

TK = (addr) -> TestToken.at(addr)

ST = () -> await ShareToken.deployed()

XR = () -> await ControlToken.deployed()

contract("first_cycle", (accounts) ->
  it("start_cycle", () ->
    fund = await FUND(1, -1, accounts[0])

    # start cycle
    await fund.nextPhase({from: accounts[0]})

    # check phase
    cyclePhase = +await fund.cyclePhase.call()
    assert.equal(cyclePhase, 0, "cycle phase didn't change after cycle start")

    # check cycle number
    cycleNumber = +await fund.cycleNumber.call()
    assert.equal(cycleNumber, 1, "cycle number didn't change after cycle start")
  )

  it("deposit_ether", () ->
    fund = await BetokenFund.deployed()
    dai = await DAI(fund)
    kn = await KN(fund)
    st = await ST()

    # mint DAI for KN
    await dai.mint(kn.address, 1e27, {from: accounts[0], gasPrice: 0})

    # deposit ether
    amount = 1e18
    prevEtherBlnce = await web3.eth.getBalance(accounts[0])
    await fund.deposit({from: accounts[0], value: amount, gasPrice: 0})

    # check shares
    shareBlnce = await st.balanceOf.call(accounts[0])
    assert.equal(shareBlnce.toNumber(), amount * 600, "received share amount incorrect")

    # check fund balance
    fundBalance = await fund.totalFundsInDAI.call()
    assert.equal(fundBalance.toNumber(), amount * 600, "fund balance incorrect")

    # check user ether balance
    etherBlnce = await web3.eth.getBalance(accounts[0])
    assert.equal(prevEtherBlnce.sub(etherBlnce).toNumber(), amount, "ether balance increase incorrect")
  )

  it("deposit_dai", () ->
    fund = await BetokenFund.deployed()
    dai = await DAI(fund)
    st = await ST()

    # mint DAI for user
    amount = 2e18
    await dai.mint(accounts[1], amount, {from: accounts[0]})

    # deposit DAI
    fundBalance = await fund.totalFundsInDAI.call()
    prevDAIBlnce = await dai.balanceOf.call(accounts[1])
    await dai.approve(fund.address, amount, {from: accounts[1]})
    await fund.depositToken(dai.address, amount, {from: accounts[1]})
    await dai.approve(fund.address, 0, {from: accounts[1]})

    # check shares
    shareBlnce = await st.balanceOf.call(accounts[1])
    assert.equal(shareBlnce.toNumber(), amount, "received share amount incorrect")

    # check fund balance
    newFundBalance = await fund.totalFundsInDAI.call()
    assert.equal(newFundBalance.sub(fundBalance).toNumber(), amount, "fund balance increase incorrect")

    # check dai balance
    daiBlnce = await await dai.balanceOf.call(accounts[1])
    assert.equal(prevDAIBlnce.sub(daiBlnce).toNumber(), amount, "DAI balance decrease incorrect")
  )

  it("withdraw_ether", () ->
    fund = await BetokenFund.deployed()
    dai = await DAI(fund)
    st = await ST()

    # withdraw ether
    amount = 1e17
    prevShareBlnce = await st.balanceOf.call(accounts[0])
    prevFundBlnce = await fund.totalFundsInDAI.call()
    prevEtherBlnce = await web3.eth.getBalance(accounts[0])
    await fund.withdraw(amount, {from: accounts[0], gasPrice: 0})

    # check shares
    shareBlnce = await st.balanceOf.call(accounts[0])
    assert.equal(prevShareBlnce.sub(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = await fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.sub(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check ether balance
    etherBlnce = await web3.eth.getBalance(accounts[0])
    assert.equal(etherBlnce.sub(prevEtherBlnce).toNumber(), amount // 600, "ether balance increase incorrect")
  )

  it("withdraw_dai", () ->
    fund = await BetokenFund.deployed()
    dai = await DAI(fund)
    st = await ST()

    # withdraw dai
    amount = 1e17
    prevShareBlnce = await st.balanceOf.call(accounts[1])
    prevFundBlnce = await fund.totalFundsInDAI.call()
    prevDAIBlnce = await dai.balanceOf.call(accounts[1])
    await fund.withdrawToken(dai.address, amount, {from: accounts[1]})

    # check shares
    shareBlnce = await st.balanceOf.call(accounts[1])
    assert.equal(prevShareBlnce.sub(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = await fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.sub(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check dai balance
    daiBlnce = await await dai.balanceOf.call(accounts[1])
    assert.equal(daiBlnce.sub(prevDAIBlnce).toNumber(), amount * (1 - 0.03), "DAI balance increase incorrect")
  )
)