package main

import "core:container/small_array"
import "core:fmt"
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


BANJO_LAYOUT_STANDARD_5_STRINGS := StringInstrumentLayout {
	{open_note = .G, first_fret = 5, last_fret = 17},
	{open_note = .D, first_fret = 1, last_fret = 12},
	{open_note = .G, first_fret = 1, last_fret = 12},
	{open_note = .B, first_fret = 1, last_fret = 12},
	{open_note = .D, first_fret = 1, last_fret = 12},
}

GUITAR_LAYOUT_STANDARD_6_STRING := StringInstrumentLayout {
	{open_note = .E, first_fret = 1, last_fret = 12},
	{open_note = .A, first_fret = 1, last_fret = 12},
	{open_note = .D, first_fret = 1, last_fret = 12},
	{open_note = .G, first_fret = 1, last_fret = 12},
	{open_note = .B, first_fret = 1, last_fret = 12},
	{open_note = .E, first_fret = 1, last_fret = 12},
}

// Maximum distance between the two most remote fingers.
MAX_FINGER_DISTANCE :: 5

note_add :: proc(note_kind: NoteKind, offset: u8) -> NoteKind {
	return cast(NoteKind)((cast(u8)note_kind + offset) % 12)
}

next_note_kind :: proc(note_kind: NoteKind, step: Step) -> NoteKind {
	return note_add(note_kind, cast(u8)step)
}

make_scale :: proc(note_kind: NoteKind, scale: ScaleKind) -> Scale {
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

StringStateOpen :: struct {}
StringStateMuted :: struct {}
StringState :: union {
	StringStateOpen,
	StringStateMuted,
	u8,
}
MAX_STRINGS_SUPPORTED :: 10
Fingering :: small_array.Small_Array(MAX_STRINGS_SUPPORTED, StringState)

make_chord :: proc(scale: Scale, chord_kind: ChordKind) -> Chord {
	res := Chord{}

	for pos in chord_kind {
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

fingering_min_max :: proc(fingering: []StringState) -> (u8, u8, bool) {
	min: u8 = 0
	max: u8 = 0
	ok := false

	for finger in fingering {
		switch v in finger {
		case StringStateMuted:
			continue
		case StringStateOpen:
			continue
		case u8:
			ok = true
			if v < min {min = v}
			if v > max {max = v}
		}
	}
	return min, max, ok
}


is_fingering_valid_for_chord :: proc(
	chord: []NoteKind,
	instrument_layout: StringInstrumentLayout,
	// This array has as many entries as the instrument has strings.
	// `fingering[a] = b` means: the string `a` is picked on fret `b`, or if `b == 0`, the string `a` is open.
	fingering: []StringState,
) -> bool {
	assert(len(fingering) == len(instrument_layout))

	// Check that the distance between the first and last finger is <= MAX_FINGER_DISTANCE.
	{
		finger_start, finger_end, at_least_one_string_picked := fingering_min_max(fingering)
		if at_least_one_string_picked {
			dist_squared := (finger_start - finger_end) * (finger_start - finger_end)

			if dist_squared >= MAX_FINGER_DISTANCE * MAX_FINGER_DISTANCE {
				return false
			}
		}
	}

	// Check that the fingering abides by the chord.
	{
		for &finger, string_i in fingering {
			string_layout := instrument_layout[string_i]
			note, muted := make_note_for_string_state(finger, string_layout)
			// If the string is muted, it cannot invalidate the chord.
			if muted {continue}

			if !slice.contains(chord, note) {
				return false
			}
		}
	}

	return true
}

increment_string_state :: proc(
	string_state: ^StringState,
	string_layout: StringLayout,
) -> (
	keep_going: bool,
) {
	switch v in string_state^ {
	case StringStateMuted:
		string_state^ = StringStateOpen{}
		return true

	case StringStateOpen:
		string_state^ = string_layout.first_fret
		return true

	case u8:
		if v == string_layout.last_fret {
			string_state^ = StringStateMuted{}
			// Terminal state.
			return false
		} else {
			string_state^ = v + 1
			return true
		}
	}
	unreachable()
}

next_fingering :: proc(
	fingering: ^[]StringState,
	instrumentLayout: StringInstrumentLayout,
) -> (
	keep_going: bool,
) {
	assert(len(fingering) > 0)
	assert(len(fingering) == len(instrumentLayout))

	#reverse for _, string_i in fingering {
		string_layout := instrumentLayout[string_i]

		keep_going = increment_string_state(&fingering[string_i], string_layout)

		if keep_going {return true}

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
find_all_fingerings_for_chord :: proc(
	chord: []NoteKind,
	instrument_layout: StringInstrumentLayout,
) -> [][]StringState {

	res: [dynamic][]StringState
	fingering := Fingering{}
	for _ in instrument_layout {
		small_array.append(&fingering, StringStateOpen{})
	}
	assert(len(instrument_layout) == small_array.len(fingering))
	fingering_slice := small_array.slice(&fingering)

	for next_fingering(&fingering_slice, instrument_layout) {
		if !is_fingering_valid_for_chord(
			chord,
			instrument_layout,
			small_array.slice(&fingering),
		) {continue}

		clone, err := slice.clone(small_array.slice(&fingering))
		if err != nil {
			panic("clone failed")
		}

		append(&res, clone)

	}

	return res[:]
}


make_note_for_string_state :: proc(
	string_state: StringState,
	string_layout: StringLayout,
) -> (
	note: NoteKind,
	muted: bool,
) {
	switch v in string_state {
	case StringStateMuted:
		return NoteKind{}, true
	case StringStateOpen:
		return string_layout.open_note, false
	case u8:
		return note_add(string_layout.open_note, v), false
	}

	unreachable()
}

main :: proc() {
	// {
	// 	c_major_scale := make_scale(.C, major_scale_steps)
	// 	c_major_chord := make_chord(c_major_scale, major_chord)
	// 	c_major_chord_slice := small_array.slice(&c_major_chord)
	// 	c_major_chord_fingerings := find_all_fingerings_for_chord(
	// 		c_major_chord_slice,
	// 		BANJO_LAYOUT_STANDARD_5_STRINGS,
	// 	)
	// 	defer delete(c_major_chord_fingerings)

	// 	for fingering in c_major_chord_fingerings {
	// 		for finger, i in fingering {
	// 			string_layout := BANJO_LAYOUT_STANDARD_5_STRINGS[i]
	// 			note, ok := make_note_for_string_state(finger, string_layout)
	// 			if ok {
	// 				fmt.print(finger, note, " | ")
	// 			} else {
	// 				fmt.print("x  | ")
	// 			}
	// 		}
	// 	}
	// }
	fmt.println("\n---------- Banjo G ----------")
	{
		g_major_scale := make_scale(.G, major_scale_steps)
		g_major_chord := make_chord(g_major_scale, major_chord)
		g_major_chord_slice := small_array.slice(&g_major_chord)
		fmt.println(g_major_chord_slice)
		g_major_chord_fingerings := find_all_fingerings_for_chord(
			g_major_chord_slice,
			BANJO_LAYOUT_STANDARD_5_STRINGS,
		)
		defer delete(g_major_chord_fingerings)

		for fingering in g_major_chord_fingerings {
			fmt.print("\n")
			for finger, i in fingering {
				string_layout := BANJO_LAYOUT_STANDARD_5_STRINGS[i]
				note, muted := make_note_for_string_state(finger, string_layout)
				if muted {
					fmt.print("x  | ")
				} else {
					fmt.print(finger, note, " | ")
				}
			}
		}
	}
	// fmt.println("\n---------- GUITAR ----------")
	// {
	// 	g_major_scale := make_scale(.G, major_scale_steps)
	// 	g_major_chord := make_chord(g_major_scale, major_chord)
	// 	g_major_chord_slice := small_array.slice(&g_major_chord)
	// 	g_major_chord_fingerings := find_all_fingerings_for_chord(
	// 		g_major_chord_slice,
	// 		GUITAR_LAYOUT_STANDARD_6_STRING,
	// 	)
	// 	defer delete(g_major_chord_fingerings)

	// 	for fingering in g_major_chord_fingerings {
	// 		fmt.print("\n---fingering: ")
	// 		for finger, i in fingering {
	// 			string_layout := GUITAR_LAYOUT_STANDARD_6_STRING[i]
	// 			note, ok := make_note_for_string_state(finger, string_layout)
	// 			fmt.print(finger, note, ok, ", ")
	// 		}
	// 	}
	// }
}

@(test)
test_make_scale :: proc(_: ^testing.T) {
	major_scale := make_scale(.A, major_scale_steps)
	assert(major_scale == [7]NoteKind{.A, .B, .C_Sharp, .D, .E, .F_Sharp, .G_Sharp})

	minor_scale := make_scale(.A, minor_scale_steps)
	assert(minor_scale == [7]NoteKind{.A, .B, .C, .D, .E, .F, .G})
}

@(test)
test_make_chord :: proc(_: ^testing.T) {
	c_major_scale := make_scale(.C, major_scale_steps)
	c_major_chord := make_chord(c_major_scale, major_chord)
	c_major_chord_slice := small_array.slice(&c_major_chord)

	assert(slice.equal(c_major_chord_slice, []NoteKind{.C, .E, .G}))


	d_major_scale := make_scale(.D, major_scale_steps)
	d_major_7_chord := make_chord(d_major_scale, major_chord_7)
	d_major_7_chord_slice := small_array.slice(&d_major_7_chord)

	assert(slice.equal(d_major_7_chord_slice, []NoteKind{.D, .F_Sharp, .A, .C_Sharp}))
}

@(test)
test_valid_fingering_for_chord :: proc(_: ^testing.T) {
	{
		c_major_scale := make_scale(.C, major_scale_steps)
		c_major_chord := make_chord(c_major_scale, major_chord)

		assert(
			true ==
			is_fingering_valid_for_chord(
				small_array.slice(&c_major_chord),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState{StringStateOpen{}, 2, StringStateOpen{}, 1, 2},
			),
		)
		// That's a C5 !
		assert(
			false ==
			is_fingering_valid_for_chord(
				small_array.slice(&c_major_chord),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState{StringStateOpen{}, 2, 2, 1, 2},
			),
		)
	}


	{
		g_major_scale := make_scale(.G, major_scale_steps)
		g_major_chord := make_chord(g_major_scale, major_chord)
		assert(
			true ==
			is_fingering_valid_for_chord(
				small_array.slice(&g_major_chord),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState {
					StringStateOpen{},
					StringStateOpen{},
					StringStateOpen{},
					StringStateOpen{},
					StringStateOpen{},
				},
			),
		)
	}
}

@(test)
test_invalid_fingering_for_chord_distance_too_big :: proc(_: ^testing.T) {
	{
		c_major_scale := make_scale(.C, major_scale_steps)
		c_major_chord := make_chord(c_major_scale, major_chord)

		assert(
			false ==
			is_fingering_valid_for_chord(
				small_array.slice(&c_major_chord),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState{StringStateOpen{}, 2, 12, 1, 2},
			),
		)
	}
}

@(test)
test_next_fingering :: proc(_: ^testing.T) {
	fingering := []StringState {
		StringStateOpen{},
		StringStateOpen{},
		StringStateOpen{},
		StringStateOpen{},
		StringStateOpen{},
	}

	assert(true == next_fingering(&fingering, BANJO_LAYOUT_STANDARD_5_STRINGS))
	assert(
		slice.equal(
			[]StringState {
				StringStateOpen{},
				StringStateOpen{},
				StringStateOpen{},
				StringStateOpen{},
				1,
			},
			fingering,
		),
	)

	assert(true == next_fingering(&fingering, BANJO_LAYOUT_STANDARD_5_STRINGS))
	assert(
		slice.equal(
			[]StringState {
				StringStateOpen{},
				StringStateOpen{},
				StringStateOpen{},
				StringStateOpen{},
				2,
			},
			fingering,
		),
	)


	fingering = []StringState {
		StringStateOpen{},
		StringStateOpen{},
		StringStateOpen{},
		StringStateOpen{},
		12,
	}
	assert(true == next_fingering(&fingering, BANJO_LAYOUT_STANDARD_5_STRINGS))
	v: u8
	ok: bool
	_, ok = fingering[0].(StringStateOpen)
	assert(ok)
	_, ok = fingering[1].(StringStateOpen)
	assert(ok)
	_, ok = fingering[2].(StringStateOpen)
	assert(ok)
	v, ok = fingering[3].(u8)
	assert(ok)
	assert(v == u8(1))
	_, ok = fingering[4].(StringStateMuted)
	assert(ok)

	fingering = []StringState{StringStateOpen{}, 12, 12, 12, 12}
	assert(true == next_fingering(&fingering, BANJO_LAYOUT_STANDARD_5_STRINGS))

	v, ok = fingering[0].(u8)
	assert(ok)
	assert(v == u8(BANJO_LAYOUT_STANDARD_5_STRINGS[0].first_fret))
	_, ok = fingering[1].(StringStateMuted)
	assert(ok)
	_, ok = fingering[2].(StringStateMuted)
	assert(ok)
	_, ok = fingering[3].(StringStateMuted)
	assert(ok)
	_, ok = fingering[4].(StringStateMuted)
	assert(ok)
}

@(test)
test_increment_string_state :: proc(_: ^testing.T) {
	string_layout := BANJO_LAYOUT_STANDARD_5_STRINGS[0]

	{
		string_state: StringState = StringStateMuted{}
		keep_going := increment_string_state(&string_state, string_layout)
		assert(keep_going)
		_, ok := string_state.(StringStateOpen)
		assert(ok)
	}


	{
		string_state: StringState = StringStateOpen{}
		keep_going := increment_string_state(&string_state, string_layout)
		assert(keep_going)

		v, ok := string_state.(u8)
		assert(ok)
		assert(v == string_layout.first_fret)
	}

	{
		string_state: StringState = string_layout.first_fret
		keep_going := increment_string_state(&string_state, string_layout)
		assert(keep_going)

		v, ok := string_state.(u8)
		assert(ok)
		assert(v == string_layout.first_fret + 1)
	}

	{
		string_state: StringState = string_layout.last_fret - 1
		keep_going := increment_string_state(&string_state, string_layout)
		assert(keep_going)

		v, ok := string_state.(u8)
		assert(ok)
		assert(v == string_layout.last_fret)
	}
	{
		string_state: StringState = string_layout.last_fret
		keep_going := increment_string_state(&string_state, string_layout)
		assert(!keep_going)

		_, ok := string_state.(StringStateMuted)
		assert(ok)
	}
}

@(test)
test_make_note_for_string_state :: proc(_: ^testing.T) {
	string_layout := BANJO_LAYOUT_STANDARD_5_STRINGS[0]
	{
		_, muted := make_note_for_string_state(StringStateMuted{}, string_layout)
		assert(muted)
	}
	{
		note, muted := make_note_for_string_state(StringStateOpen{}, string_layout)
		assert(!muted)
		assert(note == string_layout.open_note)
	}
	{
		note, muted := make_note_for_string_state(u8(2), string_layout)
		assert(!muted)
		assert(note == .A)
	}
}
