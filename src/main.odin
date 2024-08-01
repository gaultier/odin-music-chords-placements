package main

import "core:container/small_array"
import "core:fmt"


NoteKind :: enum {
	A = 0,
	A_Sharp,
	B,
	C,
	C_Sharp,
	D,
	D_Sharp,
	E,
	F,
	F_Sharp,
	G,
	G_Sharp,
}

// Note :: struct {
// 	kind:  NoteKind,
// 	level: u8,
// }

Step :: enum {
	Half  = 1,
	Whole = 2,
}

ScaleKind :: [7]Step
major_scale_steps :: ScaleKind{.Whole, .Whole, .Half, .Whole, .Whole, .Whole, .Half}
minor_scale_steps :: ScaleKind{.Whole, .Half, .Whole, .Whole, .Half, .Whole, .Whole}

Scale :: [7]NoteKind

next_note_kind :: proc(note_kind: NoteKind, step: Step) -> NoteKind {
	return cast(NoteKind)((cast(u8)note_kind + cast(u8)step) % 12)
}

scale_for_note_kind :: proc(note_kind: NoteKind, scale: ScaleKind) -> Scale {
	res := Scale{}
	res[0] = note_kind

	for i := 1; i < len(res); i += 1 {
		res[i] = next_note_kind(res[i - 1], scale[i - 1])
	}

	assert(next_note_kind(res[len(res) - 1], scale[len(scale) - 1]) == res[0])

	return res
}

ChordKind :: []u8
major_chord :: ChordKind{1, 3, 5}
major_chord_7 :: ChordKind{1, 3, 5, 7}

Chord :: small_array.Small_Array(10, NoteKind)

make_chord :: proc(scale: Scale, chord_kind: ChordKind) -> Chord {
	res := Chord{}

	for pos in major_chord {
		small_array.push(&res, scale[pos - 1])
	}
	return res
}

StringInstrumentLayout :: []NoteKind


main :: proc() {
	for note in NoteKind {
		major_scale := scale_for_note_kind(note, major_scale_steps)
		fmt.println(note, major_scale)

		minor_scale := scale_for_note_kind(note, minor_scale_steps)
		fmt.println(note, minor_scale)

		fmt.println(note, make_chord(major_scale, major_chord))
		fmt.println(note, make_chord(major_scale, major_chord_7))
		fmt.println(note, make_chord(minor_scale, major_chord))
		fmt.println(note, make_chord(minor_scale, major_chord_7))
		fmt.println()
	}


	// banjo_layout := StringInstrumentLayout{.D, .G, .B, .D}
}
