local SPEAKER = peripheral.find("speaker")
-- local CREATE_SOURCE = peripheral.find("create_source")

if not SPEAKER then
	error("No speaker found!")
end

term.clear()

local customSongFilePath = ...

if customSongFilePath and not fs.exists(customSongFilePath) then
	error("Custom song file path does not exist!")
end

--------------------------------
-- Util
--------------------------------

local function includes(table, value)
	for _, v in pairs(table) do
		if v == value then return true end
	end
	return false
end

--------------------------------
-- ONBS File API
--------------------------------

local ONBS = { parser = {} }
ONBS.parser.short = function(file)
	return file.read() + file.read() * 256
end
ONBS.parser.int = function(file)
	return
		file.read() + file.read() * 256
		+ file.read() * 65536
		+ file.read() * 16777216
end
ONBS.parser.string = function(file)
	local str = ''
	local length = ONBS.parser.int(file)
	for i = 1, length do
		local char = file.read()
		if not char then break end
		str = str .. string.char(char)
	end
	return str
end
ONBS.parser.meta = function(file)
	local meta = {}
	meta.length = ONBS.parser.short(file)
	-- If the first two bytes are 0 this is a modern ONBS file.
	if meta.length == 0 then
		meta.isModern = true
		meta.NBSVersion = file.read()
		meta.vanillaInstrumentCount = file.read()
		meta.length = ONBS.parser.short(file)
	end
	meta.layerCount = ONBS.parser.short(file)

	meta.name = ONBS.parser.string(file)
	if meta.name == '' then meta.name = "Untitled" end

	meta.author = ONBS.parser.string(file)
	if meta.author == '' then meta.author = "Unknown" end

	meta.originalAuthor = ONBS.parser.string(file)
	if meta.originalAuthor == '' then meta.originalAuthor = "Unknown" end

	meta.description = ONBS.parser.string(file)
	meta.tempo = ONBS.parser.short(file) / 100

	-- Skip fields we don't care about
	file.read()           -- Auto-save enabled
	file.read()           -- Auto-save duration
	file.read()           -- Time signature
	ONBS.parser.int(file) -- Minutes spent
	ONBS.parser.int(file) -- Left clicks
	ONBS.parser.int(file) -- Right clicks
	ONBS.parser.int(file) -- Note blocks added
	ONBS.parser.int(file) -- Note blocks removed
	ONBS.parser.string(file) -- MIDI/Schematic file name
	-- More modern meta data
	if meta.isModern then
		meta.loop = file.read()                -- Loop on/off
		meta.maxLoopCount = file.read()        -- Loop count
		meta.loopStartTick = ONBS.parser.short(file) -- Loop start tick
	end
	return meta
end
ONBS.parser.tick = function(file, song, wrapNotes)
	local tick = {}
	local noteblockID = 0
	local jumps = ONBS.parser.short(file) -- Number of jumps in this tick
	while jumps > 0 do
		noteblockID = noteblockID + jumps

		local instrument = file.read()
		if not song.meta.isModern and instrument > 9 then
			error("Cannot parse NBS files with custom instruments!")
		elseif instrument > 15 then
			error("Cannot parse ONBS files with custom instruments!")
		end
		instrument = instrument + 1 -- Lua tables start at 1

		local note = file.read() - 33
		if wrapNotes then
			note = note % 25
		else
			if note < 0 or note > 24 then
				error("Cannot parse NBT files with notes outside the vanilla noteblock range!")
			end
		end

		local volume = 100
		if song.meta.isModern then
			volume = file.read()
		end

		if not tick[instrument] then tick[instrument] = {} end
		tick[instrument][noteblockID] = { key = note, volume = volume }
		-- Skip fields we don't care about from the modern format
		if song.meta.isModern then
			file.read()    -- Panning
			ONBS.parser.short(file) -- Pitch Tuning
		end
		-- Read next jump
		jumps = ONBS.parser.short(file)
	end
	return tick
end
ONBS.parser.nextTick = function(file, song)
	-- Add an empty tick for each jump
	local jumps = ONBS.parser.short(file)
	for i = 1, jumps - 1 do
		table.insert(song.ticks, {})
	end
	return jumps > 0
end
ONBS.open = function(path, wrapNotes)
	local file = fs.open(path, "rb")
	if not file then return nil end
	local song = {
		meta = ONBS.parser.meta(file),
		ticks = {},
	}

	if song.meta.name == "Untitled" then
		song.meta.name = fs.getName(path):sub(1, -5)
	end

	while ONBS.parser.nextTick(file, song) do
		local tick = ONBS.parser.tick(file, song, wrapNotes)
		table.insert(song.ticks, tick)
		-- Prevent "too long without yielding" error
		os.queueEvent("ONBS_TICK_PARSED")
		os.pullEvent("ONBS_TICK_PARSED")
	end

	file.close()
	return song
end

--------------------------------
-- Song Management
--------------------------------

local songList = {}

local function getSongListFromFolder(path)
	songList = {}
	local files = fs.list(path)
	for _, fileName in pairs(files) do
		if fileName:sub(-4) == ".nbs" then
			table.insert(songList, {
				name = fileName:sub(1, -5),
				path = fs.combine(path, fileName)
			})
		end
	end
end

local function getSongListFromRepo(url)
	local response, err = http.get(url)
	if not response then
		error("Failed to get song list from repo: " .. tostring(err))
	end
	local data = textutils.unserialiseJSON(response.readAll())
	response.close()

	songList = {}
	for _, file in pairs(data) do
		if file.name:sub(-4) == ".nbs" then
			table.insert(songList, {
				name = file.name:sub(1, -5),
				url = file.download_url
			})
		end
	end
end

if not fs.exists("./.nbs-player") then
	fs.makeDir("./.nbs-player")
end

if not fs.exists("./.nbs-player/songs") then
	fs.makeDir("./.nbs-player/songs")
end

local function downloadSong(songListItem, savePath)
	savePath = savePath or "./.nbs-player/songs/{SONG_NAME}.nbs"
	savePath = savePath:gsub('{SONG_NAME}', songListItem.name)

	local response, err = http.get(songListItem.url)
	if not response then
		error("Failed to download song: " .. tostring(err))
	end

	local file = fs.open(savePath, "wb")
	file.write(response.readAll())
	file.close()
	response.close()
end

local function loadSong(songListItem, path)
	path = path or "./.nbs-player/songs/{SONG_NAME}.nbs"
	path = path:gsub('{SONG_NAME}', songListItem.name)
	if not fs.exists(path) then
		downloadSong(songListItem, path)
	end
	return ONBS.open(path, true)
end

local function loadShuffledSong()
	index = math.random(#songList)
	local songListItem = songList[index]

	local savePath = './.nbs-player/shuffledSong.nbs'
	if fs.exists(savePath) then
		fs.delete(savePath)
	end

	local song

	if customSongFilePath then
		song = ONBS.open(songListItem.path, true)
	else
		song = loadSong(songListItem, savePath)
	end

	if song.meta.name == "shuffledSong" then
		song.meta.name = songListItem.name
	end

	return song
end

--------------------------------
-- Playback
--------------------------------

local mainVolume = 100
local drumVolume = 50

local activeSong = nil
local paused = false
local skip = false

local INSTRUMENTS = {
	'harp',
	'bass',
	'basedrum',
	'snare',
	'hat',
	'guitar',
	'flute',
	'bell',
	'chime',
	'xylophone',
	'iron_xylophone',
	'cow_bell',
	'didgeridoo',
	'bit',
	'banjo',
	'pling',
}

local DRUMS = {
	'bass',
	'basedrum',
	'snare',
	'hat',
}

local function buttonClick()
	SPEAKER.playSound("ui.button.click")
end

local function sleep(seconds)
	local ticks = seconds * 20
	ticks = math.floor(ticks + 0.5)
	for _ = 1, ticks do os.sleep(0.05) end
end

local function shuffleSong()
	index = math.random(#songList)
end

local function playActiveSong()
	for _, tick in ipairs(activeSong.ticks) do
		while paused do os.sleep(0.05) end

		for instrumentIndex, notes in pairs(tick) do
			for _, note in pairs(notes) do
				local instrument = INSTRUMENTS[instrumentIndex]
				local volume = (note.volume or 100) * (0.01 * mainVolume)
				-- Drums have a separate volume control
				if includes(DRUMS, instrument) then
					volume = volume * (0.01 * drumVolume)
				end
				SPEAKER.playNote(
					instrument,
					-- Volume is a float between 0 and 3.
					0.03 * volume,
					note.key
				)
			end
		end

		sleep(1 / activeSong.meta.tempo)
	end
end

--------------------------------
-- GUI
--------------------------------

local function drawCenteredText(text, y, color, bufferChar, bufferColor)
	local screenSizeX, _ = term.getSize()
	local textLength = #text
	local startX = math.floor((screenSizeX - textLength) / 2) + 1

	term.setCursorPos(1, y)
	term.clearLine()
	if bufferChar and bufferColor then
		term.setTextColor(bufferColor)
		term.write(string.rep(bufferChar, startX))
		term.setCursorPos(1, y)
	end

	term.setTextColor(color)
	term.setCursorPos(startX, y)
	term.write(text)

	if bufferChar and bufferColor then
		term.setTextColor(bufferColor)
		term.setCursorPos(startX + textLength, y)
		term.write(string.rep(bufferChar, screenSizeX - (startX + textLength) + 1))
	end
end

local function drawHorizontalLine(y, char, color)
	local screenSizeX, _ = term.getSize()
	term.setTextColor(color)
	term.setCursorPos(1, y)
	term.write(string.rep(char, screenSizeX))
end

local function drawNowPlayingSlot()
	local screenSizeX, screenSizeY = term.getSize()

	term.setBackgroundColor(colors.black)
	term.setTextColor(colors.white)
	term.setCursorPos(1, 1)

	drawCenteredText(" Now Playing ", 2, colors.lightGray, "\140", colors.gray)
	drawHorizontalLine(7, "\131", colors.gray)
end

local function drawScrollingText(text, y, color, speed)
	local screenSizeX, _ = term.getSize()
	if #text <= screenSizeX then
		term.setBackgroundColor(colors.black)
		drawCenteredText(text, y, color)
		return
	end

	local loopDelay = 12
	local t = math.floor(os.clock() * speed)
	local offset = math.max(0, (t % (#text + 4 + loopDelay)) - loopDelay)
	local displayText = string.rep(text .. "    ", 2)
	local textToShow = displayText:sub(offset + 1, offset + screenSizeX)

	term.setCursorPos(1, y)
	term.clearLine()
	term.setBackgroundColor(colors.black)
	term.setTextColor(color)
	term.write(textToShow)
end

local function drawNowPlayingTitle()
	drawScrollingText(activeSong.meta.name, 4, colors.lime, 4)
	if activeSong.meta.originalAuthor ~= "Unknown"
		and activeSong.meta.originalAuthor ~= activeSong.meta.author
	then
		drawScrollingText("by " .. activeSong.meta.originalAuthor .. " & " .. activeSong.meta.author, 5, colors.yellow, 4)
	else
		drawScrollingText("by " .. activeSong.meta.author, 5, colors.yellow, 4)
	end
end

local screenSizeX, screenSizeY = term.getSize()
local BUTTONS = {
	{
		rect = {
			screenSizeX / 2 - 4,
			8,
			2,
			1
		},
		draw = function()
			local screenSizeX, _ = term.getSize()
			term.setBackgroundColor(colors.black)
			term.setTextColor(colors.white)
			term.setCursorPos(screenSizeX / 2 - 4, 8)
			if paused then
				term.write("|>")
			else
				term.write("||")
			end
		end,
		click = function()
			paused = not paused
		end
	},
	{
		rect = {
			screenSizeX / 2 + 4,
			8,
			2,
			1
		},
		draw = function()
			local screenSizeX, _ = term.getSize()
			term.setBackgroundColor(colors.black)
			term.setTextColor(colors.white)
			term.setCursorPos(screenSizeX / 2 + 4, 8)
			term.write(">>")
		end,
		click = function()
			skip = true
		end
	},
}

local function initializeDisplay()
	term.setBackgroundColor(colors.black)
	term.clear()
	drawNowPlayingSlot()

	for _, btn in ipairs(BUTTONS) do
		btn.draw()
	end
end

local function updateDisplay()
	while true do
		drawNowPlayingTitle()
		os.sleep(0.1)
	end
end


local function mouseInput()
	while true do
		local event, button, x, y = os.pullEvent('mouse_click')
		for _, btn in ipairs(BUTTONS) do
			if
				x >= btn.rect[1] and
				x < btn.rect[1] + btn.rect[3] and
				y >= btn.rect[2] and
				y < btn.rect[2] + btn.rect[4]
			then
				buttonClick()
				btn.click()
				btn.draw()
			end
		end

		if skip then
			skip = false
			term.setCursorPos(1, 4)
			term.clearLine()
			drawCenteredText(" Song Skipped! ", 4, colors.orange, " ", colors.black)
			term.setCursorPos(1, 5)
			term.clearLine()
			break
		end
	end
end

local function main()
	term.clear()

	term.setCursorPos(1, 1)
	term.write("Fetching song list...")

	if customSongFilePath then
		getSongListFromFolder(customSongFilePath)
	else
		getSongListFromRepo("https://api.github.com/repos/flytegg/nbs-songs/contents/")
	end


	while true do
		initializeDisplay()

		term.setCursorPos(1, 4)
		term.clearLine()
		drawCenteredText("Downloading...", 4, colors.orange, " ", colors.black)
		term.setCursorPos(1, 5)
		term.clearLine()

		activeSong = loadShuffledSong()
		parallel.waitForAny(playActiveSong, updateDisplay, mouseInput)
		os.sleep(1)
	end

	term.clear()
	term.setCursorPos(1, 1)
end

main()
