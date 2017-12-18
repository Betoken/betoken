import './body.html'
import './body.css'
import './tablesort.js'
import { Betoken } from '../objects/betoken.js'
import Chart from 'chart.js'

betoken_addr = ""
betoken = new Betoken(betoken_addr)

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