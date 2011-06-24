var fs = require('fs'), net = require('net'), irc = {}, config;
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

// socket stuff
irc.socket = new net.Socket();
irc.socket.on('connect', function(){
	console.log('hooray');
	if (config.server.pass) irc.sendRaw('PASS ' + config.server.pass);
	irc.sendRaw('NICK ' + config.bot.nick);
	irc.sendRaw('USER ' + config.bot.user + ' 0 * :' + config.bot.real);
});
irc.socket.on('data', function(data){
	data = data.split('\r\n');
	for (var i = 0; i < data.length; i++) {
		console.log('[' + config.server.host + '] << ' + data[i]);
		irc.handle(data[i]);
	}
});

irc.socket.setEncoding('utf8');
irc.socket.setNoDelay();
irc.socket.connect(config.server.port, config.server.host);

// handler
irc.handle = function(data){
	if (data[0] != ':') {
		data = data.split(' ');
		if (data[0] == 'PING') irc.sendRaw('PONG ' + data[1]);
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
					irc.sendRaw('PONG :' + msg);
					break;
				case 'PRIVMSG':
					if (msg[0] == String.fromCharCode(1) && msg.substr(-1) == String.fromCharCode(1)) {
						// ctcp handlers
						irc.onCtcp(data, msg);
						return;
					}
					break;
			}
			irc.onMessage(data, msg);
		} else {
			switch (data[1]) {
				case '376': // End of /MOTD command.
				case '422': // MOTD File is missing
					irc.sendRaw('MODE ' + config.bot.nick + ' +B'); // I'm a bot!
					for (var i in config.channels) irc.sendRaw('JOIN ' + config.channels[i]);
					break;
			}
			irc.onServerMessage(data, msg);
		}
	}
}

irc.sendRaw = function(data){
	irc.socket.write(data + '\r\n', 'utf8', function(){
		console.log('[' + config.server.host + '] >> ' + data);
	});
}

irc.onMessage = function(data, msg){
}

irc.onCtcp = function(data, msg){
}

irc.onServerMessage = function(data, msg){
}
