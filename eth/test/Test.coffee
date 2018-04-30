BetokenFund = artifacts.require "BetokenFund"
ControlToken = artifacts.require "ControlToken"
ShareToken = artifacts.require "ShareToken"
TestKyberNetwork = artifacts.require "TestKyberNetwork"
TestToken = artifacts.require "TestToken"

ETH_TOKEN_ADDRESS = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
epsilon = 1e-15

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
  owner = accounts[0]

  it("start_cycle", () ->
    fund = await FUND(1, -1, owner)
    account = accounts[0]

    # start cycle
    await fund.nextPhase({from: owner})

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
    account = accounts[0]

    # mint DAI for KN
    await dai.mint(kn.address, 1e27, {from: owner, gasPrice: 0})

    # deposit ether
    amount = 1e18
    prevEtherBlnce = await web3.eth.getBalance(account)
    await fund.deposit({from: account, value: amount, gasPrice: 0})

    # check shares
    shareBlnce = await st.balanceOf.call(account)
    assert.equal(shareBlnce.toNumber(), amount * 600, "received share amount incorrect")

    # check fund balance
    fundBalance = await fund.totalFundsInDAI.call()
    assert.equal(fundBalance.toNumber(), amount * 600, "fund balance incorrect")

    # check user ether balance
    etherBlnce = await web3.eth.getBalance(account)
    assert.equal(prevEtherBlnce.sub(etherBlnce).toNumber(), amount, "ether balance increase incorrect")
  )

  it("deposit_dai", () ->
    fund = await BetokenFund.deployed()
    dai = await DAI(fund)
    st = await ST()
    account = accounts[1]

    # mint DAI for user
    amount = 1e18
    await dai.mint(account, amount, {from: owner})

    # deposit DAI
    fundBalance = await fund.totalFundsInDAI.call()
    prevDAIBlnce = await dai.balanceOf.call(account)
    await dai.approve(fund.address, amount, {from: account})
    await fund.depositToken(dai.address, amount, {from: account})
    await dai.approve(fund.address, 0, {from: account})

    # check shares
    shareBlnce = await st.balanceOf.call(account)
    assert.equal(shareBlnce.toNumber(), amount, "received share amount incorrect")

    # check fund balance
    newFundBalance = await fund.totalFundsInDAI.call()
    assert.equal(newFundBalance.sub(fundBalance).toNumber(), amount, "fund balance increase incorrect")

    # check dai balance
    daiBlnce = await await dai.balanceOf.call(account)
    assert.equal(prevDAIBlnce.sub(daiBlnce).toNumber(), amount, "DAI balance decrease incorrect")
  )

  it("withdraw_ether", () ->
    fund = await BetokenFund.deployed()
    st = await ST()
    account = accounts[0]

    # withdraw ether
    amount = 1e17
    prevShareBlnce = await st.balanceOf.call(account)
    prevFundBlnce = await fund.totalFundsInDAI.call()
    prevEtherBlnce = await web3.eth.getBalance(account)
    await fund.withdraw(amount, {from: account, gasPrice: 0})

    # check shares
    shareBlnce = await st.balanceOf.call(account)
    assert.equal(prevShareBlnce.sub(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = await fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.sub(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check ether balance
    etherBlnce = await web3.eth.getBalance(account)
    assert.equal(etherBlnce.sub(prevEtherBlnce).toNumber(), amount // 600, "ether balance increase incorrect")
  )

  it("withdraw_dai", () ->
    fund = await BetokenFund.deployed()
    dai = await DAI(fund)
    st = await ST()
    account = accounts[1]

    # withdraw dai
    amount = 1e17
    prevShareBlnce = await st.balanceOf.call(account)
    prevFundBlnce = await fund.totalFundsInDAI.call()
    prevDAIBlnce = await dai.balanceOf.call(account)
    await fund.withdrawToken(dai.address, amount, {from: account})

    # check shares
    shareBlnce = await st.balanceOf.call(account)
    assert.equal(prevShareBlnce.sub(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = await fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.sub(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check dai balance
    daiBlnce = await await dai.balanceOf.call(account)
    assert.equal(daiBlnce.sub(prevDAIBlnce).toNumber(), amount * (1 - 0.03), "DAI balance increase incorrect")
  )

  it("phase_0_to_1", () ->
    fund = await BetokenFund.deployed()
    await fund.nextPhase({from: owner})
  )

  it("buy_ether_and_sell", () ->
    fund = await BetokenFund.deployed()
    xr = await XR()
    account = accounts[1]

    prevKROBlnce = await xr.balanceOf.call(account)
    prevFundEtherBlnce = await web3.eth.getBalance(fund.address)

    # buy ether
    amount = 1e17
    await fund.createInvestment(ETH_TOKEN_ADDRESS, amount, {from: account, gasPrice: 0})

    # check KRO balance
    kroBlnce = await xr.balanceOf.call(account)
    assert.equal(prevKROBlnce.sub(kroBlnce).toNumber(), amount, "Kairo balance decrease incorrect")

    # check fund ether balance
    fundDAIBlnce = await fund.totalFundsInDAI.call()
    kroTotalSupply = await xr.totalSupply.call()
    fundEtherBlnce = await web3.eth.getBalance(fund.address)
    assert.equal(fundEtherBlnce.sub(prevFundEtherBlnce).toNumber(), fundDAIBlnce.div(kroTotalSupply).mul(amount).div(600).toNumber()//1, "ether balance increase incorrect")


    # sell ether
    await fund.sellInvestmentAsset(0, {from: account, gasPrice: 0})

    # check KRO balance
    kroBlnce = await xr.balanceOf.call(account)
    assert.equal(prevKROBlnce.sub(kroBlnce).toNumber() / amount < epsilon, true, "Kairo balance changed")

    # check fund ether balance
    fundEtherBlnce = await web3.eth.getBalance(fund.address)
    assert.equal(fundEtherBlnce.sub(prevFundEtherBlnce).toNumber() / amount < epsilon, true, "fund ether balance changed")
  )

  it("phase_1_to_2", () ->
    fund = await BetokenFund.deployed()
    await fund.nextPhase({from: owner})
  )

  it("redeem_commission", () ->
    fund = await BetokenFund.deployed()
    dai = await DAI(fund)
    account = accounts[0]

    prevDAIBlnce = await dai.balanceOf.call(account)

    # redeem commission
    await fund.redeemCommission({from: account})

    # check DAI balance
    daiBlnce = await dai.balanceOf.call(account)
    assert.equal(daiBlnce.sub(prevDAIBlnce).toNumber() > 0, true, "didn't receive commission")
  )

  it("redeem_commission_in_shares", () ->
    fund = await BetokenFund.deployed()
    st = await ST()
    account = accounts[1]

    prevShareBlnce = await st.balanceOf.call(account)

    # redeem commission
    await fund.redeemCommissionInShares({from: account})

    # check Share balance
    shareBlnce = await st.balanceOf.call(account)
    assert.equal(shareBlnce.sub(prevShareBlnce).toNumber() > 0, true, "didn't receive commission")
  )
)