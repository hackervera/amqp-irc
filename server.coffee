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
    pub = {}
    connection = null
    user.channel = {}
    user.connection = {}
    user.joined = []
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
            chans = input[1].split ","
            for chan in chans
                do (chan)->
                    channel[chan] ?= {}
                    channel[chan][user.nick] = user
                    nicks = Object.keys(channel[chan]).join(' ')
                    connection = user.connection[chan] = amqp.createConnection({host: 'nostat.us'})
                    
                    user.stream.write ":#{user.nick}!* JOIN #{chan}\r\n"
                    
                    connection.on 'ready', ->
                        pub.nick = user.nick
                        pub.chan = chan
                        pub.type = "JOIN"
                        connection.publish chan, JSON.stringify pub
                        q = connection.queue("#{user.nick}:#{chan}",{autoDelete: false})
                        q.bind chan
                        q.subscribe (message)->
                            
                            pub = JSON.parse message.data
                            
                            if pub.type == "PRIVMSG"
                                output = """
                                    :#{pub.nick}!USER@127.0.0.1 PRIVMSG #{pub.chan} #{pub.message}\r\n
                                """
        
                            if pub.type == "PART"
                                output = """
                                    :#{pub.nick}!USER@127.0.0.1 PART #{pub.chan} #{pub.message}\r\n
                                """          
                            
                            if pub.type == "QUIT"
                                output = """
                                    :#{pub.nick}!USER@127.0.0.1 QUIT\r\n
                                """     
                            if pub.type == "JOIN"
                                output = """
                                    :#{pub.nick}!USER@127.0.0.1 JOIN #{pub.chan}\r\n
                                """
                            
                            try
                                unless pub.nick == user.nick && pub.type == "PRIVMSG"
                                    users[user.nick].stream.write output 
                            catch e
                                console.log e
                            console.log "OUTPUT #{output}"  
                    output = """
                        :#{user.host} 331 #{user.nick} #{chan} :No topic is set
                        :#{user.host} 353 #{user.nick} = #{chan} :#{nicks}
                        :#{user.host} 366 #{user.nick} #{chan} :End of /NAMES list.\r\n
                    """
                    console.log output
                    users[user.nick].stream.write output
    
        input = line.split ' ', 3       
        if input[0] == "PRIVMSG"
            chan = input[1]
            message = line.match(/.*? .*? (.*)/)[1]
            pub.nick = user.nick
            pub.message = message
            pub.chan = chan
            pub.type = "PRIVMSG"
            connection.publish chan, JSON.stringify pub
            console.log "pushed message to queue: #{JSON.stringify pub}"
        
        if input[0] == "QUIT"
            pub.nick = user.nick
            pub.type = "QUIT"
            for conn in Object.keys(user.connection)
                user.connection[conn].end()
                console.log "Closing connections for #{user.nick}"
            connection.publish '*', JSON.stringify pub

        
        if input[0] == "PART"
            pub.nick = user.nick
            pub.chan = input[1]
            pub.type = "PART"
            connection.publish input[1], JSON.stringify pub
            
        
            

        console.log line.toString()
    stream.on 'end', ->
        pub.nick = user.nick
        pub.type = "QUIT"
        connection.publish '*', JSON.stringify pub
        console.log "DISCONNECTED"
        
server = net.createServer(stream)
server.listen 6667

