import './body.html'
import './body.css'
import './tablesort.js'
import { Betoken } from '../objects/betoken.js'

betoken_addr = ""
betoken = new Betoken(betoken_addr)

$(document).ready(() ->
    $('.menu .item').tab()
    $('table').tablesort()
)