net = require 'net'
redis = require 'redis'
amqp = require './node-amqp'
client = redis.createClient()
host = require('./config').info.server
console.log host
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
            try
                stream.write ":#{user.host} 001 #{user.nick} Hello #{user.nick}!\r\n"
            catch e
                console.log e
            console.log "User host: #{user.host}"
        
        if input[0] == "JOIN"
            chans = input[1].split ","
            for chan in chans
                do (chan)->
                    channel[chan] ?= {}
                    channel[chan][user.nick] = user
                    nicks = Object.keys(channel[chan]).join(' ')
                    
                    for nick in nicks.split(' ')
                        stream.write ":#{user.host} 352 #{user.nick} #{chan} ~freenode staff.barbird.com anthony.freenode.net #{nick} H :0 ir\r\n"
                    stream.write ":#{user.host} 315 #{user.nick} #{chan} :End of /WHO list.\r\n"
                    stream.write ":#{user.host} 368 #{user.nick} #{chan} :End of Channel Ban List\r\n"
                    connection = user.connection[chan] = amqp.createConnection({host: host})
                    
                    try
                       #user.stream.write ":#{user.nick}!* JOIN #{chan}\r\n"
                       console.log 'foo'
                    catch e
                        console.log e
                    output = """
                        :#{user.host} 331 #{user.nick} #{chan} :No topic is set
                        :#{user.host} 353 #{user.nick} = #{chan} :#{nicks}
                        :#{user.host} 366 #{user.nick} #{chan} :End of /NAMES list.\r\n
                    """
                    console.log output
                    try
                        user.stream.write output
                    catch e
                        console.log e
                    
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
                                if pub.message.charAt(0) != ":"
                                    pub.message = ":#{pub.message}"
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

    
        input = line.split ' ', 3       
        if input[0] == "PRIVMSG"
            chan = input[1]
            message = line.match(/.*? .*? (.*)/)[1]
            pub.nick = user.nick
            pub.message = message
            pub.chan = chan
            pub.type = "PRIVMSG"
            try
                connection.publish chan, JSON.stringify pub
            catch e
                console.log e
            console.log "pushed message to queue: #{JSON.stringify pub}"
        
        if input[0] == "QUIT"
            pub.nick = user.nick
            pub.type = "QUIT"
            user.stream.write ":#{user.nick}!* QUIT\r\n"
            
            try
                connection.publish '*', JSON.stringify pub
            catch e
                console.log e
            for conn in Object.keys(user.connection)
                user.connection[conn].end()
                console.log "Closing connections for #{user.nick}"
            stream.end()

        
        if input[0] == "PART"
            
            pub.nick = user.nick
            pub.chan = input[1]
            pub.type = "PART"
            user.stream.write ":#{user.nick}!* PART #{input[1]}\r\n"
            try
                connection.publish input[1], JSON.stringify pub
            catch e
                console.log e
            user.connection[input[1]].end()

        console.log line.toString()
    stream.on 'end', ->
        for conn in Object.keys(user.connection)
                user.connection[conn].end()
        pub.nick = user.nick
        pub.type = "QUIT"
        #connection.publish '*', JSON.stringify pub
        console.log "DISCONNECTED"
        
server = net.createServer(stream)
server.listen 6667

