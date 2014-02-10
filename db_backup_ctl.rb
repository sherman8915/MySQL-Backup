#!/usr/bin/ruby

require 'optparse'
require_relative './db_backup'

options = {}

#defaults
options[:date_pattern]='%Y-%m-%d_%H-%M-%S'
options[:backup_dir]='/mnt/backups/mysql/'
options[:data_dir]='/mnt/data/'
options[:s3cmd_config_path]='/root/.s3cfg'
options[:s3_bucket_path]='s3://db-backups/'
options[:encryption_key_path]='/opt/dbTools/dbStage_pub.pem'
options[:rotation_size]=4
options[:rotate]=false
options[:user]='user'
options[:password]='\'mypass\''

OptionParser.new do |opts|
  opts.banner = "Usage: db_backup_ctl.rb [options]"

  opts.on("-b", "--incremental-backup", "Take an incremental backup") do |v|
    options[:incremental_backup] = v
  end	
	
  opts.on("-r", "--restore-incremental-backup", "Restore incremental backup") do |v|
    options[:restore_incremental_backup] = v
  end

  opts.on("-c", "--copy-files-back", "Copy back a prepared full backup") do |v|
    options[:copy_files_back] = v
  end

  opts.on("-d", "--data-dir [DATA_DIR]", "Specify the path to the mysql data dir") do |data_dir|
    options[:data_dir] = data_dir
  end

  opts.on("-D", "--backup-dir [BACKUP_DIR]", "Specify the path to the root backups dir") do |backup_dir|
    options[:backup_dir] = backup_dir
  end

  opts.on("-u", "--user [USERNAME]", "database user name") do |username|
    options[:user] = username
  end

  opts.on("-p", "--password [PASSWORD]", "database user password") do |p|
    options[:password] = p
  end

  opts.on("-s","--s3cmd-config-path [S3CMD_CONFIG_PATH]", "path to s3cmd config file (.s3cfg)") do |config_path|
    options[:s3cmd_config_path] = config_path
  end

  opts.on("-S","--s3-bucket-path [S3_BUCKET_PATH]", "S3 bucket path") do |bucket_path|
    options[:s3_bucket_path] = bucket_path
  end

  opts.on("-E","--encryption-key-path [ENCRYPTION_KEY_PATH]", "path to the public encryption key") do |key_path|
    options[:encryption_key_path] = key_path
  end

  opts.on("-R","--rotate [ROTATION_SIZE]", "rotates backups to the given rotation size") do |rotation_size|
    options[:rotation_size] = rotation_size.to_i if rotation_size!=nil
		options[:rotate] = true
  end
	
end.parse!

p options
backup=DbBackup.new(options)
puts backup.get_parsed_backup_dirs
puts "\n\nFull backups"
puts backup.get_full_backups
puts "\n\nincremental backups"
puts backup.get_incremental_backups
puts "\n\nlast full backup:"
puts backup.get_last_full_backup()
puts "\n\nlast incremental:"
puts backup.get_last_incremental_backup()

if options[:restore_incremental_backup]
	backup.restore_incremental_backups()
elsif options[:incremental_backup]
	backup.perform_incremental_backup()
elsif options[:copy_files_back]
  backup.copy_files_back()
end

if options[:rotate]
	backup.rotate_backups()
end
