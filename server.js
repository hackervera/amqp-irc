(function() {
  var User, amqp, carrier, channel, host, net, server, stream, streams, users;
  net = require('net');
  amqp = require('./node-amqp');
  host = require('./config').info.server;
  console.log(host);
  User = (function() {
    function User() {}
    return User;
  })();
  channel = {};
  streams = [];
  users = {};
  carrier = require('carrier');
  stream = function(stream) {
    var carry, connection, pub, user;
    carry = carrier.carry(stream);
    user = new User;
    pub = {};
    connection = null;
    user.channel = {};
    user.connection = {};
    user.joined = [];
    user.stream = stream;
    carry.on('line', function(line) {
      var chan, chans, conn, input, message, _fn, _i, _j, _len, _len2, _ref;
      input = line.split(' ');
      if (input[0] === "NICK") {
        if (user.nick != null) {
          delete users[user.nick];
        }
        user.nick = input[1];
        users[user.nick] = user;
        console.log("NICKS:");
      }
      if (input[0] === "USER") {
        console.log("GOT USER");
        user.host = input[3];
        try {
          stream.write(":" + user.host + " 001 " + user.nick + " Hello " + user.nick + "!\r\n");
        } catch (e) {
          console.log(e);
        }
        console.log("User host: " + user.host);
      }
      if (input[0] === "JOIN") {
        chans = input[1].split(",");
        _fn = function(chan) {
          var nick, nicks, output, _i, _len, _ref, _ref2;
          (_ref = channel[chan]) != null ? _ref : channel[chan] = {};
          channel[chan][user.nick] = user;
          nicks = Object.keys(channel[chan]).join(' ');
          _ref2 = nicks.split(' ');
          for (_i = 0, _len = _ref2.length; _i < _len; _i++) {
            nick = _ref2[_i];
            stream.write(":" + user.host + " 352 " + user.nick + " " + chan + " ~freenode staff.barbird.com anthony.freenode.net " + nick + " H :0 ir\r\n");
          }
          stream.write(":" + user.host + " 315 " + user.nick + " " + chan + " :End of /WHO list.\r\n");
          stream.write(":" + user.host + " 368 " + user.nick + " " + chan + " :End of Channel Ban List\r\n");
          connection = user.connection[chan] = amqp.createConnection({
            host: host
          });
          try {
            console.log('foo');
          } catch (e) {
            console.log(e);
          }
          output = ":" + user.host + " 331 " + user.nick + " " + chan + " :No topic is set\n:" + user.host + " 353 " + user.nick + " = " + chan + " :" + nicks + "\n:" + user.host + " 366 " + user.nick + " " + chan + " :End of /NAMES list.\r\n";
          console.log(output);
          try {
            user.stream.write(output);
          } catch (e) {
            console.log(e);
          }
          return connection.on('ready', function() {
            var q;
            pub.nick = user.nick;
            pub.chan = chan;
            pub.type = "JOIN";
            connection.publish(chan, JSON.stringify(pub));
            q = connection.queue("" + user.nick + ":" + chan, {
              autoDelete: false
            });
            q.bind(chan);
            return q.subscribe(function(message) {
              pub = JSON.parse(message.data);
              if (pub.type === "PRIVMSG") {
                if (pub.message.charAt(0) !== ":") {
                  pub.message = ":" + pub.message;
                }
                output = ":" + pub.nick + "!USER@127.0.0.1 PRIVMSG " + pub.chan + " " + pub.message + "\r\n";
              }
              if (pub.type === "PART") {
                output = ":" + pub.nick + "!USER@127.0.0.1 PART " + pub.chan + " " + pub.message + "\r\n";
              }
              if (pub.type === "QUIT") {
                output = ":" + pub.nick + "!USER@127.0.0.1 QUIT\r\n";
              }
              if (pub.type === "JOIN") {
                output = ":" + pub.nick + "!USER@127.0.0.1 JOIN " + pub.chan + "\r\n";
              }
              try {
                if (!(pub.nick === user.nick && pub.type === "PRIVMSG")) {
                  users[user.nick].stream.write(output);
                }
              } catch (e) {
                console.log(e);
              }
              return console.log("OUTPUT " + output);
            });
          });
        };
        for (_i = 0, _len = chans.length; _i < _len; _i++) {
          chan = chans[_i];
          _fn(chan);
        }
      }
      input = line.split(' ', 3);
      if (input[0] === "PRIVMSG") {
        chan = input[1];
        message = line.match(/.*? .*? (.*)/)[1];
        pub.nick = user.nick;
        pub.message = message;
        pub.chan = chan;
        pub.type = "PRIVMSG";
        try {
          connection.publish(chan, JSON.stringify(pub));
        } catch (e) {
          console.log(e);
        }
        console.log("pushed message to queue: " + (JSON.stringify(pub)));
      }
      if (input[0] === "QUIT") {
        pub.nick = user.nick;
        pub.type = "QUIT";
        user.stream.write(":" + user.nick + "!* QUIT\r\n");
        try {
          connection.publish('*', JSON.stringify(pub));
        } catch (e) {
          console.log(e);
        }
        _ref = Object.keys(user.connection);
        for (_j = 0, _len2 = _ref.length; _j < _len2; _j++) {
          conn = _ref[_j];
          user.connection[conn].end();
          console.log("Closing connections for " + user.nick);
        }
        stream.end();
      }
      if (input[0] === "PART") {
        pub.nick = user.nick;
        pub.chan = input[1];
        pub.type = "PART";
        user.stream.write(":" + user.nick + "!* PART " + input[1] + "\r\n");
        try {
          connection.publish(input[1], JSON.stringify(pub));
        } catch (e) {
          console.log(e);
        }
        user.connection[input[1]].end();
      }
      return console.log(line.toString());
    });
    return stream.on('end', function() {
      var conn, _i, _len, _ref;
      _ref = Object.keys(user.connection);
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        conn = _ref[_i];
        user.connection[conn].end();
      }
      pub.nick = user.nick;
      pub.type = "QUIT";
      return console.log("DISCONNECTED");
    });
  };
  server = net.createServer(stream);
  server.listen(8080);
}).call(this);
