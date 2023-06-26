# Backup Manager

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Description

Backup Manager is a script that allows you to create, remove, and download backups of selected files/folders on an AWS S3 server. It provides a simple and automated way to manage your backups.

## Features

- Create backups of selected files/folders and upload them to an AWS S3 server.
- Remove all backups of a specific file.
- Download the latest backup or a specific version from the AWS S3 server.
- Easy configuration through a config file.
- Simple command-line interface with various options.

## Requirements

- Bash shell
- AWS CLI configured with access to an S3 bucket

## Usage

```bash
./backup.sh [OPTIONS]
-c <config_file>: Set the configuration file (default: config/backup.rc).
-b <s3_bucket>: Set the S3 bucket name.
-l <s3_destination>: Set the destination directory in the S3 bucket (default: system-backups).
-v: Display the version and author information.
-h: Display the help message.
-p <backup_dir>: Set the path of the file/folder to be backed up.
-r: Remove all backups for the specified file.
-d <download_dir>: Download the backup to the specified directory.
-n <version>: Set the version number of the backup (optional).
```

## License

This project is licensed under the MIT License. See the LICENSE file for details.
Feel free to modify the descriptions and tags as needed.
