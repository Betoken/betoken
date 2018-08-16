import "./body.html"
import "./body.css"
import "./tablesort.js"
import { Betoken, ETH_TOKEN_ADDRESS, NET_ID } from "../objects/betoken.js"
import Chart from "chart.js"
import BigNumber from "bignumber.js"

TOKENS = require("../objects/kn_token_symbols.json")

WRONG_NETWORK_ERR = "Please switch to Rinkeby Testnet in order to use Betoken Omen. You can currently view the fund's data, but cannot make any interactions."
SEND_TX_ERR = "There was an error during sending your transaction to the Ethereum blockchain. Please check that your inputs are valid and try again later."
INPUT_ERR = "There was an error in your input. Please fix it and try again."
NO_WEB3_ERR = "Betoken can only be used in a Web3 enabled browser. Please install <a target=\"_blank\" href=\"https://metamask.io/\">MetaMask</a> or switch to another browser that supports Web3. You can currently view the fund's data, but cannot make any interactions."
METAMASK_LOCKED_ERR = "Your browser seems to be Web3 enabled, but you need to unlock your account to interact with Betoken."

# Import web3
Web3 = require "web3"
web3 = window.web3
hasWeb3 = false
if web3?
  web3 = new Web3(web3.currentProvider)
  hasWeb3 = true
else
  web3 = new Web3(new Web3.providers.HttpProvider("https://rinkeby.infura.io/v3/3057a4979e92452bae6afaabed67a724"))

# Fund object
BETOKEN_ADDR = "0x5910d5abd4d5fd58b39957664cd9735cbfe42bf0"
DEPLOYED_BLOCK = 2721413
betoken = new Betoken(BETOKEN_ADDR)


# Session data
userAddress = new ReactiveVar("0x0")
kairoBalance = new ReactiveVar(BigNumber(0))
kairoTotalSupply = new ReactiveVar(BigNumber(0))
sharesBalance = new ReactiveVar(BigNumber(0))
sharesTotalSupply = new ReactiveVar(BigNumber(0))

cyclePhase = new ReactiveVar(0)
startTimeOfCyclePhase = new ReactiveVar(0)
phaseLengths = new ReactiveVar([])
totalFunds = new ReactiveVar(BigNumber(0))
investmentList = new ReactiveVar([])
cycleNumber = new ReactiveVar(0)
commissionRate = new ReactiveVar(BigNumber(0))
assetFeeRate = new ReactiveVar(BigNumber(0))
paused = new ReactiveVar(false)
allowEmergencyWithdraw = new ReactiveVar(false)
lastCommissionRedemption = new ReactiveVar(0)
cycleTotalCommission = new ReactiveVar(BigNumber(0))


# Displayed variables
kairoAddr = new ReactiveVar("")
sharesAddr = new ReactiveVar("")
kyberAddr = new ReactiveVar("")
daiAddr = new ReactiveVar("")
tokenFactoryAddr = new ReactiveVar("")

displayedInvestmentBalance = new ReactiveVar(BigNumber(0))
displayedInvestmentUnit = new ReactiveVar("DAI")
displayedKairoBalance = new ReactiveVar(BigNumber(0))
displayedKairoUnit = new ReactiveVar("KRO")

countdownDay = new ReactiveVar(0)
countdownHour = new ReactiveVar(0)
countdownMin = new ReactiveVar(0)
countdownSec = new ReactiveVar(0)
showCountdown = new ReactiveVar(true)

transactionHash = new ReactiveVar("")
networkName = new ReactiveVar("")
networkPrefix = new ReactiveVar("")

chart = null
prevROI = new ReactiveVar(BigNumber(0))
avgROI = new ReactiveVar(BigNumber(0))
prevCommission = new ReactiveVar(BigNumber(0))
historicalTotalCommission = new ReactiveVar(BigNumber(0))

transactionHistory = new ReactiveVar([])

errorMessage = new ReactiveVar("")
successMessage = new ReactiveVar("")
kairoRanking = new ReactiveVar([])
wrongNetwork = new ReactiveVar(false)

isLoadingRanking = new ReactiveVar(true)
isLoadingInvestments = new ReactiveVar(true)
isLoadingRecords = new ReactiveVar(true)

tokenPrices = new ReactiveVar([])
tokenAddresses = new ReactiveVar([])

fundValue = new ReactiveVar(BigNumber(0))


showTransaction = (_txHash) ->
  transactionHash.set(_txHash)
  $("#transaction_sent_modal").modal("show")
  return


showError = (_msg) ->
  errorMessage.set(_msg)
  $("#error_modal").modal("show")


showSuccess = (_msg) ->
  successMessage.set(_msg)
  $("#success_modal").modal("show")


copyTextToClipboard = (text) ->
  textArea = document.createElement("textarea")

  # Place in top-left corner of screen regardless of scroll position.
  textArea.style.position = "fixed"
  textArea.style.top = 0
  textArea.style.left = 0

  # Ensure it has a small width and height. Setting to 1px / 1em
  # doesn't work as this gives a negative w/h on some browsers.
  textArea.style.width = "2em"
  textArea.style.height = "2em"

  # We don't need padding, reducing the size if it does flash render.
  textArea.style.padding = 0

  # Clean up any borders.
  textArea.style.border = "none"
  textArea.style.outline = "none"
  textArea.style.boxShadow = "none"

  # Avoid flash of white box if rendered for any reason.
  textArea.style.background = "transparent"

  textArea.value = text

  document.body.appendChild(textArea)

  textArea.select()

  try
    successful = document.execCommand("copy")
    if successful
      showSuccess("Copied #{text} to clipboard")
    else
      showError("Oops, unable to copy")
  catch err
    showError("Oops, unable to copy")

  document.body.removeChild(textArea)
  return


clock = () ->
  setInterval(
    () ->
      now = Math.floor(new Date().getTime() / 1000)
      target = startTimeOfCyclePhase.get() + phaseLengths.get()[cyclePhase.get()]
      distance = target - now

      if distance > 0
        showCountdown.set(true)
        days = Math.floor(distance / (60 * 60 * 24))
        hours = Math.floor((distance % (60 * 60 * 24)) / (60 * 60))
        minutes = Math.floor((distance % (60 * 60)) / 60)
        seconds = Math.floor(distance % 60)

        countdownDay.set(days)
        countdownHour.set(hours)
        countdownMin.set(minutes)
        countdownSec.set(seconds)
      else
        showCountdown.set(false)
  , 1000)


drawChart = () ->
  chart = new Chart($("#ROIChart"),
    type: "line",
    data:
      datasets: [
        label: "ROI Per Cycle"
        backgroundColor: "#b9eee1"
        borderColor: "#1fdaa6"
        data: []
      ]
    ,
    options:
      scales:
        xAxes: [
          type: "linear"
          position: "bottom"
          scaleLabel:
            display: true
            labelString: "Investment Cycle"
          ticks:
            stepSize: 1
          gridLines:
            display: false
        ]
        yAxes: [
          type: "linear"
          position: "left"
          scaleLabel:
            display: true
            labelString: "Percent"
          ticks:
            beginAtZero: true
          gridLines:
            display: false
        ]
  )


assetSymbolToPrice = (_symbol) ->
  return tokenPrices.get()[TOKENS.indexOf(_symbol)]


assetAddressToSymbol = (_addr) ->
  return TOKENS[tokenAddresses.get().indexOf(_addr)]


assetSymbolToAddress = (_symbol) ->
  return tokenAddresses.get()[TOKENS.indexOf(_symbol)]


loadFundMetadata = () ->
  await Promise.all([
    # get params
    phaseLengths.set((await betoken.getPrimitiveVar("getPhaseLengths")).map((x) -> +x)),
    commissionRate.set(BigNumber(await betoken.getPrimitiveVar("commissionRate")).div(1e18)),
    assetFeeRate.set(BigNumber(await betoken.getPrimitiveVar("assetFeeRate"))),
    
    # Get contract addresses
    kairoAddr.set(betoken.addrs.controlToken),
    sharesAddr.set(betoken.addrs.shareToken),
    kyberAddr.set(await betoken.getPrimitiveVar("kyberAddr")),
    daiAddr.set(await betoken.getPrimitiveVar("daiAddr")),
    tokenFactoryAddr.set(await betoken.addrs.tokenFactory),
    tokenAddresses.set(await Promise.all(TOKENS.map(
      (_token) ->
        return await betoken.tokenSymbolToAddress(_token)
    )))
  ])


loadFundData = () ->
  receivedROICount = 0
    
  ###
  # Get fund data
  ###
  await Promise.all([
    cycleNumber.set(+await betoken.getPrimitiveVar("cycleNumber")),
    cyclePhase.set(+await betoken.getPrimitiveVar("cyclePhase")),
    startTimeOfCyclePhase.set(+await betoken.getPrimitiveVar("startTimeOfCyclePhase")),
    paused.set(await betoken.getPrimitiveVar("paused")),
    allowEmergencyWithdraw.set(await betoken.getPrimitiveVar("allowEmergencyWithdraw")),
    sharesTotalSupply.set(BigNumber(await betoken.getShareTotalSupply())),
    totalFunds.set(BigNumber(await betoken.getPrimitiveVar("totalFundsInDAI"))),
    kairoTotalSupply.set(BigNumber(await betoken.getKairoTotalSupply()))
  ])
  

  # Get statistics
  prevROI.set(BigNumber(0))
  avgROI.set(BigNumber(0))
  historicalTotalCommission.set(BigNumber(0))
  await Promise.all([
    cycleTotalCommission.set(BigNumber(await betoken.getMappingOrArrayItem("totalCommissionOfCycle", cycleNumber.get()))),
    prevCommission.set(BigNumber(await betoken.getMappingOrArrayItem("totalCommissionOfCycle", cycleNumber.get() - 1)))
  ])

  # Get commission and draw ROI chart
  chart.data.datasets[0].data = []
  chart.update()

  await Promise.all([
    betoken.contracts.betokenFund.getPastEvents("TotalCommissionPaid",
      fromBlock: DEPLOYED_BLOCK
    ).then(
      (events) ->
        for _event in events
          commission = BigNumber(_event.returnValues._totalCommissionInDAI)
          # Update total commission
          historicalTotalCommission.set(historicalTotalCommission.get().add(commission))
    ),
    betoken.contracts.betokenFund.getPastEvents("ROI",
      fromBlock: DEPLOYED_BLOCK
    ).then(
      (events) ->
        for _event in events
          data = _event.returnValues
          ROI = BigNumber(data._afterTotalFunds).minus(data._beforeTotalFunds).div(data._afterTotalFunds).mul(100)

          # Update chart data
          chart.data.datasets[0].data.push(
            x: data._cycleNumber
            y: ROI.toString()
          )
          chart.update()

          # Update previous cycle ROI
          if +data._cycleNumber == cycleNumber.get() || +data._cycleNumber == cycleNumber.get() - 1
            prevROI.set(ROI)

          # Update average ROI
          receivedROICount += 1
          avgROI.set(avgROI.get().add(ROI.minus(avgROI.get()).div(receivedROICount)))
    )
  ])
 
  return


loadUserData = () ->
  if hasWeb3
    # Get user address
    userAddr = (await web3.eth.getAccounts())[0]
    web3.eth.defaultAccount = userAddr
    if userAddr?
      userAddress.set(userAddr)

      # Get shares balance
      sharesBalance.set(BigNumber(await betoken.getShareBalance(userAddr)))
      if !sharesTotalSupply.get().isZero()
        displayedInvestmentBalance.set(sharesBalance.get().div(sharesTotalSupply.get()).mul(totalFunds.get()).div(1e18))

      # Get user's Kairo balance
      kairoBalance.set(BigNumber(await betoken.getKairoBalance(userAddr)))
      displayedKairoBalance.set(kairoBalance.get().div(1e18))

      # Get last commission redemption cycle number
      lastCommissionRedemption.set(+await betoken.getMappingOrArrayItem("lastCommissionRedemption", userAddr))

      # Get deposit and withdraw history
      isLoadingRecords.set(true)
      transactionHistory.set([])
      getDepositWithdrawHistory = (_type) ->
        events = await betoken.contracts.betokenFund.getPastEvents(_type,
          fromBlock: DEPLOYED_BLOCK
          filter: {_sender: userAddr}
        )
        for event in events
          data = event.returnValues
          entry =
            type: _type
            timestamp: new Date(+data._timestamp * 1e3).toString()
            token: await betoken.getTokenSymbol(data._tokenAddress)
            amount: BigNumber(data._tokenAmount).div(10**(+await betoken.getTokenDecimals(data._tokenAddress))).toFormat(4)
          tmp = transactionHistory.get()
          tmp.push(entry)
          transactionHistory.set(tmp)

      # Get token transfer history
      getTransferHistory = (token, isIn) ->
        tokenContract = switch token
          when "KRO" then betoken.contracts.controlToken
          when "BTKS" then betoken.contracts.shareToken
          else null
        events = await tokenContract.getPastEvents("Transfer", {
          fromBlock: DEPLOYED_BLOCK
          filter: if isIn then { to: userAddr } else { from: userAddr }
        })
        for _event in events
          if not _event?
            continue
          data = _event.returnValues
          if (isIn && data._to != userAddr) || (!isIn && data._from != userAddr)
            continue

          entry =
            type: "Transfer " + if isIn then "In" else "Out"
            token: token
            amount: BigNumber(data._amount).div(1e18).toFormat(4)
            timestamp: new Date((await web3.eth.getBlock(_event.blockNumber)).timestamp * 1e3).toString()
          tmp = transactionHistory.get()
          tmp.push(entry)
          transactionHistory.set(tmp)

      await Promise.all([
        getDepositWithdrawHistory("Deposit"),
        getDepositWithdrawHistory("Withdraw"),
        getTransferHistory("KRO", true),
        getTransferHistory("KRO", false),
        getTransferHistory("BTKS", true),
        getTransferHistory("BTKS", false)
      ])
      isLoadingRecords.set(false)

      await loadDecisions()


loadTokenPrices = () ->
  tokenPrices.set(await Promise.all(TOKENS.map(
    (_token) ->
      return BigNumber(await betoken.getTokenPrice(_token)).div(1e18)
  )))


loadDecisions = () ->
  # Get list of user's investments
  isLoadingInvestments.set(true)
  investments = await betoken.getInvestments(userAddress.get())
  if investments.length != 0
    handleProposal = (id) ->
      betoken.getTokenSymbol(investments[id].tokenAddress).then(
        (_symbol) ->
          investments[id].id = id
          investments[id].tokenSymbol = _symbol
          investments[id].investment = BigNumber(investments[id].stake).div(kairoTotalSupply.get()).mul(totalFunds.get()).div(1e18).toFormat(4)
          investments[id].stake = BigNumber(investments[id].stake).div(1e18).toFormat(4)
          investments[id].sellPrice = if investments[id].isSold then BigNumber(investments[id].sellPrice) else assetSymbolToPrice(_symbol).mul(1e18)
          investments[id].ROI = BigNumber(investments[id].sellPrice).sub(investments[id].buyPrice).div(investments[id].buyPrice).mul(100).toFormat(4)
          investments[id].kroChange = BigNumber(investments[id].ROI).mul(investments[id].stake).div(100).toFormat(4)
      )
    handleAllProposals = (handleProposal(i) for i in [0..investments.length-1])
    await Promise.all(handleAllProposals)
    investmentList.set(investments)
  isLoadingInvestments.set(false)


loadRanking = () ->
  # activate loader
  isLoadingRanking.set(true)

  # load NewUser events to get list of users
  events = await betoken.contracts.betokenFund.getPastEvents("NewUser",
    fromBlock: DEPLOYED_BLOCK
  )

  # fetch addresses
  addresses = events.map((_event) -> _event.returnValues._user)
  addresses = Array.from(new Set(addresses)) # remove duplicates

  # fetch KRO balances
  ranking = await Promise.all(addresses.map(
    (_addr) ->
      stake = BigNumber(0)
      return betoken.getInvestments(_addr).then(
        (investments) ->
          addStake = (i) ->
            if !i.isSold
              currentStakeValue = assetSymbolToPrice(assetAddressToSymbol(i.tokenAddress)).mul(1e18).sub(i.buyPrice).div(i.buyPrice).mul(i.stake).add(i.stake)
              stake = stake.add(currentStakeValue)
          return Promise.all(addStake(i) for i in investments)
      ).then(
        () ->
          return {
            rank: 0
            address: _addr
            kairoBalance: BigNumber(await betoken.getKairoBalance(_addr)).add(stake).div(1e18).toFixed(18)
          }
      )
  ))

  # sort entries
  ranking.sort((a, b) -> BigNumber(b.kairoBalance).sub(a.kairoBalance).toNumber())

  # give ranks
  ranking = ranking.map(
    (_entry, _id) ->
      _entry.rank = _id + 1
      return _entry
  )

  # display ranking
  kairoRanking.set(ranking)

  # deactivate loader
  isLoadingRanking.set(false)


loadStats = () ->
  _fundValue = BigNumber(0)
  getTokenValue = (_token) ->
      balance = BigNumber(await betoken.getTokenBalance(assetSymbolToAddress(_token), betoken.addrs.betokenFund))
          .div(BigNumber(10).toPower(await betoken.getTokenDecimals(assetSymbolToAddress(_token))))
      value = balance.mul(assetSymbolToPrice(_token))
      _fundValue = _fundValue.add(value)
  await Promise.all((getTokenValue(t) for t in TOKENS))
  fundDAIBalance = BigNumber(await betoken.getTokenBalance(daiAddr.get(), betoken.addrs.betokenFund))
  _fundValue = _fundValue.add(fundDAIBalance.div(1e18))
  fundValue.set(_fundValue)


loadAllData = () ->
  await loadFundMetadata()
  await loadFundData()
  await loadTokenPrices()
  await loadUserData()
  await loadRanking()
  await loadStats()


loadDynamicData = () ->
  await loadFundData()
  await loadTokenPrices()
  await loadUserData()
  await loadRanking()
  await loadStats()


$("document").ready(() ->
  $("table").tablesort()
  $('a.item').tab()
  drawChart()

  if web3?
    clock()

    netID = await web3.eth.net.getId()
    if netID != NET_ID
      wrongNetwork.set(true)
      showError(WRONG_NETWORK_ERR)
      web3 = new Web3(new Web3.providers.HttpProvider("https://rinkeby.infura.io/v3/3057a4979e92452bae6afaabed67a724"))
    else
      if !hasWeb3
        showError(NO_WEB3_ERR)
      else if (await web3.eth.getAccounts()).length == 0
        showError(METAMASK_LOCKED_ERR)
    
    # Get Network ID
    netID = await web3.eth.net.getId()
    switch netID
      when 1
        net = "Main Ethereum Network"
        pre = ""
      when 3
        net = "Ropsten Testnet"
        pre = "ropsten."
      when 4
        net = "Rinkeby Testnet"
        pre = "rinkeby."
      when 42
        net = "Kovan Testnet"
        pre = "kovan."
      else
        net = "Unknown Network"
        pre = ""
    networkName.set(net)
    networkPrefix.set(pre)

    # Initialize Betoken object and then load data
    betoken.init().then(loadAllData).then(
      () ->
        # refresh every 2 minutes
        setInterval(loadDynamicData, 2 * 60 * 1000)
    )
)


Template.body.helpers(
  transaction_hash: () -> transactionHash.get()
  network_prefix: () -> networkPrefix.get()
  error_msg: () -> errorMessage.get()
  success_msg: () -> successMessage.get()
)


Template.body.events(
  "click .copyable": (event) ->
    copyTextToClipboard(event.target.innerText)
)


Template.top_bar.helpers(
  show_countdown: () -> showCountdown.get()
  paused: () -> paused.get()
  allow_emergency_withdraw: () -> if allowEmergencyWithdraw.get() then "" else "disabled"
  betoken_addr: () -> BETOKEN_ADDR
  kairo_addr: () -> kairoAddr.get()
  shares_addr: () -> sharesAddr.get()
  kyber_addr: () -> kyberAddr.get()
  dai_addr: () -> daiAddr.get()
  token_factory_addr: () -> tokenFactoryAddr.get()
  network_prefix: () -> networkPrefix.get()
  network_name: () -> networkName.get()
  need_web3: () -> if (userAddress.get() != "0x0" && hasWeb3 && !wrongNetwork.get()) then "" else "disabled"
)


Template.top_bar.events(
  "click .next_phase": (event) ->
    try
      betoken.nextPhase(showTransaction, loadDynamicData)
    catch error
      console.log error

  "click .emergency_withdraw": (event) ->
    betoken.emergencyWithdraw(showTransaction, loadUserData)

  "click .info_button": (event) ->
    $("#contract_info_modal").modal("show")
)


Template.countdown_timer.helpers(
  day: () -> countdownDay.get()
  hour: () -> countdownHour.get()
  minute: () -> countdownMin.get()
  second: () -> countdownSec.get()
  phase: () ->
    switch cyclePhase.get()
      when 0
        "Deposit & Withdraw"
      when 1
        "Manage Investments"
      when 2
        "Redeem Commission"
)


Template.sidebar.helpers(
  user_address: () -> userAddress.get()
  user_balance: () -> displayedInvestmentBalance.get().toFormat(18)
  balance_unit: () -> displayedInvestmentUnit.get()
  user_kairo_balance: () -> displayedKairoBalance.get().toFormat(18)
  kairo_unit: () -> displayedKairoUnit.get()
  can_redeem_commission: () -> cyclePhase.get() == 2 && lastCommissionRedemption.get() < cycleNumber.get()
  expected_commission: () ->
    if kairoTotalSupply.get().greaterThan(0)
      if cyclePhase.get() == 2
        # Actual commission that will be redeemed
        return kairoBalance.get().div(kairoTotalSupply.get()).mul(cycleTotalCommission.get()).div(1e18).toFormat(18)
      # Expected commission based on previous average ROI
      roi = if avgROI.get().gt(0) then avgROI.get() else BigNumber(0)
      return kairoBalance.get().div(kairoTotalSupply.get()).mul(totalFunds.get().div(1e18)).mul(roi.div(100).mul(commissionRate.get()).add(assetFeeRate.get().div(1e18))).toFormat(18)
    return BigNumber(0).toFormat(18)
)


Template.sidebar.events(
  "click .kairo_unit_switch": (event) ->
    if event.target.checked
      #Display proportion
      if !kairoTotalSupply.get().isZero()
        displayedKairoBalance.set(kairoBalance.get().div(kairoTotalSupply.get()).times("100"))
      displayedKairoUnit.set("%")
    else
      #Display Kairo
      displayedKairoBalance.set(BigNumber(kairoBalance.get().div(1e18)))
      displayedKairoUnit.set("KRO")

  "click .balance_unit_switch": (event) ->
    if event.target.checked
      #Display BTKS
      displayedInvestmentBalance.set(sharesBalance.get().div(1e18))
      displayedInvestmentUnit.set("BTKS")
    else
      #Display DAI
      if !sharesTotalSupply.get().isZero()
        displayedInvestmentBalance.set(sharesBalance.get().div(sharesTotalSupply.get()).mul(totalFunds.get()).div(1e18))
      displayedInvestmentUnit.set("DAI")

  "click .redeem_commission": (event) ->
    betoken.redeemCommission(showTransaction, loadUserData)

  "click .redeem_commission_in_shares": (event) ->
    betoken.redeemCommissionInShares(showTransaction, loadDynamicData)
)


Template.transact_box.onCreated(
  () ->
    Template.instance().depositInputHasError = new ReactiveVar(false)
    Template.instance().withdrawInputHasError = new ReactiveVar(false)
    Template.instance().sendTokenAmountInputHasError = new ReactiveVar(false)
    Template.instance().sendTokenRecipientInputHasError = new ReactiveVar(false)
)


Template.transact_box.helpers({
  is_disabled: () ->
    if cyclePhase.get() != 0
      "disabled"

  has_error: (input_id) ->
    hasError = false
    switch input_id
      when 0
        hasError = Template.instance().depositInputHasError.get()
      when 1
        hasError = Template.instance().withdrawInputHasError.get()
      when 2
        hasError = Template.instance().sendTokenAmountInputHasError.get()
      when 3
        hasError = Template.instance().sendTokenRecipientInputHasError.get()

    if hasError
      "error"

  transaction_history: () -> transactionHistory.get()

  tokens: () -> TOKENS

  need_web3: () -> if (userAddress.get() != "0x0" && hasWeb3 && !wrongNetwork.get()) then "" else "disabled"

  is_loading: () -> isLoadingRecords.get()
})


Template.transact_box.events({
  "click .deposit_button": (event) ->
    try
      Template.instance().depositInputHasError.set(false)
      amount = BigNumber($("#deposit_input")[0].value)
      tokenSymbol = $("#deposit_token_type")[0].value

      if !amount.gt(0)
        Template.instance().depositInputHasError.set(true)
        return

      tokenAddr = await betoken.tokenSymbolToAddress(tokenSymbol)
      betoken.depositToken(tokenAddr, amount, showTransaction, loadDynamicData)
    catch
      Template.instance().depositInputHasError.set(true)

  "click .withdraw_button": (event) ->
    try
      Template.instance().withdrawInputHasError.set(false)
      amount = BigNumber($("#withdraw_input")[0].value)
      tokenSymbol = $("#withdraw_token_type")[0].value

      if !amount.greaterThan(0)
        Template.instance().withdrawInputHasError.set(true)
        return

      tokenAddr = await betoken.tokenSymbolToAddress(tokenSymbol)
      betoken.withdrawToken(tokenAddr, amount, showTransaction, loadDynamicData)
    catch error
      Template.instance().withdrawInputHasError.set(true)

  "click .token_send_button": (event) ->
    try
      Template.instance().sendTokenAmountInputHasError.set(false)
      Template.instance().sendTokenRecipientInputHasError.set(false)

      amount = BigNumber(web3.utils.toWei($("#send_token_amount_input")[0].value))
      toAddress = $("#send_token_recipient_input")[0].value
      tokenType = $("#send_token_type")[0].value

      if !amount.greaterThan(0)
        Template.instance().sendTokenAmountInputHasError.set(true)
        return

      if !web3.utils.isAddress(toAddress)
        Template.instance().sendTokenRecipientInputHasError.set(true)
        return

      if tokenType == "KRO"
        if amount.greaterThan(kairoBalance.get())
          Template.instance().sendTokenAmountInputHasError.set(true)
          return
        betoken.sendKairo(toAddress, amount, showTransaction, loadUserData)
      else if tokenType == "BTKS"
        if amount.greaterThan(sharesBalance.get())
          Template.instance().sendTokenAmountInputHasError.set(true)
          return
        betoken.sendShares(toAddress, amount, showTransaction, loadUserData)
    catch
      Template.instance().sendTokenAmountInputHasError.set(true)
})


Template.stats_tab.helpers({
  cycle_length: () ->
    if phaseLengths.get().length > 0
      BigNumber(phaseLengths.get().reduce((t, n) -> t+n)).div(24 * 60 * 60).toDigits(3)
  total_funds: () -> totalFunds.get().div(1e18).toFormat(2)
  prev_roi: () -> prevROI.get().toFormat(2)
  avg_roi: () -> avgROI.get().toFormat(2)
  prev_commission: () -> prevCommission.get().div(1e18).toFormat(2)
  historical_commission: () -> historicalTotalCommission.get().div(1e18).toFormat(2)
  fund_value: () -> fundValue.get().toFormat(2)
  cycle_roi: () -> fundValue.get().sub(totalFunds.get().div(1e18)).div(totalFunds.get().div(1e18)).mul(100).toFormat(4)
})


Template.decisions_tab.helpers({
  investment_list: () -> investmentList.get()
  wei_to_eth: (_weis) -> BigNumber(_weis).div(1e18).toFormat(4)
  new_investment_is_disabled: () ->
    if cyclePhase.get() == 1 then "" else "disabled"
  tokens: () -> TOKENS
  need_web3: () -> if (userAddress.get() != "0x0" && hasWeb3 && !wrongNetwork.get()) then "" else "disabled"
  is_loading: () -> isLoadingInvestments.get()
})


Template.decisions_tab.events({
  "click .sell_investment": (event) ->
    id = this.id
    if cyclePhase.get() == 1
      betoken.sellAsset(id, showTransaction, loadDynamicData)

  "click .new_investment": (event) ->
    $("#new_investment_modal").modal({
      onApprove: (e) ->
        try
          tokenSymbol = $("#invest_token_type")[0].value
          address = await betoken.tokenSymbolToAddress(tokenSymbol)

          kairoAmountInWeis = BigNumber($("#stake_input_new")[0].value).times("1e18")
          checkKairoAmountError(kairoAmountInWeis)

          betoken.createInvestment(address, kairoAmountInWeis, showTransaction, loadUserData)
        catch error
          showError(error.toString() || INPUT_ERR)
    }).modal("show")

  "keyup .prompt": (event) ->
    filterTable(event, "decision_table")

  "click .refresh": (event) ->
    await loadTokenPrices()
    await loadDecisions()
})


checkKairoAmountError = (kairoAmountInWeis) ->
  if !kairoAmountInWeis.greaterThan(0)
    throw new Error("Stake amount should be positive.")
  if kairoAmountInWeis.greaterThan(kairoBalance.get())
    throw new Error("You can't stake more Kairos than you have!")

Template.ranking_tab.helpers({
  kairo_ranking: () ->  kairoRanking.get()
  is_loading: () -> isLoadingRanking.get()
  user_rank: () ->
    for entry in kairoRanking.get()
      if entry.address == userAddress.get()
        return entry.rank
    return "N/A"
  user_value: () ->
    for entry in kairoRanking.get()
      if entry.address == userAddress.get()
        return BigNumber(entry.kairoBalance).toFixed(4)
    return "N/A"
})

Template.ranking_tab.events({
  "keyup .prompt": (event) ->
    filterTable(event, "ranking_table")

  "click .goto_my_rank": (event) ->
    for entry in kairoRanking.get()
      if entry.address == userAddress.get()
        $("#ranking_table tr")[entry.rank - 1].scrollIntoView(true)

  "click .refresh": (event) ->
    await loadTokenPrices()
    await loadRanking()
})

filterTable = (event, tableID) ->
  searchInput = event.target.value.toLowerCase()
  entries = $("##{tableID} tr")
  for entry in entries
    searchTarget = entry.children[1]
    if searchTarget
      if searchTarget.innerText.toLowerCase().indexOf(searchInput) > -1
        entry.style.display = ""
      else
        entry.style.display = "none"