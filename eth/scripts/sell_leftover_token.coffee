BetokenFund = artifacts.require "BetokenFund"
TestTokenFactory = artifacts.require "TestTokenFactory"

BETOKEN_ADDR = "0x5910d5ABD4d5fD58b39957664Cd9735CbfE42bF0"
TOKEN_FACTORY_ADDR = "0x76fc4b929325D04f5e3F3724eFDDFB45B52d3160"

tokenFactory = TestTokenFactory.at(TOKEN_FACTORY_ADDR)
betoken = BetokenFund.at(BETOKEN_ADDR)

TOKENS = [
    "ZRX",
    "ETH",
    "LINK"
]

module.exports = (callback) ->
    for token in TOKENS
        tokenFactory.getToken(token).then(
            (_addr) ->
                console.log "#{token}: #{_addr}"
                betoken.sellLeftoverToken(_addr)
        )