from processing import add_age_at_admission, normalise_score


def test_score_is_normalised(patients):
    norm = normalise_score(patients)["score_norm"].dropna()
    assert ((norm >= 0) & (norm <= 1)).all()


def test_normalise_score_leaves_its_input_alone(patients):
    # Rule 4 in section 3: same input, same output. Without the copy in
    # normalise_score the order the tests run in would start to matter.
    before = list(patients.columns)
    normalise_score(patients)
    assert list(patients.columns) == before


def test_age_at_admission_is_derived(patients):
    out = add_age_at_admission(patients)
    ages = out["age_at_admission"].dropna()
    assert len(ages) > 0
    assert ((ages >= 0) & (ages <= 120)).all()
