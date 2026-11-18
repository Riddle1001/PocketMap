-- Conveyors carry a grounded walker without moving real Source entities.
local IO = PocketMap.MapIO
local NOT_SOLID, VISUAL_ONLY = 2, 1
local CLIENTS_IN_VEHICLES, PUSH_ONCE = 32, 128

local function setup( state, record )
	local current = IO.State( state, record )
	if not current.conveyor then
		current.conveyor = { direction = IO.Direction( record ), speed = IO.Number( record.entity, "speed", 100 ) }
	end
	return current.conveyor
end

IO.Register( "func_conveyor", {
	solid = function( _, record ) return bit.band( IO.Number( record.entity, "spawnflags", 0 ), NOT_SOLID ) == 0 end,
	setspeed = function( state, record, value )
		local speed = tonumber( value )
		if speed then setup( state, record ).speed = speed end
	end,
	start = function( state, record ) IO.State( state, record ).enabled = true end,
	stop = function( state, record ) IO.State( state, record ).enabled = false end,
} )

local function onBelt( session, state, record, mins, maxs )
	if session.groundRecord then return session.groundRecord == record end
	-- Collision leaves the grounded hull slightly above the belt.
	local lo, hi = IO.Bounds( record, state )
	return lo and math.abs( session.move.origin.z + mins.z - hi.z ) <= 2
		and IO.Overlaps( session, record, Vector( mins.x, mins.y, mins.z - 2 ), maxs )
end

IO.OnStep( "Conveyors", function( session, state, dt )
	local records = IO.OfClass( state.world, "func_conveyor" )
	if #records == 0 then return end
	local grounded = not session.noclip and session.onground
	local mins, maxs
	if grounded then mins, maxs = IO.PlayerHull( session ) end
	for _, record in ipairs( records ) do
		local flags = IO.Number( record.entity, "spawnflags", 0 )
		local conveyor = setup( state, record )
		local touching = grounded and conveyor.speed ~= 0 and bit.band( flags, VISUAL_ONLY + NOT_SOLID ) == 0
			and IO.Enabled( state, record ) and onBelt( session, state, record, mins, maxs )
		if touching then
			local delta = conveyor.direction * ( conveyor.speed * dt )
			if session.groundRecord == record then
				IO.Carry( session, record, delta )
			else
				local move = session.move
				local trace = session:TraceHull( move.origin, move.origin + delta, mins, maxs )
				move.origin = move.origin + delta * trace.Fraction
			end
			if not state.touching[record] then IO.Fire( state, record, "OnStartTouch", record, record ) end
		elseif state.touching[record] then
			IO.Fire( state, record, "OnEndTouch", record, record )
		end
		state.touching[record] = touching or nil
	end
end )

IO.Register( "trigger_push", {} )

local function pushVector( record, current )
	if not record.pushVector then
		local speed = IO.Number( record.entity, "speed", 100 )
		local direction = IO.Angle( IO.Value( record.entity, "pushdir" ) ):Forward()
		record.pushVector = direction * ( speed == 0 and 100 or speed )
	end
	local angles, initial = current and current.angles, record.angles
	if angles and ( angles.p ~= initial.p or angles.y ~= initial.y or angles.r ~= initial.r ) then
		local origin, zero = Vector(), Angle()
		local direction = WorldToLocal( record.pushVector, zero, origin, initial )
		return LocalToWorld( direction, zero, origin, angles )
	end
	return record.pushVector
end

IO.OnStep( "PushTriggers", function( session, state, dt )
	local previous = session.triggerPush
	session.triggerPush, session.triggerPushLift = nil, nil
	local records = IO.OfClass( state.world, "trigger_push" )
	if #records == 0 then return end

	local mins, maxs = IO.PlayerHull( session )
	local move = session.move
	local base, lift
	for _, record in ipairs( records ) do
		local current = state.records[record]
		local flags = IO.Number( record.entity, "spawnflags", 1 )
		local touching = not session.noclip and not ( current and current.pushUsed )
			and bit.band( flags, CLIENTS_IN_VEHICLES ) == 0 and IO.Enabled( state, record )
			and IO.TriggerAllowsPlayer( state, record )
			and IO.TriggerOverlaps( session, record, mins, maxs )
		local wasTouching = state.touching[record]
		if touching then
			if not wasTouching then
				IO.Fire( state, record, "OnStartTouch", state.activator, record )
				IO.Fire( state, record, "OnStartTouchAll", state.activator, record )
			end
			local push = pushVector( record, current )
			if bit.band( flags, PUSH_ONCE ) ~= 0 then
				IO.State( state, record ).pushUsed = true
				move.velocity = move.velocity + push
				lift = lift or push.z > 0
			else
				base = base and base + push or push
			end
		elseif wasTouching then
			IO.Fire( state, record, "OnEndTouch", state.activator, record )
			IO.Fire( state, record, "OnEndTouchAll", state.activator, record )
		end
		state.touching[record] = touching or nil
	end

	-- Each touch renews the base velocity for the next move. On exit the
	-- horizontal component becomes ordinary momentum once.
	if previous and not base and not session.noclip then
		move.velocity = move.velocity + Vector( previous.x, previous.y, 0 ) * ( 1 + dt * 0.5 )
	end
	session.triggerPush = base
	if lift or base and base.z > 0 then
		session.triggerPushLift = true
		if session.onground then
			local up = Vector( 0, 0, 1 )
			local trace = session:TraceHull( move.origin, move.origin + up, mins, maxs )
			move.origin = move.origin + up * trace.Fraction
			session.onground, session.groundRecord = false, nil
		end
	end
end )
