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
	
	joinChannel: (channel, key = '') ->
		@channels[channel.toLowerCase()] = {topic: {}, users: {}}
		@sendRaw "JOIN #{channel} #{key}"
	
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
							@bot.modules.emit 'onCtcp', [from, to, msg.substr(1, -1)]
						else
							@bot.modules.emit 'onPrivmsg', [from, to, msg]
				
				@bot.modules.emit 'onClientMsg', [data, cmd, to, msg]
			
			# server command
			else
				switch data[1]
					when '331' # RPL_NOTOPIC
						@channels[data[3].toLowerCase()].topic = {text: '', user: '', time: ''}
					when '332' # RPL_TOPIC
						@channels[data[3].toLowerCase()].topic.text ?= msg
					when '333'
						topic = @channels[data[3].toLowerCase()].topic
						topic.user = data[4]
						topic.time = data[5]
					
					when '353' # RPL_NAMREPLY
						users = (@channels[data[4].toLowerCase()].users ?= {})
						for nick in msg.split(' ')
							if nick isnt ''
								if '~&@%+'.indexOf(nick[0]) isnt -1
									users[nick.substr(1)] = nick[0]
								else
									users[nick] = ''
					when '366' # RPL_ENDOFNAMES
						# we should probably do a WHO on the channel here
						;
					
					when '376', '422' # "End of /MOTD command." or "MOTD File is missing"
						@sendRaw "MODE #{ @bot.config.bot.nick } +B" # I'm a bot!
						@joinChannel channel for channel in @bot.config.channels
				
				@bot.modules.emit 'onServerMsg', [data, msg]
		return
