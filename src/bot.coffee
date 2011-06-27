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
		path = require.resolve module
		delete require.cache[path]
		@modules[module] = require(module).init(@bot)
		console.log "loaded module '#{module}'"
	
	reload: ->
		this.load module for module in @modules
		return
	
	emit: (event, data) ->
		for $, module of @modules
			module[event].apply module, data if module[event]?

# bot class
class bot
	constructor: (@config) ->
		@modules = new ModuleHandler(this)
		@modules.load module for module in @config.modules
	
	connect: ->
		@irc = new IRC(this)

# init
bots = {}
for id, settings of config
	(bots[id] = new bot(settings)).connect()
