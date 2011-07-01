_modes = '~&@%+'

class IRC
	constructor: (@bot) ->
		@_buffer = ''
		@channels = {}
		@users = {}
		@_connect @bot.config.server
	
	_connect: (server) ->
		# init connection
		if server.ssl
			@socket = require('tls').connect server.port, server.host, =>
				@socket.emit 'connect'
		else
			@socket = require('net').createConnection server.port, server.host
		
		# event handlers
		@socket.on 'connect', =>
			# setings
			@socket.setNoDelay()
			@socket.setEncoding 'utf8'
			
			# irc auth
			@sendRaw "PASS #{server.pass}" if server.pass isnt ''
			@sendRaw "NICK #{@bot.config.bot.nick}"
			@sendRaw "USER #{@bot.config.bot.user} 0 * :#{@bot.config.bot.real}"
			@bot.nick = @bot.config.bot.nick
			return
		
		@socket.on 'data', (data) =>
			lines = (@_buffer + data).split '\r\n'
			@_buffer = lines.pop()
			for line in lines
				console.log "[#{server.host}] >> #{line}"
				@_handle line
			return
		
		# done!
		return
	
	sendRaw: (data) ->
		@socket.write data + '\r\n', 'utf8', =>
			console.log "[#{@bot.config.server.host}] << #{data}"
	
	getChannel: (channel) ->
		@channels[channel.toLowerCase()] ?= {created: 0, topic: {text: '', user: '', time: ''}, users: {}, modes: []}
	
	getUser: (nick) ->
		@users[nick.toLowerCase()] ?= {ident: '', host: '', server: '', nick: '', away: false, modes: [], hops: 0, real: ''}
	
	privmsg: (to, msg) ->
		@sendRaw "PRIVMSG #{to} :#{msg}"
	
	action: (to, action) ->
		@privmsg to, "\x01ACTION #{action}\x01"
	
	_handle: (data) ->
		if data[0] isnt ':' # server command
			data = data.split ' '
			@sendRaw "PONG #{data[1]}" if data[0] is 'PING'
		else
			if (pos = (data = data.substr 1).indexOf ' :') isnt -1
				msg = data.substr pos + 2
				data = data.substr 0, pos
			
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
					# JOIN #
					when 'JOIN'
						break if from.nick isnt @bot.nick
						@sendRaw "MODE #{msg}"
						@sendRaw "WHO #{msg}"
					
					# KICK #
					when 'KICK'
						if data[3] == @bot.nick
							delete @channels[data[2].toLowerCase()]
						else
							channel = @getChannel data[2]
							delete channel.users[data[3].toLowerCase()]
					
					when 'MODE'
						if (channel = data[2])[0] == '#'
							@sendRaw "MODE #{data[2]}"
							@sendRaw "NAMES #{data[2]}"
					
					# NICK #
					when 'NICK'
						oldnick = from.nick.toLowerCase()
						newnick = msg.toLowerCase()
						
						# update @bot.nick
						@bot.nick = msg if from.nick == @bot.nick
						
						# update @channels
						for $, channel of @channels
							if (mode = channel.users[oldnick])?
								channel.users[newnick] = mode
								delete channel.users[oldnick]
						
						# update @users
						@users[newnick] = @getUser oldnick
						delete @users[oldnick]
						
						# emit
						@bot.modules.emit 'nick', from, msg
					
					# PRIVMSG #
					when 'PRIVMSG'
						if msg[0] == msg.substr(-1) == '\x01'
							@bot.modules.emit 'ctcp', from, to, msg.substring(1, msg.length - 1)
						else
							@bot.modules.emit 'privmsg', from, to, msg
					
					# QUIT #
					when 'QUIT'
						user = from.nick.toLowerCase()
						delete @users[user]
						(delete channel.users[user] if channel.users[user]?) for $, channel of @channels
					
					# else #
					else
						@bot.modules.emit cmd.toLowerCase(), from, to, msg
				
				@bot.modules.emit 'clientMsg', data, cmd, to, msg
			
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
					
					when '324' # RPL_CHANNELMODES
						# TODO: actually parse this
						@getChannel(data[3]).modes = data[4].substr(1).split('')
					when '329' # RPL_CREATIONTIME
						@getChannel(data[3]).created = data[4]
					
					when '353' # RPL_NAMREPLY
						users = @getChannel(data[4]).users
						for nick in msg.split ' '
							if nick isnt ''
								# separate out user modes
								nick = nick.split ''
								modes = while _modes.indexOf(nick[0]) isnt -1
									nick.shift()
								# add to channel.users[] array
								users[nick.join('').toLowerCase()] = modes
					when '366' # RPL_ENDOFNAMES
						;
					
					when '352' # RPL_WHOREPLY
						modestr = data[8].split ''
						away = modestr.shift() == 'G'
						modes = (mode for mode in modestr when _modes.indexOf(mode) is -1)
						[hops, real...] = msg.split ' '
						@users[data[7].toLowerCase()] =
							ident  : data[4]
							host   : data[5]
							server : data[6]
							nick   : data[7]
							away   : away
							modes  : modes
							hops   : parseInt hops
							real   : real.join ' '
					when '315' # RPL_ENDOFWHO
						;
				
				@bot.modules.emit 'serverMsg', data, msg
		return
