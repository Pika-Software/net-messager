install( "packages/glua-extensions", "https://github.com/Pika-Software/glua-extensions" )

local util_AddNetworkString = util.AddNetworkString
local ErrorNoHaltWithStack = ErrorNoHaltWithStack
local table_HasIValue = table.HasIValue
local CLIENT, SERVER = CLIENT, SERVER
local setmetatable = setmetatable
local gPackage = gpm.Package
local ArgAssert = ArgAssert
local IsValid = IsValid
local xpcall = xpcall
local pairs = pairs
local type = type
local net = net

local SYNC = {}
SYNC.__index = SYNC
net.SYNC_META = SYNC

-- Identifier
function SYNC:GetIdentifier()
    return self.Identifier
end

-- Data
function SYNC:GetTable()
    return self.Data
end

function SYNC:Get( key, default )
    local value = self.Data[ key ]
    if value == nil then return default end
    return value
end

function SYNC:IsValid()
    return self.Valid
end

function SYNC:Set( key, value )
    if not self:IsValid() then return end
    self.Data[ key ] = value

    if SERVER then
        self:Send( key, value )
    end

    for _, callback in pairs( self.Callbacks ) do
        xpcall( callback, ErrorNoHaltWithStack, self, key, value )
    end
end

-- Change callbacks
function SYNC:GetCallbacks()
    return self.Callbacks
end

function SYNC:GetCallback( name )
    return self.Callbacks[ name ]
end

function SYNC:SetCallback( name, func )
    ArgAssert( func, 2, "function" )
    self.Callbacks[ name ] = func
end

function SYNC:AddCallback( func, name )
    ArgAssert( func, 1, "function" )
    self:SetCallback( name or func, func )
end

function SYNC:RemoveCallback( any )
    self.Callbacks[ any ] = nil
end

-- Sending
if SERVER then

    -- override this function. it must return a table of players or nil (will broadcast to all players)
    function SYNC:Filter( key, value ) end

    function SYNC:Send( key, value, ply )
        if not self:IsValid() then return end
        local players = self:Filter( key, value )

        if ply ~= nil then
            if not IsValid( ply ) then return end

            if type( players ) == "table" then
                if not table_HasIValue( players, ply ) then return end
            elseif type( players ) == "CRecipientFilter" then
                if not table_HasIValue( players:GetPlayers(), ply ) then return end
            end

            players = ply
        end

        self.Messager:Start()
            self.Messager:WritePayload( self.Messager.SYNC_ACTION_ID, self.Identifier )
            net.WriteCompressedType( key )
            net.WriteCompressedType( value )
        self.Messager:Send( players )
    end

    function SYNC:Sync( ply )
        if not self:IsValid() then return end
        for key, value in pairs( self.Data ) do
            self:Send( key, value, ply )
        end
    end

end

-- Receiving
if CLIENT then

    function SYNC:Receive()
        self:Set( net.ReadCompressedType(), net.ReadCompressedType() )
    end

end

function SYNC:Destroy()
    if SERVER then
        local players = self:Filter()
        self.Messager:Start()
            self.Messager:WritePayload( self.Messager.DESTROY_ACTION_ID, self.Identifier )
        self.Messager:Send( players )
    end

    self.Messager.Syncs[ self.Identifier ] = nil
    self.Valid = false
end

local MESSAGER = {}
MESSAGER.__index = MESSAGER
net.MESSAGER_META = MESSAGER

-- Sending
if SERVER then

    function MESSAGER:Start()
        net.Start( self.NetworkString )
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
        if not IsValid( ply ) or ply:IsBot() then return end
        for _, sync in pairs( self.Syncs ) do
            if not sync:IsValid() then continue end
            sync:Sync( ply )
        end
    end

end

-- Getting sync
function MESSAGER:GetSync( identifier )
    return self.Syncs[ identifier ]
end

-- Actions
MESSAGER.SYNC_ACTION_ID = 1
MESSAGER.DESTROY_ACTION_ID = 2

if CLIENT then

    MESSAGER.Actions = {
        [ MESSAGER.SYNC_ACTION_ID ] = function( self, identifier )
            local sync = self:GetSync( identifier )
            if not sync then return end
            sync:Receive()
        end,
        [ MESSAGER.DESTROY_ACTION_ID ] = function( self, identifier )
            local sync = self:GetSync( identifier )
            if not sync then return end
            sync:Destroy()
        end
    }

end

function MESSAGER:CreateSync( identifier )
    local sync = self.Syncs[ identifier ]
    if sync ~= nil and sync:IsValid() then
        return sync
    end

    sync = setmetatable( {
        ["Identifier"] = identifier,
        ["Messager"] = self,
        ["Callbacks"] = {},
        ["Data"] = {}
    }, SYNC )

    self.Syncs[ identifier ] = sync
    return sync
end

function net.Messager( name )
    ArgAssert( name, 1, "string" )

    local messanger = setmetatable( {
        ["NetworkString"] = gPackage:GetIdentifier( name ),
        ["Syncs"] = {}
    }, MESSAGER )

    if SERVER then
        util_AddNetworkString( messanger.NetworkString )
    end

    if CLIENT then
        net.Receive( messanger.NetworkString, function()
            local action = messanger.Actions[ net.ReadUInt( 8 ) ]
            if action ~= nil then
                action( messanger, net.ReadType() )
            end
        end )
    end

    return messanger
end