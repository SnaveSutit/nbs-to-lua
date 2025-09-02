import fs from 'fs'
import pathjs from 'path'
import { exec } from 'child_process'
// @ts-ignore
import NBSReader from 'nbs-reader'
import Blueprint from 'factorio-blueprint'

const SONG_FILES = 'D:/github-repos/NBSsongs/songs'
const TEST_SONG = 'D:/github-repos/NBSsongs/songs/Duel of the Fates.nbs'

const TEST_BLUEPRINT =
	'0eNrVVttu2zAM/Rc9O0V8yZL6oT8yDIJsM4lQ3UDJ2YzA/z5KXo00HdL5ISvyYpukeEieQxs+s0b14FCawOozk601ntXfz8zLgxEq+sLggNVMBtAsY0boaDm0BxRai0bByjsQr4BszJg0HfxidT5mn0LshQ+rgMJ4ZzGsGlDhAqEYf2QMTJBBwtRRMgZuet1QrTq/CZQxZz3lWhPrE97z0yZjA6Wtt08bKtNJhHaKVxmjsQNaxRs4ipO0GJNaiW0vAwcTh+Sd9PHO6r1QHrI5jCA6fhSm4xGEmqRuA/YXJ97801FtOwJZj6momXrwsV4eLwjd5bCyS0yMY+TzioDithgfGMjzKwpuDU2xbk7eS/SBfyJnayk4ofog4jqto6GdQBEiOHtJ4T8FoltDAEyzT9j8JGgZufTcydAeZ6olIWKvaf5ESEk1bYD0vB7/ncj8gsRoV5FYouldJ06JoRHtKz9Z1cfBaM9m30HZRig1zJ2RYX9yZ9XgjtYMk/Jj9AN+mPFIR1NgTk8ua7gW7m1ppkwN3otDpJX9TfpyqfTlXaWXaM3KIvx/+asF8ldX8m8eVv5qqfzFXeX3wZov0L4Yl3xD32tfPqz2m6XaV3f+6jsH+DUv/7cFC/AogtNPTyK4vvgvy9iJYJMqxS6vts/Fdrsrd2VJBPwGRopyXg=='

// fs.writeFileSync('test.json', new Blueprint(TEST_BLUEPRINT).toJSON())

interface INote {
	Tick: number
	Layer: number
	Inst: number
	Key: number
	Velocity: number
	Panning: number
	Pitch: number
}

type NoteGroup = INote[]

enum MinecraftInstrument {
	HARP,
	BASS,
	BASEDRUM,
	SNARE,
	HAT,
	GUITAR,
	FLUTE,
	BELL,
	CHIME,
	XYLOPHONE,
	IRON_XYLOPHONE,
	COW_BELL,
	DIDGERIDOO,
	BIT,
	BANJO,
	PLING,
}

enum FactorioInstrument {
	ALARMS,
	MISC,
	DRUMKIT,
	PIANO,
	BASS,
	LEAD,
	SAWTOOTH,
	SQUARE,
	CELESTA,
	VIBRAPHONE,
	PLUCKED_STRINGS,
	STEEL_DRUM,
}

const NoteMap = {
	[MinecraftInstrument.HARP]: FactorioInstrument.PIANO,
	[MinecraftInstrument.BASS]: FactorioInstrument.BASS,
	[MinecraftInstrument.GUITAR]: FactorioInstrument.PLUCKED_STRINGS,
	[MinecraftInstrument.FLUTE]: FactorioInstrument.CELESTA,
	[MinecraftInstrument.BELL]: FactorioInstrument.VIBRAPHONE,
	[MinecraftInstrument.CHIME]: FactorioInstrument.STEEL_DRUM,
	[MinecraftInstrument.XYLOPHONE]: FactorioInstrument.PIANO,
	[MinecraftInstrument.PLING]: FactorioInstrument.STEEL_DRUM,
	[MinecraftInstrument.SNARE]: FactorioInstrument.DRUMKIT,
	[MinecraftInstrument.BASEDRUM]: FactorioInstrument.BASS,
	[MinecraftInstrument.HAT]: FactorioInstrument.DRUMKIT,
	[MinecraftInstrument.IRON_XYLOPHONE]: FactorioInstrument.PIANO,
	[MinecraftInstrument.COW_BELL]: FactorioInstrument.DRUMKIT,
	[MinecraftInstrument.DIDGERIDOO]: FactorioInstrument.SQUARE,
	[MinecraftInstrument.BIT]: FactorioInstrument.SAWTOOTH,
	[MinecraftInstrument.BANJO]: FactorioInstrument.PLUCKED_STRINGS,
}

const currentPos = { x: 0, y: 0 }

let lastSpeaker: any

function createSpeaker(
	blueprint: Blueprint,
	tick: number,
	note: number,
	instrument: FactorioInstrument
) {
	const entity = blueprint.createEntity('programmable_speaker', currentPos)
	entity.setParameters({
		volume: 1,
		playGlobally: true,
		allowPolyphony: true,
	})
	entity.setCircuitParameters({
		instrument,
		note,
	})
	entity.setCondition({
		left: 'coal',
		operator: '=',
		// @ts-ignore
		right: tick + 1,
	})

	return entity
}

const TIME_MULTIPLIER = 5

function generateBlueprint(path: string): string {
	const blueprint = new Blueprint()
	const file = NBSReader(path)
	// console.log(file)
	// exit()

	const totalTime = file.Length * TIME_MULTIPLIER
	console.log('Total time:', totalTime)

	let count = 0
	for (const group of file.Notes as NoteGroup[]) {
		if (group.length === 0) continue

		for (const note of group) {
			let entity: ReturnType<typeof createSpeaker>
			switch (note.Inst) {
				case MinecraftInstrument.SNARE: {
					entity = createSpeaker(
						blueprint,
						note.Tick * TIME_MULTIPLIER,
						4,
						FactorioInstrument.DRUMKIT
					)
					break
				}
				case MinecraftInstrument.HAT: {
					entity = createSpeaker(
						blueprint,
						note.Tick * TIME_MULTIPLIER,
						5,
						FactorioInstrument.DRUMKIT
					)
					break
				}
				case MinecraftInstrument.COW_BELL: {
					entity = createSpeaker(
						blueprint,
						note.Tick * TIME_MULTIPLIER,
						15,
						FactorioInstrument.DRUMKIT
					)
					break
				}
				default: {
					// @ts-ignore
					const instrument = NoteMap[note.Inst]
					entity = createSpeaker(
						blueprint,
						note.Tick * TIME_MULTIPLIER,
						note.Key - 24,
						instrument
					)
					break
				}
			}
			// console.log('Instrument:', instrument, note.Inst)a

			if (currentPos.x === 0) {
				const firstInLastRow = blueprint.findEntity({
					x: currentPos.x,
					y: currentPos.y - 1,
				})
				if (firstInLastRow) {
					entity.connect(firstInLastRow, undefined, undefined, 'red')
				}
			}

			if (lastSpeaker) entity.connect(lastSpeaker, undefined, undefined, 'red')
			lastSpeaker = entity

			currentPos.x++
			if (currentPos.x % 6 == 0) currentPos.x++
			if (currentPos.x > Math.round(Math.sqrt(file.Length))) {
				currentPos.x = 0
				currentPos.y++
			}
		}

		count++
	}

	return blueprint.encode()
}

// console.log(generateBlueprint(TEST_SONG))

exec('clip').stdin!.end(generateBlueprint(TEST_SONG))
