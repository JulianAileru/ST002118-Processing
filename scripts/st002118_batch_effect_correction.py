import sys
import os 
import pandas as pd 
import numpy as np
ROOT = "/users/j/a/jaileru/ST002118-Processing"
from serrf_py.base import Preprocessor,BatchCorrectionPipeline
from serrf_py.correlation_errors import SERRF

data = pd.read_parquet(f"{ROOT}/results/st002118_feature_table.parquet")
metadata = pd.read_csv(f"{ROOT}/metadata/sample_metadata.csv")
metadata = metadata.set_index("sample_name")
preprocessor = Preprocessor(
    imputation_method=None,
    normalization_method="TIC",
    transformation_method=None
)

corrector = SERRF(
    qc_str="_SP_",       # substring identifying QC samples in sample names
    blank_str="_B_", # substring identifying blank samples
    n_jobs=-1,         # parallel jobs for Random Forest fitting
    num_features=10,   # number of correlated features to use per signal
    use_ranger=True 
)
log_file = 'ST002118_11_16_2026.log' # specify log file or stdout will just be directed to the console
pipeline = BatchCorrectionPipeline(method=corrector, preprocessing_config=preprocessor,log_file=log_file)
corrected = pipeline.correct(data=data, metadata=metadata)
corrected.to_csv("ST002118_Batch_Corrected.csv")