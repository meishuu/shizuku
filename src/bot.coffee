# includes
fs = require 'fs'

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
		@modules = {}
	
	load: (module) ->
		# kill cache from require
		delete require.cache[require.resolve module]
		# set up module
		m = new require(module)
		m._events = {}
		m.bot = @bot
		m.on = (event, handler) =>
			m._events[event] ?= []
			m._events[event].push handler
		# load it!
		try
			m.module.call m
		catch e
			console.log "[#{@bot.id}] ModuleHandler: ERROR! #{e.message}"
			console.log "[#{@bot.id}] ModuleHandler: ERROR! failed to load '#{module}'"
			return false
		@modules[module] = m
		console.log "[#{@bot.id}] ModuleHandler: loaded '#{module}'"
	
	reload: ->
		@load module for module of @modules
		return
	
	emit: (event, args...) ->
		for $, module of @modules
			if module._events[event]?
				handler.apply module, args for handler in module._events[event]
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
