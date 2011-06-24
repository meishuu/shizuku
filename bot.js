var fs = require('fs');
var irc = require(__dirname + '/classes/irc.js'), config;
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

var bot = function(config){
	this.config = config;
	this.modules = require(__dirname + '/classes/modules.js').init(this);
	for (var i in config.modules) this.modules.load(config.modules[i]);
};
bot.prototype = {
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
