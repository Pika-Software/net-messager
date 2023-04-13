-- NetEvents
--[[

    -- SHARED CODE
    local net_events = net.Events("fractions.sync")

    -- FireEvent(ply, name, opts)
    -- SetValue(ply, key, value, opts)

    net.WriteType

    net_events.Receive = function(self)
        local id = net.ReadUInt(8)
        local key = net.ReadString()
        local value = self:ReadType()

        local cls = CLASSES[id]
        if cls then cls:Set(key, value) end
    end

    function net_events:WriteType(value)
        net.WriteType(value)
    end

    function net_events:ReadType()
        return net.ReadType()
    end

    net_events.Write = function(self, id, key, value)
        net.WriteUInt(id, 8)
        net.WriteString(key)
        self:WriteType()
    end

    local ply = Entity(1)
    net_events:Send(id, key, value, ply)

]]

--[[
local messager = net.Messager()

]]
 
--[[

local obj = net.NewSync( "obj" )

-- default
obj:SetFilter( function()
    return players.GetAll()
end )

-- `string` key, `any` default
obj:Get( "key", default )

-- `string` key, `any` value
obj:Set( "key", value )

-- `string` key, `boolean` use patterns
obj:Delete( "key", false )

-- returns all key/value table
PrintTable( obj:GetTable() )

-- `function` callback, `string` name
obj:AddCallback( function( key, value ) end, "name" )

-- `string` name
obj:RemoveCallback( "name" )

]]
do -- Sync class
    net.SYNC_META = net.SYNC_META or {}
    local META = net.SYNC_META
    META.__index = META

    function META:Filter() end -- override this function. it must return a table of players or nil (will broadcast to all players)

    function META:Get(key, default)
        return self.data[key] or default
    end

    function META:Set(key, value)
        self.data[key] = value
        self:Send(key, value)
    end

    funct
end