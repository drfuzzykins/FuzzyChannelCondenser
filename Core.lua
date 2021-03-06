﻿-- Copyright 2010 Drfuzzykins <internet@is.seerius.biz>
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--    http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local THROTTLE_DELAY = .5
local CHAT_TYPE_INFO = ChatTypeInfo["SYSTEM"]

local EVENT_TYPES = {
		["CHAT_MSG_CHANNEL_JOIN"] = "Joined",
		["CHAT_MSG_CHANNEL_LEAVE"] = "Left",

		["YOU_JOINED"] = "Joined",
		["YOU_LEFT"] = "Left",
		["YOU_CHANGED"] = "Changed",

		["SUSPENDED"] = "Left",
		["SET_MODERATOR"] = "GainedModerator",
		["UNSET_MODERATOR"] = "LostModerator",
		["OWNER_CHANGED"] = "GainedOwner"
	}

local AceAddon = LibStub("AceAddon-3.0")
local AceTimer = LibStub("AceTimer-3.0"):Embed({ })
local L = LibStub("AceLocale-3.0"):GetLocale("FuzzyChannelCondenser")
local FuzzyChannelCondenser = AceAddon:NewAddon("FuzzyChannelCondenser")

local Prat
local PratChannelColorMemory

local playerName = UnitName("player")
local throttles = { }

_G.FuzzyChannelCondenser = FuzzyChannelCondenser

local function formatPlayerName(frame, name)
	local text = ("|Hplayer:%s|h[%1$s]|h"):format(name)

	if Prat then
		-- Fake a Prat message and send it through a callback to all the modules
		-- to get all the possible formatting options on the player's name.
		local player, server = strsplit("-", name)
		local message =
			{
				EVENT = "CHAT_MSG_SAY", CHATTYPE = "SAY", MESSAGE = "", TYPEPOSTFIX = "", TYPEPREFIX = "",
				lL = "|Hplayer:", PLAYERLINK = name, LL = "|h", pP = "[", PLAYER = player, Pp = "]", Ll = "|h"
			}

		if server and server:len() > 0 then
			message.sS = "-"
			message.SERVER = server
		end

		Prat.callbacks:Fire("Prat_FrameMessage", message, frame, message.EVENT)
		Prat.callbacks:Fire("Prat_PreAddMessage", message, frame, message.EVENT)

		-- If the player's name wasn't outright removed, get rid of any
		-- pre/postfix portions of the message and use it for the new player name.
		if not message.DONOTPROCESS and (message.pP:len() > 0 or message.PLAYER:len() > 0 or message.Pp:len() > 0) then
			message.TYPEPREFIX = ""
			message.TYPEPOSTFIX = ""

			text = Prat.BuildChatText(message)
		end
	end

	return text
end

local function formatChannelName(frame, channelNumber, channelName)
	local text = ("|Hchannel:%d|h[%1$d. %s]|h"):format(channelNumber, channelName)
	local info = ChatTypeInfo["CHANNEL" .. channelNumber]

	if Prat then
		-- Fake a Prat message and send it through a callback to all the modules
		-- to get all the possible formatting options on the channel's name.
		local channelLink = ("[%d. %s]"):format(channelNumber, channelName)
		local message =
			{
				EVENT = "CHAT_MSG_CHANNEL_NOTICE", CHATTYPE = "CHANNEL_NOTICE", MESSAGE = "", TYPEPOSTFIX = "", TYPEPREFIX = "",
				CHANNELNUM = tostring(channelNumber), CC = ". ", nN = "|H", NN = "|h", Nn = "|h", CHANLINK = "channel:" .. channelNumber,
				CHANNEL = channelName, cC = "[", Cc = "]", PLAYERLINK = ""
			}

		Prat.callbacks:Fire("Prat_FrameMessage", message, frame, message.EVENT)
		Prat.callbacks:Fire("Prat_PreAddMessage", message, frame, message.EVENT)

		-- If the channel's name wasn't outright removed, get rid of any
		-- pre/postfix portions of the message and use it for the new player name.
		if not message.DONOTPROCESS and (message.cC:len() > 0 or message.CHANNELNUM:len() > 0 or message.CC:len() > 0 or message.CHANNEL:len() > 0 or message.Cc:len() > 0) then
			message.TYPEPREFIX = ""
			message.TYPEPOSTFIX = ""

			text = Prat.BuildChatText(message)
		end
	end

	if PratChannelColorMemory and PratChannelColorMemory:IsEnabled() then
		-- Retrieve color information from Prat's Channel Color Memory module and
		-- use it to colorize the channel's name.
		local color = PratChannelColorMemory.db.profile.colors[channelName]

		if color then
			info.r = color.r
			info.g = color.g
			info.b = color.b
		end
	end

	return ("|cff%02x%02x%02x%s|r"):format(floor(info.r * 255), floor(info.g * 255), floor(info.b * 255), text)
end

local function intersectThrottledChannelLists(throttles, a, b, c)
	local lista = throttles[a]
	local listb = throttles[b]
	local listc = throttles[c]

	if not lista or not listb then return end

	if not listc then
		listc = { }
		throttles[c] = listc
	end

	for keya, channela in pairs(lista) do
		for keyb, channelb in pairs(listb) do
			if channela == channelb then
				tinsert(listc, channela)

				lista[keya] = nil
				listb[keyb] = nil
			end
		end
	end

	if #lista == 0 then throttles[a] = nil end
	if #listb == 0 then throttles[b] = nil end
end

local function printThrottledEvents(description)
	local frame, player = unpack(description)
	local frameThrottles = throttles[frame]
	local playerThrottles = frameThrottles[player]
	local you = player == playerName

	frameThrottles[player] = nil
	player = formatPlayerName(frame, player)
	intersectThrottledChannelLists(playerThrottles, "GainedModerator", "GainedOwner", "GainedOwnerAndModerator")

	for event, channels in pairs(playerThrottles) do
		if type(channels) == "table" and #channels > 0 then
			local channelList = strjoin(L["ChannelDelimiter"], unpack(channels))
			local message

			event = event .. (#channels == 1 and "Channel" or "Channels")

			if you then
				message = L["You" .. event]:format(channelList)
			else
				message = L[event]:format(player, channelList)
			end

			frame:AddMessage(message, CHAT_TYPE_INFO.r, CHAT_TYPE_INFO.g, CHAT_TYPE_INFO.b, CHAT_TYPE_INFO.id)
		end
	end
end

local function isVisibleChannel(frame, channel, zoneID)
	channel = strupper(channel)
	if zoneID == 0 then zoneID = nil end

	for index, value in pairs(frame.channelList) do
		if strupper(value) == channel or frame.zoneChannelList[index] == zoneID then
			return true
		end
	end

	return false
end

local function messageFilter(frame, event, ...)
	local eventType, player, _, _, _, _, zoneID, channelNumber, channelName = ...
	local chatFilters = ChatFrame_GetMessageEventFilters(event)

	-- Fix for pre-3.1 chat filtering addons.
	if type(frame) ~= "table" then return false end

	if not EVENT_TYPES[event] and not EVENT_TYPES[eventType] then return false end
	if not isVisibleChannel(frame, channelName, zoneID) then return false end

	if chatFilters then
		for _, chatFilter in pairs(chatFilters) do
			if chatFilter ~= messageFilter then
				local filter, newEventType, newPlayer, _, _, _, _, _, newChannelNumber, newChannelName = chatFilter(frame, event, eventType, player, _, _, _, _, _, channelNumber, channelName)

				if filter then
					return true
				elseif newEventType then
					eventType, player, channelNumber, channelName = newEventType, newPlayer, newChannelNumber, newChannelName
				end
			end
		end
	end

	event = EVENT_TYPES[event] or EVENT_TYPES[eventType]

	if not event then return false end
	if not player or player == "" then player = playerName end

	local frameThrottles = throttles[frame]

	if not frameThrottles then
		frameThrottles = { [player] = { [event] = { } } }
		throttles[frame] = frameThrottles
	end

	local playerThrottles = frameThrottles[player]

	if not playerThrottles then
		playerThrottles = { [event] = { } }
		frameThrottles[player] = playerThrottles
	end

	local eventThrottles = playerThrottles[event]

	if not eventThrottles then
		eventThrottles = { }
		playerThrottles[event] = eventThrottles
	end

	tinsert(eventThrottles, formatChannelName(frame, channelNumber, channelName))

	AceTimer:CancelTimer(playerThrottles.timer, true)
	playerThrottles.timer = AceTimer:ScheduleTimer(printThrottledEvents, THROTTLE_DELAY, { frame, player })

	return true
end

function FuzzyChannelCondenser:OnInitialize()
	--
end

function FuzzyChannelCondenser:OnEnable()
	Prat = _G.Prat

	if Prat then
		PratChannelColorMemory = Prat.Addon:GetModule("ChannelColorMemory", true)
	end

	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_JOIN", messageFilter)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_LEAVE", messageFilter)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", messageFilter)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE_USER", messageFilter)
end

function FuzzyChannelCondenser:OnDisable()
	ChatFrame_RemoveMessageEventFilter("CHAT_MSG_CHANNEL_JOIN", messageFilter)
	ChatFrame_RemoveMessageEventFilter("CHAT_MSG_CHANNEL_LEAVE", messageFilter)
	ChatFrame_RemoveMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", messageFilter)
	ChatFrame_RemoveMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE_USER", messageFilter)
end
