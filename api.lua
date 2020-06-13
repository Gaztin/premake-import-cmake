local p = premake
local m = p.extensions.impcmake

p.api.register {
	name  = 'cmakevariables',
	scope = 'config',
	kind  = 'key-mixed',
}

p.api.register {
	name  = 'cmakecache',
	scope = 'workspace',
	kind  = 'key-mixed',
}
