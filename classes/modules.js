exports.init = function(bot){
	return new ModuleHandler(bot);
}

var ModuleHandler = function(bot){
	this._bot = bot;
	this._modules = {};
}

ModuleHandler.prototype.load = function(module){
	var path = require.resolve(module);
	delete require.cache[path];
	this._modules[module] = require(module).init(this._bot);
	console.log('loaded module "' + module + '"');
}

ModuleHandler.prototype.reload = function(){
	for (var i in this._modules) this.load(i);
}

ModuleHandler.prototype.emit = function(event, data){
	for (var i in this._modules) this._modules[i].on(event, data);
}
