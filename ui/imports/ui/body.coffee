import "./body.html"
import "./body.css"
import "./tablesort.js"
import { Betoken } from "../objects/betoken.js"
import Chart from "chart.js"
import BigNumber from "bignumber.js"

SEND_TX_ERR = "There was an error during sending your transaction to the Ethereum blockchain. Please check that your inputs are valid and try again later."
INPUT_ERR = "There was an error in your input. Please fix it and try again."
STAKE_BOTH_SIDES_ERR = "You have already staked on the opposite side of this proposal! If you want to change your mind, you can cancel your stake under \"My Proposals\"."

#Import web3
Web3 = require "web3"
web3 = window.web3
hasWeb3 = false
if typeof web3 != "undefined"
  web3 = new Web3(web3.currentProvider)
  hasWeb3 = true
else
  web3 = new Web3(new Web3.providers.HttpProvider("https://rinkeby.infura.io/m7Pdc77PjIwgmp7t0iKI"))

#Fund object
betoken_addr = new ReactiveVar("0x6ca70247ee747078103902f37d2afc3ad0b57c73")
betoken = new Betoken(betoken_addr.get())

#Session data
userAddress = new ReactiveVar("Not Available")
kairoBalance = new ReactiveVar(BigNumber(0))
kairoTotalSupply = new ReactiveVar(BigNumber(0))
sharesBalance = new ReactiveVar(BigNumber(0))
sharesTotalSupply = new ReactiveVar(BigNumber(0))

cyclePhase = new ReactiveVar(0)
startTimeOfCyclePhase = new ReactiveVar(0)
phaseLengths = new ReactiveVar([])
totalFunds = new ReactiveVar(BigNumber(0))
proposalList = new ReactiveVar([])
cycleNumber = new ReactiveVar(0)
commissionRate = new ReactiveVar(BigNumber(0))
paused = new ReactiveVar(false)
allowEmergencyWithdraw = new ReactiveVar(false)
lastCommissionRedemption = new ReactiveVar(0)
cycleTotalCommission = new ReactiveVar(BigNumber(0))

#Displayed variables
kairoAddr = new ReactiveVar("")
sharesAddr = new ReactiveVar("")
kyberAddr = new ReactiveVar("")
displayedInvestmentBalance = new ReactiveVar(BigNumber(0))
displayedInvestmentUnit = new ReactiveVar("ETH")
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
  proposals = []
  receivedROICount = 0

  #Get Network ID
  web3.eth.net.getId().then(
    (_id) ->
      switch _id
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

      if _id != 4
        showError("Please switch to Rinkeby Testnet in order to try Betoken Alpha")
      return
  )

  web3.eth.getAccounts().then(
    (accounts) ->
      web3.eth.defaultAccount = accounts[0]
      return accounts[0]
  ).then(
    (_userAddress) ->
      #Initialize user address
      if typeof _userAddress != "undefined"
        userAddress.set(_userAddress)

      betoken.getShareTotalSupply().then(
        (_totalSupply) -> sharesTotalSupply.set(BigNumber(_totalSupply))
      ).then(
        () ->
          betoken.getShareBalance(_userAddress).then(
            (_sharesBalance) ->
              #Get user's Shares balance
              sharesBalance.set(BigNumber(_sharesBalance))
              if !sharesTotalSupply.get().isZero()
                displayedInvestmentBalance.set(sharesBalance.get().div(sharesTotalSupply.get()).mul(totalFunds.get()).div(1e18))
          )
      )

      betoken.getKairoBalance(_userAddress).then(
        (_kairoBalance) ->
          #Get user's Kairo balance
          kairoBalance.set(BigNumber(_kairoBalance))
          displayedKairoBalance.set(BigNumber(web3.utils.fromWei(_kairoBalance, "ether")))
      )

      betoken.getMappingOrArrayItem("lastCommissionRedemption", _userAddress).then(
        (_result) -> lastCommissionRedemption.set(_result)
      )

      #Get proposals & participants
      Promise.all([
        betoken.getKairoTotalSupply().then(
          (_kairoTotalSupply) ->
            #Get Kairo's total supply
            kairoTotalSupply.set(BigNumber(_kairoTotalSupply))
            return
        ),
        betoken.getPrimitiveVar("totalFundsInWeis").then(
          #Get total funds
          (_totalFunds) -> totalFunds.set(BigNumber(_totalFunds))
        ),
      ]).then(
        () ->
          ###betoken.getMappingOrArrayItem("proposals", userAddress.get()).then(
            (_proposals) ->
              proposals = _proposals
              if proposals.length == 0
                return

              handleProposal = (id) ->
                betoken.getTokenSymbol(proposals[id]).then(
                  (_symbol) ->
                    proposals[id].id = id
                    proposals[id].tokenSymbol = _symbol
                    proposals[id].investment = BigNumber(proposals[id].stake).div(kairoTotalSupply.get()).mul(totalFunds.get())
                )
              handleAllProposals = (handleProposal(i) for i in [0..proposals.length])
              Promise.all(getAllSymbols)
          ).then(
            () ->
              proposalList.set(proposals)
          )###
      )

      #Listen for transactions
      transactionHistory.set([])

      getTransactionHistory = (_type) ->
        betoken.contracts.betokenFund.getPastEvents(_type,
          fromBlock: 0
          filter: {_sender: _userAddress}
        ).then(
          (_events) ->
            for _event in _events
              data = _event.returnValues
              entry =
                type: _type
                timestamp: new Date(+data._timestamp * 1e3).toString()
              betoken.getTokenSymbol(data._tokenAddress).then(
                (_tokenSymbol) ->
                  entry.token = _tokenSymbol
              ).then(() -> betoken.getTokenDecimals(data._tokenAddress)).then(
                (_tokenDecimals) ->
                  entry.amount = BigNumber(data._tokenAmount).div(10**(+_tokenDecimals)).toFormat(4)
              ).then(
                () ->
                  tmp = transactionHistory.get()
                  tmp.push(entry)
                  transactionHistory.set(tmp)
              )
        )
      getTransactionHistory("Deposit")
      getTransactionHistory("Withdraw")

      betoken.contracts.controlToken.getPastEvents("Transfer",
        fromBlock: 0
        filter: {from: _userAddress}
      ).then(
        (_events) ->
          for _event in _events
            data = _event.returnValues
            entry =
              type: "Transfer Out"
              token: "KRO"
              amount: BigNumber(data.value).div(1e18).toFormat(4)
            web3.eth.getBlock(_event.blockNumber).then(
              (_block) ->
                entry.timestamp = new Date(_block.timestamp * 1e3).toString()
                tmp = transactionHistory.get()
                tmp.push(entry)
                transactionHistory.set(tmp)
            )
      )
      betoken.contracts.controlToken.getPastEvents("Transfer",
        fromBlock: 0
        filter: {to: _userAddress}
      ).then(
        (_events) ->
          for _event in _events
            data = _event.returnValues
            entry =
              type: "Transfer In"
              token: "KRO"
              amount: BigNumber(data.value).div(1e18).toFormat(4)
            web3.eth.getBlock(_event.blockNumber).then(
              (_block) ->
                entry.timestamp = new Date(_block.timestamp * 1e3).toString()
                tmp = transactionHistory.get()
                tmp.push(entry)
                transactionHistory.set(tmp)
            )
      )
      betoken.contracts.shareToken.getPastEvents("Transfer",
        fromBlock: 0
        filter: {from: _userAddress}
      ).then(
        (_events) ->
          for _event in _events
            data = _event.returnValues
            entry =
              type: "Transfer Out"
              token: "BTKS"
              amount: BigNumber(data.value).div(1e18).toFormat(4)
            web3.eth.getBlock(_event.blockNumber).then(
              (_block) ->
                entry.timestamp = new Date(_block.timestamp * 1e3).toString()
                tmp = transactionHistory.get()
                tmp.push(entry)
                transactionHistory.set(tmp)
            )
      )
      betoken.contracts.controlToken.getPastEvents("Transfer",
        fromBlock: 0
        filter: {to: _userAddress}
      ).then(
        (_events) ->
          for _event in _events
            data = _event.returnValues
            entry =
              type: "Transfer In"
              token: "BTKS"
              amount: BigNumber(data.value).div(1e18).toFormat(4)
            web3.eth.getBlock(_event.blockNumber).then(
              (_block) ->
                entry.timestamp = new Date(_block.timestamp * 1e3).toString()
                tmp = transactionHistory.get()
                tmp.push(entry)
                transactionHistory.set(tmp)
            )
      )
  )

  #Get cycle data
  betoken.getPrimitiveVar("cyclePhase").then(
    (_cyclePhase) -> cyclePhase.set(+_cyclePhase)
  )
  betoken.getPrimitiveVar("startTimeOfCyclePhase").then(
    (_startTime) -> startTimeOfCyclePhase.set(+_startTime)
  )
  betoken.getPrimitiveVar("getPhaseLengths").then(
    (_phaseLengths) -> phaseLengths.set(_phaseLengths.map((x) -> +x))
  )
  betoken.getPrimitiveVar("commissionRate").then(
    (_result) -> commissionRate.set(BigNumber(_result).div(1e18))
  )
  betoken.getPrimitiveVar("paused").then(
    (_result) -> paused.set(_result)
  )
  betoken.getPrimitiveVar("allowEmergencyWithdraw").then(
    (_result) -> allowEmergencyWithdraw.set(_result)
  )
  betoken.getPrimitiveVar("totalCommission").then(
    (_result) -> cycleTotalCommission.set(BigNumber(_result))
  )

  #Get contract addresses
  kairoAddr.set(betoken.addrs.controlToken)
  sharesAddr.set(betoken.addrs.shareToken)
  betoken.getPrimitiveVar("kyberAddr").then(
    (_kyberAddr) ->
      kyberAddr.set(_kyberAddr)
  )

  #Get statistics
  prevROI.set(BigNumber(0))
  avgROI.set(BigNumber(0))
  prevCommission.set(BigNumber(0))
  historicalTotalCommission.set(BigNumber(0))
  betoken.getPrimitiveVar("cycleNumber").then(
    (_result) ->
      cycleNumber.set(+_result)
  ).then(
    () ->
      chart.data.datasets[0].data = []
      chart.update()
      betoken.contracts.betokenFund.getPastEvents("ROI",
        fromBlock: 0
      ).then(
        (_events) ->
          for _event in _events
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

            #Update average ROI
            receivedROICount += 1
            avgROI.set(avgROI.get().add(ROI.minus(avgROI.get()).div(receivedROICount)))
      )

      betoken.contracts.betokenFund.getPastEvents("CommissionPaid",
        fromBlock: 0
      ).then(
        (_events) ->
          for _event in _events
            data = _event.returnValues
            commission = BigNumber(data._totalCommissionInWeis)
            #Update previous cycle commission
            if +data._cycleNumber == cycleNumber.get() - 1
              prevCommission.set(commission)

            #Update total commission
            historicalTotalCommission.set(historicalTotalCommission.get().add(commission))
      )
  )

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
  network_prefix: () -> networkPrefix.get()
)

Template.top_bar.events(
  "click .next_phase": (event) ->
    try
      betoken.endPhase(cyclePhase.get(), showTransaction)
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
  can_redeem_commission: () -> cyclePhase.get() == 4 && lastCommissionRedemption.get() < cycleNumber.get()
  expected_commission: () ->
    if kairoTotalSupply.get().greaterThan(0)
      if cyclePhase.get() == 4
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
      displayedKairoBalance.set(BigNumber(web3.utils.fromWei(kairoBalance.get().toString(), "ether")))
      displayedKairoUnit.set("KRO")

  "click .balance_unit_switch": (event) ->
    if event.target.checked
      #Display BTKS
      displayedInvestmentBalance.set(sharesBalance.get().div(1e18))
      displayedInvestmentUnit.set("BTKS")
    else
      #Display ETH
      if !sharesTotalSupply.get().isZero()
        displayedInvestmentBalance.set(sharesBalance.get().div(sharesTotalSupply.get()).mul(totalFunds.get()).div(1e18))
      displayedInvestmentUnit.set("ETH")
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
    if (cyclePhase.get() != 0 && _type != "token") || (cycleNumber.get() == 1 && _type == "withdraw")\
        || (cyclePhase.get() == 4 && _type == "token")
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
      amount = BigNumber(web3.utils.toWei($("#deposit_input")[0].value))

      if !amount.greaterThan(0)
        Template.instance().sendTokenAmountInputHasError.set(true)
        return

      betoken.deposit(amount, showTransaction)
    catch
      Template.instance().depositInputHasError.set(true)

  "click .withdraw_button": (event) ->
    try
      Template.instance().withdrawInputHasError.set(false)
      amount = BigNumber(web3.utils.toWei($("#withdraw_input")[0].value))

      if !amount.greaterThan(0)
        Template.instance().sendTokenAmountInputHasError.set(true)
        return

      # Check that Betoken balance is > withdraw amount
      if amount.greaterThan(sharesBalance.get().div(sharesTotalSupply.get()).mul(totalFunds.get()))
        showError("Oops! You tried to withdraw more Ether than you have in your account!")
        Template.instance().withdrawInputHasError.set(true)
        return

      betoken.withdraw(amount, showTransaction)
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

Template.proposals_tab.helpers(
  proposal_list: () -> proposalList.get()
  should_have_actions: () -> cyclePhase.get() == 3
  wei_to_eth: (_weis) -> BigNumber(_weis).div(1e18).toFormat(4)

  redeem_kro_is_disabled: (_isSold) ->
    if _isSold then "disabled" else ""

  new_proposal_is_disabled: () ->
    if cyclePhase.get() == 1 then "" else "disabled"
)

Template.proposals_tab.events(
  "click .execute_proposal": (event) ->
    id = this.id
    if cyclePhase.get() == 3
      betoken.sellProposalAsset(id, showTransaction)

  "click .new_proposal": (event) ->
    $("#new_proposal_modal").modal(
      onApprove: (e) ->
        try
          address = $("#address_input_new")[0].value
          if (!web3.utils.isAddress(address))
            throw "Invalid token address."

          kairoAmountInWeis = BigNumber($("#stake_input_new")[0].value).times("1e18")
          checkKairoAmountError(kairoAmountInWeis)

          betoken.createProposal(address, kairoAmountInWeis, showTransaction)
        catch error
          showError(error.toString() || INPUT_ERR)
    ).modal("show")
)

checkKairoAmountError = (kairoAmountInWeis) ->
  if !kairoAmountInWeis.greaterThan(0)
    throw "Stake amount should be positive."
  if kairoAmountInWeis.greaterThan(kairoBalance.get())
    throw "You can't stake more Kairos than you have!"
