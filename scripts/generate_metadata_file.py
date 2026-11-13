"""Build per-injection sample metadata for ST002118 / AN003466.

Joins the mwTab SUBJECT_SAMPLE_FACTORS (Metabolomics Workbench) with the
prep-order/batch table in metadata/Lichtveld Prep List.docx, which is not on MW.
Join key: docx "DRCC ID" (S_1)  <->  mwTab RAW_FILE_NAME (Lich_S_1).

The docx has 900 rows vs 824 on MW: 68 B_* samples (blanks, not uploaded to MW)
plus 4 S_* and 4 SP_* that were prepped but have no MW file.

Prep order is NOT run order (the prep list groups samples by type within a batch), so
injection order is taken from each mzML's <run startTimeStamp> (acquisition time).

Outputs: metadata/prep_list.csv, metadata/sample_metadata.csv,
         adap_big/ST002118_metadata.csv (ADAP-BIG --factors file)
"""
import re
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

import pandas as pd
import requests

PROJ = Path(__file__).resolve().parents[1]
DOCX = PROJ / "metadata" / "Lichtveld Prep List.docx"
RAW_LIST = PROJ / "raw" / "raw_files.txt"
MZML_DIR = PROJ / "mzML"
URL = "https://www.metabolomicsworkbench.org/rest/study/analysis_id/AN003466/mwtab/json"
W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"


def read_docx_table(path):
    """First table of a .docx as a DataFrame (stdlib XML; no python-docx needed)."""
    root = ET.fromstring(zipfile.ZipFile(path).read("word/document.xml"))
    tbl = next(root.iter(W + "tbl"))
    rows = [["".join(t.text or "" for t in tc.iter(W + "t")).strip() for tc in tr.iter(W + "tc")]
            for tr in tbl.iter(W + "tr")]
    df = pd.DataFrame([r for r in rows[1:] if any(r)], columns=rows[0])
    df = df.rename(columns={"Prep Order": "prep_order", "Batch": "batch", "Section": "section",
                            "DRCC ID": "drcc_id", "HHEAR-ECHO Sample ID": "hhear_id_prep",
                            "Notes": "prep_notes"})
    return df.astype({"prep_order": int, "batch": int, "section": int})


def mzml_start_time(path):
    """Acquisition start time from the <run startTimeStamp="..."> attribute (near the file head)."""
    with open(path, "r", errors="ignore") as fh:
        m = re.search(r'<run [^>]*startTimeStamp="([^"]+)"', fh.read(50_000))
    return pd.to_datetime(m.group(1)) if m else pd.NaT


# ADAP-BIG SampleType.parse() keywords: sp/pool -> POOL, nist/standard -> STANDARD,
# study/sample -> STUDY, anything unrecognized -> OTHER. Avoid "reference material"
# for HHEAR, which would make it STANDARD (same class as NIST).
ADAP_TYPE = {"Study Sample": "study", "Study Pool": "sp",
             "NIST Reference Material": "nist", "HHEAR Reference Material": "hhear"}


# --- mwTab sample factors ---
mw = requests.get(URL, timeout=60).json()[0]          # response is a list, one per analysis
ssf = pd.json_normalize(mw["SUBJECT_SAMPLE_FACTORS"])  # flattens nested dicts -> "Factors.Sample Type" etc.
ssf = ssf.rename(columns={"Sample ID": "sample_id", "Factors.Sample Type": "sample_type",
                          "Additional sample data.HHEAR ID": "hhear_id",
                          "Additional sample data.RAW_FILE_NAME": "raw_file_name"})
ssf = ssf[["sample_id", "sample_type", "hhear_id", "raw_file_name"]]
ssf["drcc_id"] = ssf["raw_file_name"].str.removeprefix("Lich_")

# --- prep list (batch info) ---
prep = read_docx_table(DOCX)

# --- local raw files ---
raw = pd.DataFrame({"raw_path": [l.strip() for l in RAW_LIST.read_text().splitlines() if l.strip()]})
raw["raw_file_name"] = raw["raw_path"].map(lambda p: Path(p).stem)

# --- join + checks ---
meta = ssf.merge(raw, on="raw_file_name", how="outer", validate="1:1", indicator="_raw")
assert (meta["_raw"] == "both").all(), "raw files and mwTab samples don't match 1:1"
meta = meta.drop(columns="_raw").merge(prep, on="drcc_id", how="left", validate="1:1", indicator="_prep")
assert (meta["_prep"] == "both").all(), meta.loc[meta["_prep"] != "both", "drcc_id"].tolist()
has_id = meta["hhear_id"].ne("N/A")
assert (meta.loc[has_id, "hhear_id"] == meta.loc[has_id, "hhear_id_prep"]).all(), "HHEAR ID mismatch"

meta["hhear_id"] = meta["hhear_id"].replace("N/A", pd.NA)
meta["mzml_path"] = meta["raw_file_name"].map(lambda b: str(MZML_DIR / f"{b}.mzML"))
meta["acquisition_time"] = meta["mzml_path"].map(
    lambda p: mzml_start_time(p) if Path(p).exists() else pd.NaT)
have_times = meta["acquisition_time"].notna().all()
if have_times:
    meta = meta.sort_values("acquisition_time")
    meta["injection_order"] = range(1, len(meta) + 1)
    # each batch must occupy one contiguous block of the run
    assert (meta["batch"].diff().fillna(0) >= 0).all(), "batches interleave in acquisition time"
else:
    print(f"WARNING: {meta['acquisition_time'].isna().sum()} mzML missing; injection_order not set")
    meta["injection_order"] = pd.NA
meta = meta[["sample_id", "raw_file_name", "drcc_id", "hhear_id", "sample_type",
             "injection_order", "acquisition_time", "prep_order", "batch", "section",
             "prep_notes", "raw_path", "mzml_path"]]

prep.to_csv(PROJ / "metadata" / "prep_list.csv", index=False)
meta.to_csv(PROJ / "metadata" / "sample_metadata.csv", index=False)

# --- ADAP-BIG factors file (columns follow m3p_b1_b6_metadata.csv) ---
# Required by ADAP-BIG: injection_order, sample_name, batch. sample_name is matched to the
# mzML filename without extension. batch_folder is not used by the console app (files are
# found recursively under -f); kept only for parity with the template.
if have_times:
    factors = pd.DataFrame({
        "injection_order": meta["injection_order"],
        "sample_name": meta["raw_file_name"],
        "sample_type": meta["sample_type"].map(ADAP_TYPE),
        "sample_type_original": meta["sample_type"],
        "batch": meta["batch"],
        "batch_folder": meta["batch"].map(lambda b: f"BATCH{b:06d}"),
    })
    assert factors["sample_type"].notna().all(), set(meta.loc[factors["sample_type"].isna(), "sample_type"])
    factors.to_csv(PROJ / "adap_big" / "ST002118_metadata.csv", index=False)
    print(f"adap_big/ST002118_metadata.csv: {len(factors)} rows")

print(f"sample_metadata.csv: {len(meta)} injections")
print(pd.crosstab(meta["batch"], meta["sample_type"], margins=True))
not_on_mw = prep.loc[~prep["drcc_id"].isin(meta["drcc_id"]), "drcc_id"]
print(f"\nPrepped but not on MW ({len(not_on_mw)}):",
      not_on_mw.str.split("_").str[0].value_counts().to_dict(),
      [i for i in not_on_mw if not i.startswith("B_")])
