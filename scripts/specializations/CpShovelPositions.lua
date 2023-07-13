--[[
	This specialization is used to control the shovel position into 4 stages:
		- Loading position 0.2m above the ground.
		- Transport position 
		- Pre unloading position
		- Unloading position

	TODO: 
		- Fine tuning
		- Testing from different front loaders ...
		- Add Telescopic handlers support.
]]--

---@class CpShovelPositions
CpShovelPositions = {
	DEACTIVATED = 0,
	LOADING = 1,
	TRANSPORT = 2,
	PRE_UNLOAD = 3,
	UNLOADING = 4,
	NUM_STATES = 4,
	LOADING_POSITION = {
		ARM_LIMITS = {
			0,
			0.1
		},
		SHOVEL_LIMITS = {
			88,
			92
		},
	},
	TRANSPORT_POSITION = {
		ARM_LIMITS = {
			0.1,
			0.20
		},
		SHOVEL_LIMITS = {
			53,
			57
		},
	},
	PRE_UNLOAD_POSITION = {
		ARM_LIMITS = {
			7,
			7
		},
		SHOVEL_LIMITS = {
			43,
			47
		},
	},
	UNLOADING_POSITION = {
		ARM_LIMITS = {
			7,
			7
		},
	},
	DEBUG = true
}
CpShovelPositions.MOD_NAME = g_currentModName
CpShovelPositions.NAME = ".cpShovelPositions"
CpShovelPositions.SPEC_NAME = CpShovelPositions.MOD_NAME .. CpShovelPositions.NAME
CpShovelPositions.KEY = "." .. CpShovelPositions.SPEC_NAME

function CpShovelPositions.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
	g_devHelper.consoleCommands:registerConsoleCommand('cpSetShovelState', 'cpSetShovelState', 'consoleCommandSetShovelState', CpShovelPositions)
	g_devHelper.consoleCommands:registerConsoleCommand('cpSetShovelArmLimit', 'cpSetShovelArmLimit', 'consoleCommandSetPreUnloadArmLimit', CpShovelPositions)
end

function CpShovelPositions.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Shovel, specializations) and not 
		SpecializationUtil.hasSpecialization(Trailer, specializations) and not 
		SpecializationUtil.hasSpecialization(ConveyorBelt, specializations)
end

function CpShovelPositions.register(typeManager, typeName, specializations)
	if CpShovelPositions.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpShovelPositions.SPEC_NAME)
	end
end

function CpShovelPositions.registerEventListeners(vehicleType)	
	SpecializationUtil.registerEventListener(vehicleType, "onLoad", CpShovelPositions)
	SpecializationUtil.registerEventListener(vehicleType, "onDraw", CpShovelPositions)	
	SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", CpShovelPositions)
	SpecializationUtil.registerEventListener(vehicleType, "onPostAttach", CpShovelPositions)
end

function CpShovelPositions.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "cpSetShovelState", CpShovelPositions.cpSetShovelState)
    SpecializationUtil.registerFunction(vehicleType, "cpResetShovelState", CpShovelPositions.cpResetShovelState)
	SpecializationUtil.registerFunction(vehicleType, "cpSetupShovelPositions", CpShovelPositions.cpSetupShovelPositions)
	SpecializationUtil.registerFunction(vehicleType, "areCpShovelPositionsDirty", CpShovelPositions.areCpShovelPositionsDirty)
	SpecializationUtil.registerFunction(vehicleType, "getCpShovelUnloadingPositionHeight", CpShovelPositions.getCpShovelUnloadingPositionHeight)
end

--------------------------------------------
--- Console Commands
--------------------------------------------

local function executeConsoleCommand(func, ...)
	local vehicle = g_currentMission.controlledVehicle
	if not vehicle then 
		CpUtil.info("Not entered a valid vehicle!")
		return false
	end
	if vehicle:getIsAIActive() then 
		CpUtil.infoVehicle(vehicle, "Error, AI is active!")
		return false
	end
	local shovels, found = AIUtil.getAllChildVehiclesWithSpecialization(vehicle, Shovel)
	if not found then 
		CpUtil.infoVehicle(vehicle, "No shovel implement found!")
		return false
	end
	return func(shovels[1], ...)
end

function CpShovelPositions:consoleCommandSetShovelState(state)
	return executeConsoleCommand(function(shovelImplement, state)
		state = tonumber(state)
		if state == nil or state < 0 or state > CpShovelPositions.NUM_STATES then 
			CpUtil.infoVehicle(shovelImplement, "No valid state(0 - %d) was given!", CpShovelPositions.NUM_STATES)
			return false
		end
		shovelImplement:cpSetShovelState(state)
	end, state)
end

function CpShovelPositions:consoleCommandSetPreUnloadArmLimit(min, max)
	return executeConsoleCommand(function(shovelImplement, min, max)
		min = tonumber(min)
		max = tonumber(max)
		if min == nil or max == nil then 
			CpUtil.infoVehicle(shovelImplement, "No valid limits given! min: %s, max: %s", tostring(min), tostring(max))
			return false
		end
		CpShovelPositions.PRE_UNLOAD_POSITION.ARM_LIMITS = { min, max }
	end, min, max)
end

--------------------------------------------
--- Event Listener
--------------------------------------------

function CpShovelPositions:onLoad(savegame)
	--- Register the spec: spec_ShovelPositions
    self.spec_cpShovelPositions = self["spec_" .. CpShovelPositions.SPEC_NAME]
    local spec = self.spec_cpShovelPositions
	--- Current shovel state.
	spec.state = CpShovelPositions.DEACTIVATED
	spec.isDirty = false
end

function CpShovelPositions:onPostAttach()
	if self.spec_cpShovelPositions then
		CpShovelPositions.cpSetupShovelPositions(self)
	end
end

function CpShovelPositions:onDraw()
	if CpShovelPositions.DEBUG and self:getRootVehicle() then 
		local angle, shovelNode, maxAngle, minAngle, factor = CpShovelPositions.getShovelData(self)
		if shovelNode then
			DebugUtil.drawDebugNode(shovelNode, "shovelNode")
		end
	end
end

function CpShovelPositions:onUpdateTick(dt)
	local spec = self.spec_cpShovelPositions
	if spec.shovelToolIx == nil or spec.armToolIx == nil or self.rootVehicle == nil then 
		return
	end
	if spec.state == CpShovelPositions.LOADING then 
		CpShovelPositions.updateLoadingPosition(self, dt)
	elseif spec.state == CpShovelPositions.TRANSPORT then 
		CpShovelPositions.updateTransportPosition(self, dt)
	elseif spec.state == CpShovelPositions.PRE_UNLOAD then 
		CpShovelPositions.updatePreUnloadPosition(self, dt)
	elseif spec.state == CpShovelPositions.UNLOADING then 
		CpShovelPositions.updateUnloadingPosition(self, dt)
	end
end

--- Changes the current shovel state position.
function CpShovelPositions:cpSetShovelState(state)
	local spec = self.spec_cpShovelPositions
	if spec.state ~= state then
		spec.state = state
		if state == CpShovelPositions.DEACTIVATED then 
			ImplementUtil.stopMovingTool(spec.armVehicle, spec.armTool)
			ImplementUtil.stopMovingTool(spec.shovelVehicle, spec.shovelTool)
		end
	end
end

--- Deactivates the shovel position control.
function CpShovelPositions:cpResetShovelState()
	CpShovelPositions.debug(self, "Reset shovelPositionState.")
	local spec = self.spec_cpShovelPositions
	spec.state = CpShovelPositions.DEACTIVATED
	ImplementUtil.stopMovingTool(spec.armVehicle, spec.armTool)
	ImplementUtil.stopMovingTool(spec.shovelVehicle, spec.shovelTool)
end

--- Is the current target shovel position not yet reached?
function CpShovelPositions:areCpShovelPositionsDirty()
	local spec = self.spec_cpShovelPositions
	return spec.isDirty
end

--- Sets the relevant moving tools.
function CpShovelPositions:cpSetupShovelPositions()
	local spec = self.spec_cpShovelPositions
	spec.shovelToolIx = nil
	spec.armToolIx = nil
	spec.shovelTool = nil
	spec.armTool = nil
	local rootVehicle = self:getRootVehicle()
	local childVehicles = rootVehicle:getChildVehicles()
	for _, vehicle in ipairs(childVehicles) do
		if vehicle.spec_cylindered then
			for i, tool in pairs(vehicle.spec_cylindered.movingTools) do
				if tool.controlGroupIndex ~= nil then 
					if tool.axis == "AXIS_FRONTLOADER_ARM" then 
						spec.armToolIx = i
						spec.armTool = tool
						spec.armVehicle = vehicle
						spec.armProjectionNode = CpUtil.createNode("CpShovelArmProjectionNode", 
							0, 0, 0, vehicle.rootNode)
						spec.armToolRefNode = CpUtil.createNode("CpShovelArmToolRefNode", 
							0, 0, 0, vehicle.rootNode)
					elseif tool.axis == "AXIS_FRONTLOADER_TOOL" then 
						spec.shovelToolIx = i
						spec.shovelTool = tool
						spec.shovelVehicle = vehicle
					end
				end
			end
		end
	end
end

--- Sets the current shovel position values, like the arm and shovel rotations.
---@param dt number
---@param shovelLimits table
---@param armLimits table
---@param useHighDumpShovel boolean|nil
---@param heightOffset number|nil
---@return boolean|nil
function CpShovelPositions:setShovelPosition(dt, shovelLimits, armLimits, useHighDumpShovel, heightOffset)
	local min, max = unpack(shovelLimits)
	--- Target angle of the shovel node, which is at the end of the shovel.
	local targetAngle = math.rad(min) + math.rad(max - min)/2
	min, max = unpack(armLimits)
	--- Target height of the arm.
	--- This is relative to the attacher joint of the shovel.
	local targetHeight = min + (max - min)/2

	local shovelTool = self.spec_cpShovelPositions.shovelTool
	local armTool = self.spec_cpShovelPositions.armTool
	local shovelVehicle = self.spec_cpShovelPositions.shovelVehicle
	local armVehicle = self.spec_cpShovelPositions.armVehicle

	local curRot = {}
	curRot[1], curRot[2], curRot[3] = getRotation(shovelTool.node)
	local oldShovelRot = curRot[shovelTool.rotationAxis]

	curRot = {}
	curRot[1], curRot[2], curRot[3] = getRotation(armTool.node)
	local oldArmRot = curRot[armTool.rotationAxis]

	local armProjectionNode = self.spec_cpShovelPositions.armProjectionNode
	local armToolRefNode = self.spec_cpShovelPositions.armToolRefNode

	local radiusArmToolToShovelTool = calcDistanceFrom(shovelTool.node, armTool.node)
	
	local attacherJointNode = self.spec_attachable.attacherJoint.node
	local angle, shovelNode = CpShovelPositions.getShovelData(self)
	local _, shovelY, _ = localToLocal(self.rootNode, attacherJointNode, 0, 0, 0)
	heightOffset = heightOffset or 0

	--- local tempNode = createTransformGroup("tempVehicleSizeCenter")
	-- link(vehicle.rootNode, tempNode)
	-- setTranslation(tempNode, vehicle.size.widthOffset, vehicle.size.heightOffset + vehicle.size.height / 2, vehicle.size.lengthOffset)
	-- DebugUtil.drawDebugCube(tempNode, vehicle.size.width, vehicle.size.height, vehicle.size.length, 0, 0, 1)
	-- delete(tempNode)


	--- All values will be calculated in the coordinate system from the vehicle root node.

	local _, ty, tz = localToLocal(getChildAt(armTool.node, 0), armVehicle.rootNode, 0, 0, 0)
	local ax, ay, az = localToLocal(armTool.node, armVehicle.rootNode, 0, 0, 0)
	local sx, sy, sz = 0, targetHeight - shovelY - self.size.heightOffset + heightOffset, 0
	local ex, ey, ez = 0, targetHeight - shovelY - self.size.heightOffset + heightOffset, 20
	local yMax = ay + radiusArmToolToShovelTool
	local yMin = ay - radiusArmToolToShovelTool
	if sy > yMax then 
		--- Makes sure the target height is still reachable
		sy = yMax - 0.01
		ey = yMax - 0.01
	end
	if sy < yMin then 
		--- Makes sure the target height is still reachable
		sy = yMin + 0.01
		ey = yMin + 0.01
	end
	local hasIntersection, i1z, i1y, i2z, i2y = MathUtil.getCircleLineIntersection(az, ay, radiusArmToolToShovelTool,
															sz, sy, ez, ey)
	
	local isDirty, alpha, oldRotRelativeArmRot
	if hasIntersection then
		setTranslation(armProjectionNode, 0, i1y, i1z)
		setTranslation(armToolRefNode, ax, ay, az)
		local _, shy, shz = localToLocal(shovelTool.node, armVehicle.rootNode, 0, 0, 0)
		local dirZ, dirY = MathUtil.vector2Normalize(shz - az, shy - ay)
		oldRotRelativeArmRot = MathUtil.getYRotationFromDirection(-dirZ, dirY) + math.pi/2

		alpha = math.atan2(i1y - ay, i1z - az)
		local beta = -math.atan2(i2y - ay, i2z - az)
		local angle = MathUtil.clamp(oldArmRot - MathUtil.getAngleDifference(alpha, oldRotRelativeArmRot), armTool.rotMin, armTool.rotMax)
		isDirty = ImplementUtil.moveMovingToolToRotation(armVehicle, armTool, dt, angle)
	end

	local highDumpShovelIx = g_vehicleConfigurations:get(self, "shovelMovingToolIx")
	if highDumpShovelIx then 
		local tool = self.spec_cylindered.movingTools[highDumpShovelIx]
		if useHighDumpShovel then
			local _, dy, _ = localDirectionToWorld(getParent(tool.node), 0, 0, 1)
			angle = math.acos(dy)
			targetAngle = math.pi/2 - math.pi/8
			isDirty = ImplementUtil.moveMovingToolToRotation(self, tool, dt, tool.rotMax) or isDirty
		else 
			isDirty = ImplementUtil.moveMovingToolToRotation(self, tool, dt, tool.rotMin) or isDirty
		end
	end
	local deltaAngle = targetAngle - angle
	local goalAngle = MathUtil.clamp(oldShovelRot + deltaAngle, shovelTool.rotMin, shovelTool.rotMax)
	isDirty = ImplementUtil.moveMovingToolToRotation(shovelVehicle, 
		shovelTool, dt, goalAngle) or isDirty
	
	--- Debug information
	local wsx, wsy, wsz = localToWorld(armVehicle.rootNode, sx, sy, sz)
	local wex, wey, wez = localToWorld(armVehicle.rootNode, ex, ey, ez)
	if g_currentMission.controlledVehicle == self.rootVehicle and CpDebug:isChannelActive(CpDebug.DBG_SILO) then 
		DebugUtil.drawDebugLine(wsx, wsy, wsz, wex, wey, wez)
		DebugUtil.drawDebugCircleAtNode(armVehicle.rootNode, radiusArmToolToShovelTool, 30, nil, 
			true, {ax, ay, az})
		CpUtil.drawDebugNode(armVehicle.rootNode)
		CpUtil.drawDebugNode(armTool.node)
		CpUtil.drawDebugNode(shovelTool.node)
		CpUtil.drawDebugNode(armProjectionNode)
		CpUtil.drawDebugNode(armToolRefNode)

		local debugData = {}
		if hasIntersection then	
			table.insert(debugData, {
				value = "",
				name = "Arm Rotation" })
			table.insert(debugData, { 
				name = "alpha", value = math.deg(alpha) })
			table.insert(debugData, { 
				name = "deltaAlphaOld", value = math.deg(MathUtil.getAngleDifference(alpha, oldArmRot)) })
			table.insert(debugData, { 
				name = "old", value = math.deg(oldArmRot) })
			table.insert(debugData, {
				name = "deltaAlpha", value = math.deg(MathUtil.getAngleDifference(alpha, oldRotRelativeArmRot)) })
			table.insert(debugData, {
				name = "dirRot", value = math.deg(oldRotRelativeArmRot) })
			table.insert(debugData, {
				name = "distAlpha", value = MathUtil.vector2Length(i1z - tz, i1y - ty) })
		
			table.insert(debugData, {
				value = "",
				name = "",
				columnOffset = 0.12
			})
		end
		table.insert(debugData, {
			value = "",
			name = "Shovel Rotation" })
		table.insert(debugData, { 
			name = "angle", value = math.deg(angle) })
		table.insert(debugData, { 
			name = "deltaAngle", value = math.deg(deltaAngle) })	
		table.insert(debugData, { 
			name = "targetAngle", value = math.deg(targetAngle) })	
		DebugUtil.renderTable(0.4, 0.4, 0.018, debugData, 0)
	end
	return isDirty
end

function CpShovelPositions:updateLoadingPosition(dt)
	local spec = self.spec_cpShovelPositions
	local angle = CpShovelPositions.getShovelData(self)
	local heightOffset = self.rootVehicle.getCpSettings and self.rootVehicle:getCpSettings().loadingShovelHeightOffset:getValue()
	local isDirty
	if angle then 
		isDirty = CpShovelPositions.setShovelPosition(self, dt, 
			CpShovelPositions.LOADING_POSITION.SHOVEL_LIMITS, 
			CpShovelPositions.LOADING_POSITION.ARM_LIMITS, 
			nil, heightOffset)
	end
	spec.isDirty = isDirty
end

function CpShovelPositions:updateTransportPosition(dt)
	local spec = self.spec_cpShovelPositions
	local angle = CpShovelPositions.getShovelData(self)
	local isDirty
	if angle then 
		isDirty = CpShovelPositions.setShovelPosition(self, dt, 
			CpShovelPositions.TRANSPORT_POSITION.SHOVEL_LIMITS, CpShovelPositions.TRANSPORT_POSITION.ARM_LIMITS)
	end
	spec.isDirty = isDirty
end

function CpShovelPositions:updatePreUnloadPosition(dt)
	local spec = self.spec_cpShovelPositions
	local angle = CpShovelPositions.getShovelData(self)
	local isDirty
	if angle then
		isDirty = CpShovelPositions.setShovelPosition(self, dt, 
			CpShovelPositions.PRE_UNLOAD_POSITION.SHOVEL_LIMITS, CpShovelPositions.PRE_UNLOAD_POSITION.ARM_LIMITS) 
	end
	spec.isDirty = isDirty
end

function CpShovelPositions:updateUnloadingPosition(dt)
	local spec = self.spec_cpShovelPositions
	local angle, _, maxAngle = CpShovelPositions.getShovelData(self)
	local isDirty
	if angle and maxAngle then 
		isDirty = CpShovelPositions.setShovelPosition(self, dt, 
		{math.deg(maxAngle), math.deg(maxAngle) + 2}, 
		CpShovelPositions.PRE_UNLOAD_POSITION.ARM_LIMITS, true)
	end
	spec.isDirty = isDirty
end

function CpShovelPositions:getCpShovelUnloadingPositionHeight()
	return CpShovelPositions.PRE_UNLOAD_POSITION.ARM_LIMITS
end

--- Gets all relevant shovel data.
function CpShovelPositions:getShovelData()
	local shovelSpec = self.spec_shovel
	if shovelSpec == nil then 
		CpShovelPositions.debug(self, "Shovel spec not found!")
		return 
	end
	local info = shovelSpec.shovelDischargeInfo
    if info == nil or info.node == nil then 
		CpShovelPositions.debugt(self, "Info or node not found!")
		return 
	end
    if info.maxSpeedAngle == nil or info.minSpeedAngle == nil then
		CpShovelPositions.debug(self, "maxSpeedAngle or minSpeedAngle not found!")
		return 
	end

	if shovelSpec.shovelNodes == nil then 
		CpShovelPositions.debug(self, "Shovel nodes not found!")
		return 
	end

	if shovelSpec.shovelNodes[1] == nil then 
		CpShovelPositions.debug(self, "Shovel nodes index 0 not found!")
		return 
	end

	if shovelSpec.shovelNodes[1].node == nil then 
		CpShovelPositions.debug(self, "Shovel node not found!")
		return 
	end
	local _, dy, _ = localDirectionToWorld(info.node, 0, 0, 1)
	local angle = math.acos(dy)
	local factor = math.max(0, math.min(1, (angle - info.minSpeedAngle) / (info.maxSpeedAngle - info.minSpeedAngle)))
	return angle, shovelSpec.shovelNodes[1].node, info.maxSpeedAngle, info.minSpeedAngle, factor
end

function CpShovelPositions.debug(implement, ...)
	if CpShovelPositions.DEBUG then
		CpUtil.infoImplement(implement, ...)
	end
end