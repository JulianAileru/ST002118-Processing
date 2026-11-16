# ST002118 — raw data → mzML → Data Preprocessing Using ADAP-BIG → Feature Table

- Description: *Exposures to Metals in Pregnant Women and the Impact on Fetal Development and Birth Outcomes in Suriname*
- Study ID: (Metabolomics Workbench ST002118) 
- Additional Information: 824 injections. Thermo Q Exactive HF-X, RP (Waters HSS T3), ESI positive.

Source: `ftp://www.metabolomicsworkbench.org/Studies/ST002118_HHEAR_Lichtveld.zip`

## Layout
```
raw/zip/              downloaded archive                         (ignored)
raw/extracted/        unzipped vendor .raw files                 (ignored)
raw/raw_files.txt     sorted list of .raw paths (drives the array job)
containers/           pwiz.sif + build provenance                (ignored)
mzML/                 converted output                           (ignored)
metadata/             sample metadata (see below)
adap_big/             ADAP-BIG workflow, settings, factors, run script
adap_big/runs/        ADAP-BIG project outputs                   (ignored)
logs/                 SLURM logs                                 (ignored; dir must exist)
scripts/              pipeline
st002118-processing/  pixi environment (python, pandas, requests, mwtab)
```


## Steps
```bash
cd /users/j/a/jaileru/ST002118-Processing
sbatch scripts/01_download.sbatch                         # datamover partition; resumable
sbatch scripts/02_extract.sbatch                          # after 01 succeeds
srun -p interact --mem=16G -t 2:00:00 --pty bash scripts/03_pull_container.sh   # can run in parallel with 01

# 04: msconvert — test one file first
sbatch --array=0 --export=ALL,FILES_PER_TASK=1 scripts/04_msconvert_array.sbatch

# 04: full run (re-submitting is safe; existing mzML are skipped)
N=$(wc -l < raw/raw_files.txt); FPT=10
sbatch --array=0-$(( (N+FPT-1)/FPT - 1 ))%40 --export=ALL,FILES_PER_TASK=$FPT scripts/04_msconvert_array.sbatch

# 05: sample metadata + ADAP-BIG factors file (needs mzML for acquisition times)
python scripts/generate_metadata_file.py

# 06: ADAP-BIG feature detection, alignment, normalization, batch correction
sbatch adap_big/ADAP-ST002118.sh

# 07: export between-batch aligned features (.csv + .msp) from an existing run — no reprocessing
sbatch adap_big/ADAP-export-aligned.sh [adap_big/runs/adap-big_<timestamp>]   # default: latest run
```
`msconvert_one.sh` runs *inside* the container and is called by the array job; it is not meant to be run directly.

## msconvert settings
`--mzML --zlib --64 --filter "peakPicking vendor msLevel=1-"` (centroided, all MS levels).
Override with `--export=ALL,PEAKPICK_FILTER=` to keep profile mode.

## Metadata
`scripts/generate_metadata_file.py` joins three sources:

| Source | Provides |
|---|---|
| mwTab JSON from the Workbench REST API (`/rest/study/analysis_id/AN003466/mwtab/json`) | sample type, HHEAR ID, raw file name |
| `metadata/Lichtveld Prep List.docx` (not tracked; not on the Workbench) | prep order, **batch** (1–8), section |
| mzML `<run startTimeStamp>` | acquisition time → **injection order** |

Join key: prep-list *DRCC ID* (`S_1`) ↔ mwTab `RAW_FILE_NAME` (`Lich_S_1`).

Outputs:
- `metadata/prep_list.csv` — the docx table as-is (900 rows)
- `metadata/sample_metadata.csv` — one row per injection (824)
- `metadata/acquisition_times.csv` — start timestamp per mzML
- `adap_big/ST002118_metadata.csv` — ADAP-BIG `--factors` file

Notes:
- **Prep order ≠ injection order.** The prep list groups samples by type within a batch; the actual
  run order (from timestamps) is NIST, then repeating [10 study samples, HHEAR, SP], ending with NIST.
  Batches are contiguous in time (2021-11-05 → 2021-11-25).
- The prep list has 76 rows with no file on the Workbench: 68 `B_*` (blanks, not uploaded) plus
  `S_452, S_456, S_471, S_541, SP_14, SP_33, SP_34, SP_59`.

Injections per batch:

| batch | study | sp | hhear | nist |
|---|---|---|---|---|
| 1 | 80 | 8 | 8 | 3 |
| 2 | 80 | 7 | 8 | 3 |
| 3 | 80 | 8 | 8 | 3 |
| 4 | 80 | 8 | 8 | 3 |
| 5 | 80 | 6 | 8 | 3 |
| 6 | 77 | 8 | 8 | 3 |
| 7 | 79 | 8 | 8 | 3 |
| 8 | 112 | 11 | 12 | 3 |

## ADAP-BIG (v1.6.0)
- `workflow.xml`: chromatogram building → peak detection → MS2 pairing → within-batch join alignment →
  between-batch alignment → normalization → batch-effect correction → RSD filter → renormalization →
  re-correction.
- **Background removal is removed** from the workflow because ST002118 has no blank injections
  (with no blanks the module would be a pass-through anyway). The between-batch aligner therefore
  reads `aligned_component` instead of `filtered_component`.
- Sample types in the factors file use ADAP-BIG's keywords: `study`, `sp` (→ Pool),
  `nist` (→ standard), `hhear` (→ other). `settings.xml` uses **Pool** (SP) as the alignment
  reference and **NIST** for normalization, batch-effect correction and the RSD filter.
  HHEAR is deliberately not labelled "reference material", which ADAP-BIG would class with NIST.
- Factors columns required by ADAP-BIG: `injection_order`, `sample_name` (mzML filename without
  extension), `batch`. `batch_folder` is not used by the console app.

### ADAP-BIG output: `.ser` files and the Output module
ADAP-BIG saves each workflow step's result in `adap_big/runs/<run>/` as a `.ser` file: a
zlib-compressed **Java serialized object** (e.g. `org.dulab.adapbig.base.RawDataFile`). These are
internal checkpoints that only ADAP-BIG can read. They are not feature tables.

Tables and spectra come from `org.dulab.adapbig.output.OutputModule`, which the original workflow did
not include. It can run as a workflow step or standalone against an existing run
(`java -cp adap-big-console-app-v1.6.0.jar org.dulab.adapbig.output.OutputMain ...`). How it works
(not documented upstream; read from the jar):
- **One file per call. The format comes from the `--output` extension:** `.csv` | `.msp` | `.pdf`.
  An output name without an extension fails with `Unknown format`.
- `--outputlevel` is `ms1` (default) or `ms2` and only affects `.msp` output.
- `--multi-batch ALL_BATCHES` is required to export the combined results, because the Output
  module is not a multi-batch module.
- `--with_ions` adds per-ion m/z and intensity values to the CSV.
- On a bad argument it prints the usage message but still logs `OutputModule is finished`.
  Check the log text, not just the job status.

`workflow.xml` now includes two pairs of Output steps (`.csv` + MS/MS `.msp`): one after
between-batch alignment (`aligned_component` / `aligned_features`) and one at the end of the workflow
(`batch_effect_corrected` / `recorrected_features`). The current run (`adap-big_20261113-133737`)
was made before these steps were added, so its exports came from `ADAP-export-aligned.sh`.

## Results
`results/` is git-ignored: the files exceed GitHub's 100 MB limit. They are regenerated by steps 06–07.

| File | Contents |
|---|---|
| `ST002118_aligned_features.csv` (914 MB) | Between-batch aligned features, **before** normalization / batch-effect correction. 39,331 features (all MS1) × 824 injections. Per feature: `position, name, ms_level, polarity, retention_time, height, area, mz, neutral_mass, adducts, p_value, rsd_area`, then `retention_time, height, area, mz` for each `<sample>.mzML` |
| `ST002118_aligned_features_msms.msp` (110 MB) | 115,741 MS/MS spectra paired to those features (often several per feature). `Name` = `#<id> <mz>@<rt> MS1+` links each spectrum to its feature |

Source: run `adap-big_20261113-133737`, `ALL_BATCHES/5.ALIGNED_COMPONENTS/aligned_features.ser`.
