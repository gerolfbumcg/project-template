# Veilig werken met een LLM-assistent in R en Python

Handleiding voor het opzetten van een project waarin een assistent (Positron, Claude Code)
volledig kan meelezen zonder dat er ooit secrets of echte data in beeld komen.

**Uitgangspunt:** het doel is niet om gevoeligheden goed te versleutelen, maar om ervoor
te zorgen dat ze er niet zijn. Encryptie is een pleister op een situatie waarin gevoelige
gegevens ergens staan waar ze niet horen. Deze handleiding werkt daarom naar een opzet toe
waarin de laptop — de machine waar de assistent draait — structureel niets gevoeligs bevat.

> Alle code, mapnamen, bestandsnamen en identifiers zijn Engelstalig en identiek aan de
> Engelse versie van deze handleiding (`secure-project-setup-EN.md`). Alleen de toelichting
> is Nederlands.

---

## 1. Bedreigingsmodel

Waar het concreet mis kan gaan:

| Route | Voorbeeld |
|---|---|
| Commit | `git add .` pakt een `.csv` met echte gegevens mee |
| Git-historie | een secret is later verwijderd maar staat nog in oude commits |
| Assistent leest bestand | agent opent `.Renviron` "om context te krijgen" |
| Assistent leest console | je draait code met echte data in de sessie waar de assistent meekijkt |
| Gerenderde output | `_freeze/`, `*_files/`, `.html` bevatten uitgevoerde resultaten |
| Sessie-residu | `.RData` en `.Rhistory` bevatten je laatste objecten |
| Handmatige plak | je kopieert een foutmelding met een patiëntnaam erin naar de chat |

De eerste twee dek je af met tooling. De rest dek je alleen af met **structuur**: de
gevoelige gegevens staan op een plek waar de assistent fysiek niet bij kan.

---

## 2. De drie zones

```
LAPTOP                                POSIT WORKBENCH
──────                                ───────────────
~/projects/myproject/                 ~/projects/myproject/
   = git repository                      = the same git repository
   = Positron workspace                  = no assistant running
   = Claude Code scope
   = fixtures, no real data                       │
   = .env.example, no secrets                     │ reads via environment variables
                                                  ▼
                                       /share/projects/myproject/
                                          = the "vault": real data and secrets
                                          = not reachable from outside
                                          = not inside any workspace root
```

Drie regels die hieruit volgen:

1. **De laptop is schoon by construction.** Daar staat geen echte data en geen secret.
   Niet omdat je oplet, maar omdat er niets is om te lezen.
2. **De vault ligt buiten elke workspace-root.** Geen submap van het project, geen symlink
   het project in. Anders is hij alsnog binnen bereik van indexering en agent-tooling.
3. **Ontwikkelen en uitvoeren gebeuren in gescheiden sessies.** Ook op Workbench, waar geen
   assistent draait: het scheelt dat je nooit per ongeluk console-output met echte data
   kopieert naar een chat op je laptop.

---

## 3. Projectstructuur

```
myproject/
├── .env.example              # every key, placeholder values only
├── .envcheck.toml            # configuration for the checker
├── .gitignore
├── .pre-commit-config.yaml
├── .python-version           # interpreter pinned for uv
├── Makefile                  # make test | make run | make check
├── README.md
├── pyproject.toml            # Python dependencies, managed with uv
├── uv.lock                   # locked versions, committed
├── secure-project-setup-EN.md
├── secure-project-setup-NL.md
├── docs/
│   └── claude-code-brief.md  # the standing brief for the assistant
├── mk/
│   └── guard.mk              # check-env and check-vault, as an include
├── src/
│   ├── R/
│   │   ├── config.R          # single place where the environment is read
│   │   ├── processing.R
│   │   └── safe_profile.R    # output summary without values
│   └── python/
│       ├── config.py
│       ├── processing.py
│       └── safe_profile.py
├── tests/
│   ├── conftest.py           # puts src/python on the path; shared fixtures
│   ├── test_processing.py
│   ├── fixtures/             # fake data, committed to git
│   │   ├── schema.yaml
│   │   └── patients.csv
│   └── testthat/
│       ├── helper-src.R      # sources src/R, which is not a package
│       └── test-processing.R
├── scripts/
│   └── main.R                # entry point: reads config, runs the pipeline
└── tools/
    ├── check_env_paths.py
    ├── check_vault_keys.sh   # .env.example vs the vault, skips without a vault
    └── generate_fixtures.R   # builds tests/fixtures/ from schema.yaml
```

De template-repository draagt hier nog vier bestanden bovenop, die een project dat eruit
voortkomt niet houdt: `tools/adopt.sh`, `tools/new-project.sh`, `tools/adopt-existing.sh` en
`tools/runbook.sh`, samen met de twee documenten in `docs/` die ze beschrijven. Ze bestaan om
dit skelet in een project te zetten; zodra dat gebeurd is hebben ze geen functie meer, en
`new-project.sh` verwijdert ze als een van zijn stappen.

Wat opvalt: er is geen `data/` map in de repo. Bewust. Zodra die er is, belandt er ooit
iets echts in.

De drie codemappen zijn niet inwisselbaar:

- **`src/`** is importeerbare code: functies zonder bijwerkingen bij het laden, die niets van
  de omgeving weten. Precies één bestand leest de omgeving -- `config.R` / `config.py`,
  paragraaf 4.5 -- en al het andere krijgt binnen wat het nodig heeft als argument. Dit is
  wat je tests tegen fixtures aanroepen.
- **`scripts/`** bevat entry points. Die draaien van boven naar beneden, roepen
  `load_config()` aan en schrijven bestanden weg. Het is de enige plek die weet waar echte
  data staat, en ze worden niet getest.
- **`tools/`** bevat ontwikkelhulpmiddelen die geen van beide zijn: de checker, de
  fixture-generator. Die draaien bij het opzetten, niet als onderdeel van de analyse.

Een functie hoort in `src/` als deze vier gelden. Zodra er één niet opgaat, hoort hij in
`scripts/`:

1. **Geen omgevingstoegang.** Geen `Sys.getenv()`, geen `os.environ`. Alles wat hij over
   paden of credentials moet weten, komt binnen als argument. `config.R` / `config.py` is de
   enige uitzondering, en bestaat juist om de ene plek te zijn die dat wél doet -- en dat is
   wat deze regel overal elders betaalbaar houdt.
2. **Geen I/O.** Niet lezen, niet schrijven, niet verbinden. `read.csv()` hoort in het script.
3. **Geen bijwerkingen bij het laden.** `source()` of `import` definieert alleen dingen.
4. **Zelfde input, zelfde output.** In pandas betekent dat het dataframe kopiëren voordat je
   het aanpast, anders wordt de volgorde waarin je tests draaien ineens relevant.

`src/` vrijhouden van omgevingstoegang is wat de rest van de opzet overeind houdt: als die
grens schoon is, raakt maar een handvol entry points ooit echte data aan. De andere drie
regels maken het testbaar, en dat is dezelfde grens vanaf de andere kant bekeken.

---

## 4. Stap voor stap opzetten

Deze sectie bouwt de opzet vanaf een lege map, zodat elk onderdeel wordt geïntroduceerd met
de reden dat het er is. In de praktijk typ je dit niet over: het skelet is een repository, en
`docs/starting-a-new-project.md` is de korte mechanische route. Lees deze sectie voor de
redenering; volg die andere om daadwerkelijk te beginnen.

### 4.1 Repo aanmaken op de laptop

```bash
mkdir -p ~/projects/myproject && cd ~/projects/myproject
git init
```

### 4.2 `.gitignore` neerzetten — vóór de eerste commit

```gitignore
# --- secrets and environment ---
.env
.env.*
!.env.example
.Renviron
*.pem
*.key
*.p12

# --- data ---
data/
*.csv
*.xlsx
*.parquet
*.rds
*.sav
*.dta
# fixtures are fake and may be committed; gitignore has no inline comments, so
# this exception must sit on a line of its own or it silently matches nothing
!tests/fixtures/*.csv

# --- R session residue ---
.Rhistory
.RData
.Rproj.user/
*.Rproj.user

# --- rendered output (contains executed results!) ---
_freeze/
.quarto/
*_files/
*.html
*_cache/

# --- Python ---
__pycache__/
.venv/
.ipynb_checkpoints/
.pytest_cache/

# --- output and scratch ---
tmp/
output/

# --- other ---
renv/library/
```

De regel `*.csv` met een uitzondering voor `tests/fixtures/` is de belangrijkste hier: hij
draait de standaard om van "alles mag tenzij" naar "niets mag tenzij".

### 4.3 Sessie-residu uitzetten (R)

```r
usethis::use_blank_slate()      # never save or restore .RData
```

Of handmatig in Positron/RStudio: *Tools → Global Options → Workspace* op "Never".

### 4.4 `.env.example` maken

```dotenv
# This file lists exactly the variables the project reads, with placeholder
# values. Its counterpart on the execution environment, secrets.env, holds the
# same keys with real values.
#
# VAULT_ROOT is deliberately absent: it belongs to the machine, not to the
# project, and it is what locates secrets.env in the first place. It lives in
# ~/.Renviron and is declared under env_vars_optional in .envcheck.toml.

PROJECT_DATA_DIR=./tests/fixtures
PROJECT_OUTPUT_DIR=./tmp/output

# Uncomment what you actually use, and add it to config.R / config.py in the
# same edit. Every key listed here needs a real value on the execution
# environment, so a key that no code reads leaves a live credential sitting
# there for nothing.
# DB_HOST=localhost
# DB_PORT=5432
# DB_NAME=myproject
# DB_USER=changeme
# DB_PASSWORD=changeme
```

`secrets.env` in de vault is dit bestand met echte waarden: dezelfde keys, dezelfde volgorde,
niets extra's. Die eigenschap is het beschermen waard, want daar hangt de controleerbaarheid
aan — kunnen de twee bestanden verschillende keys bevatten, dan zegt `ENV002` niets meer over
de uitvoeromgeving.

Verder twee regels. Alle waarden hier zijn placeholders, en dit bestand gaat wél in git. En het bevat
precies wat het project daadwerkelijk leest, niet meer. Elke key hier vraagt om een echte
waarde op de uitvoeromgeving, dus een key die geen enkele code leest laat daar een werkende
credential staan waar niemand iets aan heeft. De `ENV002`-check bewaakt beide richtingen,
zodat `.env.example` en de code niet uit elkaar kunnen lopen.

### 4.5 Eén centrale configuratieplek

Zet het inlezen van de omgeving op één plek, zodat de rest van je code nergens meer een
pad of credential kent.

**R — `src/R/config.R`:**

```r
VAULT_SECRETS_FILE <- "secrets.env"

project_root <- function() {
  if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(getwd())
}

load_config <- function() {
  root <- project_root()
  vault_root <- Sys.getenv("VAULT_ROOT")

  if (nzchar(vault_root)) {
    secrets <- file.path(vault_root, basename(root), VAULT_SECRETS_FILE)
    if (!file.exists(secrets)) {
      stop(sprintf("VAULT_ROOT is set but %s does not exist.", secrets), call. = FALSE)
    }
    readRenviron(secrets)
  } else {
    Sys.setenv(
      PROJECT_DATA_DIR   = file.path(root, "tests", "fixtures"),
      PROJECT_OUTPUT_DIR = file.path(root, "tmp", "output")
    )
  }

  required <- function(name) {
    value <- Sys.getenv(name)   # envcheck: ignore -- generic accessor
    if (!nzchar(value)) stop(sprintf("environment variable %s is not set", name), call. = FALSE)
    value
  }

  # Add credentials as the project starts needing them, and uncomment the
  # matching key in .env.example in the same edit:
  #   db_host = required("DB_HOST"),
  #   db_pass = required("DB_PASSWORD")
  list(
    data_dir   = required("PROJECT_DATA_DIR"),
    output_dir = required("PROJECT_OUTPUT_DIR")
  )
}
```

**Python — `src/python/config.py`:**

```python
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
```

Eén variabele, één keer per machine gezet, bedient al je projecten: `VAULT_ROOT`. De rest
wordt afgeleid uit de naam van de projectmap, die per conventie gelijk is aan de naam van de
vault-map. Die conventie is nu dragend, dus `load_config()` geeft een duidelijke fout als
`VAULT_ROOT` gezet is maar het afgeleide pad niet bestaat, in plaats van door te gaan met
lege waarden.

Merk op dat beide talen hetzelfde `secrets.env` lezen. R's `readRenviron()` begrijpt hetzelfde
`KEY=value`-formaat dat `_read_env_file()` parseert, dus één bestand bedient beide en staat
geen wachtwoord op twee plekken.

### 4.6 De checker installeren

```bash
mkdir -p tools
cp check_env_paths.py tools/
cp .envcheck.toml .
python3 tools/check_env_paths.py --check-unused
```

Omdat `config.R` en `config.py` de omgevingstoegang in een helper verpakken, moet de checker
weten dat `required()` een variabele leest — anders lijkt elke key in `.env.example`
ongebruikt. De meegeleverde `.envcheck.toml` regelt dit al:

```toml
env_getters = ["required", "_required"]
```

Hernoem je de helper, dan hernoem je hem hier ook. De default in het script zelf is bewust
een lege lijst: `required` is een gangbare functienaam, en hem als accessor behandelen in een
project dat dat nooit heeft aangegeven, verzint omgevingsvariabelen uit gewone argumenten.

De twee regels waar de helper zelf `Sys.getenv(name)` aanroept krijgen een
`# envcheck: ignore`-comment, omdat de naam daar een parameter is en statisch niet te
herleiden valt.

Zie sectie 9 voor wat de checker precies meldt.

### 4.7 Pre-commit installeren

```bash
pipx install pre-commit
cp .pre-commit-config.yaml .
pre-commit install
pre-commit autoupdate            # the pinned revisions in the file go stale
pre-commit run --all-files
```

### 4.8 Eerste commit en push

```bash
git add .
git status                       # look. actually look.
git commit -m "Project skeleton"
```

Vanaf nu: `git add -p` in plaats van `git add .`. Dat loopt per wijziging langs en vraagt
per stuk om ja of nee.

---

## 5. Secrets: de `chmod 600`-aanpak

### 5.1 Op de Workbench-share

```bash
mkdir -p /share/projects/myproject
chmod 700 /share/projects/myproject

cat > /share/projects/myproject/secrets.env <<'EOF'
PROJECT_DATA_DIR=/share/projects/myproject/data
PROJECT_OUTPUT_DIR=/share/projects/myproject/output
DB_HOST=db.internal.example
DB_USER=svc_myproject
DB_PASSWORD=...
EOF
chmod 600 /share/projects/myproject/secrets.env
```

En in `~/.Renviron` op Workbench — dus in je home, buiten elke repo — één regel, die nooit
meer verandert en al je toekomstige projecten dekt:

```dotenv
VAULT_ROOT=/share/projects
```

Dit is waarom de vault-map exact zo moet heten als de repo: `config.R` en `config.py` plakken
`VAULT_ROOT` en de naam van de projectmap aan elkaar om `secrets.env` te vinden. Het betekent
ook dat je tien projecten tegelijk open kunt hebben zonder iets om te zetten.

Zet daarnaast in `~/.profile` op Workbench:

```bash
umask 077
```

Zonder dat schrijft je code output weg met groepsleesrechten en lekt er alsnog data naar
collega's op dezelfde server.

### 5.2 Op de laptop

Hier zet je **helemaal niets**. `VAULT_ROOT` is niet gezet, dus `load_config()` wijst het
project zelf naar `tests/fixtures`. Er is geen configuratiebestand om te vergeten en geen
waarde om verkeerd in te vullen. De laptop heeft geen credentials omdat hij ze niet nodig
heeft — daar draait alleen code tegen nep-data.

Dit is het punt van de hele opzet. Elke maatregel die je op de laptop zou moeten nemen om
secrets te beschermen, is een teken dat er secrets staan die er niet horen te staan.

### 5.3 Wat `chmod 600` wel en niet doet

Wel: collega's op dezelfde Workbench kunnen het bestand niet lezen. Niet: systeembeheerders
met root kunnen het wel, en bij een backup van de share gaat het mee. Dat is voor de meeste
situaties acceptabel — die mensen kunnen de onderliggende data toch al inzien — maar wees
je ervan bewust.

Moet je secrets delen met collega's, gebruik dan een ACL in plaats van groepsrechten:

```bash
setfacl -m u:colleague:r /share/projects/myproject/secrets.env
getfacl /share/projects/myproject/secrets.env
```

### 5.4 Wanneer je verder gaat dan dit

Er zijn twee situaties waarin `chmod 600` tekortschiet:

- **Je wilt secrets in git zetten** om ze met een team te delen. Dan heb je encryptie nodig:
  [SOPS](https://github.com/getsops/sops) met [age](https://github.com/FiloSottile/age)
  versleutelt per veld, zodat je diffs leesbaar blijven. Belangrijkste ontwerpregel:
  versleutel vanaf dag één naar meerdere ontvangers (jouw laptop, Workbench, én een
  escrow-sleutel waarvan de private key alleen in je wachtwoordmanager staat), anders is
  een verloren laptop een verloren project.
- **Je wilt dat secrets nooit op schijf staan.** Dan hoort er een secret manager onder:
  HashiCorp Vault, AWS/GCP Secrets Manager, of 1Password CLI (`op run -- make run`), die de
  waarden pas bij het starten van het proces injecteert.

Beide zijn een verbetering, geen voorwaarde. Zolang de secrets op één afgeschermde share
staan en nergens anders, heb je het grootste deel van het risico al weg.

---

## 6. Fixtures

Een fixture is vaste testdata: klein, nep, en elke run identiek. Ze staan in de repo, dus
de assistent mag ze zien, en je tests draaien er tegenaan in plaats van tegen de echte bron.

### 6.1 Het schema vastleggen

Beschrijf de *structuur* van de echte data, niet de inhoud. Dit doe je één keer, met de
hand, op de uitvoeromgeving.

```yaml
# tests/fixtures/schema.yaml
patients:
  n_rows: 25
  columns:
    - {name: patient_id,     type: character, pattern: "P[0-9]{6}"}
    - {name: birth_year,     type: integer,   min: 1930, max: 2010}
    - {name: sex,            type: factor,    levels: [A, B, C]}
    - {name: region,         type: factor,    levels: [north, central, south]}
    - {name: admission_date, type: date,      min: 2020-01-01, max: 2024-12-31}
    - {name: score,          type: numeric,   min: 0, max: 100, na_share: 0.05}
```

Wees kritisch op het schema zelf. Een lijst met alle voorkomende diagnosecodes of
viercijferige postcodes is metadata die op zichzelf herleidbaar kan zijn. Vervang zeldzame
categorieën door verzonnen labels, zoals hierboven bij `sex` en `region`.

### 6.2 De generator

```r
# tools/generate_fixtures.R
set.seed(42)                                   # deterministic: same output every run
n <- 25
patients <- data.frame(
  patient_id     = sprintf("P%06d", seq_len(n)),
  birth_year     = sample(1930:2010, n, replace = TRUE),
  sex            = sample(c("A", "B", "C"), n, replace = TRUE),
  region         = sample(c("north", "central", "south"), n, replace = TRUE),
  admission_date = as.Date("2020-01-01") + sample(0:1825, n, replace = TRUE),
  score          = round(runif(n, 0, 100), 1)
)
patients$score[sample(n, 2)] <- NA            # missing values belong in there

# edge cases by hand: this is where your code actually breaks
edge_cases <- patients[1:3, ]
edge_cases$patient_id <- c("P000001", "", "P999999")   # duplicate, empty, extreme
edge_cases$birth_year <- c(1930, NA, 2010)

dir.create("tests/fixtures", showWarnings = FALSE, recursive = TRUE)
write.csv(rbind(patients, edge_cases), "tests/fixtures/patients.csv", row.names = FALSE)
```

`set.seed()` is niet optioneel: zonder vaste seed verandert je fixture bij elke run en
worden je tests onbetrouwbaar.

### 6.3 Tests die er tegenaan draaien

`src/` is een map met functiedefinities, geen geïnstalleerd package, dus niets laadt het
vanzelf. Elke taal heeft één stukje bedrading nodig, en het loont te weten welk: zonder dat
faalt elke test met "could not find function", wat leest als een kapotte test in plaats van
een ontbrekende import.

Aan de R-kant sourcet testthat elke `helper-*.R` in de testmap voordat de tests draaien:

```r
# tests/testthat/helper-src.R
# Sourced by testthat before the tests run. `src/` holds plain function
# definitions rather than a package, so nothing loads them otherwise and every
# test fails with "could not find function".
src_r <- testthat::test_path("..", "..", "src", "R")
stopifnot(dir.exists(src_r))

for (file in list.files(src_r, pattern = "\\.[Rr]$", full.names = TRUE)) {
  source(file)
}
```

De hele map sourcen is bewust. Het werkt alleen doordat `src/` geen bijwerkingen bij het
laden heeft, dus een bestand dat bij het inladen werk gaat doen breekt de tests in plaats van
onopgemerkt te blijven.

```r
# tests/testthat/test-processing.R
test_that("score is normalised correctly", {
  path <- testthat::test_path("..", "fixtures", "patients.csv")
  df   <- read.csv(path)
  out  <- normalise_score(df)
  expect_true(all(out$score_norm >= 0 & out$score_norm <= 1, na.rm = TRUE))
})
```

Aan de Python-kant doet `conftest.py` hetzelfde werk, naast de gedeelde fixtures:

```python
# tests/conftest.py
import sys
import pandas as pd, pytest
from pathlib import Path

# `src/python/` holds plain modules, not an installed package, so it is not
# importable otherwise. The R side does the same in tests/testthat/helper-src.R.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src" / "python"))

@pytest.fixture
def patients():
    return pd.read_csv(Path(__file__).parent / "fixtures" / "patients.csv")
```

```python
# tests/test_processing.py
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
```

`pytest` en `pandas` staan in `pyproject.toml` en liggen vast in `uv.lock`, dus een machine
klaarzetten om de suite te draaien is één commando:

```bash
uv sync
```

Dat maakt `.venv/` aan met de vastgezette interpreter en de vastgelegde versies. `make test`
draait de Python-helft vervolgens via `uv run --frozen`, wat hard faalt als `pyproject.toml`
en `uv.lock` uit elkaar zijn gelopen in plaats van stilletjes iets nieuwers op te lossen.
Commit `uv.lock` en `.python-version`; `.venv/` is genegeerd.

---

## 7. Uitvoeren met echte data

### 7.1 Twee commando's, twee sessies

```makefile
# Makefile
#
# The static checks live in mk/guard.mk, so this file and the fragment an
# adopting project includes cannot drift apart.
include mk/guard.mk

.PHONY: test run check

# Fixtures only. VAULT_ROOT is cleared explicitly, so this stays safe on the
# execution environment too -- without it, `make test` there would silently run
# against real data. The Python half runs through uv against uv.lock, so the
# suite does not depend on whatever happens to be installed.
test:
	VAULT_ROOT= Rscript -e 'testthat::test_dir("tests/testthat")'
	VAULT_ROOT= uv run --frozen pytest -q

# Real data. Execution environment only, in a session with no assistant.
run:
	Rscript scripts/main.R

# Runs on every machine: the vault comparison skips itself when VAULT_ROOT is
# unset. An adopting project makes its own check target depend on these two
# instead of redefining them.
check: check-env check-vault
```

`check-env` en `check-vault` staan in `mk/guard.mk`, niet hier. Dat fragment is wat
`tools/adopt.sh` kopieert naar een project dat deze opzet overneemt: de targetnamen zijn
genamespaced omdat make een opnieuw gedefinieerd target stil vervangt, dus een `Makefile`
met een kale `check` zou de eigen check van dat project wissen. Sectie 4.6 behandelt de
checker die deze twee targets draaien.

`make run` gebruikt de waarden uit `~/.Renviron` op Workbench. Je zet dit commando bewust
niet in de allow-lijst van de assistent.

Het leegmaken van `VAULT_ROOT` in het `test`-target is geen versiering. Op de uitvoeromgeving
ís die variabele gezet, dus zonder dat zou `make test` daar stilletjes de testsuite tegen
productiedata draaien — en de output in de vault wegschrijven.

### 7.2 De console is de lekkende kant

Zelfs zonder assistent op Workbench: wat je uit een uitvoersessie kopieert naar een chat op
je laptop, gaat naar het model. Kopieer daarom nooit ruwe output. Gebruik een samenvatting
die per definitie geen waarden bevat:

```r
# src/R/safe_profile.R
safe_profile <- function(df) {
  data.frame(
    column   = names(df),
    type     = vapply(df, function(x) class(x)[1], character(1)),
    n_na     = vapply(df, function(x) sum(is.na(x)), integer(1)),
    n_unique = vapply(df, function(x) length(unique(x)), integer(1)),
    row.names = NULL
  )
}
```

```python
def safe_profile(df):
    import pandas as pd
    return pd.DataFrame({
        "dtype": df.dtypes.astype(str),
        "n_na": df.isna().sum(),
        "n_unique": df.nunique(),
    }).assign(n_rows=len(df))
```

Dit is bijna altijd genoeg om een bug te bespreken. `head()`, `str()` en `summary()` niet —
die drukken waarden af.

### 7.3 Metadata lekt ook, en dat ziet er onschuldig uit

`safe_profile()` lost het dataprobleem op. Tegen het tweede kanaal doet het niets, en dat is
lastiger op te merken omdat er helemaal geen records in de output zitten.

Plak een foutmelding om er hulp bij te krijgen — de meest legitieme reden die er is — en je
geeft tegelijk de vorm van je systeem weg: bestandsnamen, mapstructuur, variabelenamen,
hostnames in een stacktrace, tabel- en kolomnamen in een databasefout, een serviceaccount in
een mislukte verbinding. Niets daarvan is data. Alles samen beschrijft wat je hebt en hoe het
is ingericht.

Er is geen `safe_profile()` voor. Een foutmelding moet intact blijven om bruikbaar te zijn, en
hem redigeren brengt je terug bij het denylist-probleem uit de volgende sectie. De remedie zit
stroomopwaarts: **zorg dat de namen zelf niets prijsgeven.** Een repo `myproject` met een
script `get_joined_data.R` lekt niets als dat pad in een traceback opduikt. Datzelfde script
onder een klantnaam, een dossiernummer of een studiecode lekt elke keer dat iemand ergens een
fout plakt.

Dit is dus nog een reden voor de indeling uit sectie 3, en een naamgevingsregel:

- Namen van repo's, mappen en bestanden beschrijven de *functie*, nooit het onderwerp. Niet
  `acme-churn-2024/`, niet `get_patient_records.R`.
- Hetzelfde geldt voor tabel- en kolomnamen die je zelf bepaalt, en voor de namen van de
  omgevingsvariabelen in `.env.example` — dat bestand gaat mee in git en is leesbaar voor
  iedereen met toegang tot de repo.
- Moet het onderwerp ergens echt voorkomen, laat dat dan in de vault gebeuren, in
  `secrets.env`, dat de uitvoeromgeving nooit verlaat.

Ga ervan uit dat alles wat de checker of een stacktrace kan printen, ooit door jou in een
chat, een issue of een supportticket wordt geplakt. Kies je namen daarop, dan hoeft de vraag
of het veilig was om te plakken niet meer beantwoord te worden.

### 7.4 Waarom "gevoelige waarden eruit filteren" niet werkt

De verleiding is om echte output te nemen en de gevoelige stukken te vervangen. Dat is een
denylist: hij verwijdert alleen wat je vooraf hebt opgesomd. Een naam die niet in je lijst
stond, een nummer in een ander formaat, een vrij tekstveld, een combinatie van postcode en
zeldzame diagnose die samen herleidbaar is — die glippen er doorheen, zonder foutmelding.

De omkering werkt wel: bepaal wat er *wél* uit mag (kolomnamen, types, aantallen) en gooi de
rest weg. Een filter dat je bouwt om secrets uit output te halen, houd je alsnog — maar als
alarm, niet als filter. Draai `gitleaks detect --no-git` over alles wat de uitvoeromgeving
verlaat en behandel een treffer als "mijn werkwijze klopt niet", niet als "mooi, opgeschoond".

Moet je koppelbaarheid behouden, gebruik dan deterministische pseudonimisatie: een HMAC over
het ID met een salt die alleen op de uitvoeromgeving staat. Dezelfde persoon krijgt overal
hetzelfde nepnummer, zonder terugrekenbaarheid.

---

## 8. De assistent op de laptop begrenzen

### 8.1 Claude Code

`.claude/settings.json` in de repo (gaat mee in git, geldt voor iedereen):

```json
{
  "permissions": {
    "deny": [
      "Read(./.env)",
      "Read(./.env.local)",
      "Read(./.Renviron)",
      "Read(./data/**)",
      "Read(**/*.pem)",
      "Read(**/*.key)",
      "Read(~/.ssh/**)",
      "Bash(make run)",
      "Bash(ssh *)",
      "Bash(scp *)"
    ],
    "allow": [
      "Bash(make test)",
      "Bash(make check)",
      "Bash(git status)",
      "Bash(git diff *)"
    ],
    "ask": [
      "Bash(git push *)"
    ]
  }
}
```

Twee kanttekeningen. Ten eerste: deny-regels hebben in het verleden bugs gehad waarbij ze
niet werden afgedwongen — test ze in een wegwerpmap met nepgegevens voordat je erop
vertrouwt. Ten tweede: dit is je *tweede* slot. Het eerste slot is dat er op de laptop niets
te lezen valt.

### 8.2 Positron

Positron werkt met een workspace-root. Open uitsluitend `~/projects/myproject`, nooit een
multi-root workspace waar een datamap bij zit. Controleer bij de assistent-integratie die je
gebruikt welke context wordt meegestuurd — meestal open editors, de terminal en de
Environment-pane. Die laatste twee worden zelden gedocumenteerd en zijn precies waar
resultaten in belanden.

### 8.3 Op Workbench

Geen assistent actief. Houd dat zo — dat is wat de hele opzet werkbaar maakt.

---

## 9. De vangnetten

### 9.1 De eigen checker

```bash
python3 tools/check_env_paths.py --check-unused
```

| Code | Betekenis |
|---|---|
| `ABS001` | absoluut padliteral in code (`/mnt/...`, `~/...`, `C:\...`, `\\server\...`) |
| `ABS002` | `setwd()` of `os.chdir()` |
| `ENV001` | env-variabele gebruikt die niet in `.env.example` staat |
| `ENV002` | key in `.env.example` die nergens gebruikt wordt |
| `ENV003` | env-variabele opgehaald met een niet-constante naam |
| `SEC001` | credential-achtige naam krijgt een letterlijke stringwaarde |
| `SEC002` | connection string met ingebedde credentials |
| `SEC003` | `.env.example` bevat een waarde die geen placeholder lijkt |
| `FILE001` | bestand dat niet in de repo hoort (`.env`, `.Renviron`, `.RData`, ...) |

`ENV002` is minder vanzelfsprekend dan hij lijkt: een key die nergens meer gebruikt wordt,
is meestal een restant van verwijderde code — en op de uitvoeromgeving staat dan nog steeds
een echte waarde voor iets wat niemand meer nodig heeft. Opruimen.

Onderdrukken van een terechte uitzondering: `# envcheck: ignore` achter de regel. Werkt in
zowel R als Python.

Twee instellingen in `.envcheck.toml` doen er in de praktijk toe. `env_getters` somt de
projectfuncties op die een omgevingsvariabele op naam lezen, zodat `required("DB_HOST")` als
gebruik meetelt. `allow_path_regex` laat padliteralen toe die terecht absoluut zijn. Houd
beide lijsten kort: elke regel erin is een uitzondering op precies datgene wat de checker
moet bewaken.

Melden alle hooks "no files to check", dan is er nog niets gestaged.
`pre-commit --all-files` betekent alle bestanden *die git kent*, niet alle bestanden op
schijf. Draai eerst `git add -A`.

### 9.2 De vault-keyvergelijking

```bash
bash tools/check_vault_keys.sh
```

Vergelijkt de actieve keys in `.env.example` met die in `$VAULT_ROOT/<project>/secrets.env`
en meldt beide richtingen: een variabele die de code leest maar waar in de vault geen waarde
voor staat, of een waarde in de vault die niets meer leest. Die tweede is de belangrijkste —
dat is een werkende credential die zijn code heeft overleefd.

Op een machine zonder vault meldt hij dat hij overslaat en geeft exit 0, zodat `make check`
zich overal hetzelfde gedraagt. Een pre-commit hook kan het niet zijn, want de vault bestaat
niet op de laptop waar je commit.

### 9.3 gitleaks

Zoekt met patronen en entropie-heuristiek naar credentials. Drie manieren van inzetten:

```bash
gitleaks detect --source . --redact          # one-off pass over the full history
gitleaks protect --staged --redact           # as a pre-commit hook
```

De derde is CI. Die is niet optioneel: `git commit --no-verify` slaat elke lokale hook over.

### 9.4 GitHub push protection

Server-side scanning die een push met een herkend credential blokkeert. Gratis en standaard
aan voor publieke repositories; voor private repositories heb je GitHub Advanced Security /
Secret Protection nodig, en op persoonlijke accounts is het niet beschikbaar. Beperking:
het herkent alleen bekende tokenformaten en scant geen bestaande historie. Voor
persoonsgegevens doet het niets.

### 9.5 nbstripout

Git-filter die output-cellen uit `.ipynb` haalt bij het committen. Voor R-land is het
equivalent geen tool maar de `.gitignore` uit stap 4.2: `_freeze/`, `*_files/` en `*.html`.
`_freeze/` is de sluipmoordenaar — Quarto cachet daar uitgevoerde chunk-output inclusief
tabellen met echte waarden, en die map wordt routineus meegecommit.

### 9.6 `git add -p`

Interactief stagen: git loopt per wijziging langs en vraagt per stuk ja of nee. Kost dertig
seconden en dwingt je te kijken naar wat je pusht. `git add .` doet het tegenovergestelde.

---

## 10. Als het toch misgaat

De volgorde is belangrijk.

1. **Roteer het secret.** Nu, voordat je iets anders doet. Zolang de credential geldig is,
   maakt het niet uit hoe goed je hem uit git haalt.
2. **Bepaal de reikwijdte.** Is er gepusht? Is er geforkt? Staat het in een CI-log, een
   artefact, een issue?
3. **Herschrijf de historie** met `git filter-repo` (niet `filter-branch`, die is verouderd
   en traag). Force-push, en laat iedereen opnieuw clonen in plaats van pullen.
4. **Vraag GitHub om garbage collection.** Losse commits blijven na een force-push nog via
   de API bereikbaar. Neem contact op met support om ze definitief te laten verwijderen.
5. **Bij persoonsgegevens:** meld intern bij je privacy officer / FG. Een datalek heeft een
   meldtermijn van 72 uur; die begint bij ontdekking, niet bij het lek.

Ging het om echte data in plaats van een secret, dan valt stap 1 weg en is stap 5 de
belangrijkste.

---

## 11. Checklist

**Bij het opzetten**

- [ ] `.gitignore` staat er vóór de eerste commit, met `*.csv` en een uitzondering voor fixtures
- [ ] `.RData`/`.Rhistory` uitgezet (`usethis::use_blank_slate()`)
- [ ] `.env.example` bevat alle keys, alleen placeholders
- [ ] Namen van repo, mappen, bestanden en variabelen beschrijven de functie, niet het onderwerp
- [ ] Alle paden en credentials via één `config.R` / `config.py`
- [ ] Vault staat buiten elke workspace-root, `chmod 700` map, `chmod 600` bestanden
- [ ] `umask 077` in `~/.profile` op de uitvoeromgeving
- [ ] `tools/check_env_paths.py` draait schoon
- [ ] `pre-commit install` gedaan, `pre-commit run --all-files` schoon
- [ ] `.claude/settings.json` met deny-regels, getest in een wegwerpmap
- [ ] `make test` draait tegen fixtures, `make run` alleen handmatig op Workbench

**Wekelijks / bij elke push**

- [ ] `git add -p` in plaats van `git add .`
- [ ] `git status` gelezen voordat je commit
- [ ] Niets uit een uitvoersessie gekopieerd zonder door `safe_profile()` te halen

**Bij een nieuwe collega of nieuwe machine**

- [ ] Clone bevat geen data — als hij dat wel doet, is er iets fout gegaan
- [ ] `VAULT_ROOT` alleen zetten op de uitvoeromgeving, nooit op een laptop
- [ ] De naam van de vault-map is exact gelijk aan de naam van de repo-map

---

## Bijlage: waar dit naartoe werkt

De einddoelstelling is dat de vraag "mag de assistent dit zien?" niet meer gesteld hoeft te
worden, omdat het antwoord altijd ja is. Alles wat de assistent kan bereiken is code en
nep-data. Alles wat gevoelig is, staat op één plek, op één machine, achter één set
permissies — en die machine draait geen assistent.

Elke uitzondering die je op die regel maakt, kost je het voordeel van de hele opzet. Als je
merkt dat je een uitzondering nodig hebt, is dat meestal een signaal dat een stuk code op de
verkeerde plek draait, niet dat de regel te streng is.
