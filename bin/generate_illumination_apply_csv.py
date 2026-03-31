#!/usr/bin/env python3
"""
Generate load_data.csv for CellProfiler steps that apply illumination correction.

Reads metadata JSON for image info. Globs *.npy from images directory to find
illumination correction files. Matches illum files to channels by parsing
{plate}_Illum{channel}.npy filename pattern.

Generates CSV with paired columns: FileName_Orig{ch} / FileName_Illum{ch}
plus metadata columns.

Used by both assay development and analysis steps.
Uses only Python standard library.
"""

import argparse
import csv
import glob
import json
import os
import re
import sys


def read_metadata_json(json_path):
    """Read and validate metadata JSON file."""
    with open(json_path, 'r') as f:
        data = json.load(f)

    if 'meta' not in data:
        raise ValueError("JSON must contain 'meta' key")
    if 'images' not in data:
        raise ValueError("JSON must contain 'images' key")
    if not data['images']:
        raise ValueError("images list is empty")

    return data


def find_illumination_files(images_dir):
    """
    Find illumination .npy files and extract channel from filename.

    Expected pattern: {plate}_Illum{channel}.npy
    Returns dict: channel -> filename
    """
    npy_files = glob.glob(os.path.join(images_dir, "*.npy"))
    illum_by_channel = {}

    for npy_path in npy_files:
        filename = os.path.basename(npy_path)
        match = re.match(r'.+?_Illum(.+?)\.npy', filename)
        if match:
            channel = match.group(1)
            illum_by_channel[channel] = filename

    if not illum_by_channel:
        raise ValueError(
            f"No illumination .npy files found in {images_dir}. "
            f"Expected pattern: {{plate}}_Illum{{channel}}.npy"
        )

    print(f"Found illumination files for channels: {sorted(illum_by_channel.keys())}", file=sys.stderr)
    return illum_by_channel


def generate_csv(data, illum_by_channel, output_file):
    """
    Generate load_data.csv from metadata and illumination files.

    Groups images by (well, site) to create one row per field of view
    with all channels represented.
    """
    meta = data['meta']
    images = data['images']

    # Get unique channels from image metadata
    channels = sorted(set(img['channel'] for img in images))

    # Group images by (well, site)
    grouped = {}
    for img in images:
        key = (img['well'], img['site'])
        if key not in grouped:
            grouped[key] = {'meta': img, 'by_channel': {}}
        grouped[key]['by_channel'][img['channel']] = img['filename']

    # Build fieldnames: FileName_Orig{ch}, FileName_Illum{ch} for each channel, then metadata
    fieldnames = []
    for ch in channels:
        fieldnames.append(f'FileName_Orig{ch}')
    fieldnames.extend([
        'Metadata_Batch',
        'Metadata_Plate',
        'Metadata_Well',
        'Metadata_Col',
        'Metadata_Row',
        'Metadata_Site',
    ])
    for ch in channels:
        fieldnames.append(f'FileName_Illum{ch}')

    with open(output_file, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        for (well, site), group in sorted(grouped.items()):
            row = {
                'Metadata_Batch': group['meta']['batch'],
                'Metadata_Plate': group['meta']['plate'],
                'Metadata_Well': well,
                'Metadata_Col': group['meta']['col'],
                'Metadata_Row': group['meta']['row'],
                'Metadata_Site': site,
            }

            for ch in channels:
                row[f'FileName_Orig{ch}'] = group['by_channel'].get(ch, '')
                row[f'FileName_Illum{ch}'] = illum_by_channel.get(ch, '')

            writer.writerow(row)

    print(f"Generated {output_file} with {len(grouped)} rows, {len(channels)} channels", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description='Generate load_data.csv for CellProfiler illumination application'
    )
    parser.add_argument('--metadata', required=True, help='Path to metadata JSON file')
    parser.add_argument('--images-dir', default='./images', help='Directory containing images and .npy files')
    parser.add_argument('--output', default='load_data.csv', help='Output CSV file path')

    args = parser.parse_args()

    data = read_metadata_json(args.metadata)
    illum_by_channel = find_illumination_files(args.images_dir)
    generate_csv(data, illum_by_channel, args.output)


if __name__ == '__main__':
    main()
