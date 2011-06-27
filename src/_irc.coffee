class IRC
	constructor: (@bot) ->
		@buffer = ''
		@channels = {}
		@connect @bot.config.server
	
	connect: (server) ->
		# init connection
		if server.ssl
			@socket = require('tls').connect server.port, server.host, () =>
				@socket.emit 'connect'
		else
			@socket = require('net').createConnection server.port, server.host
		
		# event handlers
		@socket.on 'connect', () =>
			# setings
			@socket.setNoDelay()
			@socket.setEncoding 'utf8'
			
			# irc auth
			@sendRaw "PASS #{server.pass}" if server.pass isnt ''
			@sendRaw "NICK #{@bot.config.bot.nick}"
			@sendRaw "USER #{@bot.config.bot.user} 0 * :#{@bot.config.bot.real}"
			return
		
		@socket.on 'data', (data) =>
			lines = (@buffer + data).split '\r\n'
			@buffer = lines.pop()
			for line in lines
				console.log "[#{server.host}] >> #{line}"
				@handle line
			return
		
		# done!
		return
	
	sendRaw: (data) ->
		@socket.write data + '\r\n', 'utf8', () =>
			console.log "[#{@bot.config.server.host}] << #{data}"
	
	getChannel: (channel) ->
		@channels[channel.toLowerCase()] ?= {topic: {text: '', user: '', time: ''}, users: {}}
	
	handle: (data) ->
		if data[0] isnt ':' # server command
			data = data.split ' '
			@sendRaw "PONG #{data[1]}" if data[0] is 'PING'
		else
			[data, msg] = data.substr(1).split(':', 2)
			data = data.split ' '
			
			# client command
			if isNaN(parseInt(data[1]))
				[from, cmd, to] = data
				match = from.match /(.+)!(.+)@(.+)/
				from = {
					full:  from,
					nick:  if match? then match[1] else '',
					ident: if match? then match[2] else '',
					host:  if match? then match[3] else '',
				}
				
				switch cmd
					when 'PRIVMSG'
						if msg[0] == msg.substr(-1) == '\x01'
							@bot.modules.emit 'onCtcp', from, to, msg.substr(1, -1)
						else
							@bot.modules.emit 'onPrivmsg', from, to, msg
				
				@bot.modules.emit 'onClientMsg', data, cmd, to, msg
			
			# server command
			else
				switch data[1]
					when '376', '422' # "End of /MOTD command." or "MOTD File is missing"
						@sendRaw "MODE #{@bot.config.bot.nick} +B" # I'm a bot!
						for c in @bot.config.channels
							[chan, key] = c.split ','
							@sendRaw "JOIN #{chan} #{key || ''}"
					
					when '331' # RPL_NOTOPIC
						@getChannel(data[3]).topic = {text: '', user: '', time: ''}
					when '332' # RPL_TOPIC
						@getChannel(data[3]).topic.text = msg
					when '333'
						topic = @getChannel(data[3]).topic
						topic.user = data[4]
						topic.time = data[5]
					
					when '353' # RPL_NAMREPLY
						users = @getChannel(data[4]).users
						for nick in msg.split ' '
							if nick isnt ''
								nick = nick.split ''
								# parse user modes
								modes = while '~&@%+'.indexOf(nick[0]) isnt -1
									nick.shift()
								# init object in users[] array
								users[nick.join('').toLowerCase()] =
									modes: modes
									server: ''
									ident: ''
									real: ''
									host: ''
					when '366' # RPL_ENDOFNAMES
						@getChannel(data[3]).users = {}
						@sendRaw "WHO #{data[3]}"
					
					when '352' # RPL_WHOREPLY
						user = (@getChannel(data[3]).users[data[7].toLowerCase()] ?= {})
						user.ident  = data[4]
						user.host   = data[5]
						user.server = data[6]
						user.real   = msg.split(' ', 2)[1]
					when '315' # RPL_ENDOFWHO
						;
				
				@bot.modules.emit 'onServerMsg', data, msg
		return
