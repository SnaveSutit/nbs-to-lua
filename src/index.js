const fs = require('fs')
const pathjs = require('path')
const NBSReader = require('nbs-reader')
const { exit } = require('process')

const outputFolder = './generated_songs/'
const song_dir = 'D:/github-repos/NBSsongs/songs'

const manifest = {}

function convert(song_path, song_name) {
	let file = NBSReader(song_path)
	// fs.writeFileSync('./converted.json', JSON.stringify(file, null, '\t'))

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

	let last_group
	for (const group of file.Notes) {
		if (group.length == 0) continue
		if (!last_group) {
			last_group = group
			continue
		}
		string_out += '{'
		for (note of last_group) {
			let diff = group[0].Tick - note.Tick
			let inst = instruments[note.Inst]
			let key = (note.Key - 33 + 24) % 24
			// output.push({ diff, inst, key })
			string_out += `{diff=${diff},inst='${inst}',key=${key}},`
		}
		string_out += '},'
		last_group = group
	}
	// Get last note of song
	string_out += '{'
	for (note of last_group) {
		let diff = 1
		let inst = instruments[note.Inst]
		let key = (note.Key - 33 + 24) % 24
		// output.push({ diff, inst, key })
		string_out += `{diff=${diff},inst='${inst}',key=${key}},`
	}
	string_out += '},'

	string_out = `{timing=${1 / file.Tempo},notes={${string_out}}}`

	manifest[song_name] = {
		author: file.SongAuthor,
		originalAuthor: file.OriginalAuthor,
	}

	fs.writeFileSync(pathjs.join(outputFolder, `${song_name}`), string_out)
}

const files = fs.readdirSync(song_dir)
fs.mkdirSync(outputFolder, { recursive: true })

for (const file of files) {
	let p = pathjs.parse(file)
	console.log(p.name)
	try {
		convert(pathjs.join(song_dir, file), p.name)
	} catch (e) {
		console.error(e)
	}
	fs.writeFileSync('./manifest.json', JSON.stringify(manifest, null, '\t'))
}
