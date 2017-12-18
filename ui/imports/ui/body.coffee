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
      (result) ->
        userAddress.set(result)
    ).then(
      () ->
        return betoken.getKairoBalance(userAddress.get())
    ).then(
      (result) ->
        kairoBalance.set(result)
        displayedKairoBalance.set(web3.util.fromWei(result, "ether"))
    ).then(
      () ->
        return betoken.getKairoTotalSupply()
    ).then(
      (result) ->
        kairoTotalSupply.set(result)
    )
)

Template.phase_indicator.helpers(
  phase_active: (index) ->
    isActive = new ReactiveVar("")
    betoken.getPrimitiveVar("cyclePhase").then(
      (result) ->
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