# includes
fs = require 'fs'
coffee = require 'coffee-script'

# 1: read config file
try
	config = fs.readFileSync "#{__dirname}/config.json", 'utf8'
catch e
	console.error "[ERROR] config.json: #{e.message}"
	console.error "[ERROR] config.json: error opening file"
	process.exit 1

# 2: parse it
try
	config = JSON.parse config
catch e
	console.error "[ERROR] config.json: #{e.message}"
	console.error "[ERROR] config.json: error parsing file"
	process.exit 1

# ModuleHandler class
class ModuleHandler
	constructor: (@bot) ->
		@commands = {}
		@modules = {}
	
	require: (module) ->
		try
			path = require.resolve module
		catch e
			console.warn "[#{@bot.id}] ModuleHandler: ERROR! [#{module}]: #{e.message}"
			return false
		
		delete require.cache[path]
		require(module)
	
	load: (module) ->
		# set up module
		m = new @require(module)
		m._events = {}
		m.bot = @bot
		m.on = (event, handler) => (m._events[event] ?= []).push handler
		m.cmd = (command, handler) =>
			throw "command '#{command}' already registered" if @commands[command]?
			@commands[command] = {module: m, func: handler}
		m.require = @require
		# load it!
		try
			m.module.call m
		catch e
			console.warn "[#{@bot.id}] ModuleHandler: ERROR! #{module}: failed to init module"
			console.warn "[#{@bot.id}] ModuleHandler: ERROR! #{module}: #{e.message}"
			return false
		@modules[module] = m
		console.log "[#{@bot.id}] ModuleHandler: loaded '#{module}'"
		return true
	
	reload: ->
		@load module for module of @modules
		return
	
	emit: (event, args...) ->
		for $, module of @modules
			if module._events[event]?
				try
					handler.apply module, args for handler in module._events[event]
				catch e
					console.warn "[#{@bot.id}] ModuleHandler: ERROR! #{module}: error in event '#{event}'"
					console.warn "[#{@bot.id}] ModuleHandler: ERROR! #{module}: #{e.message}"
		return

# IRC class
class IRC
	_modes = '~&@%+'
	
	constructor: (@bot) ->
		@channels = {}
		@users = {}
		@_buffer =
			in: ''
			out:
				queue: []
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
			# socket settings
			@socket.setNoDelay()
			@socket.setEncoding 'utf8'
			
			# irc auth
			@sendRaw "PASS #{server.pass}" if server.pass isnt ''
			@sendRaw "NICK #{@bot.config.bot.nick}"
			@sendRaw "USER #{@bot.config.bot.user} 0 * :#{@bot.config.bot.real}"
			@bot.nick = @bot.config.bot.nick
			return
		
		@socket.on 'data', (data) =>
			lines = (@_buffer.in + data).split '\r\n'
			@_buffer.in = lines.pop()
			for line in lines
				console.log "[#{server.host}] >> #{line}"
				@_handle line
			return
		
		# done!
		true
	
	sendRaw: (data) ->
		@socket.write data + '\r\n', 'utf8', =>
			console.log "[#{@bot.config.server.host}] << #{data}"
	
	getChannel: (channel) ->
		@channels[channel.toLowerCase()] ?= {created: 0, topic: {text: '', user: '', time: ''}, users: {}, modes: []}
	
	getUser: (nick) ->
		@users[nick.toLowerCase()] ?= {ident: '', host: '', server: '', nick: '', away: false, modes: [], hops: 0, real: ''}
	
	_setUser: (data) ->
		@users[data.nick.toLowerCase()] = data
	
	privmsg: (to, msg) ->
		@sendRaw "PRIVMSG #{to} :#{msg}"
	
	action: (to, action) ->
		@privmsg to, "\x01ACTION #{action}\x01"
	
	notice: (to, msg) ->
		@sendRaw "NOTICE #{to} :#{msg}"
	
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
						delete @users[oldnick]
						@sendRaw "WHOIS #{newnick}"
						
						# emit
						@bot.modules.emit 'nick', from, msg
					
					# NOTICE #
					when 'NOTICE'
						if from.nick == 'NickServ' and msg.indexOf('IDENTIFY') isnt -1
							@privmsg 'NickServ', "IDENTIFY #{@bot.config.bot.pass}" if @bot.config.bot.pass isnt ''
					
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
						@privmsg 'NickServ', "IDENTIFY #{@bot.config.bot.pass}" if @bot.config.bot.pass isnt ''
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
					
					when '311' # RPL_WHOISUSER
						user = @getUser data[3]
						user.nick  = data[3]
						user.ident = data[4]
						user.host  = data[5]
						user.real  = msg
						@_setUser user
					when '307' # "is a registered nick"
						user = @getUser data[3]
						if !~user.modes.indexOf 'r'
							user.modes.push 'r'
							@_setUser user
					when '319' # RPL_WHOISCHANNELS
						;
					when '312' # RPL_WHOISSERVER
						user = @getUser data[3]
						user.server = data[4]
						@_setUser user
					when '301' # RPL_AWAY
						user = @getUser data[3]
						user.away = true
						@_setUser user
					when '313' # RPL_WHOISOPERATOR
						;
					when '671' # "is using a Secure Connection"
						;
					when '317' # RPL_WHOISIDLE
						;
					when '318' # RPL_ENDOFWHOIS
						;
				
				@bot.modules.emit 'serverMsg', data, msg
		return

# bot class
class bot
	constructor: (@id, @config) ->
		@modules = new ModuleHandler(@)
		@modules.load module for module in @config.modules
	
	connect: ->
		@irc = new IRC(@)

# init
bots = {}
for id, settings of config
	(bots[id] = new bot(id, settings)).connect()
