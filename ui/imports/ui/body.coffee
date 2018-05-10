import "./body.html"
import "./body.css"
import "./tablesort.js"
import { Betoken } from "../objects/betoken.js"
import Chart from "chart.js"
import BigNumber from "bignumber.js"

SEND_TX_ERR = "There was an error during sending your transaction to the Ethereum blockchain. Please check that your inputs are valid and try again later."
INPUT_ERR = "There was an error in your input. Please fix it and try again."
STAKE_BOTH_SIDES_ERR = "You have already staked on the opposite side of this proposal! If you want to change your mind, you can cancel your stake under \"My Proposals\"."

# Import web3
Web3 = require "web3"
web3 = window.web3
hasWeb3 = false
if web3?
  web3 = new Web3(web3.currentProvider)
  hasWeb3 = true
else
  web3 = new Web3(new Web3.providers.HttpProvider("https://rinkeby.infura.io/m7Pdc77PjIwgmp7t0iKI"))

# Fund object
betoken_addr = new ReactiveVar("0x56b5be914b7c544ad22c66998471d826fff9c5a4")
betoken = new Betoken(betoken_addr.get())
astAddr = "0xedc86bdd73604b3d9d62afa0cd70c0f95dd106fd"

# Session data
userAddress = new ReactiveVar("Not Available")
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
paused = new ReactiveVar(false)
allowEmergencyWithdraw = new ReactiveVar(false)
lastCommissionRedemption = new ReactiveVar(0)
cycleTotalCommission = new ReactiveVar(BigNumber(0))

# Displayed variables
kairoAddr = new ReactiveVar("")
sharesAddr = new ReactiveVar("")
kyberAddr = new ReactiveVar("")
daiAddr = new ReactiveVar("")
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

loadFundData = () ->
  investments = []
  receivedROICount = 0

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
  if netID != 4
    showError("Please switch to Rinkeby Testnet in order to try Betoken Alpha")

  # Get user address
  userAddr = (await web3.eth.getAccounts())[0]
  web3.eth.defaultAccount = userAddr
  if userAddr?
    userAddress.set(userAddr)

  # Get shares balance
  sharesTotalSupply.set(BigNumber(await betoken.getShareTotalSupply()))
  totalFunds.set(BigNumber(await betoken.getPrimitiveVar("totalFundsInDAI")))
  sharesBalance.set(BigNumber(await betoken.getShareBalance(userAddr)))
  if !sharesTotalSupply.get().isZero()
    displayedInvestmentBalance.set(sharesBalance.get().div(sharesTotalSupply.get()).mul(totalFunds.get()).div(1e18))

  # Get user's Kairo balance
  kairoBalance.set(BigNumber(await betoken.getKairoBalance(userAddr)))
  kairoTotalSupply.set(BigNumber(await betoken.getKairoTotalSupply()))
  displayedKairoBalance.set(kairoBalance.get().div(1e18))

  # Get fund data
  cycleNumber.set(+await betoken.getPrimitiveVar("cycleNumber"))
  cyclePhase.set(+await betoken.getPrimitiveVar("cyclePhase"))
  startTimeOfCyclePhase.set(+await betoken.getPrimitiveVar("startTimeOfCyclePhase"))
  phaseLengths.set(await betoken.getPrimitiveVar("getPhaseLengths").map((x) -> +x))
  commissionRate.set(BigNumber(await betoken.getPrimitiveVar("commissionRate")).div(1e18))
  paused.set(await betoken.getPrimitiveVar("paused"))
  allowEmergencyWithdraw.set(await betoken.getPrimitiveVar("allowEmergencyWithdraw"))
  cycleTotalCommission.set(BigNumber(await betoken.getPrimitiveVar("totalCommission")))

  # Get last commission redemption cycle number
  lastCommissionRedemption.set(+await betoken.getMappingOrArrayItem("lastCommissionRedemption", userAddr))

  # Get list of investments
  investments = await betoken.getInvestments(userAddress.get())
  if investments.length != 0
    handleProposal = (id) ->
      betoken.getTokenSymbol(investments[id].tokenAddress).then(
        (_symbol) ->
          investments[id].id = id
          investments[id].tokenSymbol = _symbol
          investments[id].investment = BigNumber(investments[id].stake).div(kairoTotalSupply.get()).mul(totalFunds.get()).div(1e18).toFormat(4)
          investments[id].ROI = if investments[id].isSold then BigNumber(investments[id].sellPrice).sub(investments[id].buyPrice).div(investments[id].buyPrice).toFormat(4) else "N/A"
          investments[id].kroChange = if investments[id].isSold then BigNumber(investments[id].ROI).mul(investments[id].stake).div(1e18).toFormat(4) else "N/A"
          investments[id].stake = BigNumber(investments[id].stake).div(1e18).toFormat(4)
      )
    handleAllProposals = (handleProposal(i) for i in [0..investments.length-1])
    await Promise.all(handleAllProposals)
    investmentList.set(investments)

  # Get deposit and withdraw history
  transactionHistory.set([])
  getDepositWithdrawHistory = (_type) ->
    events = await betoken.contracts.betokenFund.getPastEvents(_type,
      fromBlock: 0
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
  getDepositWithdrawHistory("Deposit")
  getDepositWithdrawHistory("Withdraw")

  # Get token transfer history
  getTransferHistory = (token, isIn) ->
    tokenContract = switch token
      when "KRO" then betoken.contracts.controlToken
      when "BTKS" then betoken.contracts.shareToken
      else null
    events = await tokenContract.getPastEvents("Transfer",
      fromBlock: 0
      filter: if not isIn then {from: userAddr} else {to: userAddr}
    )
    for _event in events
      data = _event.returnValues
      entry =
        type: "Transfer " + if isIn then "In" else "Out"
        token: token
        amount: BigNumber(data.value).div(1e18).toFormat(4)
        timestamp: new Date((await web3.eth.getBlock(_event.blockNumber)).timestamp * 1e3).toString()
      tmp = transactionHistory.get()
      tmp.push(entry)
      transactionHistory.set(tmp)

  getTransferHistory("KRO", true)
  getTransferHistory("KRO", false)
  getTransferHistory("BTKS", true)
  getTransferHistory("BTKS", false)

  # Get contract addresses
  kairoAddr.set(betoken.addrs.controlToken)
  sharesAddr.set(betoken.addrs.shareToken)
  kyberAddr.set(await betoken.getPrimitiveVar("kyberAddr"))
  daiAddr.set(await betoken.getPrimitiveVar("daiAddr"))

  # Get statistics
  prevROI.set(BigNumber(0))
  avgROI.set(BigNumber(0))
  prevCommission.set(BigNumber(0))
  historicalTotalCommission.set(BigNumber(0))

  # Get commission
  events = await betoken.contracts.betokenFund.getPastEvents("TotalCommissionPaid",
    fromBlock: 0
  )
  for _event in events
    data = _event.returnValues

    commission = BigNumber(data._totalCommissionInWeis)
    # Update previous cycle commission
    if +data._cycleNumber == cycleNumber.get() - 1
      prevCommission.set(commission)

    # Update total commission
    historicalTotalCommission.set(historicalTotalCommission.get().add(commission))

  # Draw chart
  chart.data.datasets[0].data = []
  chart.update()
  events = await betoken.contracts.betokenFund.getPastEvents("ROI",
    fromBlock: 0
  )
  for _event in events
    data = _event.returnValues
    ROI = BigNumber(data._afterTotalFunds).minus(data._beforeTotalFunds).div(data._afterTotalFunds).mul(100)

    #Update chart data
    chart.data.datasets[0].data.push(
      x: data._cycleNumber
      y: ROI.toString()
    )
    chart.update()

    #Update previous cycle ROI
    if +data._cycleNumber == cycleNumber.get() || +data._cycleNumber == cycleNumber.get() - 1
      prevROI.set(ROI)

    # Update average ROI
    receivedROICount += 1
    avgROI.set(avgROI.get().add(ROI.minus(avgROI.get()).div(receivedROICount)))
  return

$("document").ready(() ->
  $(".menu .item").tab()
  $("table").tablesort()

  if typeof web3 != "undefined"
    web3.eth.net.getId().then(
      (_id) ->
        if _id != 4
          showError("Please switch to Rinkeby Testnet in order to try Betoken Alpha")
        return
    )

    clock()

    chart = new Chart($("#myChart"),
      type: "line",
      data:
        datasets: [
          label: "ROI Per Cycle"
          backgroundColor: "rgba(0, 0, 100, 0.5)"
          borderColor: "rgba(0, 0, 100, 1)"
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
          ]
          yAxes: [
            type: "linear"
            position: "left"
            scaleLabel:
              display: true
              labelString: "Percent"
            ticks:
              beginAtZero: true
          ]
    )

    #Initialize Betoken object
    betoken.init().then(loadFundData)

  if !hasWeb3
    showError("Betoken can only be used in a Web3 enabled browser. Please install <a href=\"https://metamask.io/\">MetaMask</a> or switch to another browser that supports Web3. You can currently view the fund's data, but cannot make any interactions.")
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
  betoken_addr: () -> betoken_addr.get()
  kairo_addr: () -> kairoAddr.get()
  shares_addr: () -> sharesAddr.get()
  kyber_addr: () -> kyberAddr.get()
  dai_addr: () -> daiAddr.get()
  ast_addr: () -> astAddr
  network_prefix: () -> networkPrefix.get()
)

Template.top_bar.events(
  "click .next_phase": (event) ->
    try
      betoken.nextPhase(showTransaction)
    catch error
      console.log error

  "click .emergency_withdraw": (event) ->
    betoken.emergencyWithdraw(showTransaction)

  "click .change_contract": (event) ->
    $("#change_contract_modal").modal(
      onApprove: (e) ->
        try
          new_addr = $("#contract_addr_input")[0].value
          if !web3.utils.isAddress(new_addr)
            throw ""
          betoken_addr.set(new_addr)
          betoken = new Betoken(betoken_addr.get())
          betoken.init().then(loadFundData)
        catch error
          showError("Oops! That wasn't a valid contract address!")
    ).modal("show")

  "click .info_button": (event) ->
    $("#contract_info_modal").modal("show")
)

Template.countdown_timer.helpers(
  day: () -> countdownDay.get()
  hour: () -> countdownHour.get()
  minute: () -> countdownMin.get()
  second: () -> countdownSec.get()
)

Template.phase_indicator.helpers(
  phase_active: (index) ->
    if cyclePhase.get() == index
      return "active"
    return ""
)

Template.sidebar.helpers(
  network_name: () -> networkName.get()
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
      return kairoBalance.get().div(kairoTotalSupply.get()).mul(totalFunds.get().div(1e18)).mul(avgROI.get().div(100)).mul(commissionRate.get()).toFormat(18)
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
    betoken.redeemCommission(showTransaction)

  "click .redeem_commission_in_shares": (event) ->
    betoken.redeemCommissionInShares(showTransaction)
)

Template.transact_box.onCreated(
  () ->
    Template.instance().depositInputHasError = new ReactiveVar(false)
    Template.instance().withdrawInputHasError = new ReactiveVar(false)
    Template.instance().sendTokenAmountInputHasError = new ReactiveVar(false)
    Template.instance().sendTokenRecipientInputHasError = new ReactiveVar(false)
)

Template.transact_box.helpers(
  is_disabled: (_type) ->
    if (cyclePhase.get() != 0 && _type != "token") || (cyclePhase.get() == 2 && _type == "token")
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
)

Template.transact_box.events(
  "click .deposit_button": (event) ->
    try
      Template.instance().depositInputHasError.set(false)
      amount = BigNumber($("#deposit_input")[0].value)
      tokenType = $("#deposit_token_type")[0].value

      if !amount.greaterThan(0)
        Template.instance().sendTokenAmountInputHasError.set(true)
        return

      if tokenType == "ETH"
        betoken.deposit(amount.mul(1e18), showTransaction)
      else
        tokenAddr = switch tokenType
          when "DAI" then daiAddr.get()
          when "AST" then astAddr
        betoken.depositToken(tokenAddr, amount, showTransaction)
    catch
      Template.instance().depositInputHasError.set(true)

  "click .withdraw_button": (event) ->
    try
      Template.instance().withdrawInputHasError.set(false)
      amount = BigNumber($("#withdraw_input")[0].value)
      tokenType = $("#withdraw_token_type")[0].value

      if !amount.greaterThan(0)
        Template.instance().sendTokenAmountInputHasError.set(true)
        return

      if tokenType == "ETH"
        betoken.withdraw(amount.mul(1e18), showTransaction)
      else
        tokenAddr = switch tokenType
          when "DAI" then daiAddr.get()
          when "AST" then astAddr
        betoken.withdrawToken(tokenAddr, amount, showTransaction)
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
        betoken.sendKairo(toAddress, amount, showTransaction)
      else if tokenType == "BTKS"
        if amount.greaterThan(sharesBalance.get())
          Template.instance().sendTokenAmountInputHasError.set(true)
          return
        betoken.sendShares(toAddress, amount, showTransaction)
    catch
      Template.instance().sendTokenAmountInputHasError.set(true)
)

Template.stats_tab.helpers(
  cycle_length: () -> BigNumber(phaseLengths.get().reduce((t, n) -> t+n)).div(24 * 60 * 60).toDigits(3)
  total_funds: () -> totalFunds.get().div("1e18").toFormat(2)
  prev_roi: () -> prevROI.get().toFormat(2)
  avg_roi: () -> avgROI.get().toFormat(2)
  prev_commission: () -> prevCommission.get().div(1e18).toFormat(2)
  historical_commission: () -> historicalTotalCommission.get().div(1e18).toFormat(2)
)

Template.decisions_tab.helpers(
  investment_list: () -> investmentList.get()
  wei_to_eth: (_weis) -> BigNumber(_weis).div(1e18).toFormat(4)
  new_investment_is_disabled: () ->
    if cyclePhase.get() == 1 then "" else "disabled"
)

Template.decisions_tab.events(
  "click .sell_investment": (event) ->
    id = this.id
    if cyclePhase.get() == 1
      betoken.sellAsset(id, showTransaction)

  "click .new_investment": (event) ->
    $("#new_investment_modal").modal(
      onApprove: (e) ->
        try
          address = $("#address_input_new")[0].value
          if (!web3.utils.isAddress(address))
            throw "Invalid token address."

          kairoAmountInWeis = BigNumber($("#stake_input_new")[0].value).times("1e18")
          checkKairoAmountError(kairoAmountInWeis)

          betoken.createInvestment(address, kairoAmountInWeis, showTransaction)
        catch error
          showError(error.toString() || INPUT_ERR)
    ).modal("show")
)

checkKairoAmountError = (kairoAmountInWeis) ->
  if !kairoAmountInWeis.greaterThan(0)
    throw "Stake amount should be positive."
  if kairoAmountInWeis.greaterThan(kairoBalance.get())
    throw "You can't stake more Kairos than you have!"
