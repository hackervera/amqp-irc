net = require 'net'
redis = require 'redis'
amqp = require './node-amqp'




        
client = redis.createClient()
class User
channel = {}
streams = []
users = {}
carrier = require 'carrier'

stream = (stream)->
    carry = carrier.carry stream
    user = new User
    user.channel = {}
    user.connection = {}
    user.joined = []
    connection = null
    q = null
    user.stream = stream
    carry.on 'line', (line)->
        input = line.split ' '
        
        if input[0] == "NICK"
            if user.nick?
                delete users[user.nick]

            user.nick = input[1]
            users[user.nick] = user
            console.log "NICKS:"
            
        
        if input[0] == "USER"
            console.log "GOT USER"
            user.host = input[3]
            stream.write ":#{user.host} 001 #{user.nick} Hello #{user.nick}!\r\n"
            console.log "User host: #{user.host}"
        
        if input[0] == "JOIN"
            chan = input[1]
            channel[chan] ?= {}
            channel[chan][user.nick] = user
            console.log "CHANS: #{Object.keys(channel[chan])}"            
            
            nicks = Object.keys(channel[chan]).join(' ')
            console.log "ALL NICKS for #{chan}: #{nicks}"
            for nonce in Object.keys(channel[chan])
                person = channel[chan][nonce]
                try
                    person.stream.write ":#{user.nick}!USER@127.0.0.1 JOIN #{chan}\r\n"
                catch e
                    console.log e
            user.channel[input[1]] = input[1]            
            connection = user.connection[chan] = amqp.createConnection({host: 'nostat.us'})
            connection.on 'ready', ->
                q = connection.queue("#{user.nick}:#{chan}",{autoDelete: false})
                q.bind chan
                q.subscribe (message)->
                    console.log "Received: #{message.data} for #{user.nick}"
                    pub = JSON.parse message.data
                    
                    output = """
                        :#{pub.nick}!USER@127.0.0.1 PRIVMSG #{pub.chan} #{pub.message}\r\n
                    """
                    unless pub.nick == user.nick
                        try
                            user.stream.write output 
                        catch e
                            console.log e
                        console.log "OUTPUT #{output}"  
            #:#{user.nick}!USER@127.0.0.1 JOIN #{chan}
            output = """
                
                :#{user.host} 331 #{user.nick} #{chan} :No topic is set
                :#{user.host} 353 #{user.nick} = #{chan} :#{nicks}
                :#{user.host} 366 #{user.nick} #{chan} :End of /NAMES list.\r\n
            """
            console.log output
            stream.write output
        input = line.split ' ', 3
        
        if input[0] == "PRIVMSG"
            chan = input[1]
            message = line.match(/.*? .*? (.*)/)[1]
            pub = 
                nick: user.nick
                message: message
                chan: chan
            connection.publish chan, JSON.stringify pub
            console.log "pushed message to queue: #{JSON.stringify pub}"
        
        if input[0] == "QUIT"
            for conn in Object.keys(user.connection)
                user.connection[conn].end()
                console.log "Closing connections for #{user.nick}"

        console.log line.toString()
server = net.createServer(stream)
server.listen 6667