package main

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

Chord :: []u8
major_chord :: Chord{0, 2, 4}
major_chord_7 :: Chord{0, 2, 4, 6}

make_major_chord :: proc(scale: Scale) -> [3]NoteKind {
	res := [3]NoteKind{}

	for pos, i in major_chord {
		res[i] = scale[pos]
	}
	return res
}

make_major_chord_7 :: proc(scale: Scale) -> [4]NoteKind {
	res := [4]NoteKind{}

	for pos, i in major_chord_7 {
		res[i] = scale[pos]
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

		fmt.println(note, make_major_chord(major_scale))
		fmt.println(note, make_major_chord_7(major_scale))
		fmt.println(note, make_major_chord(minor_scale))
		fmt.println(note, make_major_chord_7(minor_scale))
		fmt.println()
	}


	// banjo_layout := StringInstrumentLayout{.D, .G, .B, .D}
}
