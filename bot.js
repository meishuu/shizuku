var fs = require('fs'), net = require('net'), tls = require('tls');
var irc = require('./classes/irc.js'), config;
try {
	config = fs.readFileSync('config.json', 'utf8');
} catch (e) {
	console.error('[ERROR] config.json: ' + e.message);
	console.error('[ERROR] config.json: error opening file');
	process.exit(1);
}
config = JSON.parse(config);
/* JSON.parse()'s error is probably more informative
try {
	config = JSON.parse(config);
} catch (e) {
	console.log(e);
	console.error('[ERROR] config.json: ' + e.message);
	console.error('[ERROR] config.json: error parsing file');
	process.exit(1);
}
*/

// TODO: bot class
var bot = function(config){
	this.config = config;
};
bot.prototype = {
	modules: {emit: function(){}},
	
	connect: function(){
		this.irc = irc.init(this);
	},
};

// init
var bots = {};
for (var name in config) {
	bots[name] = new bot(config[name]);
	bots[name].connect();
}
