def safe_profile(df):
    import pandas as pd
    return pd.DataFrame({
        "dtype": df.dtypes.astype(str),
        "n_na": df.isna().sum(),
        "n_unique": df.nunique(),
    }).assign(n_rows=len(df))
