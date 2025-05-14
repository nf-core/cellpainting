#!/usr/bin/env python

#Author: Franz AKE
#Script for running pycytominer annotate on single-cell profiles
#================================================================

#1- load modules
import argparse
import pandas as pd
import os
from pycytominer import annotate

# 2- Argument parser
parser = argparse.ArgumentParser(description="Run pycytominer annotate on single-cell profiles")
parser.add_argument("--profile", required=True, help="Path to input profile Parquet file")
parser.add_argument("--platemap", required=True, help="Path to platemap metadata CSV file")
parser.add_argument("--mergeKeys", required=True, help="Merge key columns")
parser.add_argument("--outputType", required=True, help="Merge key columns")
args = parser.parse_args()

#3- read platemap metadata
platemap_df = pd.read_csv(args.platemap, sep="\t")

# -- Define output filename
profile_base = os.path.splitext(os.path.basename(args.profile))[0]
output_file = f"{profile_base}_annotated.parquet"


#3- run Annotate from pycytominer
annotate(
    profiles=args.profile,
    platemap=platemap_df,
    join_on=args.mergeKeys.split(","),
    output_file=output_file,
    output_type=args.outputType,
    add_metadata_id_to_platemap=True,
    clean_cellprofiler=False,
)
