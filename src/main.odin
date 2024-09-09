package main

import "core:container/small_array"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:testing"


NoteKind :: enum {
	A,
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
#assert(cast(u8)NoteKind.G_Sharp == 11)

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


BANJO_LAYOUT := StringInstrumentLayout {
	{open_note = .G, first_fret = 4, last_fret = 17},
	{open_note = .D, first_fret = 1, last_fret = 12},
	{open_note = .G, first_fret = 1, last_fret = 12},
	{open_note = .B, first_fret = 1, last_fret = 12},
	{open_note = .D, first_fret = 1, last_fret = 12},
}

MAX_FINGER_DISTANCE :: 5

note_add :: proc(note_kind: NoteKind, offset: u8) -> NoteKind {
	return cast(NoteKind)((cast(u8)note_kind + offset) % 12)
}

next_note_kind :: proc(note_kind: NoteKind, step: Step) -> NoteKind {
	return note_add(note_kind, cast(u8)step)
}

compute_scale :: proc(note_kind: NoteKind, scale: ScaleKind) -> Scale {
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

StringLayout :: struct {
	open_note:  NoteKind,
	first_fret: u8,
	last_fret:  u8,
}

StringInstrumentLayout :: []StringLayout

find_fret_for_note_on_string :: proc(
	note_kind: NoteKind,
	starting_fret: u8,
	string_layout: StringLayout,
) -> (
	u8,
	bool,
) {
	for i := max(starting_fret, string_layout.first_fret); i < string_layout.last_fret; i += 1 {
		// TODO: check if correct.
		current_note := note_add(string_layout.open_note, i - string_layout.first_fret)
		if current_note == note_kind {
			return i, true
		}
	}
	return 0, false
}

is_string_picked :: proc(finger: u8) -> bool {
	return finger > 0
}

is_fingering_for_chord_valid :: proc(
	chord: []NoteKind,
	instrument_layout: StringInstrumentLayout,
	// This array has as many entries as the instrument has strings.
	// `fingering[a] = b` means: the string `a` is picked on fret `b`, or if `b == 0`, the string `a` is open.
	fingering: []u8,
) -> bool {
	assert(len(fingering) == len(instrument_layout))

	// Check that the distance between the first and last finger is <= max_finger_distance.
	{
		picked_strings, err := slice.filter(
			fingering,
			is_string_picked,
			allocator = context.temp_allocator,
		)
		if err != nil {
			panic("failed to allocate")
		}
		defer free_all(context.temp_allocator)

		finger_start := slice.min(picked_strings)
		finger_end := slice.max(picked_strings)
		dist_squared := (finger_start - finger_end) * (finger_start - finger_end)

		if dist_squared >= MAX_FINGER_DISTANCE * MAX_FINGER_DISTANCE {
			return false
		}
	}

	// Check that the fingering abides by the chord.
	{
		for finger, string_i in fingering {
			string_layout := instrument_layout[string_i]
			note := note_add(string_layout.open_note, finger)

			if !slice.contains(chord, note) {
				return false
			}
		}
	}


	return true
}

// Returns: true if we (safely) overflowed, false otherwise.
increment_fret :: proc(fret: ^u8, string_layout: StringLayout) -> bool {
	switch fret^ {
	case 0:
		fret^ = string_layout.first_fret
		return false
	case string_layout.last_fret:
		fret^ = 0
		return true

	case:
		fret^ += 1
		return false
	}
}

next_fingering :: proc(fingering: ^[]u8, instrumentLayout: StringInstrumentLayout) -> bool {
	assert(len(fingering) > 0)
	assert(len(fingering) == len(instrumentLayout))

	#reverse for _, string_i in fingering {
		string_layout := instrumentLayout[string_i]

		overflowed := increment_fret(&fingering[string_i], string_layout)

		if !overflowed {return true}

		// The slot has reached the maximum value, need to inspect the left-hand part to increment it.
	}

	// Reached the end.
	return false
}

// Rules:
// - Each string is either muted, open, or picked by one finger and produces 0 (muted) or 1 (otherwise) note .
// - The maximum distance between all picked frets is 4 or 5 due to the physical length of fingers.
// - Every fret of every string gets considered
// TODO: muted strings.
find_fingerings_for_chord :: proc(
	chord: []NoteKind,
	instrument_layout: StringInstrumentLayout,
	starting_fret: u8,
) -> [][]u8 {

	res: [dynamic][]u8
	fingering := small_array.Small_Array(10, u8){}
	for _ in instrument_layout {
		small_array.append(&fingering, 0)
	}
	assert(len(instrument_layout) == small_array.len(fingering))
	fingering_slice := small_array.slice(&fingering)


	for next_fingering(&fingering_slice, BANJO_LAYOUT) {
		if is_fingering_for_chord_valid(chord, instrument_layout, small_array.slice(&fingering)) {
			clone, err := slice.clone(small_array.slice(&fingering))
			if err != nil {
				panic("clone failed")
			}

			append(&res, clone)
		}
	}


	return res[:]
}


main :: proc() {
	for note in NoteKind {
		major_scale := compute_scale(note, major_scale_steps)
		fmt.println(note, major_scale)

		minor_scale := compute_scale(note, minor_scale_steps)
		fmt.println(note, minor_scale)

		fmt.println(note, make_chord(major_scale, major_chord))
		fmt.println(note, make_chord(major_scale, major_chord_7))
		fmt.println(note, make_chord(minor_scale, major_chord))
		fmt.println(note, make_chord(minor_scale, major_chord_7))
		fmt.println()
	}


	fmt.println(find_fret_for_note_on_string(.F, 2, BANJO_LAYOUT[1]))
	fmt.println(find_fret_for_note_on_string(.A_Sharp, 0, BANJO_LAYOUT[0]))

	major_scale := compute_scale(.C, major_scale_steps)
	c_major_chord := make_chord(major_scale, major_chord)
	c_major_chord_slice := small_array.slice(&c_major_chord)
	c_major_chord_fingerings := find_fingerings_for_chord(c_major_chord_slice, BANJO_LAYOUT, 0)
	defer delete(c_major_chord_fingerings)

	for fingering in c_major_chord_fingerings {
		fmt.print("\n---fingering: ")
		for finger, i in fingering {
			string_layout := BANJO_LAYOUT[i]
			note := note_add(string_layout.open_note, finger)
			fmt.print(finger, note, ", ")
		}
	}
}

@(test)
test_compute_scale :: proc(_: ^testing.T) {
	major_scale := compute_scale(.A, major_scale_steps)
	assert(major_scale == [7]NoteKind{.A, .B, .C_Sharp, .D, .E, .F_Sharp, .G_Sharp})

}

@(test)
test_valid_fingering_for_chord :: proc(_: ^testing.T) {

	{
		c_major_scale := compute_scale(.C, major_scale_steps)
		c_major_chord := make_chord(c_major_scale, major_chord)

		assert(
			true ==
			is_fingering_for_chord_valid(
				small_array.slice(&c_major_chord),
				BANJO_LAYOUT,
				[]u8{0, 2, 0, 1, 2},
			),
		)
		// That's a C5 !
		assert(
			false ==
			is_fingering_for_chord_valid(
				small_array.slice(&c_major_chord),
				BANJO_LAYOUT,
				[]u8{0, 2, 2, 1, 2},
			),
		)
	}


	{
		g_major_scale := compute_scale(.G, major_scale_steps)
		g_major_chord := make_chord(g_major_scale, major_chord)
		assert(
			true ==
			is_fingering_for_chord_valid(
				small_array.slice(&g_major_chord),
				BANJO_LAYOUT,
				[]u8{0, 0, 0, 0, 0},
			),
		)
	}
}

@(test)
test_invalid_fingering_for_chord_distance_too_big :: proc(_: ^testing.T) {
	{
		c_major_scale := compute_scale(.C, major_scale_steps)
		c_major_chord := make_chord(c_major_scale, major_chord)

		assert(
			false ==
			is_fingering_for_chord_valid(
				small_array.slice(&c_major_chord),
				BANJO_LAYOUT,
				[]u8{0, 2, 12, 1, 2},
			),
		)
	}
}

@(test)
test_next_fingering :: proc(_: ^testing.T) {
	fingering := []u8{0, 0, 0, 0, 0}

	assert(true == next_fingering(&fingering, BANJO_LAYOUT))
	assert(slice.equal([]u8{0, 0, 0, 0, 1}, fingering))

	assert(true == next_fingering(&fingering, BANJO_LAYOUT))
	assert(slice.equal([]u8{0, 0, 0, 0, 2}, fingering))


	fingering = []u8{0, 0, 0, 0, 12}
	assert(true == next_fingering(&fingering, BANJO_LAYOUT))
	assert(slice.equal([]u8{0, 0, 0, 1, 0}, fingering))

	fingering = []u8{0, 12, 12, 12, 12}
	assert(true == next_fingering(&fingering, BANJO_LAYOUT))
	assert(slice.equal([]u8{4, 0, 0, 0, 0}, fingering))
}
