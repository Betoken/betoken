https = require "https"
fs = require "fs"

wait = (time) ->
    return new Promise(
        (resolve) ->
            setTimeout(resolve, time)
    )

main = () ->
    knTokenSymbols = require "../deployment_configs/kn_token_symbols.json"
    allTokens = require "../scripts/ethTokens.json"
    tokens = []
    for token in allTokens
        if token.symbol in knTokenSymbols# and token.decimal >= 11
            apiStr = "https://api.ethplorer.io/getTokenInfo/#{token.address}?apiKey=freekey"
            data = await (new Promise((resolve, reject) ->
                https.get(apiStr, (res) ->
                    rawData = ""
                    res.on("data", (chunk) ->
                        rawData += chunk
                    )
                    res.on("end", () ->
                        parsedData = JSON.parse(rawData)
                        resolve(parsedData)
                    )
                ).on("error", reject)
            ))
            tokens.push({
                name: data.name
                symbol: token.symbol
                decimals: token.decimal
            })
            console.log data.name
            await wait(2000)
    
    fs.writeFileSync("./eth/deployment_configs/kn_tokens.json", JSON.stringify(tokens))

main()