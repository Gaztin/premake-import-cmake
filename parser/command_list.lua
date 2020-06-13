local p         = premake
local m         = p.extensions.impcmake
local executors = { }

function m.executeCommand( cmd, condscope__refwrap )
	local executor = executors[ cmd.name ]
	if( executor ~= nil ) then
		executor( cmd, condscope__refwrap )
		return true
	else
		return false
	end
end

executors[ 'cmake_minimum_required' ] = function( cmd )
	-- TODO: Throw if higher than @m._LASTEST_CMAKE_VERSION
	m.downloadCMakeModules( m._LASTEST_CMAKE_VERSION )
end

executors[ 'project' ] = function( cmd )
	local groupName = cmd.arguments[ 1 ]

	group( groupName )
end

executors[ 'set' ] = function( cmd )
	local arguments    = table.arraycopy( cmd.arguments )
	local variableName = table.remove( arguments, 1 )
	local values       = { }
	local parentScope  = false
	local isCache      = false

	local i = 0
	while( i < #arguments ) do
		i = i + 1

		if( arguments[ i ] == 'PARENT_SCOPE' ) then
			parentScope = true

		elseif( arguments[ i ] == 'CACHE' ) then
			local entrytype = arguments[ i + 1 ]
			local docstring = arguments[ i + 2 ]
			local force     = false
			i = i + 2

			isCache = true

			while( i < #arguments ) do
				i = i + 1

				if( arguments[ i ] == 'FORCE' ) then
					force = true
				else
					p.warn( 'Unhandled cache option "%s" for command "%s"', arguments[ i ], cmd.name )
				end
			end

			if( cache_entries[ variableName ] == nil or force ) then
				cache_entries[ variableName ] = table.implode( values, '', '', ' ' )
			end

		else
			table.insert( values, m.resolveVariables( arguments[ i ] ) )
		end
	end

	if( not isCache ) then
		if( parentScope ) then
			p.warn( 'Unsupported option PARENT_SCOPE was declared for command "%s"', cmd.name )
		end

		cmakevariables {
			[ variableName ] = table.implode( values, '', '', ' ' ),
		}
	end
end

executors[ 'add_executable' ] = function( cmd )
	local arguments = cmd.arguments

	if( arguments[ 2 ] == 'IMPORTED' ) then

		p.error( 'Executable is an IMPORTED target, which is unsupported' )

	elseif( arguments[ 2 ] == 'ALIAS' ) then

		-- Add alias
		aliases[ arguments[ 1 ] ] = arguments[ 3 ]

	else
		local prj  = project( arguments[ 1 ] )
		prj._cmake = { }

		kind( 'ConsoleApp' )
		location( baseDir )

		for i=2,#arguments do
			if( arguments[ i ] == 'WIN32' ) then
				kind( 'WindowedApp' )
			elseif( arguments[ i ] == 'MACOSX_BUNDLE' ) then
				-- TODO: https://cmake.org/cmake/help/v3.0/prop_tgt/MACOSX_BUNDLE.html
			else
				local f = m.resolveVariables( arguments[ i ] )

				for _,v in ipairs( string.explode( f, ' ' ) ) do
					local rebasedSourceFile = path.rebase( v, baseDir, os.getcwd() )

					files { rebasedSourceFile }
				end
			end
		end
	end
end

executors[ 'add_library' ] = function( cmd )
	local arguments = table.arraycopy( cmd.arguments )

	if( table.contains( { 'STATIC', 'SHARED', 'MODULE' }, arguments[ 2 ] ) ) then

		-- Unused or unsupported modifiers
		if( arguments[ 3 ] == 'EXCLUDE_FROM_ALL' ) then
			table.remove( arguments, 3 )
		elseif( arguments[ 3 ] == 'IMPORTED' ) then
			p.error( 'Library uses unsupported modifier "%s"', arguments[ 3 ] )
		end

		local prj  = project( arguments[ 1 ] )
		prj._cmake = { }

		location( baseDir )

		-- Library type
		if( arguments[ 2 ] == 'STATIC' ) then
			kind( 'StaticLib' )
		elseif( arguments[ 2 ] == 'SHARED' ) then
			kind( 'SharedLib' )
		elseif( arguments[ 2 ] == 'MODULE' ) then
			p.error( 'Project uses unsupported library type "%s"', arguments[ 2 ] )
		end

		for i=3,#arguments do
			local f = m.resolveVariables( arguments[ i ] )

			for _,v in ipairs( string.explode( f, ' ' ) ) do
				local rebasedSourceFile = path.rebase( v, baseDir, os.getcwd() )

				files { rebasedSourceFile }
			end
		end

	elseif( arguments[ 2 ] == 'OBJECT' ) then

		p.error( 'Library is an object library, which is unsupported' )

	elseif( arguments[ 2 ] == 'ALIAS' ) then

		-- Add alias
		aliases[ arguments[ 1 ] ] = arguments[ 3 ]

	elseif( arguments[ 2 ] == 'INTERFACE' ) then

		p.error( 'Library is an interface library, which is unsupported' )

	end
end

executors[ 'target_include_directories' ] = function( cmd )
	local arguments      = table.arraycopy( cmd.arguments )
	local projectName    = resolveAlias( table.remove( arguments, 1 ) )
	local currentProject = p.api.scope.project
	local projectToAmend = p.workspace.findproject( p.api.scope.workspace, projectName )
	local modifiers      = { }

	-- Make sure project exists
	if( projectToAmend == nil ) then
		p.error( 'Project "%s" referenced in "%s" not found in workspace', addToProject, cmd.name )
	end

	-- Temporarily activate amended project
	p.api.scope.project = projectToAmend

	-- Add source files
	for _,arg in ipairs( arguments ) do
		if( table.contains( { 'SYSTEM', 'BEFORE', 'INTERFACE', 'PUBLIC', 'PRIVATE' }, arg ) ) then
			modifiers[ arg ] = true
		else
			local includeFunc = iif( modifiers[ 'SYSTEM' ] == true, sysincludedirs, includedirs )

			if( modifiers[ 'BEFORE'    ] == true ) then p.warn( 'Unhandled modifier "BEFORE" was specified for "target_include_directories"'    ) end
			if( modifiers[ 'INTERFACE' ] == true ) then p.warn( 'Unhandled modifier "INTERFACE" was specified for "target_include_directories"' ) end

			arg = m.resolveVariables( arg )

			for _,v in ipairs( string.explode( arg, ' ' ) ) do
				local rebasedIncludeDir = path.rebase( v, baseDir, os.getcwd() )

				includeFunc { rebasedIncludeDir }

				if( modifiers[ 'PUBLIC' ] == true ) then
					if( modifiers[ 'SYSTEM' ] == true ) then
						projectToAmend._cmake.publicsysincludedirs = projectToAmend._cmake.publicsysincludedirs or { }
						table.insert( projectToAmend._cmake.publicsysincludedirs, rebasedIncludeDir )
					else
						projectToAmend._cmake.publicincludedirs = projectToAmend._cmake.publicincludedirs or { }
						table.insert( projectToAmend._cmake.publicincludedirs, rebasedIncludeDir )
					end
				end
			end

			-- Reset modifiers
			modifiers = { }
		end

	end

	-- Restore scope
	p.api.scope.project = currentProject
end

executors[ 'target_link_libraries' ] = function( cmd )
	local arguments      = table.arraycopy( cmd.arguments )
	local projectName    = resolveAlias( table.remove( arguments, 1 ) )
	local currentProject = p.api.scope.project
	local projectToAmend = p.workspace.findproject( p.api.scope.workspace, projectName )
	local modifiers      = { }

	-- Make sure project exists
	if( projectToAmend == nil ) then
		p.error( 'Project "%s" referenced in "%s" not found in workspace', addToProject, cmd.name )
	end

	-- Temporarily activate amended project
	p.api.scope.project = projectToAmend

	-- Add source files
	for _,arg in ipairs( arguments ) do
		if( table.contains( { 'PRIVATE', 'PUBLIC', 'INTERFACE', 'LINK_INTERFACE_LIBRARIES', 'LINK_PRIVATE', 'LINK_PUBLIC' }, arg ) ) then
			modifiers[ arg ] = true
		else
			arg = m.resolveVariables( arg )

			for _,v in ipairs( string.explode( arg, ' ' ) ) do
				local targetName = resolveAlias( v )
				local prj        = p.workspace.findproject( p.api.scope.workspace, targetName )

				-- Add includedirs marked PUBLIC
				if( prj and prj._cmake ) then
					if( prj._cmake.publicincludedirs ) then
						for _,dir in ipairs( prj._cmake.publicincludedirs ) do
							includedirs { dir }
						end
					end
					if( prj._cmake.publicsysincludedirs ) then
						for _,dir in ipairs( prj._cmake.publicsysincludedirs ) do
							sysincludedirs { dir }
						end
					end
				end

				links { targetName }
			end

			-- Reset modifiers
			modifiers = { }
		end

	end

	-- Restore scope
	p.api.scope.project = currentProject
end

executors[ 'target_compile_definitions' ] = function( cmd )
	local arguments      = table.arraycopy( cmd.arguments )
	-- According to the docs, cannot be an alias target
	local targetName     = table.remove( arguments, 1 )
	local projectToAmend = p.workspace.findproject( p.api.scope.workspace, targetName )
	local allowedScopes  = { 'INTERFACE', 'PUBLIC', 'PRIVATE' }
	local i              = 0

	while( i < #arguments ) do
		i = i + 1

		if( table.contains( allowedScopes, arguments[ i ] ) ) then
			local items = { }

			while( ( i < #arguments ) and ( not table.contains( allowedScopes, arguments[ i + 1 ] ) ) ) do
				i = i + 1

				local item = arguments[ i ]

				-- Remove leading '-D'
				item = string.gsub( item, '-D', '', 1 )

				-- Ignore empty items
				local isEmpty = ( string.len( item ) == 0 ) or
				                ( ( string.sub( item, 1, 1 ) == '"' ) and
				                  ( string.sub( item, 2, 2 ) == '"' ) )

				if( not isEmpty ) then
					table.insert( items, arguments[ i ] )
				end
			end

			defines( items )
		end
	end
end

executors[ 'install' ] = function( cmd )
	-- Skip installation rules
	p.warnOnce( p.api.scope.project, string.format( 'Skipping installation rules for project "%s"', p.api.scope.project.name ) )
end

executors[ 'message' ] = function( cmd )
	local arguments    = cmd.arguments
	local allowedModes = { 'FATAL_ERROR', 'SEND_ERROR', 'WARNING',     'AUTHOR_WARNING',
	                       'DEPRECATION', 'NOTICE',     'STATUS',      'VERBOSE',
	                       'DEBUG',       'TRACE',      'CHECK_START', 'CHECK_PASS',
	                       'CHECK_FAIL' }

	if( #arguments > 1 ) then
		local mode = arguments[ 1 ]
		local msg  = m.toRawString( arguments[ 2 ] )

		if( mode == 'FATAL_ERROR' or mode == 'SEND_ERROR' ) then
			term.pushColor( term.red )
		elseif( mode == 'WARNING' or mode == 'AUTHOR_WARNING' ) then
			term.pushColor( term.yellow )
		elseif( mode == 'DEPRECATION' ) then
			term.pushColor( term.cyan )
		elseif( mode == 'NOTICE' or mode == 'STATUS' or mode == 'VERBOSE' or mode == 'DEBUG' or mode == 'TRACE' or mode == 'CHECK_START' or mode == 'CHECK_PASS' or mode == 'CHECK_FAIL' ) then
			term.pushColor( term.white )
		else
			p.warn( 'Unhandled message mode "%s"', mode )
			term.pushColor( term.white )
		end

		printf( '[CMake]<%s>: %s', mode, msg )
		term.popColor()

	else
		local msg = m.toRawString( arguments[ 1 ] )

		printf( '[CMake]: %s', msg )
	end
end

executors[ 'set_property' ] = function( cmd )
	local index           = 1
	local scope           = cmd.arguments[ index ]
	local propertyHandler = nil
	local meta            = nil
	local options         = { 'APPEND', 'APPEND_STRING' }
	index                 = index + 1

	if( scope == 'GLOBAL' ) then
		propertyHandler = function( meta, property, values )
			p.warn( 'Unhandled property %s in GLOBAL scope', property )
		end

	elseif( scope == 'DIRECTORY' ) then
		local dir = cmd.arguments[ index ]
		index     = index + 1

		propertyHandler = function( dir, property, values )
			p.warn( 'Unhandled property %s in DIRECTORY scope', property )
		end
		meta = dir

	elseif( scope == 'TARGET' ) then
		local targets = { }

		propertyHandler = function( targets, property, values )
			p.warn( 'Unhandled property %s in TARGET scope', property )
		end

		while( ( not table.contains( options, cmd.arguments[ index ] ) ) and ( cmd.arguments[ index ] ~= 'PROPERTY' ) ) do
			table.insert( targets, cmd.arguments[ index ] )
			index = index + 1
		end

		meta = targets

	elseif( scope == 'SOURCE' ) then
		local sources = { }

		propertyHandler = function( sources, property, values )
			p.warn( 'Unhandled property %s in SOURCE scope', property )
		end

		while( ( not table.contains( options, cmd.arguments[ index ] ) ) and ( cmd.arguments[ index ] ~= 'PROPERTY' ) ) do
			table.insert( sources, cmd.arguments[ index ] )
			index = index + 1
		end

		meta = sources

	elseif( scope == 'INSTALL' ) then
		local installFiles = { }

		propertyHandler = function( installFiles, property, values )
			p.warn( 'Unhandled property %s in INSTALL scope', property )
		end

		while( ( not table.contains( options, cmd.arguments[ index ] ) ) and ( cmd.arguments[ index ] ~= 'PROPERTY' ) ) do
			table.insert( installFiles, cmd.arguments[ index ] )
			index = index + 1
		end

		meta = installFiles

	elseif( scope == 'TEST' ) then
		local tests = { }

		propertyHandler = function( tests, property, values )
			p.warn( 'Unhandled property %s in TEST scope', property )
		end

		while( ( not table.contains( options, cmd.arguments[ index ] ) ) and ( cmd.arguments[ index ] ~= 'PROPERTY' ) ) do
			table.insert( tests, cmd.arguments[ index ] )
			index = index + 1
		end

		meta = tests

	elseif( scope == 'CACHE' ) then
		local entries = { }

		propertyHandler = function( entries, property, values )
			if( property == 'STRINGS' ) then
				for _,entry in ipairs( entries ) do
					cache_entries_allowed[ entry ] = values
				end
			else
				p.warn( 'Unhandled property %s in CACHE scope', property )
			end
		end

		while( ( not table.contains( options, cmd.arguments[ index ] ) ) and ( cmd.arguments[ index ] ~= 'PROPERTY' ) ) do
			table.insert( entries, cmd.arguments[ index ] )
			index = index + 1
		end

		meta = entries

	else
		p.error( 'Unhandled scope for "%s"', cmd.name )
	end

	-- Additional options
	while( cmd.arguments[ index ] ~= 'PROPERTY' ) do
		local option = cmd.arguments[ index ]

		if( option == 'APPEND' ) then
			-- TODO: Implement APPEND
		elseif( option == 'APPEND_STRING' ) then
			-- TODO: Implement APPEND_STRING
		else
			p.error( 'Unhandled option "%s" for command "%s"', option, cmd.name )
		end

		index = index + 1
	end
	index = index + 1

	local property = cmd.arguments[ index ]
	local values   = { }
	index = index + 1

	for i = index, #cmd.arguments do
		table.insert( values, cmd.arguments[ i ] )
	end

	propertyHandler( meta, property, values )
end

executors[ 'find_package' ] = function( cmd )
	if( os.isfile( m.CMAKE_MODULES_CACHE_AVAILABLE ) ) then
		-- TODO: Full signature
		-- TODO: COMPONENTS and OPTIONAL_COMPONENTS
		local arguments        = table.arraycopy( cmd.arguments )
		local possible_options = { 'EXACT', 'QUIET', 'MODULE', 'REQUIRED', 'NO_POLICY_SCOPE' }
		local packageName      = table.remove( arguments, 1 )
		local version          = iif( arguments[ 1 ] and not table.contains( possible_options, arguments[ 1 ] ), table.remove( arguments, 1 ), '0.0.0' )
		local options          = table.intersect( possible_options, arguments )

		if( table.contains( options, 'EXACT' ) ) then
			-- TODO: EXACT
		end
		if( table.contains( options, 'QUIET' ) ) then
			-- TODO: QUET
		end
		if( table.contains( options, 'MODULE' ) ) then
			-- TODO: MODULE
		end
		if( table.contains( options, 'REQUIRED' ) ) then
			-- TODO: REQUIRED
		end
		if( table.contains( options, 'NO_POLICY_SCOPE' ) ) then
			-- TODO: NO_POLICY_SCOPE
		end

		local fileName = string.format( 'Find%s.cmake', packageName )
		local filePath = path.join( m.CMAKE_MODULES_CACHE, fileName )

		if( os.isfile( filePath ) ) then
			local prevPackage = m.currentPackage
			m.currentPackage = packageName

			cmakecache {
				[ packageName .. '_ROOT' ] = path.getdirectory( filePath ),
			}

			-- Load module script
			m.parseScript( filePath )

			m.currentPackage = prevPackage
		end

	else
		p.error( 'CMake module cache is not available for command "%s"', cmd.name )
	end
end

executors[ 'find_path' ] = function( cmd )
	local possibleOptions    = { 'HINTS', 'PATHS', 'PATH_SUFFIXES', 'DOC', 'REQUIRED',
	                            'NO_DEFAULT_PATH', 'NO_PACKAGE_ROOT_PATH', 'NO_CMAKE_PATH',
	                            'NO_CMAKE_ENVIRONMENT_PATH', 'NO_SYSTEM_ENVIRONMENT_PATH',
	                            'NO_CMAKE_SYSTEM_PATH', 'CMAKE_FIND_ROOT_PATH_BOTH',
	                            'ONLY_CMAKE_FIND_ROOT_PATH', 'NO_CMAKE_FIND_ROOT_PATH' }
	local arguments          = table.arraycopy( cmd.arguments )
	local var                = table.remove( arguments, 1 )
	local names              = { }
	local hints              = { }
	local paths              = { }
	local subDirs            = { }
	local docString          = ''
	local isRequired         = false
	local searchPackageRoot  = m.isTrue( m.expandVariable( 'CMAKE_FIND_USE_PACKAGE_ROOT_PATH', iif( m.currentPackage ~= nil, m.TRUE, m.FALSE ) ) )
	local searchCMakePath    = m.isTrue( m.expandVariable( 'CMAKE_FIND_USE_CMAKE_PATH', m.TRUE ) )
	local searchCMakeEnvPath = m.isTrue( m.expandVariable( 'CMAKE_FIND_USE_CMAKE_ENVIRONMENT_PATH', m.TRUE ) )
	local searchSysEnvPath   = m.isTrue( m.expandVariable( 'CMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH', m.TRUE ) )
	local searchCMakeSysPath = m.isTrue( m.expandVariable( 'CMAKE_FIND_USE_CMAKE_SYSTEM_PATH', m.TRUE ) )
	local useFindRootPathVar = true
	local searchOnlyRoots    = false

	-- Names
	if( arguments[ 1 ] == 'NAMES' ) then
		table.remove( arguments, 1 )
		while( not table.contains( possibleOptions, arguments[ 1 ] ) ) do
			table.insert( names, table.remove( arguments, 1 ) )
		end
	else
		table.insert( names, table.remove( arguments, 1 ) )
	end

	-- Parse options
	while( #arguments > 0 ) do
		local option = table.remove( arguments, 1 )

		if( option == 'HINTS' ) then
			-- Directories to search in
			while( not table.contains( possibleOptions, arguments[ 1 ] ) ) do
				local arg = table.remove( arguments, 1 )

				if( arg == 'ENV' ) then
					local env = table.remove( arguments, 1 )

					table.insert( hints, os.getenv( env ) )
				else
					table.insert( hints, arg )
				end
			end

		elseif( option == 'PATHS' ) then
			-- Directories to search in (prioritized last)
			while( not table.contains( possibleOptions, arguments[ 1 ] ) ) do
				local arg = table.remove( arguments, 1 )

				if( arg == 'ENV' ) then
					local env = table.remove( arguments, 1 )

					table.insert( paths, os.getenv( env ) )
				else
					table.insert( paths, arg )
				end
			end

		elseif( option == 'PATH_SUFFIXES' ) then
			-- Subdirectories to search in
			while( not table.contains( possibleOptions, arguments[ 1 ] ) ) do
				local arg = table.remove( arguments, 1 )

				table.insert( subDirs, arg )
			end

		elseif( option == 'DOC' ) then
			-- Documentation string
			local arg = table.remove( arguments, 1 )

			docString = arg

		elseif( option == 'REQUIRED' ) then
			-- Abort if nothing is found
			local arg = table.remove( arguments, 1 )

			isRequired = m.isTrue( arg )

		elseif( option == 'NO_DEFAULT_PATH' ) then
			searchPackageRoot  = false
			searchCMakePath    = false
			searchCMakeEnvPath = false
			searchSysEnvPath   = false
			searchCMakeSysPath = false

		elseif( option == 'NO_PACKAGE_ROOT_PATH' ) then
			searchPackageRoot = false

		elseif( option == 'NO_CMAKE_PATH' ) then
			searchCMakePath = false

		elseif( option == 'NO_CMAKE_ENVIRONMENT_PATH' ) then
			searchCMakeEnvPath = false

		elseif( option == 'NO_SYSTEM_ENVIRONMENT_PATH' ) then
			searchSysEnvPath = false

		elseif( option == 'NO_CMAKE_SYSTEM_PATH' ) then
			searchCMakeSysPath = false

		elseif( option == 'CMAKE_FIND_ROOT_PATH_BOTH' ) then
			-- Don't need to change any settings

		elseif( option == 'ONLY_CMAKE_FIND_ROOT_PATH' ) then
			searchOnlyRoots = true

		elseif( option == 'NO_CMAKE_FIND_ROOT_PATH' ) then
			useFindRootPathVar = false
		end
	end

	-- Apply options

	if( searchPackageRoot ) then
		local packageRoot = p.api.scope.workspace.cmakecache[ m.currentPackage .. '_ROOT' ]

		if( packageRoot ) then
			for _,name in ipairs( names ) do
				local filePath = path.join( packageRoot, name )

				if( os.isfile( filePath ) ) then
					cmakecache {
						[ var ] = packageRoot,
					}
					return
				end
			end
		end
	end

	if( searchCMakePath ) then
		local libraryArchitecture = m.expandVariable( 'CMAKE_LIBRARY_ARCHITECTURE' )
		local prefixPath          = m.expandVariable( 'CMAKE_PREFIX_PATH' )
		local prefixes            = string.explode( prefixPath, ';' )

		for _,prefix in ipairs( prefixes ) do
			local dir = path.join( prefix, 'include' )

			for _,name in ipairs( names ) do
				if( libraryArchitecture ~= m.NOTFOUND ) then
					local archDir  = path.join( dir, libraryArchitecture )
					local filePath = path.join( archDir, name )

					if( os.isfile( filePath ) ) then
						cmakecache {
							[ var ] = archDir,
						}
						return
					end
				end

				local filePath = path.join( dir, name )

				if( os.isfile( filePath ) ) then
					cmakecache {
						[ var ] = dir,
					}
					return
				end
			end
		end

		local includePath = m.expandVariable( 'CMAKE_INCLUDE_PATH' )

		if( includePath ~= m.NOTFOUND ) then
			local paths = string.explode( includePath, ';' )

			for _,pathh in ipairs( paths ) do
				for _,name in ipairs( names ) do
					local filePath = path.join( pathh, name )

					if( os.isfile( filePath ) ) then
						cmakecache {
							[ var ] = pathh,
						}
						return
					end
				end
			end
		end

		local frameworkPath = m.expandVariable( 'CMAKE_FRAMEWORK_PATH' )

		if( frameworkPath ~= m.NOTFOUND ) then
			local paths = string.explode( frameworkPath, ';' )

			for _,pathh in ipairs( paths ) do
				for _,name in ipairs( names ) do
					local filePath = path.join( pathh, name )

					if( os.isfile( filePath ) ) then
						cmakecache {
							[ var ] = pathh,
						}
						return
					end
				end
			end
		end
	end

	if( searchCMakeEnvPath ) then
		local separator           = iif( os.is( 'windows' ), ';', ':' )
		local libraryArchitecture = os.getenv( 'CMAKE_LIBRARY_ARCHITECTURE' )
		local prefixPath          = os.getenv( 'CMAKE_PREFIX_PATH' )
		local prefixes            = iif( prefixPath, string.explode( prefixPath, separator ), { } )

		for _,prefix in ipairs( prefixes ) do
			local dir = path.join( prefix, 'include' )

			for _,name in ipairs( names ) do
				if( libraryArchitecture ) then
					local archDir  = path.join( dir, libraryArchitecture )
					local filePath = path.join( archDir, name )

					if( os.isfile( filePath ) ) then
						cmakecache {
							[ var ] = archDir,
						}
						return
					end
				end

				local filePath = path.join( dir, name )

				if( os.isfile( filePath ) ) then
					cmakecache {
						[ var ] = dir,
					}
					return
				end
			end
		end

		local includePath = os.getenv( 'CMAKE_INCLUDE_PATH' )

		if( includePath ) then
			local paths = string.explode( includePath, separator )

			for _,pathh in ipairs( paths ) do
				for _,name in ipairs( names ) do
					local filePath = path.join( pathh, name )

					if( os.isfile( filePath ) ) then
						cmakecache {
							[ var ] = pathh,
						}
						return
					end
				end
			end
		end

		local frameworkPath = os.getenv( 'CMAKE_FRAMEWORK_PATH' )

		if( frameworkPath ) then
			local paths = string.explode( frameworkPath, separator )

			for _,pathh in ipairs( paths ) do
				for _,name in ipairs( names ) do
					local filePath = path.join( pathh, name )

					if( os.isfile( filePath ) ) then
						cmakecache {
							[ var ] = pathh,
						}
						return
					end
				end
			end
		end
	end

	for _,hint in ipairs( hints ) do
		for _,name in ipairs( names ) do
			local filePath = path.join( hint, name )

			if( os.isfile( filePath ) ) then
				cmakecache {
					[ var ] = hint,
				}
				return
			end
		end
	end

	-- TODO: 5. Search standard system environment variables
	-- TODO: 6. Search CMake variables in the Platform files

	for _,pathh in ipairs( paths ) do
		for _,name in ipairs( names ) do
			local filePath = path.join( pathh, name )

			if( os.isfile( filePath ) ) then
				cmakecache {
					[ var ] = hint,
				}
				return
			end
		end
	end
end

executors[ 'if' ] = function( cmd, condscope__refwrap )
	if( cmd.name == 'if' ) then
		local newscope         = { }
		newscope.parent        = condscope__refwrap.ptr
		newscope.tests         = { }
		condscope__refwrap.ptr = newscope

		if( ( #condscope__refwrap.ptr.parent.tests > 0 ) and ( condscope__refwrap.ptr.parent.tests[ #condscope__refwrap.ptr.parent.tests ] ) ) then
			table.insert( condscope__refwrap.ptr.tests, true )
		else
			return
		end

	elseif( cmd.name == 'elseif' ) then
		if( #condscope__refwrap.ptr.tests == 0 ) then
			return
		end

		-- Look at all tests except the first one, which is always true
		local tests = table.pack( select( 2, table.unpack( condscope__refwrap.ptr.tests ) ) )

		if( table.contains( tests, true ) ) then
			table.insert( condscope__refwrap.ptr.tests, false )
			return
		end
	end

	local test = m.expandConditions( cmd.argString )

	table.insert( condscope__refwrap.ptr.tests, test )
end

executors[ 'elseif' ] = executors[ 'if' ]

executors[ 'else' ] = function( cmd, condscope__refwrap )
	if( #condscope__refwrap.ptr.tests > 0 ) then
		-- Look at all tests except the first one, which is always true
		local tests = table.pack( select( 2, table.unpack( condscope__refwrap.ptr.tests ) ) )

		table.insert( condscope__refwrap.ptr.tests, not table.contains( tests, true ) )
	end
end

executors[ 'endif' ] = function( cmd, condscope__refwrap )
	condscope__refwrap.ptr = condscope__refwrap.ptr.parent
end
