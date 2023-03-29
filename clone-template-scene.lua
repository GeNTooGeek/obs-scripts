--[[
**
**  clone-template-scene.lua -- OBS Studio Lua Script for Cloning Template Scene
**  Copyright (c) 2021-2022 Dr. Ralf S. Engelschall <rse@engelschall.com>
**  Distributed under MIT license <https://spdx.org/licenses/MIT.html>
**
**	Updated by Sterling McClung for his own purposes.
**
**
**
--]]

--  global OBS API
local obs = obslua

--	Sterling McClung
--	helper function: Enum
function enum(tbl)
    local length = #tbl
    for i = 1, length do
        local v = tbl[i]
        tbl[v] = i
    end

    return tbl
end

--  global context information
local ctx = {
    propsDef    = nil,  -- property definition
    propsDefSrc = nil,  -- property definition (source scene)
    propsSet    = nil,  -- property settings (model)
    propsVal    = {},   -- property values
    propsValSrc = nil,  -- property values (first source scene)
	debugLevel	= -1000,  -- property definition (debug level)
}

local DebugLevel = {
	None		= 0,
	Error		= 100,
	Warning		= 200,
	Info		= 300,
	Debug		= 400,
	Trace		= 8000,
}

local StatusMessageType = DebugLevel

--	helper function: convert obs.LOG_* value to string
local function GetLogTypeString(statusType)

	if statusType == obs.LOG_ERROR then
		return "Error"
	elseif statusType == obs.LOG_WARNING then
		return "Warning"
	elseif statusType == obs.LOG_INFO then
		return "Info"
	elseif statusType == obs.LOG_DEBUG then
		return "Debug"
	elseif statusType == StatusMessageType.Trace then
		return "Trace"
	end
	
	return ""
end

--  helper function: set status message
local function statusMessage (statusType, message)
	local workingDebugLevel = (ctx.propsVal and ctx.propsVal.debugLevel or 0)
	--if workingDebugLevel >10000 then
	--	statusType 
	if workingDebugLevel > 0 then
		obs.script_log(statusType, message)
		if statusType <= workingDebugLevel then
			local formatString = (ctx.propsVal.statusMessage ~= "" and (ctx.propsVal.statusMessage .. "\r\n%s: %s")) or "%s: %s"
			obs.obs_data_set_string(ctx.propsSet, "statusMessage", string.format(formatString, GetLogTypeString(statusType), message))
			obs.obs_properties_apply_settings(ctx.propsDef, ctx.propsSet)
		end
	end
    return true
end

local traceCount = 0
local osTime = 0

local function trace(message)

	local fullMessage = message .. ": %i"
	
	if traceCount >= 10 then
		traceCount = 0
	else
		traceCount = traceCount + 1
	end
	
	-- statusMessage(StatusMessageType.Trace, string.format(fullMessage, obs.os_gettime_ns()))
	statusMessage(obs.LOG_INFO, string.format(fullMessage, obs.os_gettime_ns()))
	
	return true
end



--  helper function: find scene by name
local function findSceneByName (name)
    local scenes = obs.obs_frontend_get_scenes()
    if scenes == nil then
        return nil
    end
    for _, scene in ipairs(scenes) do
        local n = obs.obs_source_get_name(scene)
        if n == name then
            obs.source_list_release(scenes)
            return scene
        end
    end
    obs.source_list_release(scenes)
    return nil
end

--  helper function: replace a string
local function stringReplace (str, from, to)
	trace("stringReplace begin: " .. (str ~= nil and str or "") .. ":" .. (from ~= nil and from or "") .. ":" .. (to ~= nil and to or ""))
    local function regexEscape (s)
		trace("regexEscape begin")
        return string.gsub(s, "[%(%)%.%%%+%-%*%?%[%^%$%]]", "%%%1")
    end
	local returnValue = string.gsub(str, regexEscape(from), to)
	trace(returnValue)
    return returnValue
end

--  called for the actual cloning action
local function doClone ()

	trace("doClone beginning")

    --  find source scene (template)
    local sourceScene = findSceneByName(ctx.propsVal.sourceScene)
    
	trace("doClone check source exists")
	if sourceScene == nil then
        statusMessage(obs.LOG_ERROR, string.format("source scene \"%s\" not found!",
            ctx.propsVal.sourceScene))
        return true
    end

    --  find target scene (clone)
    local targetScene = findSceneByName(ctx.propsVal.targetScene)
	trace("doClone check target exists")
    if targetScene ~= nil then
        statusMessage(obs.LOG_ERROR, string.format("target scene \"%s\" already exists!",
            ctx.propsVal.targetScene))
        return true
    end

    --  create target scene
    obs.script_log(obs.LOG_INFO, string.format("create: SCENE  \"%s\"",
		ctx.propsVal.targetScene))
    targetScene = obs.obs_scene_create(ctx.propsVal.targetScene)
	local sourceSceneNameStripped = stringReplace(ctx.propsVal.sourceScene, ctx.propsVal.templateString, "")
	trace("doClone scene created")

    --  iterate over all source scene (template) sources
	trace("doClone get template sources")
    local sourceSceneBase = obs.obs_scene_from_source(sourceScene)
    local sourceItems = obs.obs_scene_enum_items(sourceSceneBase)
	trace("doClone " .. #sourceItems .. " sources found")
	for _, sourceItem in ipairs(sourceItems) do
		trace("begin source loop")
        local sourceSrc = obs.obs_sceneitem_get_source(sourceItem)
		
        --  determine source and destination name
        local sourceNameSrc = obs.obs_source_get_name(sourceSrc)
		trace(sourceNameSrc or "NameNotFound")
		local sourceNameDst = stringReplace(sourceNameSrc, ctx.propsVal.templateString, "")
		trace(sourceNameDst)
		sourceNameDst = stringReplace(sourceNameDst, sourceSceneNameStripped, ctx.propsVal.targetScene)
		
		local sourceType = obs.obs_source_get_id(sourceSrc)
		trace("SourceType: " .. sourceType)
		
		-- Only deep copy source if it includes the stripped scene name in its source name
		-- and if the source is not a scene source
		if string.find(sourceNameSrc, sourceSceneNameStripped) and sourceType ~= "scene" then
			obs.script_log(obs.LOG_INFO, string.format("create: SOURCE \"%s/%s\"", ctx.propsVal.targetScene, sourceNameDst))
	
			--  create source
			trace("getting sourceSrc settings")
			local settings = obs.obs_source_get_settings(sourceSrc)
			--	check for existing source name
			trace("getting sourceNameDst source by name")
			local checkSource = obs.obs_get_source_by_name(sourceNameDst)
			trace("got sourceNameDst source by name: " .. (checkSource == nil and "nil" or "found"))
			local checkCounter = 1
			while checkSource ~= nil do
				trace("doClone target source name collision while loop")
				obs.obs_source_release(checkSource)
				checkCounter = checkCounter + 1
				checkSource = obs.obs_get_source_by_name(sourceNameDst .. checkCounter)
			end
			trace("releasing checkSource")
			obs.obs_source_release(checkSource)
			
			local targetSource = obs.obs_source_create(sourceType, ((checkCounter > 1) and (sourceNameDst .. checkCounter) or sourceNameDst), settings, nil)
	
			--  add source to scene
			local targetItem = obs.obs_scene_add(targetScene, targetSource)
	
			--  copy source private settings
			local privSettings = obs.obs_source_get_private_settings(sourceSrc)
			local hidden = obs.obs_data_get_bool(privSettings, "mixer_hidden")
			local volumeLocked = obs.obs_data_get_bool(privSettings, "volume_locked")
			local showInMultiview = obs.obs_data_get_bool(privSettings, "show_in_multiview")
			obs.obs_data_release(privSettings)
			privSettings2 = obs.obs_source_get_private_settings(targetSource)
			obs.obs_data_set_bool(privSettings2, "mixer_hidden", hidden)
			obs.obs_data_set_bool(privSettings2, "volume_locked", volumeLocked)
			obs.obs_data_set_bool(privSettings2, "show_in_multiview", showInMultiview)
			obs.obs_data_release(privSettings2)
			obs.obs_data_release(privSettings)
	
			--  copy source transforms
			local transform = obs.obs_transform_info()
			obs.obs_sceneitem_get_info(sourceItem, transform)
			obs.obs_sceneitem_set_info(targetItem, transform)
	
			--  copy source crop
			local crop = obs.obs_sceneitem_crop()
			obs.obs_sceneitem_get_crop(sourceItem, crop)
			obs.obs_sceneitem_set_crop(targetItem, crop)
	
			--  copy source filters
			obs.obs_source_copy_filters(targetSource, sourceSrc)
	
			--  copy source volume
			local volume = obs.obs_source_get_volume(sourceSrc)
			obs.obs_source_set_volume(targetSource, volume)
	
			--  copy source muted state
			local muted = obs.obs_source_muted(sourceSrc)
			obs.obs_source_set_muted(targetSource, muted)
	
			--  copy source push-to-mute state
			local pushToMute = obs.obs_source_push_to_mute_enabled(sourceSrc)
			obs.obs_source_enable_push_to_mute(targetSource, pushToMute)
	
			--  copy source push-to-mute delay
			local pushToMuteDelay = obs.obs_source_get_push_to_mute_delay(sourceSrc)
			obs.obs_source_set_push_to_mute_delay(targetSource, pushToMuteDelay)
	
			--  copy source push-to-talk state
			local pushToTalk = obs.obs_source_push_to_talk_enabled(sourceSrc)
			obs.obs_source_enable_push_to_talk(targetSource, pushToTalk)
	
			--  copy source push-to-talk delay
			local pushToTalkDelay = obs.obs_source_get_push_to_talk_delay(sourceSrc)
			obs.obs_source_set_push_to_talk_delay(targetSource, pushToTalkDelay)
	
			--  copy source sync offset
			local offset = obs.obs_source_get_sync_offset(sourceSrc)
			obs.obs_source_set_sync_offset(targetSource, offset)
	
			--  copy source mixer state
			local mixers = obs.obs_source_get_audio_mixers(sourceSrc)
			obs.obs_source_set_audio_mixers(targetSource, mixers)
	
			--  copy source deinterlace mode
			local mode = obs.obs_source_get_deinterlace_mode(sourceSrc)
			obs.obs_source_set_deinterlace_mode(targetSource, mode)
	
			--  copy source deinterlace field order
			local fieldOrder = obs.obs_source_get_deinterlace_field_order(sourceSrc)
			obs.obs_source_set_deinterlace_field_order(targetSource, fieldOrder)
	
			--  copy source flags
			local flags = obs.obs_source_get_flags(sourceSrc)
			obs.obs_source_set_flags(targetSource, flags)
	
			--  copy source enabled state
			local enabled = obs.obs_source_enabled(sourceSrc)
			obs.obs_source_set_enabled(targetSource, enabled)
	
			--  copy source visible state
			local visible = obs.obs_sceneitem_visible(sourceItem)
			obs.obs_sceneitem_set_visible(targetItem, visible)
	
			--  copy source locked state
			local locked = obs.obs_sceneitem_locked(sourceItem)
			obs.obs_sceneitem_set_locked(targetItem, locked)
	
			--  release resources
			obs.obs_source_release(targetSource)
			obs.obs_data_release(settings)
		else -- Copy by reference
			trace("doClone copy source by reference: " .. sourceNameSrc)
			local targetItem = obs.obs_scene_add(targetScene, sourceSrc)
			
			--  Transforms can be duplicated only, not referenced
			--  copy source transforms to do our best
			local transform = obs.obs_transform_info()
			obs.obs_sceneitem_get_info(sourceItem, transform)
			obs.obs_sceneitem_set_info(targetItem, transform)
			
		end
    end

    --  release resources
    obs.sceneitem_list_release(sourceItems)
    obs.obs_scene_release(targetScene)

    --  final hint
    statusMessage(obs.LOG_INFO, string.format("scene \"%s\" successfully cloned to \"%s\".",
        ctx.propsVal.sourceScene, ctx.propsVal.targetScene))
    return true
end

--  helper function: update source scenes property
local function updateSourceScenes ()
	
	--	Sterling McClung
	local tmplStr = ctx.propsVal.templateString
	
    if ctx.propsDefSrc == nil then
        return
    end
    obs.obs_property_list_clear(ctx.propsDefSrc)
    local scenes = obs.obs_frontend_get_scenes()
    if scenes == nil then
        return
    end
    ctx.propsValSrc = nil
    for _, scene in ipairs(scenes) do
        local n = obs.obs_source_get_name(scene)
		-- Sterling McClung
		-- Only list template scenes
        if string.find(n, tmplStr) then
			obs.obs_property_list_add_string(ctx.propsDefSrc, n, n)
			ctx.propsValSrc = n
		end
    end
    obs.source_list_release(scenes)
	
end

--  script hook: description displayed on script window
function script_description ()
    return [[
        <h2>Clone Template Scene</h2>
		
		Copyright &copy; 2021-2022 Sterling McClung 2<br/>
        Copyright &copy; 2021-2022 <a style="color: #ffffff; text-decoration: none;"
        href="http://engelschall.com">Dr. Ralf S. Engelschall</a><br/>
        Distributed under <a style="color: #ffffff; text-decoration: none;"
        href="https://spdx.org/licenses/MIT.html">MIT license</a>

        <p>
        <b>Clone an entire source scene (template), by creating a target
        scene (clone) and copying all corresponding sources, including
        their filters, transforms, etc.</b>

        <p>
        <u>Notice:</u> The same kind of cloning <i>cannot</i> to be achieved
        manually, as the scene <i>Duplicate</i> and the source
        <i>Copy</i> functions create references for many source types
        only and especially do not clone applied transforms. The only
        alternative is the tedious process of creating a new scene,
        step-by-step copying and pasting all sources and then also
        step-by-step copying and pasting all source transforms.

        <p>
        <u>Prerequisite:</u> This script assumes that the source
        scene is named <tt>XXX</tt> (e.g. <tt>Template-01</tt>),
        all of its sources are named <tt>XXX-ZZZ</tt> (e.g.
        <tt>Template-01-Placeholder-02</tt>), the target scene is
        named <tt>YYY</tt> (e.g. <tt>Scene-03</tt>) and all of
        its sources are consequently named <tt>YYY-ZZZ</tt> (e.g.
        <tt>Scene-03-Placeholder-02</tt>).
    ]]
end

--  script hook: define UI properties
function script_properties ()
    --  create new properties
    ctx.propsDef = obs.obs_properties_create()

	--	Sterling McClung
	--  Debug Level Field
    ctx.debugLevel = obs.obs_properties_add_list(ctx.propsDef, "debugLevel",
        "Debug Level:", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
	
	obs.obs_property_list_add_int(ctx.debugLevel, "None", 0)
	obs.obs_property_list_add_int(ctx.debugLevel, "Error", 100)
	obs.obs_property_list_add_int(ctx.debugLevel, "Warning", 200)
	obs.obs_property_list_add_int(ctx.debugLevel, "Info", 300)
	obs.obs_property_list_add_int(ctx.debugLevel, "Debug", 400)
	obs.obs_property_list_add_int(ctx.debugLevel, "Everything", 100000)
	
	--  Template String Field
    obs.obs_properties_add_text(ctx.propsDef, "templateString",
        "Template Scene String:", obs.OBS_TEXT_DEFAULT)
		
    --  create source scene list
    ctx.propsDefSrc = obs.obs_properties_add_list(ctx.propsDef,
        "sourceScene", "Source Scene (Template):",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
	
	updateSourceScenes()

    --  create target scene field
    obs.obs_properties_add_text(ctx.propsDef, "targetScene",
        "Target Scene (Clone):", obs.OBS_TEXT_DEFAULT)

    --  create clone button
    obs.obs_properties_add_button(ctx.propsDef, "clone",
        "Clone Template Scene", doClone)

    --  create status field (read-only)
    ctx.status = obs.obs_properties_add_text(ctx.propsDef, "statusMessage",
        "Status Message:", obs.OBS_TEXT_MULTILINE)
    obs.obs_property_set_enabled(ctx.status, true)

    --  apply values to definitions
    obs.obs_properties_apply_settings(ctx.propsDef, ctx.propsSet)

	
    return ctx.propsDef
end

--  script hook: define property defaults
function script_defaults (settings)

	obs.script_log(obs.LOG_DEBUG, "script_defaults")
	obs.script_log(obs.LOG_DEBUG, obs.obs_data_get_json(settings))

    --  update our source scene list (for propsValSrc below)
    updateSourceScenes()

    --  provide default values
	obs.obs_data_set_default_int(settings, "debugLevel", 200)
	obs.obs_data_set_default_string(settings, "templateString",   " - Template Scene")
    obs.obs_data_set_default_string(settings, "sourceScene",   ctx.propsValSrc)
    obs.obs_data_set_default_string(settings, "targetScene",   "Scene-01")
    obs.obs_data_set_default_string(settings, "statusMessage", "")
end

--  script hook: property values were updated
function script_update (settings)

	obs.script_log(obs.LOG_DEBUG, "script_update")
	obs.script_log(obs.LOG_DEBUG, obs.obs_data_get_json(settings))

	local previousTemplateString = ctx.propsVal.templateString

    --  remember settings
    ctx.propsSet = settings


    --  fetch property values
	obs.script_log(obs.LOG_DEBUG, "Current debugLevel: " .. (ctx.propsVal.debugLevel or "nil"))
	ctx.propsVal.debugLevel		= obs.obs_data_get_int(settings, "debugLevel")
	obs.script_log(obs.LOG_DEBUG, "New debugLevel: " .. ctx.propsVal.debugLevel)
	ctx.propsVal.templateString	= obs.obs_data_get_string(settings, "templateString")
    ctx.propsVal.sourceScene	= obs.obs_data_get_string(settings, "sourceScene")
    ctx.propsVal.targetScene	= obs.obs_data_get_string(settings, "targetScene")
    ctx.propsVal.statusMessage	= obs.obs_data_get_string(settings, "statusMessage")
	
	-- need to update source scenes, if templateString has been changed
	if previousTemplateString ~= ctx.propsVal.templateString then
		updateSourceScenes()
	end
end

--  react on script load
function script_load (settings)
    --  clear status message
    obs.obs_data_set_string(settings, "statusMessage", "")
	
	--[[
    --  react on scene list changes
    obs.obs_frontend_add_event_callback(function (event)
        if event == obs.OBS_FRONTEND_EVENT_SCENE_LIST_CHANGED then
            --  update our source scene list
            updateSourceScenes()
        end
        return true
    end)
	]]
end
