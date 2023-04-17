local ErrorNoHaltWithStack = ErrorNoHaltWithStack
local packageName = gpm.Package:GetIdentifier()
local pairs = pairs
local net = net

local SYNC = {}
SYNC.__index = SYNC

-- Data
function SYNC:GetTable()
    return self.data
end

function SYNC:Get( key, default )
    local value = self.data[ key ]
    if value == nil then return default end
    return value
end

function SYNC:Set( key, value )
    if self.destroyed then return end

    self.data[ key ] = value
    self.queue[ #self.queue + 1 ] = { key, value }

    timer.Create( self.timerName, 0.25, 1, function() self:Send() end )
end

-- Callbacks
function SYNC:AddCallback( callback, name )
    self.callbacks[ name or callback ] = callback
end

function SYNC:RemoveCallback( any )
    self.callbacks[ any ] = nil
end

-- override this function. it must return a table of players or nil (will broadcast to all players)
function SYNC:Filter() end

-- Networking
function SYNC:Send()
    if self.destroyed then return end

    local players = SERVER and self:Filter()

    self.messager:Start()
        self.messager:WritePayload( self.messager.SYNC_ACTION_ID, self.identifier )

        for num, data in ipairs( self.queue ) do
            net.WriteBool( true )
            net.WriteString( data[ 1 ] )
            net.WriteType( data[ 2 ] )
        end

        for key in pairs( self.queue ) do
            self.queue[ key ] = nil
        end

    self.messager:Send( players )
end

function SYNC:Receive()
    if self.destroyed then return end

    while net.ReadBool() do
        local key, value = net.ReadString(), net.ReadType()
        self:Set( key, value )

        for _, callback in pairs( self.callbacks ) do
            xpcall( callback, ErrorNoHaltWithStack, self, key, value )
        end
    end
end

function SYNC:Destroy()
    self.messager.syncs[ self.identifier ] = nil
    self.destroyed = true
end

local MESSAGER = {}
MESSAGER.__index = MESSAGER

MESSAGER.SYNC_ACTION_ID = 1

function MESSAGER:Start()
    net.Start( self.networkString )
end

function MESSAGER:WritePayload( actionID, identifier )
    net.WriteUInt( actionID, 8 )
    net.WriteType( identifier )
end

if SERVER then

    function MESSAGER:Send( ply )
        if ply ~= nil then
            net.Send( ply )
            return
        end

        net.Broadcast()
    end

end

if CLIENT then

    MESSAGER.Send = net.SendToServer

    MESSAGER.Actions = {
        [ MESSAGER.SYNC_ACTION_ID ] = function( self, identifier )
            local sync = self.syncs[ identifier ]
            if not sync then return end
            sync:Receive()
        end
    }

end

function MESSAGER:CreateSync( identifier )
    local sync = setmetatable( {
        ["timerName"] = self.networkString .. "/" .. tostring( identifier ),
        ["identifier"] = identifier,
        ["messager"] = self,
        ["callbacks"] = {},
        ["queue"] = {},
        ["data"] = {}
    }, SYNC )

    self.syncs[ identifier ] = sync
    return sync
end

function net.Messager( name )
    ArgAssert( name, 1, "string" )

    local messanger = setmetatable( {
        ["networkString"] = packageName .. " - " .. name,
        ["syncs"] = {}
    }, MESSAGER )

    if SERVER then
        util.AddNetworkString( messanger.networkString )
    end

    if CLIENT then
        net.Receive( messanger.networkString, function()
            local action = messanger.Actions[ net.ReadUInt( 8 ) ]
            if action ~= nil then action( messanger, net.ReadType() ) end
        end )
    end

    return messanger
end