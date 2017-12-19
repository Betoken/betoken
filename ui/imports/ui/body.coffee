import './body.html'
import './body.css'
import './tablesort.js'
import { Betoken } from '../objects/betoken.js'
import Chart from 'chart.js'
import BigNumber from 'bignumber.js'

#Import web3
Web3 = require 'web3'
web3 = window.web3
if typeof web3 != undefined
  web3 = new Web3(web3.currentProvider)
else
  web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:8545"))

betoken_addr = ""
betoken = new Betoken(betoken_addr)

userAddress = new ReactiveVar("")
kairoBalance = new ReactiveVar(BigNumber(""))
kairoTotalSupply = new ReactiveVar(BigNumber(""))
displayedKairoBalance = new ReactiveVar(BigNumber(""))
cyclePhase = new ReactiveVar(0)
totalFunds = new ReactiveVar(BigNumber(""))

$('document').ready(() ->
  $('.menu .item').tab()
  $('table').tablesort()

  ctx = document.getElementById("myChart");
  myChart = new Chart(ctx,
    type: 'line',
    data:
      datasets: [
        label: "ROI Per Cycle"
        backgroundColor: 'rgba(0, 0, 100, 0.5)'
        borderColor: 'rgba(0, 0, 100, 1)'
        data: [
          x: 1
          y: 10
        ,
          x: 2
          y: 13
        ,
          x: 3
          y: 20
        ]
      ]
    ,
    options:
      scales:
        xAxes: [
          type: 'linear'
          position: 'bottom'
          scaleLabel:
            display: true
            labelString: 'Investment Cycle'
          ticks:
            stepSize: 1
        ]
        yAxes: [
          type: 'linear'
          position: 'left'
          scaleLabel:
            display: true
            labelString: 'Percent'
          ticks:
            beginAtZero: true
        ]
  )
)

Template.body.onCreated(
  () ->
    betoken.getCurrentAccount().then(
      (_userAddress) ->
        userAddress.set(_userAddress)
    ).then(
      () ->
        return betoken.getKairoBalance(userAddress.get())
    ).then(
      (_kairoBalance) ->
        kairoBalance.set(BigNumber(_kairoBalance))
        displayedKairoBalance.set(BigNumber(web3.util.fromWei(_kairoBalance, "ether")).toFormat(4))
    ).then(
      () ->
        return betoken.getKairoTotalSupply()
    ).then(
      (_kairoTotalSupply) ->
        kairoTotalSupply.set(BigNumber(_kairoTotalSupply))
    )
)

Template.phase_indicator.helpers(
  phase_active: (index) ->
    isActive = new ReactiveVar("")
    betoken.getPrimitiveVar("cyclePhase").then(
      (_result) ->
        cyclePhase.set(+_result)
        if +_result == index
          isActive.set("active")
    )
    return isActive.get()
)

Template.sidebar.helpers(
  user_address: () ->
    return userAddress.get()

  user_balance: () ->
    balance = new ReactiveVar("")
    betoken.getMappingOrArrayItem("balanceOf", userAddress.get()).then(
      (result) ->
        balance.set(BigNumber(web3.util.fromWei(result, "ether")).toFormat(4))
    )
    return balance.get()

  user_kairo_balance: () ->
    return displayedKairoBalance.get()
)

Template.sidebar.events(
  "click .kairo_unit_switch": (event) ->
    if this.checked
      #Display proportion
      displayedKairoBalance.set(kairoBalance.get().dividedBy(kairoTotalSupply.get()).times(100).toFormat(4))
    else
      #Display Kairo
      displayedKairoBalance.set(BigNumber(web3.util.fromWei(kairoBalance.get(), "ether")).toFormat(4))
)

Template.transact_box.onCreated(
  () ->
    this.depositInputHasError = new ReactiveVar(false)
    this.withdrawInputHasError = new ReactiveVar(false)
)

Template.transact_box.helpers(
  is_disabled: () ->
    if cyclePhase.get() != 0
      return "disabled"
    return ""

  has_error: (input_id) ->
    if input_id == 0
      if this.depositInputHasError.get()
        return "error"
    else
      if this.withdrawInputHasError.get()
        return "error"
    return ""
)

Template.transact_box.events(
  "click .deposit_button": (event) ->
    try
      this.depositInputHasError.set(false)
      amount = BigNumber(web3.util.toWei(document.getElementById("deposit_input").value))
      betoken.deposit(amount)
    catch
      this.depositInputHasError.set(true)

  "click .withdraw_button": (event) ->
    try
      this.withdrawInputHasError.set(false)
      amount = BigNumber(web3.util.toWei(document.getElementById("deposit_input").value))
      betoken.withdraw(amount)
    catch
      this.depositInputHasError.set(true)
)

Template.stats_tab.onCreated(
  () ->
    betoken.getPrimitiveVar("totalFunds").then(
      (_totalFunds) ->
        totalFunds.set(BigNumber(_totalFunds))
    )
)

Template.proposals_tab.helpers(
  proposal_list: () ->
    reactive_proposals = new ReactiveVar([])
    proposals = []
    betoken.getArray("proposals").then(
      (_proposals) ->
        #Get all proposals
        allPromises = []
        for i in [0.._proposals.length - 1]
          if _proposals[i].numFor > 0
            allPromises.push(betoken.getMappingOrArrayItem("forStakedControlOfProposal", i).then(
              (_stake) ->
                investment = BigNumber(_stake).dividedBy(kairoTotalSupply.get()).times(web3.util.fromWei(totalFunds.get()))
                proposal =
                  id: i
                  token_symbol: _proposals[i].tokenSymbol
                  investment: investment.toFormat(4)
                  supporters: _proposals[i].numFor
                proposals.push(proposal)
            ))
        return Promise.all(allPromises)
    ).then(
      () ->
        reactive_proposals.set(proposals)
        return
    )
    return reactive_proposals.get()
)

Template.proposals_tab.events(
  "click .stake_button": (event) ->
    try
      kairoAmountInWeis = BigNumber(web3.util.toWei(document.getElementById("stake_input_" + this.id).value))
      betoken.supportProposal(this.id, kairoAmountInWeis)
    catch
      #Todo:Display error message

  "click .stake_button_new": (event) ->
    try
      address = document.getElementById("address_input_new").value
      tickerSymbol = document.getElementById("ticker_input_new").value
      kairoAmountInWeis = BigNumber(web3.util.toWei(document.getElementById("stake_input_new").value))
      betoken.createProposal(address, tickerSymbol, kairoAmountInWeis)
    catch
      #Todo:Display error message
)

Template.members_tab.helpers(
  member_list: () ->
    reactive_list = new ReactiveVar([])
    list = []
    betoken.getArray("participants").then(
      (_array) ->
        #Get member addresses
        list = new Array(_array.length)
        for i in [0.._array.length - 1]
          list[i].address = _array[i]
        return
    ).then(
      () ->
        #Get member ETH balances
        allPromises = []
        for member in list
          allPromises.push(web3.eth.getBalance(member.address).then(
            (_eth_balance) ->
              member.eth_balance = BigNumber(web3.util.fromWei(_eth_balance, "ether")).toFormat(4)
              return
          ))
        return Promise.all(allPromises)
    ).then(
      () ->
        #Get member KRO balances
        allPromises = []
        for member in list
          allPromises.push(betoken.getKairoBalance(member.address).then(
            (_kro_balance) ->
              member.kro_balance = BigNumber(web3.util.fromWei(_kro_balance, "ether")).toFormat(4)
              return
          ))
        return Promise.all(allPromises)
    ).then(
      () ->
        #Get member KRO proportions
        for member in list
          member.kro_proportion = member.kro_balance.dividedBy(web3.util.fromWei(kairoTotalSupply.get(), "ether")).times(100).toPrecision(4)
        return
    ).then(
      () ->
        #Update reactive_list
        reactive_list.set(list)
    )
    return reactive_list.get()
)