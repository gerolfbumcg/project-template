import pandas as pd


def normalise_score(df: pd.DataFrame, column: str = "score") -> pd.DataFrame:
    """Return df with an extra <column>_norm column scaled to 0-1."""
    if column not in df.columns:
        raise KeyError(f"column {column!r} not in data frame")
    span = df[column].max() - df[column].min()
    df = df.copy()
    df[f"{column}_norm"] = pd.NA if span == 0 else (df[column] - df[column].min()) / span
    return df


def add_age_at_admission(df: pd.DataFrame) -> pd.DataFrame:
    """Return df with age at admission derived from birth_year and admission_date."""
    missing = {"birth_year", "admission_date"} - set(df.columns)
    if missing:
        raise KeyError(f"missing columns: {sorted(missing)}")
    df = df.copy()
    df["age_at_admission"] = pd.to_datetime(df["admission_date"]).dt.year - df["birth_year"]
    return df
