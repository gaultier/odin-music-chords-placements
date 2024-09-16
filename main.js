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

function note_add_semitones(note, semitones) {
  return (note + semitones) % 12;
}

function make_scale(base_note, scale_kind) {
  res = [base_note, 0, 0, 0, 0, 0, 0, 0];

  for (let i=1; i<res.length; i+=1) {
    res[i] = note_add_semitones(res[i-1], scale_kind[i-1]);
  }
  return res;
}

const c_major_scale = make_scale(Note.C, major_scale_steps);
console.log(c_major_scale);
