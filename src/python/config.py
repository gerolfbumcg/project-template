import os
from pathlib import Path

VAULT_SECRETS_FILE = "secrets.env"
PROJECT_ROOT = Path(__file__).resolve().parents[2]


def _read_env_file(path: Path) -> None:
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip().strip("\"'"))


def _required(name: str) -> str:
    value = os.environ.get(name, "")   # envcheck: ignore -- generic accessor
    if not value:
        raise RuntimeError(f"environment variable {name} is not set")
    return value


def load_config() -> dict:
    vault_root = os.environ.get("VAULT_ROOT", "")
    if vault_root:
        secrets = Path(vault_root) / PROJECT_ROOT.name / VAULT_SECRETS_FILE
        if not secrets.is_file():
            raise RuntimeError(f"VAULT_ROOT is set but {secrets} does not exist.")
        _read_env_file(secrets)
    else:
        os.environ.setdefault("PROJECT_DATA_DIR", str(PROJECT_ROOT / "tests" / "fixtures"))
        os.environ.setdefault("PROJECT_OUTPUT_DIR", str(PROJECT_ROOT / "tmp" / "output"))

    # Add credentials as the project starts needing them, and uncomment the
    # matching key in .env.example in the same edit:
    #   "db_host": _required("DB_HOST"),
    #   "db_pass": _required("DB_PASSWORD"),
    return {
        "data_dir": Path(_required("PROJECT_DATA_DIR")),
        "output_dir": Path(_required("PROJECT_OUTPUT_DIR")),
    }
