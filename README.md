MySQL-Backup
============

Wrapper around mysql incremental and hot backup.

**Features:**

1. Incremental and full hot backup.
2. Backup archiving and synchronization with S3.
3. Backup rotatation.


**On the road map:**

1. Adding support for Public/Private key cryptography for backups



**Sample Usage:**


*$ ./db_backup_ctl.rb -h*

Usage: db_backup_ctl.rb [options]

    -b, --incremental-backup         Take an incremental backup

    -r, --restore-incremental-backup Restore incremental backup

    -c, --copy-files-back            Copy back a prepared full backup

    -d, --data-dir [DATA_DIR]        Specify the path to the mysql data dir

    -D, --backup-dir [BACKUP_DIR]    Specify the path to the root backups dir

    -u, --user [USERNAME]            database user name

    -p, --password [PASSWORD]        database user password

    -s [S3CMD_CONFIG_PATH],          path to s3cmd config file (.s3cfg)

        --s3cmd-config-path

    -S [S3_BUCKET_PATH],             S3 bucket path

        --s3-bucket-path
 
    -E [ENCRYPTION_KEY_PATH],        path to the public encryption key
 
        --encryption-key-path
 
    -R, --rotate [ROTATION_SIZE]     rotates backups to the given rotation size


**performing an incemental backup with upload to s3:**

*./db_backup_ctl.rb -b*

**you can sepecify the s3 and ecnryption flags through either command line or changing the defaults within the db_backup_ctl.rb file:**

* options[:date_pattern]='%Y-%m-%d_%H-%M-%S'
* options[:backup_dir]='/mnt/backups/mysql/'
* options[:data_dir]='/mnt/data/'
* options[:s3cmd_config_path]='/root/.s3cfg'
* options[:s3_bucket_path]='s3://db-backups/'
* options[:encryption_key_path]='/opt/dbTools/key_pub.pem'
* options[:rotation_size]=4
* options[:rotate]=false
* options[:user]='root'
* options[:password]='\'mypass\''

