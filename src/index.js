const fs = require('fs')
const pathjs = require('path')
const NBSReader = require('nbs-reader')
const { exit } = require('process')

function convert(song_path, song_name) {
	let file = NBSReader(song_path)
	// fs.writeFileSync('./converted.json', JSON.stringify(file, null, '\t'))

	var output = []
	var string_out = ''

	var instruments = [
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
	]

	var last_tick = 0
	for (const group of file.Notes) {
		if (group.length == 0) continue
		string_out += '{'
		for (note of group) {
			let diff = note.Tick - last_tick
			let inst = instruments[note.Inst]
			let key = note.Key - 33
			output.push({ diff, inst, key })
			string_out += `{diff=${diff},inst='${inst}',key=${key}},`

			last_tick = note.Tick
		}
		string_out += '},'
	}

	string_out = `local notes = {${string_out}}`
	string_out += `
for _, group in pairs(notes) do
	local this_time = os.epoch("utc") / 1000
	for _, note in pairs(group) do
		peripheral.call("back", "playNote", note.inst, 100, note.key)
		print(note.inst, note.key)
	end
	local next_time = this_time + (group[1].diff * ${1 / file.Tempo})
	while os.epoch("utc") / 1000 < next_time do
	end
	-- coroutine.yield()
	sleep(0.05)
end
`

	// fs.writeFileSync('./out.json', JSON.stringify(output, null, '\t'))
	fs.writeFileSync(`../out/${song_name}.lua`, string_out)
}

const song_dir = 'D:/github-repos/NBSsongs/songs'
const files = fs.readdirSync(song_dir)

for (const file of files) {
	let p = pathjs.parse(file)
	console.log(p.name)
	try {
		convert(pathjs.join(song_dir, file), p.name)
	} catch (e) {
		console.error(e)
	}
}
