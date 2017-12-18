import './body.html'
import './body.css'
import './tablesort.js'
import { Betoken } from '../objects/betoken.js'
import Chart from 'chart.js'

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
kairoBalance = new ReactiveVar("")
kairoTotalSupply = new ReactiveVar("")
displayedKairoBalance = new ReactiveVar("")
cyclePhase = new ReactiveVar(0)

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
        kairoBalance.set(result)
        displayedKairoBalance.set(web3.util.fromWei(result, "ether"))
    ).then(
      () ->
        return betoken.getKairoTotalSupply()
    ).then(
      (_kairoTotalSupply) ->
        kairoTotalSupply.set(_kairoTotalSupply)
    )
)

Template.phase_indicator.helpers(
  phase_active: (index) ->
    isActive = new ReactiveVar("")
    betoken.getPrimitiveVar("cyclePhase").then(
      (result) ->
        cyclePhase.set(result)
        if result == index
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
        balance.set(web3.util.fromWei(result, "ether"))
    )
    return balance.get()

  user_kairo_balance: () ->
    return displayedKairoBalance.get()
)

Template.sidebar.events(
  "click .kairo_unit_switch": (event) ->
    if this.isOn
      kairoBalanceInKRO = Number.parseFloat(web3.util.fromWei(kairoBalance.get(), "ether"))
      kairoSupplyInKRO = Number.parseFloat(web3.util.fromWei(kairoTotalSupply.get(), "ether"))
      displayedKairoBalance.set(kairoBalanceInKRO / kairoSupplyInKRO * 100)
      this.isOn = false
    else
      displayedKairoBalance.set(web3.util.fromWei(kairoBalance.get(), "ether"))
      this.isOn = true
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
      amount = web3.util.toWei(document.getElementById("deposit_input").value)
      betoken.deposit(amount)
    catch
      this.depositInputHasError.set(true)

  "click .withdraw_button": (event) ->
    try
      this.withdrawInputHasError.set(false)
      amount = web3.util.toWei(document.getElementById("deposit_input").value)
      betoken.withdraw(amount)
    catch
      this.depositInputHasError.set(true)
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
              member.eth_balance = _eth_balance
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
              member.kro_balance = web3.util.fromWei(_kro_balance, "ether")
              return
          ))
        return Promise.all(allPromises)
    ).then(
      () ->
        #Get member KRO proportions
        for member in list
          kairoBalanceInKRO = Number.parseFloat(member.kro_balance)
          kairoSupplyInKRO = Number.parseFloat(web3.util.fromWei(kairoTotalSupply.get(), "ether"))
          member.kro_proportion = kairoBalanceInKRO / kairoSupplyInKRO * 100
        return
    ).then(
      () ->
        #Update reactive_list
        reactive_list.set(list)
    )
    return reactive_list.get()
)