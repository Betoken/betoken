https = require "https"
fs = require "fs"
main = () ->
    apiStr = "https://api.ethplorer.io/getTop?apiKey=freekey&criteria=cap"
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
    tokens = data.tokens.map(
        (token) ->
            if token.decimals >= 11
                return {
                    name: token.name,
                    symbol: token.symbol,
                    decimals: token.decimals
                }
    )
    fs.writeFileSync("./eth/deployment_configs/tokens.json", JSON.stringify(tokens))

main()