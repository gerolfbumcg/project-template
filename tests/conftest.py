import sys
import pandas as pd, pytest
from pathlib import Path

# `src/python/` holds plain modules, not an installed package, so it is not
# importable otherwise. The R side does the same in tests/testthat/helper-src.R.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src" / "python"))

@pytest.fixture
def patients():
    return pd.read_csv(Path(__file__).parent / "fixtures" / "patients.csv")
