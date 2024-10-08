package main

import "core:container/small_array"
import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strconv"
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

// Count in semi-tones.
Step :: enum {
	Half  = 1,
	Whole = 2,
}


ScaleKind :: [7]Step
major_scale_steps :: ScaleKind{.Whole, .Whole, .Half, .Whole, .Whole, .Whole, .Half}
minor_scale_steps :: ScaleKind{.Whole, .Half, .Whole, .Whole, .Half, .Whole, .Whole}

Scale :: [7]NoteKind


// FIXME: last_fret
BANJO_LAYOUT_STANDARD_5_STRINGS := StringInstrumentLayout {
	{open_note = .G, first_fret = 5, last_fret = 17},
	{open_note = .D, first_fret = 1, last_fret = 17},
	{open_note = .G, first_fret = 1, last_fret = 17},
	{open_note = .B, first_fret = 1, last_fret = 17},
	{open_note = .D, first_fret = 1, last_fret = 17},
}

// FIXME: last_fret
GUITAR_LAYOUT_STANDARD_6_STRING := StringInstrumentLayout {
	{open_note = .E, first_fret = 1, last_fret = 12},
	{open_note = .A, first_fret = 1, last_fret = 12},
	{open_note = .D, first_fret = 1, last_fret = 12},
	{open_note = .G, first_fret = 1, last_fret = 12},
	{open_note = .B, first_fret = 1, last_fret = 12},
	{open_note = .E, first_fret = 1, last_fret = 12},
}

// Maximum distance between the two most remote fingers.
MAX_FINGER_DISTANCE :: 4

@(require_results)
note_add_semitones :: proc(note_kind: NoteKind, offset: u8) -> NoteKind {
	return cast(NoteKind)((cast(u8)note_kind + offset) % 12)
}

@(require_results)
make_scale :: proc(base_note: NoteKind, scale: ScaleKind) -> Scale {
	res := Scale{}
	res[0] = base_note

	for i := 1; i < len(res); i += 1 {
		res[i] = note_add_semitones(res[i - 1], cast(u8)scale[i - 1])
	}

	assert(note_add_semitones(res[len(res) - 1], cast(u8)scale[len(scale) - 1]) == res[0])
	assert(base_note == res[0])

	return res
}

ChordKind :: []u8
// 1-indexed to follow the music theory material.
chord_kind_standard :: ChordKind{1, 3, 5}
chord_kind_5 :: ChordKind{1, 5}
chord_kind_6 :: ChordKind{1, 3, 5, 6}
chord_kind_7 :: ChordKind{1, 3, 5, 7}
chord_kind_9 :: ChordKind{1, 3, 5, 7, 9}
chord_kind_11 :: ChordKind{1, 3, 5, 7, 9, 11}
chord_kind_13 :: ChordKind{1, 3, 5, 7, 9, 11, 13}

Chord :: small_array.Small_Array(10, NoteKind)

// nil: muted.
// 0: open
// N where N > 0: picked on fret N.
StringState :: Maybe(u8)

MAX_STRINGS_SUPPORTED :: 10
Fingering :: small_array.Small_Array(MAX_STRINGS_SUPPORTED, StringState)

@(require_results)
make_chord :: proc(scale: Scale, chord_kind: ChordKind) -> Chord {
	res := Chord{}

	for pos in chord_kind {
		// `pos` is 1-indexed so we have to make it zero-indexed.
		// We could go beyond the scale e.g. 9th, 11th, 13th, etc so we loop around with `%`.
		pos := pos - 1 if pos <= 8 else pos
		i := pos % 8
		small_array.push(&res, scale[i])
	}
	return res
}

StringLayout :: struct {
	open_note:  NoteKind,
	first_fret: u8,
	last_fret:  u8,
}

StringInstrumentLayout :: []StringLayout

@(require_results)
fingering_min_max :: proc(fingering: []StringState) -> (res_min: Maybe(u8), res_max: Maybe(u8)) {
	for finger in fingering {
		fret := finger.? or_continue

		if fret == 0 {continue}

		if res_min_value, ok := res_min.?; ok {
			res_min = min(res_min_value, fret)
		} else {
			res_min = fret
		}

		if res_max_value, ok := res_max.?; ok {
			res_max = max(res_max_value, fret)
		} else {
			res_max = fret
		}
	}

	_, res_min_ok := res_min.?
	_, res_max_ok := res_max.?

	if res_min_ok && !res_max_ok {
		res_max = res_min
	}

	if res_max_ok && !res_min_ok {
		res_min = res_max
	}

	return res_min, res_max
}


@(require_results)
is_fingering_valid_for_chord :: proc(
	chord: []NoteKind,
	instrument_layout: StringInstrumentLayout,
	// This array has as many entries as the instrument has strings.
	// `fingering[a] = b` means: the string `a` is picked on fret `b`, or if `b == 0`, the string `a` is open.
	fingering: []StringState,
	note_count_at_least: u8,
) -> bool {
	assert(len(fingering) == len(instrument_layout))

	// Check that the distance between the first and last finger is <= MAX_FINGER_DISTANCE.
	{
		finger_start, finger_end := fingering_min_max(fingering)
		finger_start_value, start_ok := finger_start.?
		finger_end_value, end_ok := finger_end.?
		if start_ok && end_ok {
			dist_squared :=
				(uint(finger_start_value) - uint(finger_end_value)) *
				(uint(finger_start_value) - uint(finger_end_value))

			if dist_squared >= MAX_FINGER_DISTANCE * MAX_FINGER_DISTANCE {return false}
		}
	}

	// Check that the fingering abides by the chord.
	{
		notes: Chord

		for finger, string_i in fingering {
			string_layout := instrument_layout[string_i]
			note := make_note_for_string_state(finger, string_layout) or_continue

			small_array.append(&notes, note)
		}

		if small_array.len(notes) < int(note_count_at_least) {
			return false
		}
		assert(small_array.len(notes) > 0)

		if small_array.get(notes, 0) != chord[0] { 	// Prevent a seemingly valid chord but inverted e.g. `C/G`.
			return false
		}

		for note in small_array.slice(&notes) {
			if !slice.contains(chord, note) {return false}
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
	// The state machine is:
	// Muted (nil) -> Open (0) -> Picked(first_fret) -> ... -> Picked(last_fret) -> Muted

	fret, ok := string_state.?

	// Muted -> Open (0)
	if !ok {
		string_state^ = 0
		return true
	}

	// Open(0) -> Picked(first_fret)
	if fret == 0 {
		string_state^ = string_layout.first_fret
		return true
	}


	if fret == string_layout.last_fret { 	// Picked(last_fret) -> Muted
		string_state^ = nil
		// Terminal state.
		return false
	} else { 	// Picked(N) -> Picked(N+1)
		string_state^ = fret + 1
		return true
	}
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

		// The slot has reached the maximum value, need to inspect the left-hand part to increment it, in the next loop iteration.
	}

	// Reached the end.
	return false
}

// Order by open notes desc.
@(require_results)
order_fingering_by_proximity_to_the_neck :: proc(a: []StringState, b: []StringState) -> bool {
	a_min, _ := fingering_min_max(a)
	b_min, _ := fingering_min_max(b)

	return a_min.? < b_min.?
}

// Rules:
// - Each string is either muted, open, or picked by one finger and produces 0 (muted) or 1 (otherwise) note .
// - The maximum distance between all picked frets is 4 or 5 due to the physical length of fingers.
// - Every fret of every string gets considered
// TODO: muted strings.
@(require_results)
find_all_fingerings_for_chord :: proc(
	chord: []NoteKind,
	instrument_layout: StringInstrumentLayout,
	note_count_at_least: u8,
) -> [][]StringState {
	res: [dynamic][]StringState
	fingering := Fingering{}
	for _ in instrument_layout {
		small_array.append(&fingering, nil)
	}
	assert(len(instrument_layout) == small_array.len(fingering))
	fingering_slice := small_array.slice(&fingering)

	for next_fingering(&fingering_slice, instrument_layout) {
		if !is_fingering_valid_for_chord(
			chord,
			instrument_layout,
			small_array.slice(&fingering),
			note_count_at_least,
		) {continue}

		clone, err := slice.clone(small_array.slice(&fingering))
		if err != nil {panic("clone failed")}

		append(&res, clone)
	}

	return res[:]
}


@(require_results)
make_note_for_string_state :: proc(
	string_state: StringState,
	string_layout: StringLayout,
) -> (
	note: NoteKind,
	ok: bool,
) {
	fret := string_state.? or_return

	if fret == 0 {
		return string_layout.open_note, true
	}
	return note_add_semitones(string_layout.open_note, fret), true
}

print_fingering :: proc(fingering: []StringState, instrument_layout: StringInstrumentLayout) {
	for string_state, i in fingering {
		string_layout := instrument_layout[i]
		note, _ := make_note_for_string_state(string_state, string_layout)

		fret, ok := string_state.?
		if !ok {
			fmt.print("x")
		} else {
			fmt.print(fret, note)
		}

		if i < len(fingering) - 1 {
			fmt.print(" | ")
		}
	}
	fmt.print("\n")
}

@(require_results)
parse_chord :: proc(chord: string) -> (res: Chord, ok: bool) {
	chord_slice := transmute([]u8)chord
	base_note_char, rest := slice.split_first(chord_slice)

	is_sharp: bool
	if len(rest) > 0 && slice.first(rest) == '#' {
		_, rest = slice.split_first(rest)
		is_sharp = true
	}

	base_note := NoteKind.A
	switch base_note_char {
	case 'A':
		base_note = .A_Sharp if is_sharp else .A
	case 'B':
		if is_sharp {return {}, false}
		base_note = .B
	case 'C':
		base_note = .C_Sharp if is_sharp else .C
	case 'D':
		base_note = .D_Sharp if is_sharp else .D
	case 'E':
		if is_sharp {return {}, false}
		base_note = .E
	case 'F':
		base_note = .F_Sharp if is_sharp else .F
	case 'G':
		base_note = .G_Sharp if is_sharp else .G
	case:
		return {}, false
	}

	is_minor: bool
	if len(rest) > 0 && slice.first(rest) == 'm' {
		_, rest = slice.split_first(rest)
		is_minor = true
	}


	// TODO: maj, sus, add ...


	level: u64
	is_level_present: bool
	if len(rest) > 0 {
		level = strconv.parse_u64(transmute(string)rest) or_return
		is_level_present = true
	}

	if is_level_present && level < 5 {return {}, false}

	// TODO: /9, ...

	steps := minor_scale_steps if is_minor else major_scale_steps
	scale := make_scale(base_note, steps)

	if !is_level_present {
		return make_chord(scale, chord_kind_standard), true
	}

	switch level {
	case 5:
		return make_chord(scale, chord_kind_5), true
	case 6:
		return make_chord(scale, chord_kind_6), true
	case 7:
		return make_chord(scale, chord_kind_7), true
	case 9:
		return make_chord(scale, chord_kind_9), true
	case 11:
		res = make_chord(scale, chord_kind_11)
		if !is_minor {
			// In case of a major, raise the 11th by a semi-tone to avoid dissonance.
			res.data[small_array.len(res) - 1] = note_add_semitones(
				res.data[small_array.len(res) - 1],
				1,
			)
		}
		return res, true
	case 13:
		res = make_chord(scale, chord_kind_13)
		if is_minor {
			// In case of a minor, raise the 13th by a semi-tone to avoid dissonance.
			res.data[small_array.len(res) - 1] = note_add_semitones(
				res.data[small_array.len(res) - 1],
				1,
			)
		}
		return res, true
	case:
		return {}, false
	}
}

find_all_fingerings_json_for_chord_str :: proc(chord_str: string) -> []u8 {
	chord, ok := parse_chord("Cm13")
	if !ok {return {}}

	fingerings := find_all_fingerings_for_chord(
		small_array.slice(&chord),
		BANJO_LAYOUT_STANDARD_5_STRINGS,
		2,
	)
	defer delete(fingerings)

	res, _ := json.marshal(fingerings)
	return res
}

main :: proc() {

	fmt.println("---------- Banjo C ----------")
	{
		c_major_scale := make_scale(.C, major_scale_steps)
		c_chord_kind_standard := make_chord(c_major_scale, chord_kind_standard)
		c_chord_kind_standard_slice := small_array.slice(&c_chord_kind_standard)
		fmt.println(c_chord_kind_standard_slice)

		c_chord_kind_standard_fingerings := find_all_fingerings_for_chord(
			c_chord_kind_standard_slice,
			BANJO_LAYOUT_STANDARD_5_STRINGS,
			3,
		)
		defer delete(c_chord_kind_standard_fingerings)

		slice.sort_by(c_chord_kind_standard_fingerings, order_fingering_by_proximity_to_the_neck)

		fmt.println(len(c_chord_kind_standard_fingerings))
		for fingering in c_chord_kind_standard_fingerings {
			print_fingering(fingering, BANJO_LAYOUT_STANDARD_5_STRINGS)
		}
	}
	// fmt.println("---------- Banjo G ----------")
	// {
	// 	g_major_scale := make_scale(.G, major_scale_steps)
	// 	g_chord_kind_standard := make_chord(g_major_scale, chord_kind_standard)
	// 	g_chord_kind_standard_slice := small_array.slice(&g_chord_kind_standard)
	// 	fmt.println(g_chord_kind_standard_slice)
	// 	g_chord_kind_standard_fingerings := find_all_fingerings_for_chord(
	// 		g_chord_kind_standard_slice,
	// 		BANJO_LAYOUT_STANDARD_5_STRINGS,
	// 		3,
	// 	)
	// 	defer delete(g_chord_kind_standard_fingerings)

	// 	slice.sort_by(g_chord_kind_standard_fingerings, order_fingering_by_ease)

	// 	fmt.println(len(g_chord_kind_standard_fingerings))
	// 	for fingering in g_chord_kind_standard_fingerings {
	// 		print_fingering(fingering, BANJO_LAYOUT_STANDARD_5_STRINGS)
	// 	}
	// }
	// fmt.println("---------- GUITAR ----------")
	// {
	// 	g_major_scale := make_scale(.G, major_scale_steps)
	// 	g_chord_kind_standard := make_chord(g_major_scale, chord_kind_standard)
	// 	g_chord_kind_standard_slice := small_array.slice(&g_chord_kind_standard)
	// 	fmt.println(g_chord_kind_standard_slice)
	// 	g_chord_kind_standard_fingerings := find_all_fingerings_for_chord(
	// 		g_chord_kind_standard_slice,
	// 		GUITAR_LAYOUT_STANDARD_6_STRING,
	// 		3,
	// 	)
	// 	defer delete(g_chord_kind_standard_fingerings)

	// 	fmt.println(len(g_chord_kind_standard_fingerings))
	// 	for fingering in g_chord_kind_standard_fingerings {
	// 		print_fingering(fingering, GUITAR_LAYOUT_STANDARD_6_STRING)
	// 	}
	// }

	// j := find_all_fingerings_json_for_chord_str("Am")
	// defer delete(j)
	// fmt.printf("%s", j)
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
	c_chord_kind_standard := make_chord(c_major_scale, chord_kind_standard)
	c_chord_kind_standard_slice := small_array.slice(&c_chord_kind_standard)

	assert(slice.equal(c_chord_kind_standard_slice, []NoteKind{.C, .E, .G}))


	d_major_scale := make_scale(.D, major_scale_steps)
	d_major_7_chord := make_chord(d_major_scale, chord_kind_7)
	d_major_7_chord_slice := small_array.slice(&d_major_7_chord)

	assert(slice.equal(d_major_7_chord_slice, []NoteKind{.D, .F_Sharp, .A, .C_Sharp}))
}

@(test)
test_valid_fingering_for_chord :: proc(_: ^testing.T) {
	{
		c_major_scale := make_scale(.C, major_scale_steps)
		c_chord_kind_standard := make_chord(c_major_scale, chord_kind_standard)

		// `C/E`, invalid.
		assert(
			false ==
			is_fingering_valid_for_chord(
				small_array.slice(&c_chord_kind_standard),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState{0, 2, 0, 1, 2},
				3,
			),
		)
		// `C5`, invalid.
		assert(
			false ==
			is_fingering_valid_for_chord(
				small_array.slice(&c_chord_kind_standard),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState{0, 2, 2, 1, 2},
				3,
			),
		)

		// Not enough notes.
		assert(
			false ==
			is_fingering_valid_for_chord(
				small_array.slice(&c_chord_kind_standard),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState{nil, nil, 3, 3, nil},
				3,
			),
		)

		// Distance too big.
		assert(
			false == is_fingering_valid_for_chord(
				small_array.slice(&c_chord_kind_standard),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState {
					nil,
					nil,
					5, /* C */
					1, /* C */
					17, /* G */
				},
				3,
			),
		)
		// Valid.
		assert(
			true == is_fingering_valid_for_chord(
				small_array.slice(&c_chord_kind_standard),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState {
					nil,
					nil,
					5, /* C */
					5, /* E */
					5, /* G */
				},
				3,
			),
		)
	}


	{
		g_major_scale := make_scale(.G, major_scale_steps)
		g_chord_kind_standard := make_chord(g_major_scale, chord_kind_standard)
		assert(
			true ==
			is_fingering_valid_for_chord(
				small_array.slice(&g_chord_kind_standard),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState{0, 0, 0, 0, 0},
				3,
			),
		)
	}
}

@(test)
test_invalid_fingering_for_chord_distance_too_big :: proc(_: ^testing.T) {
	{
		c_major_scale := make_scale(.C, major_scale_steps)
		c_chord_kind_standard := make_chord(c_major_scale, chord_kind_standard)

		assert(
			false ==
			is_fingering_valid_for_chord(
				small_array.slice(&c_chord_kind_standard),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState{0, 2, 12, 1, 2},
				3,
			),
		)
	}
}

@(test)
test_next_fingering :: proc(_: ^testing.T) {
	fingering := []StringState{0, 0, 0, 0, 0}

	assert(true == next_fingering(&fingering, BANJO_LAYOUT_STANDARD_5_STRINGS))
	assert(slice.equal([]StringState{0, 0, 0, 0, 1}, fingering))

	assert(true == next_fingering(&fingering, BANJO_LAYOUT_STANDARD_5_STRINGS))
	assert(slice.equal([]StringState{0, 0, 0, 0, 2}, fingering))


	fingering = []StringState{0, 0, 0, 0, BANJO_LAYOUT_STANDARD_5_STRINGS[4].last_fret}
	assert(true == next_fingering(&fingering, BANJO_LAYOUT_STANDARD_5_STRINGS))

	fret: u8
	ok: bool
	fret, ok = fingering[0].?
	assert(ok && fret == 0)
	fret, ok = fingering[1].?
	assert(ok && fret == 0)
	fret, ok = fingering[2].?
	assert(ok && fret == 0)

	fret, ok = fingering[3].?
	assert(ok && fret == 1)

	_, ok = fingering[4].?
	assert(!ok)

	fingering = []StringState {
		0,
		BANJO_LAYOUT_STANDARD_5_STRINGS[1].last_fret,
		BANJO_LAYOUT_STANDARD_5_STRINGS[2].last_fret,
		BANJO_LAYOUT_STANDARD_5_STRINGS[3].last_fret,
		BANJO_LAYOUT_STANDARD_5_STRINGS[4].last_fret,
	}
	assert(true == next_fingering(&fingering, BANJO_LAYOUT_STANDARD_5_STRINGS))

	fret, ok = fingering[0].?
	assert(ok)
	assert(fret == u8(BANJO_LAYOUT_STANDARD_5_STRINGS[0].first_fret))

	_, ok = fingering[1].?
	assert(!ok)
	_, ok = fingering[2].?
	assert(!ok)
	_, ok = fingering[3].?
	assert(!ok)
	_, ok = fingering[4].?
	assert(!ok)
}

@(test)
test_increment_string_state :: proc(_: ^testing.T) {
	string_layout := BANJO_LAYOUT_STANDARD_5_STRINGS[0]

	{
		string_state: StringState = nil
		keep_going := increment_string_state(&string_state, string_layout)
		assert(keep_going)
		fret, ok := string_state.?
		assert(ok && fret == 0)
	}


	{
		string_state: StringState = 0
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

		_, ok := string_state.?
		assert(!ok)
	}
}

@(test)
test_make_note_for_string_state :: proc(_: ^testing.T) {
	string_layout := BANJO_LAYOUT_STANDARD_5_STRINGS[0]
	{
		_, ok := make_note_for_string_state(nil, string_layout)
		assert(!ok)
	}
	{
		note, ok := make_note_for_string_state(0, string_layout)
		assert(ok)
		assert(note == string_layout.open_note)
	}
	{
		note, ok := make_note_for_string_state(u8(2), string_layout)
		assert(ok)
		assert(note == .A)
	}
}

@(test)
test_parse_chord :: proc(_: ^testing.T) {
	{
		chord, ok := parse_chord("A")
		assert(ok)
		fmt.println(small_array.slice(&chord))
		assert(slice.equal(small_array.slice(&chord), []NoteKind{.A, .C_Sharp, .E}))
	}
	{
		_, ok := parse_chord("A1")
		assert(!ok)
	}
	{
		chord, ok := parse_chord("C5")
		assert(ok)
		fmt.println(small_array.slice(&chord))
		assert(slice.equal(small_array.slice(&chord), []NoteKind{.C, .G}))
	}
	{
		_, ok := parse_chord("G8")
		assert(!ok)
	}
	{
		chord, ok := parse_chord("F#")
		assert(ok)
		fmt.println(small_array.slice(&chord))
		assert(slice.equal(small_array.slice(&chord), []NoteKind{.F_Sharp, .A_Sharp, .C_Sharp}))
	}
	{
		chord, ok := parse_chord("F#5")
		assert(ok)
		fmt.println(small_array.slice(&chord))
		assert(slice.equal(small_array.slice(&chord), []NoteKind{.F_Sharp, .C_Sharp}))
	}

	{
		chord, ok := parse_chord("Am")
		assert(ok)
		fmt.println(small_array.slice(&chord))
		assert(slice.equal(small_array.slice(&chord), []NoteKind{.A, .C, .E}))
	}
	{
		chord, ok := parse_chord("Cm13")
		assert(ok)
		fmt.println(small_array.slice(&chord))
		assert(
			slice.equal(
				small_array.slice(&chord),
				[]NoteKind{.C, .D_Sharp, .G, .A_Sharp, .D, .F, .A},
			),
		)
	}
}
