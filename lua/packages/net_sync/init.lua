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
local messager = net.Messager("network_string")
messager:CreateSync(sync_id)
messager:Start() -- Starts net message
messager:WritePayload(action_id, id)
messager:Send(ply)
]]
do -- Messager clas
    net.MESSAGER_META = net.MESSAGER_META or {}
    local META = net.MESSAGER_META
    META.__index = META

    META.SYNC_ACTION_ID = 1

    function META:Start()
        net.Start(self.name)
    end

    function META:WritePayload(action_id, id)
        net.WriteUInt(action_id, 8)
        net.WriteType(id)
    end

    function META:Send(ply)
        if ply then net.Send(ply) else net.Broadcast() end
    end

    function META:Receive()
        if SERVER then return end
        local action_id = net.ReadUInt(8)
        local id = net.ReadType()
        if action_id == self.SYNC_ACTION_ID and self.syncs[id] then
            self.syncs[id]:Receive()
        end
    end

    function META:CreateSync(id)
        local sync = setmetatable({
            messager = self,
            id = id,
            data = {},
            callbacks = {}
        }, net.SYNC_META)

        self.syncs[id] = sync
        return sync
    end

    function net.Messager(name)
        local messanger = setmetatable({}, net.MESSAGER_META)
        messanger.name = name
        messanger.syncs = {}

        if SERVER then
            util.AddNetworkString(name)
        end

        if CLIENT then
            net.Receive(name, function()
                messanger:Receive()
            end)
        end

        return messanger
    end
end

--[[

local obj = messager:CreateSync("obj")

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

obj:Destroy()

]]

do -- Sync class
    net.SYNC_META = net.SYNC_META or {}
    local META = net.SYNC_META
    META.__index = META

    function META:Filter(key, value) end -- override this function. it must return a table of players or nil (will broadcast to all players)

    function META:Get(key, default)
        local value = self.data[key]
        if value == nil then return default end
        return value
    end

    function META:Set(key, value)
        self.data[key] = value
        self:Send(key, value)
    end

    function META:Delete(key, pattern)
        if pattern then
            for k, v in pairs(self.data) do
                if k:find(key) then
                    self.data[k] = nil
                end
            end
        else
            self.data[key] = nil
        end

        self:Send(key, nil)
    end

    function META:GetTable()
        return self.data
    end

    function META:AddCallback(callback, name)
        self.callbacks[name or callback] = callback
    end

    function META:RemoveCallback(name)
        self.callbacks[name] = nil
    end

    function META:Send(key, value)
        if not SERVER then return end
        local ply = self:Filter(key, value)

        self.messager:Start()
            self.messager:WritePayload(self.messager.SYNC_ACTION_ID, self.id)
            net.WriteString(key)
            net.WriteBool(value ~= nil)
            if value ~= nil then
                net.WriteType(value)
            end
        self.messager:Send(ply)
    end

    function META:Receive()
        local key = net.ReadString()
        if net.ReadBool() then
            self:Set(key, net.ReadType())
        else
            self:Delete()
        end

        for _, callback in pairs(self.callbacks) do
            xpcall(callback, ErrorNoHaltWithStack, key, value)
        end
    end

    function META:Destroy()
        self.messager.syncs[self.id] = nil
    end
end