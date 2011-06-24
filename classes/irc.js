// irc class
var net = require('net'), tls = require('tls');

exports.init = function(bot){
	var irc = new IRC(bot);
	return irc;
};

function IRC(bot) {
	//if (!(this instanceof IRC)) return new IRC(bot);
	this.bot = bot;
	this.connect(bot.config.server);
};

IRC.prototype = {
	connect: function(server){
		var self = this;
		
		// init connection
		if (server.ssl) {
			// TODO: why can we only do one of these at a time?
			this.socket = tls.connect(server.port, server.host, function(){
				self.socket.emit('connect');
			});
		} else {
			this.socket = net.createConnection(server.port, server.host);
		}
		
		// event handlers
		this.socket.on('connect', function(){
			// settings
			self.socket.setNoDelay();
			self.socket.setEncoding('utf8');
			// irc auth
			if (server.pass) self.sendRaw('PASS ' + server.pass);
			self.sendRaw('NICK ' + self.bot.config.bot.nick);
			self.sendRaw('USER ' + self.bot.config.bot.user + ' 0 * :' + self.bot.config.bot.real);
		});
		
		this.socket.on('data', function(data){
			data = data.split('\r\n');
			for (var i = 0; i < data.length; i++) {
				console.log('[' + server.host + '] << ' + data[i]);
				self.handle(data[i]);
			}
		});
	},
	
	sendRaw: function(data){
		var host = this.bot.config.server.host;
		this.socket.write(data + '\r\n', 'utf8', function(){
			console.log('[' + host + '] >> ' + data);
		});
	},
	
	handle: function(data){
		if (data[0] != ':') {
			data = data.split(' ');
			if (data[0] == 'PING') this.sendRaw('PONG ' + data[1]);
		} else {
			data = data.substr(1);
			var pos = data.indexOf(':'), msg = '';
			if (!~pos) {
				data = data.split(' ');
			} else {
				msg = data.substr(pos + 1);
				data = data.substr(0, pos - 1).split(' ');
			}
			
			if (isNaN(parseInt(data[1]))) {
				switch (data[1]) {
					case 'PING':
						this.sendRaw('PONG :' + msg);
						break;
					case 'PRIVMSG':
						if (msg[0] == String.fromCharCode(1) && msg.substr(-1) == String.fromCharCode(1)) {
							// ctcp handlers
							this.bot.modules.emit('ctcp,' [data, msg]);
							return;
						}
						break;
				}
				this.bot.modules.emit('message', [data, msg]);
			} else {
				switch (data[1]) {
					case '376': // End of /MOTD command.
					case '422': // MOTD File is missing
						this.sendRaw('MODE ' + this.bot.config.bot.nick + ' +B'); // I'm a bot!
						for (var i in this.bot.config.channels) this.sendRaw('JOIN ' + this.bot.config.channels[i]);
						break;
				}
				this.bot.modules.emit('serverMessage', [data, msg]);
			}
		}
	},
};
