local p = premake
local m = p.extensions.impcmake

function m.isTrue( value )
	if( value == nil ) then
		return false
	end

	local t = type( value )

	if( t == 'boolean' ) then
		return value
	elseif( t == 'number' ) then
		return ( value ~= 0 )
	elseif( t == 'string' ) then
		if( ( value == m.ON ) or ( value == m.YES ) or ( value == m.TRUE ) or ( value == m.Y ) ) then
			return true
		elseif( ( value == m.OFF ) or ( value == m.NO ) or ( value == m.FALSE ) or ( value == m.N ) or ( value == m.IGNORE ) or ( value == m.NOTFOUND ) ) then
			return false
		elseif( tonumber( value ) ~= nil ) then
			return ( tonumber( value ) ~= 0 )
		end

		return m.isTrue( m.expandVariable( value ) )
	end

	p.error( '"%s" is not an eligible type for a CMake constant', t )

	return false
end

function m.resolveVariables( str )
	local scope = m.scope.current()

	-- Global variables
	repeat
		st, en = string.find( str, '${%S+}' )

		if( st ~= nil ) then
			local var   = string.sub( str, st + 2, en - 1 )
			local value = scope.variables[ var ]

			if( value ~= nil ) then
				local detokenizedValue = p.detoken.expand( value, scope.variables )
				str = string.sub( str, 1, st - 1 ) .. detokenizedValue .. string.sub( str, en + 1 )
			else
				str = string.sub( str, 1, st - 1 ) .. string.sub( str, en + 1 )
			end
		end
	until( st == nil )

	-- Environment variables
	repeat
		st, en = string.find( str, '$ENV{%S+}' )

		if( st ~= nil ) then
			local var   = string.sub( str, st + 5, en - 1 )
			local value = os.getenv( var )

			if( value ~= nil ) then
				local detokenizedValue = p.detoken.expand( value, scope.variables )
				str = string.sub( str, 1, st - 1 ) .. detokenizedValue .. string.sub( str, en + 1 )
			else
				str = string.sub( str, 1, st - 1 ) .. string.sub( str, en + 1 )
			end
		end
	until( st == nil )

	-- Cache variables
	repeat
		st, en = string.find( str, '$CACHE{%S+}' )

		if( st ~= nil ) then
			local var   = string.sub( str, st + 5, en - 1 )
			local vars  = p.api.scope.workspace.cmakecache
			local value = vars[ var ]

			if( value ~= nil ) then
				local detokenizedValue = p.detoken.expand( value, vars )
				str = string.sub( str, 1, st - 1 ) .. detokenizedValue .. string.sub( str, en + 1 )
			else
				str = string.sub( str, 1, st - 1 ) .. string.sub( str, en + 1 )
			end
		end
	until( st == nil )

	return str
end

function m.expandVariable( var, defaultValue )
	return p.api.scope.current.cmakevariables[ var ] or defaultValue or m.NOTFOUND
end

function m.isStringLiteral( str )
	return ( str:startswith( '"' ) and str:endswith( '"' ) )
end

function m.toStringLiteral( str )
	return m.isStringLiteral( str ) and str or ( '"' .. str .. '"' )
end

function m.toRawString( str )
	str = m.resolveVariables( str )

	if( m.isStringLiteral( str ) ) then
		return str:gsub( '^"(.*)"', '%1' )
	else
		return str
	end
end

function m.findUncaptured( str, delim, startIndex )
	-- Finds a substring within a string, but ignores any delimeters inside quotation marks
	-- Firstly, replace all occurrances of: \"
	-- But be careful, because we might run into a string that looks like: "\\" in which case we do not want to replace \" because that will turn into "\
	-- So first of all, replace all occurrances of \\ with something else, THEN replace every occurrance of \".
	local temp = str
	temp       = temp:gsub( '\\\\', '__' )
	temp       = temp:gsub( '\\\"', '__' )

	startIndex = startIndex or 1

	local captured = false
	for i = startIndex, #temp do
		-- TODO: delim might be multiple characters
		local char = temp:sub( i, i )

		if( char == '\"' ) then
			captured = not captured
		elseif( char == delim and not captured ) then
			return i
		end
	end

	return nil
end

function m.findMatchingParentheses( str, index )
	local left = m.findUncaptured( str, '(', index )
	if( left == nil ) then
		return nil
	end

	local numOpenParentheses = 1
	local nxt = left

	repeat
		local nextRight = m.findUncaptured( str, ')', nxt + 1 )
		nxt             = m.findUncaptured( str, '(', nxt + 1 )

		if( nxt and ( nextRight and nxt < nextRight ) or ( not nextRight ) ) then
			numOpenParentheses = numOpenParentheses + 1
		elseif( nextRight ) then
			numOpenParentheses = numOpenParentheses - 1
			nxt = nextRight

			if( numOpenParentheses == 0 ) then
				return left, nxt
			end
		end

	until( nxt == nil )

	return nil
end

function m.trimTrailingComments( str )
	-- Ignore block comments
	local comment = str:sub( 1, #str )
	if( comment:find( '#%[(=*)%[' ) or comment:find( '#%](=*)%]' ) ) then
		return str
	end

	-- Find uncaptured comment symbol	
	local index = m.findUncaptured( str, "#" )
	if( index == nil ) then
		return str
	end

	return str:sub( 1, index - 1 )
end
