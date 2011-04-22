amqp = require './node-amqp'
username = process.argv[2]
connection = amqp.createConnection({host: 'nostat.us'})
connection.on 'ready', ->
    process.stdin.resume()
    process.stdin.setEncoding('utf8');
    process.stdin.on 'data', (chunk)->
        connection.publish '*', "#{username} says: #{chunk}"
    q = connection.queue(username,{autoDelete: false})
    q.bind '#'
    console.log 'ready'
    q.subscribe (message)->
        console.log message.data.toString()

