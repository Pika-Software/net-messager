local packageName = gpm.Package:GetIdentifier()
local CLIENT, SERVER = CLIENT, SERVER
local ArgAssert = ArgAssert
local pairs = pairs
local net = net

local SYNC = {}
SYNC.__index = SYNC
net.SYNC_METATABLE = SYNC

-- Data
function SYNC:GetTable()
    return self.data
end

function SYNC:Get( key, default )
    local value = self.data[ key ]
    if value == nil then return default end
    return value
end

do

    local ErrorNoHaltWithStack = ErrorNoHaltWithStack
    local timer_Create = timer.Create
    local xpcall = xpcall

    function SYNC:Set( key, value )
        if self.destroyed then return end
        self.data[ key ] = value

        if SERVER then
            self.queue[ #self.queue + 1 ] = { key, value }
            timer_Create( self.timerName, 0.25, 1, function() self:Send() end )
        end

        for _, callback in pairs( self.callbacks ) do
            xpcall( callback, ErrorNoHaltWithStack, self, key, value )
        end
    end

end

-- Change callbacks
function SYNC:AddCallback( callback, name )
    self.callbacks[ name or callback ] = callback
end

function SYNC:RemoveCallback( any )
    self.callbacks[ any ] = nil
end

-- Sending
if SERVER then

    -- override this function. it must return a table of players or nil (will broadcast to all players)
    function SYNC:Filter() end

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

            net.WriteBool( false )

            for key in pairs( self.queue ) do
                self.queue[ key ] = nil
            end

        self.messager:Send( players )
    end

end

-- Receiving
if CLIENT then

    function SYNC:Receive()
        while net.ReadBool() do
            self:Set( net.ReadString(), net.ReadType() )
        end
    end

end

function SYNC:Destroy()
    if SERVER then
        local players = self:Filter()
        self.messager:Start()
            self.messager:WritePayload( self.messager.SYNC_DESTROY_ID, self.identifier )
        self.messager:Send( players )
    end

    self.messager.syncs[ self.identifier ] = nil
    self.destroyed = true
end

local MESSAGER = {}
MESSAGER.__index = MESSAGER
net.MESSAGER_METATABLE = MESSAGER

-- Sending
if SERVER then

    function MESSAGER:Start()
        net.Start( self.networkString )
    end

    function MESSAGER:WritePayload( actionID, identifier )
        net.WriteUInt( actionID, 8 )
        net.WriteType( identifier )
    end

    function MESSAGER:Send( ply )
        if ply ~= nil then
            net.Send( ply )
            return
        end

        net.Broadcast()
    end

end

-- Actions
MESSAGER.SYNC_ACTION_ID = 1
MESSAGER.SYNC_DESTROY_ID = 2

if CLIENT then

    MESSAGER.Actions = {}

    MESSAGER["Actions"][ MESSAGER.SYNC_ACTION_ID ] = function( self, identifier )
        local sync = self.syncs[ identifier ]
        if not sync then return end
        sync:Receive()
    end

    MESSAGER["Actions"][ MESSAGER.SYNC_DESTROY_ID ] = function( self, identifier )
        local sync = self.syncs[ identifier ]
        if not sync then return end
        sync:Destroy()
    end

end

local setmetatable = setmetatable

do

    local tostring = tostring

    function MESSAGER:CreateSync( identifier )
        local sync = self.syncs[ identifier ]
        if sync ~= nil and not sync.destroyed then
            return sync
        end

        sync = setmetatable( {
            ["timerName"] = self.networkString .. "/" .. tostring( identifier ),
            ["identifier"] = identifier,
            ["messager"] = self,
            ["callbacks"] = {},
            ["data"] = {}
        }, SYNC )

        if SERVER then
            sync.queue = {}
        end

        self.syncs[ identifier ] = sync
        return sync
    end

end

local util_AddNetworkString = util.AddNetworkString

function net.Messager( name )
    ArgAssert( name, 1, "string" )

    local messanger = setmetatable( {
        ["networkString"] = packageName .. " - " .. name,
        ["syncs"] = {}
    }, MESSAGER )

    if SERVER then
        util_AddNetworkString( messanger.networkString )
    end

    if CLIENT then
        net.Receive( messanger.networkString, function()
            local action = messanger.Actions[ net.ReadUInt( 8 ) ]
            if action ~= nil then action( messanger, net.ReadType() ) end
        end )
    end

    return messanger
end