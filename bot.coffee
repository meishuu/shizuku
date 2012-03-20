# includes
require 'coffee-script'

fs = require 'fs'
yaml = require "#{__dirname}/lib/yaml"
global.$util = require "#{__dirname}/lib/util"

# 1: read config file
try
	config = fs.readFileSync "#{__dirname}/config.yml", 'utf8'
catch e
	console.error "[ERROR] config: #{e.message}"
	console.error "[ERROR] config: error opening file"
	process.exit 1

# 2: parse it
try
	config = yaml.eval config
catch e
	console.error "[ERROR] config: #{e.message}"
	console.error "[ERROR] config: error parsing file"
	process.exit 1

#################
# ModuleHandler #
#################
class ModuleHandler
	constructor: (@bot) ->
		@commands = {}
		@modules = {}
	
	require: (module, reload = false) ->
		try
			path = require.resolve module
		catch e
			console.warn "[#{@bot.id}] ModuleHandler: ERROR! [#{module}]: #{e.message}"
			return false
		
		delete require.cache[path] if reload
		require(module)
	
	load: (module, reload = false) ->
		# set up module
		m =
			_events: {}
			bot: @bot
			on: (event, handler) -> (m._events[event] ?= []).push handler
			cmd: (command, handler) =>
				cmd = command.toLowerCase()
				throw "command '#{command}' already registered to another module" if @commands[cmd]?.module is m
				@commands[cmd] = {module: m, func: handler}
			module: @require(module, reload).module
		
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
	
	reload: (modules) ->
		@load module, true for module in (if modules? then [].concat modules else @modules)
		return
	
	emit: (event, args...) ->
		for name, module of @modules
			if module._events[event]?
				try
					handler.apply module, args for handler in module._events[event]
				catch e
					console.warn "[#{@bot.id}] ModuleHandler: ERROR! #{name}: error in event '#{event}'"
					console.warn "[#{@bot.id}] ModuleHandler: ERROR! #{name}: #{e.message}"
		return
	
	command: (from, to, msg) ->
		args = msg.split(' ')
		cmd = args[0].substr(1).toLowerCase()
		return if !(data = @commands[cmd])?
		try
			data.func.call data.module, from, to, {args, cmd, msg}
		catch e
			console.warn e
			console.warn "[#{@bot.id}] ModuleHandler: ERROR! #{data.module}: error in command '#{cmd}'"
			console.warn "[#{@bot.id}] ModuleHandler: ERROR! #{data.module}: #{e.message}"
		return

#######
# IRC #
#######
class IRC
	_modes = '~&@%+'
	
	constructor: (@bot) ->
		@channels = {}
		@users = {}
		@_buffer =
			in: ''
			out:
				prev_now: 0
				next_send: 0
				data: []
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
	
	_sendQueue: ->
		t = Date.now()
		sendq = @_buffer.out
		
		while sendq.data.length > 0
			# if next_send is in the past, we're safe to send messages.
			# update next_send to the current timestamp as a minimum value
			if t > sendq.next_send
				sendq.next_send = t
			
			# if next_send is at least 10 seconds in the future, we should wait.
			# however, if it seems like we suddenly jumped into the past,
			# the clock time probably changed, so set next_send to the current time.
			if sendq.next_send - t > 10000
				if sendq.prev_now <= t
					setTimeout (@_sendQueue.bind @), 500
					return false
				else
					sendq.next_send = t
			
			# carry on, then
			line = sendq.data.shift()
			sendq.next_send += (2 + line.length / 120 | 0) * 1000
			sendq.prev_now = t
			@socket.write line, 'utf8', => console.log "[#{@bot.config.server.host}] << #{line[0...-2]}"
		
		# all done! queue is empty now.
		return true
	
	sendRaw: (data) ->
		line = (data + '')[0..509] + '\r\n'
		empty_queue = @_buffer.out.data.length is 0
		
		@_buffer.out.data.push line
		@_sendQueue() if empty_queue
	
	###########
	# Channel #
	###########
	class Channel
		constructor: ->
			@created = 0
			@topic =
				text: ''
				user: ''
				time: ''
			@users = {}
			@modes = []
	
	getChannel: (channel, create) ->
		chan = channel.toLowerCase()
		@channels[chan] ? (create && @channels[chan] = new Channel)
	
	########
	# User #
	########
	class User
		constructor: ->
			@ident  = ''
			@host   = ''
			@server = ''
			@nick   = ''
			@away   = false
			@modes  = []
			@hops   = 0
			@real   = ''
	
	getUser: (nick, create) ->
		nick = nick.toLowerCase()
		@users[nick] ? (create && @users[nick] = new User)
	
	privmsg: (to, msg) ->
		lines = (msg + '').split '\n' unless lines instanceof Array
		@sendRaw "PRIVMSG #{to} :#{line}" for line in lines
	
	action: (to, action) ->
		@privmsg to, "\x01ACTION #{action}\x01"
	
	notice: (to, msg) ->
		@sendRaw "NOTICE #{to} :#{msg}"
	
	reply: (from, to, msg) ->
		if to[0] is '#'
			@privmsg to, msg
		else
			@notice from.nick, msg
	
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
						@bot.modules.emit 'join', from, msg
						break if from.nick isnt @bot.nick
						@sendRaw "MODE #{msg}"
						@sendRaw "WHO #{msg}"
					
					# KICK #
					when 'KICK'
						if data[3] == @bot.nick
							delete @channels[data[2].toLowerCase()]
						else
							delete channel.users[data[3].toLowerCase()] if channel = @getChannel data[2]
					
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
						@bot.modules.emit 'notice', from, to, msg
						if from.nick == 'NickServ' and msg.indexOf('IDENTIFY') isnt -1
							@privmsg 'NickServ', "IDENTIFY #{@bot.config.bot.pass}" if @bot.config.bot.pass isnt ''
					
					# PRIVMSG #
					when 'PRIVMSG'
						if msg[0] == msg.substr(-1) == '\x01'
							@bot.modules.emit 'ctcp', from, to, msg.substring(1, msg.length - 1)
						else
							@bot.modules.emit 'privmsg', from, to, msg
							@bot.modules.command from, to, msg if msg[0] == @bot.config.config.trigger
					
					# QUIT #
					when 'QUIT'
						@bot.modules.emit 'quit', from
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
						@getChannel(data[3], true).topic = {text: '', user: '', time: ''}
					when '332' # RPL_TOPIC
						@getChannel(data[3], true).topic.text = msg
					when '333'
						{topic} = @getChannel data[3], true
						topic.user = data[4]
						topic.time = data[5]
					
					when '324' # RPL_CHANNELMODES
						# TODO: actually parse this
						@getChannel(data[3], true).modes = data[4].substr(1).split('')
					when '329' # RPL_CREATIONTIME
						@getChannel(data[3], true).created = data[4]
					
					when '353' # RPL_NAMREPLY
						{users} = @getChannel data[4], true
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
						user = @getUser data[3], true
						user.nick  = data[3]
						user.ident = data[4]
						user.host  = data[5]
						user.away  = false
						user.real  = msg
					when '307' # "is a registered nick"
						{modes} = @getUser data[3], true
						modes.push 'r' if !~modes.indexOf 'r'
					when '319' # RPL_WHOISCHANNELS
						;
					when '312' # RPL_WHOISSERVER
						@getUser(data[3], true).server = data[4]
					when '301' # RPL_AWAY
						@getUser(data[3], true).away = true
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

################
# UserSettings #
################
class UserSettings
	constructor: (bot) ->
		@users = {}
		@server = bot.id
		
		setInterval (=> @_saveUsers()), 300 * 1000 # 5 minutes
		
		folder = "#{__dirname}/data/users"
		fs.stat folder, (err, stats) =>
			fs.mkdirSync folder, 0644 if !stats.isDirectory()
			fs.readFile "#{folder}/#{@server}.json", 'utf8', (err, data) =>
				if err
					throw err if err.code isnt 'ENOENT'
					console.warn('[core_users] no users file for "#{@server}". creating...');
					@_saveUsers()
				else
					@users = JSON.parse data
	
	getUserID: (from) ->
		return from.toLowerCase() if typeof(from) is 'string'
		try
			return require('core_auth').getUserID(from, @server)
		catch e
			return from.nick.toLowerCase()
	
	getUserSetting: (from, module, setting, default_val) ->
		return default_val if (user = @getUserID from) is false
		_get(@users, [user, module, setting]) ? default_val
	
	setUserSetting: (from, module, setting, value) ->
		return false if (user = @getUserID from) is false
		_set @users, [user, module, setting], value
	
	_saveUsers: ->
		fs.writeFile "#{__dirname}/data/users/#{@server}.json", JSON.stringify(@users), (err) -> console.warn err if err
	
	_get = (obj, keys) ->
		obj = obj[keys.shift()] while keys.length and obj?
		obj
	
	_set = (obj, keys, val) ->
		final = keys.pop()
		obj = obj[key] ?= {} for key in keys
		obj[final] = val

#######
# bot #
#######
class bot
	constructor: (@id, @config) ->
		@irc = new IRC @
		@users = new UserSettings @
		@modules = new ModuleHandler @
		@modules.load module for module in @config.modules

# init
bots = {}
bots[id] = new bot id, settings for id, settings of config
