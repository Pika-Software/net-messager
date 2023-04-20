local packageName = gpm.Package:GetIdentifier()
local CLIENT, SERVER = CLIENT, SERVER
local ArgAssert = ArgAssert
local pairs = pairs
local type = type
local net = net

local SYNC = {}
SYNC.__index = SYNC
net.SYNC_METATABLE = SYNC

-- Identifier
function SYNC:GetIdentifier()
    return self.identifier
end

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
    local xpcall = xpcall

    function SYNC:Set( key, value )
        if self.destroyed then return end

        ArgAssert( key, 1, "string" )
        self.data[ key ] = value

        if SERVER then
            self:Send( key, value )
        end

        for _, callback in pairs( self.callbacks ) do
            if type( callback ) ~= "function" then continue end
            xpcall( callback, ErrorNoHaltWithStack, self, key, value )
        end
    end

end

-- Change callbacks
function SYNC:GetCallbacks()
    return self.callbacks
end

function SYNC:GetCallback( name )
    return self.callbacks[ name ]
end

function SYNC:SetCallback( name, func )
    self.callbacks[ name ] = func
end

function SYNC:AddCallback( func, name )
    self:SetCallback( name or func, func )
end

function SYNC:RemoveCallback( any )
    self.callbacks[ any ] = nil
end

-- Sending
if SERVER then

    -- override this function. it must return a table of players or nil (will broadcast to all players)
    function SYNC:Filter( key, value )
        return self.messager:Filter( key, value )
    end

    function SYNC:Send( key, value, ply )
        if self.destroyed then return end

        local players = self:Filter( key, value )

        if ply ~= nil then
            if not IsValid( ply ) then return end

            if type( players ) == "table" then
                if not table.HasValue( players, ply ) then return end
            elseif type( players ) == "CRecipientFilter" then
                if not table.HasValue( players:GetPlayers(), ply ) then return end
            end

            players = ply
        end


        self.messager:Start()
            self.messager:WritePayload( self.messager.SYNC_ACTION_ID, self.identifier )

            net.WriteString( key )
            net.WriteType( value )

        self.messager:Send( players )
    end

    function SYNC:Sync( ply )
        if self.destroyed then return end

        for key, value in pairs( self.data ) do
            self:Send( key, value, ply )
        end
    end

end

-- Receiving
if CLIENT then

    function SYNC:Receive()
        self:Set( net.ReadString(), net.ReadType() )
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

    -- override this function. it must return a table of players or nil (will broadcast to all players)
    function MESSAGER:Filter( key, value ) end

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

    function MESSAGER:Sync( ply )
        ArgAssert( ply, 1, "Entity" )
        if not IsValid( ply ) then return end
        if ply:IsBot() then return end

        for _, sync in pairs( self.syncs ) do
            if sync.destroyed then continue end
            sync:Sync( ply )
        end
    end

end

-- Getting sync
function MESSAGER:GetSync( identifier )
    return self.syncs[ identifier ]
end

-- Actions
MESSAGER.SYNC_ACTION_ID = 1
MESSAGER.SYNC_DESTROY_ID = 2

if CLIENT then

    MESSAGER.Actions = {}

    MESSAGER["Actions"][ MESSAGER.SYNC_ACTION_ID ] = function( self, identifier )
        local sync = self:GetSync( identifier )
        if not sync then return end
        sync:Receive()
    end

    MESSAGER["Actions"][ MESSAGER.SYNC_DESTROY_ID ] = function( self, identifier )
        local sync = self:GetSync( identifier )
        if not sync then return end
        sync:Destroy()
    end

end

local setmetatable = setmetatable

function MESSAGER:CreateSync( identifier )
    local sync = self.syncs[ identifier ]
    if sync ~= nil and not sync.destroyed then
        return sync
    end

    sync = setmetatable( {
        ["identifier"] = identifier,
        ["messager"] = self,
        ["callbacks"] = {},
        ["data"] = {}
    }, SYNC )

    self.syncs[ identifier ] = sync
    return sync
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