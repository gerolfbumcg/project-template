import pandas as pd, pytest
from pathlib import Path

@pytest.fixture
def patients():
    return pd.read_csv(Path(__file__).parent / "fixtures" / "patients.csv")
