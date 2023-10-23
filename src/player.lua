local songFolderUrl =
"https://raw.githubusercontent.com/SnaveSutit/nbs-to-lua/main/generated_songs/"
local manifestUrl =
"https://raw.githubusercontent.com/SnaveSutit/nbs-to-lua/main/manifest.json"

local speaker = peripheral.find("speaker")
local createSource = peripheral.find("create_source")

local cursorY = 1
local termSizeX, termSizeY = term.getSize()
local closeButtonPos = { x = termSizeX, y = 1 }
local paused = false
local shuffle = true
local songThread
local songName = ""
local mainVolume = 100
local drumsVolume = 50
local songData

local function loadNextSong(lastSong)
	if lastSong then
		os.unloadAPI(lastSong)
	end

	local response = http.get(manifestUrl)
	local manifest = textutils.unserialiseJSON(response.readAll())
	response.close()

	local songList = {}
	for songName, _ in pairs(manifest) do
		table.insert(songList, songName)
	end

	local index = 1
	local chosenSong
	if shuffle then
		repeat
			index = math.random(#songList)
			chosenSong = songList[index]
		until not (lastSong == chosenSong)
	else
		index = index + 1
		if index > #songList then
			index = 1
		end
	end
	chosenSong = songList[index]

	return chosenSong
end

local function playButtonSound()
	speaker.playSound("ui.button.click")
end

local function newline(n)
	cursorY = cursorY + (n or 1)
	term.setCursorPos(1, cursorY)
end

local function clearTerm()
	cursorY = 1
	term.clear()
	term.setCursorPos(1, cursorY)
end

local function makePaddedText(text, left, right, char)
	char = char or " "
	local padding
	if left and right then
		padding = (termSizeX - #text) / 2
		return string.rep(char, math.ceil(padding)) ..
			text .. string.rep(char, padding)
	end
	padding = termSizeX - #text
	return (left and string.rep(char, padding) or "") ..
		text .. (right and string.rep(char, padding) or "")
end

local function drawProgressBar(max, cur, label)
	local value = cur / max
	local maxBarFill = termSizeX - 2
	local curBarFill = maxBarFill * value

	term.write(
		makePaddedText(
			(label and (label .. " ") or "") .. tostring(math.floor(value * 100)) .. "% ",
			true,
			true
		)
	)
	newline()
	term.write(
		"[" ..
		string.rep("#", curBarFill) ..
		string.rep(" ", maxBarFill - math.floor(curBarFill)) .. "]"
	)
end

local function getProgressBarText(cur, max, screenSizeX)
	local value = cur / max
	local maxBarFill = screenSizeX - 2
	local curBarFill = maxBarFill * value

	return "[" ..
		string.rep("#", curBarFill) ..
		string.rep(" ", maxBarFill - math.floor(curBarFill)) .. "]"
end

local groupCount = 0
local currentGroupIndex = 0

local function getSongData(name)
	local songUrl = songFolderUrl .. name
	local response = http.get(songUrl)
	songData = textutils.unserialise(response.readAll())
	response.close()
end

local function playSong()
	groupCount = #songData.notes

	for groupIndex, group in pairs(songData.notes) do
		currentGroupIndex = groupIndex
		local thisTime = os.epoch("utc") / 1000

		for _, note in pairs(group) do
			local volume = 0.01 * mainVolume
			if (note.inst == "snare" or note.inst == "hat" or note.inst == "basedrum") then
				volume = 0.01 * (drumsVolume * volume)
			end
			speaker.playNote(note.inst, volume, note.key)
		end

		local nextTime = thisTime + (group[1].diff * songData.timing)
		local diffTime = nextTime - thisTime
		coroutine.yield(os.startTimer(diffTime))
	end

	return "done"
end
songThread = coroutine.create(playSong)

local function drawScreen()
	while true do
		clearTerm()
		term.write(makePaddedText(" X", true))
		newline()
		term.write(makePaddedText(" Now Playing ", true, true, "-"))
		newline(2)
		term.write(makePaddedText(songName, true, true))
		newline(2)
		term.write(makePaddedText((paused and "|>" or "||") .. "    >>", true, true))
		newline(2)
		drawProgressBar(groupCount, currentGroupIndex)
		newline(2)
		drawProgressBar(1000, mainVolume, "Main Volume")
		newline(2)
		drawProgressBar(100, drumsVolume, "Drum Volume")
		newline(termSizeY - cursorY)
		term.write(makePaddedText("Created by SnaveSutit", true, false))
		sleep(0.05)
	end
end

local function updateCreateSource()
	while not createSource do
		createSource = peripheral.find("create_source")
		sleep(5)
	end
	while true do
		local sizeX, sizeY = createSource.getSize()
		createSource.clear()
		createSource.setCursorPos(math.floor(sizeX / 2) - 5, 1)
		createSource.write("Now Playing")
		createSource.setCursorPos(math.floor(sizeX / 2) - math.ceil(#songName / 2), 2)
		createSource.write(songName)
		createSource.setCursorPos(1, 3)
		createSource.write(getProgressBarText(currentGroupIndex, groupCount, sizeX))
		sleep(5)
	end
end

local function nextSong()
	paused = true
	songName = makePaddedText("...Intermission...", true, true)
	songName = loadNextSong(songName)
	songThread = coroutine.create(playSong)
	songData = nil
	paused = false
end

local function main()
	songName = loadNextSong()
	getSongData(songName)
	while true do
		local success, value
		if not paused then
			if not songData then
				getSongData(songName)
			end
			success, value = coroutine.resume(songThread)
		else
			success = true
			value = os.startTimer(0.05)
		end

		if not success then
			clearTerm()
			print("Playback Error!")
			print(value)
			return
		end

		if value == "done" then
			nextSong()
			value = os.startTimer(2)
		end

		local mouse
		local function getMouseClick()
			local _, button, x, y = os.pullEvent("mouse_click")
			mouse = { button = button, x = x, y = y }
		end

		local timerComplete = false
		local function waitForTimer()
			local timeout = os.startTimer(10)
			repeat
				local event, param = os.pullEvent("timer")
			until (param == value) or (param == timeout)
			timerComplete = true
		end

		parallel.waitForAny(getMouseClick, waitForTimer, drawScreen, updateCreateSource)

		if mouse and mouse.button == 1 then
			if (mouse.x == closeButtonPos.x) and (mouse.y == closeButtonPos.y) then
				playButtonSound()
				-- Close Button
				clearTerm()
				return
			elseif ((mouse.x == 10) or (mouse.x == 11)) and (mouse.y == 6) then
				-- Pause Button
				playButtonSound()
				paused = not paused
			elseif ((mouse.x == 16) or (mouse.x == 17)) and (mouse.y == 6) then
				-- Skip Button
				playButtonSound()
				nextSong()
				sleep(0.5)
				timerComplete = true
			elseif ((mouse.x >= 2) or (mouse.x <= 24)) and (mouse.y == 12) then
				-- Main volume
				playButtonSound()
				mainVolume = math.ceil((mouse.x - 2) / 23 * 1000)
			elseif ((mouse.x >= 2) or (mouse.x <= 24)) and (mouse.y == 15) then
				-- Drums Volume
				playButtonSound()
				drumsVolume = math.ceil((mouse.x - 2) / 23 * 100)
			end
			-- clearTerm()
			-- print(mouse.button, " ", mouse.x, " ", mouse.y)
			-- return
		end

		if not timerComplete then
			waitForTimer()
		end
	end
end

main()
-- getSongData("Still_Alive")
-- for k, _ in pairs(songData) do
-- 	print(k)
-- end
