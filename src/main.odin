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

Note :: struct {
	kind:  NoteKind,
	level: u8,
}


Step :: enum {
	Half  = 1,
	Whole = 2,
}

Scale :: [7]Step


next_note_kind :: proc(note_kind: NoteKind, step: Step) -> NoteKind {
	return cast(NoteKind)((cast(u8)note_kind + cast(u8)step) % 12)
}

scale_for_note_kind :: proc(note_kind: NoteKind, scale: Scale) -> [7]NoteKind {
	res := [7]NoteKind{}
	res[0] = note_kind

	for i := 1; i < len(res); i += 1 {
		res[i] = next_note_kind(res[i - 1], scale[i - 1])
	}

	assert(next_note_kind(res[len(res) - 1], scale[len(scale) - 1]) == res[0])

	return res
}

main :: proc() {
	major_scale := Scale{.Whole, .Whole, .Half, .Whole, .Whole, .Whole, .Half}
	minor_scale := Scale{.Whole, .Half, .Whole, .Whole, .Half, .Whole, .Whole}

	for note in NoteKind {
		fmt.println(note, scale_for_note_kind(note, major_scale))
		fmt.println(note, scale_for_note_kind(note, minor_scale))
	}
}
