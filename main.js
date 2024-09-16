const Note = {
  A: 0,
  A_Sharp: 1,
  B: 2,
  C: 3,
  C_Sharp: 4,
  D: 5,
  D_Sharp: 6,
  E: 7,
  F: 8,
  F_Sharp: 9,
  G: 10,
  G_Sharp: 11
};

const Step = {
  Half : 1,
  Whole : 2,
};

const major_scale_steps = [Step.Whole, Step.Whole, Step.Half, Step.Whole, Step.Whole, Step.Whole, Step.Half];
const minor_scale_steps = [Step.Whole, Step.Half, Step.Whole, Step.Whole, Step.Half, Step.Whole, Step.Whole];

const chord_kind_standard = [1, 3, 5];
const chord_kind_5 = [1, 5];
const chord_kind_7 = [1, 3, 5, 7];
const chord_kind_9 = [1, 3, 5, 7, 9];
const chord_kind_11 = [1, 3, 5, 7, 9, 11];
const chord_kind_13 = [1, 3, 5, 7, 9, 13];

const banjo_layout_standard_5_strings = [
  {open_note: Note.G, first_fret: 5, last_fret: 17},
  {open_note: Note.D, first_fret: 1, last_fret: 17},
  {open_note: Note.G, first_fret: 1, last_fret: 17},
  {open_note: Note.B, first_fret: 1, last_fret: 17},
  {open_note: Note.D, first_fret: 1, last_fret: 17},
];

const StringState = {
  Muted: -1,
  Open: 0,
};

const MAX_FINGER_DISTANCE = 4;

function note_add_semitones(note, semitones) {
  return (note + semitones) % 12;
}

function make_scale(base_note, scale_kind) {
  const res = [base_note, 0, 0, 0, 0, 0, 0, 0];

  for (let i=1; i<res.length; i+=1) {
    res[i] = note_add_semitones(res[i-1], scale_kind[i-1]);
  }
  return res;
}

function make_chord(scale, chord_kind) {
  const res = [];

  for (const pos of chord_kind) {
    const i = (pos <= 8) ? pos - 1 : (pos % 8);
    res.push(scale[i]);
  }
  return res;
}

function fingering_min_max(fingering) {
  const res = {min:0, max: 0, at_least_one_string_picked: false};

  for (const finger of fingering) {
    if (finger == StringState.Muted) { continue; }
    else if (finger == StringState.Open) { continue; }

    res.min = fret < res.min ? fret : res.min;
    res.max = res.max < fret ? fret : res.max;
  }

  return res;
}

function is_fingering_valid_for_chord(chord, instrument_layout, fingering) {
	// Check that the distance between the first and last finger is <= MAX_FINGER_DISTANCE.
  {
    const {finger_start, finger_end, at_least_one_string_picked} = fingering_min_max(fingering);
    if (at_least_one_string_picked) {
      const dist_sq = (finger_start - finger_end) * (finger_start - finger_end);
      if (dist_sq >= MAX_FINGER_DISTANCE * MAX_FINGER_DISTANCE) { return false; }
    }
  }

	// Check that the fingering abides by the chord.
  {
    for (let i =0; i < fingering.length; i +=1 ) {
      const string_layout = instrument_layout[i];
      const note = make_note_for_string_state(finger, string_layout);
			// If the string is muted, it cannot invalidate the chord.
      if (note == StringState.Muted) { continue; }

      if (!chord.contains(note)) { return false; }
    }
  }
}

function make_note_for_string_state(string_state, string_layout) {
  if (fret == StringState.Muted) { return 0; }
  else if (fret == StringState.Open) { return string_layout.open_note; }
  return note_add_semitones(string_layout.open_note, fret);
}

function find_all_fingerings_for_chord(chord, instrument_layout, note_count_at_least) {
  const res = [];
  const fingering = [];

  for (_ of instrument_layout) {
    fingering.push(StringState.Muted);
  }

  while (next_fingering(fingering, instrument_layout)) {
    if (!is_fingering_valid_for_chord(chord, instrument_layout, fingering)) { continue; }
    if (count_notes_in_fingering(fingering) < note_count_at_least) { continue; }

    res.push(fingering);
  }

  return res;
}

function count_notes_in_fingering(fingering) {
  let count = 0;

  for (string_state of fingering) {
    count += (string_state != StringState.Muted);
  }

  return count;
}

function next_fingering(fingering, instrument_layout) {
  for (let i =fingering.length; i>=0; i-=1) {
    const string_layout = instrument_layout[i];
    const keep_going = increment_string_state(fingering[i], string_layout);
    if (keep_going) return true;
    
		// The slot has reached the maximum value, need to inspect the left-hand part to increment it, in the next loop iteration.
  }

  return false;
}

const c_major_scale = make_scale(Note.C, major_scale_steps);
console.log(make_chord(c_major_scale, chord_kind_standard));
