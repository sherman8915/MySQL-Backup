#!/usr/bin/ruby

require 'date'
require 'logger'


#Date conversion is performed in the following format: DateTime.strptime('2014-01-13_20-15-39','%Y-%m-%d_%H-%M-%S')

class DbBackup

=begin
	Input: date pattern to parse backup directory, path to root backup directory
	Output: Class is initialized
=end
	def initialize(options)
		@backup_dir=options[:backup_dir]
		@date_pattern=options[:date_pattern]
		@checkpoint_file_name="xtrabackup_checkpoints"
    @user=options[:user]
    @password=options[:password]
    @data_dir=options[:data_dir]
		@s3cmd_config_path=options[:s3cmd_config_path]
		@s3_bucket_path=options[:s3_bucket_path]
		@encryption_key_path=options[:encryption_key_path]
		@rotation_size=options[:rotation_size]	
		@backups=get_parsed_backup_dirs()
		@logger=Logger.new(STDOUT)
	end

=begin
	Input: root backup directory
	Output: returned list of directories
=end	
	def get_directories(backup_dir=@backup_dir)
		dirs=Dir.entries(backup_dir).select {|entry| File.directory? File.join(backup_dir,entry) and !(entry =='.' || entry == '..') }
		return dirs
	end

=begin
	Input: 
	Output: returns a hash of backup directory names as keys, and their dates as values
=end
	def get_parsed_backup_dirs()
		#generate an hash of directories and dates
		dirs=get_directories
		dirs_parsed=[]
		dirs.each do |dirname|
			date=DateTime.strptime(dirname,@date_pattern)
			dir={}
			dir[:dirname]=dirname
			dir[:date]=date
			dir[:config]=parse_checkpoints_file(dirname)
			dirs_parsed.push(dir)
		end

		#sort the hash by date
		sorted=dirs_parsed.sort_by {|dir_parsed| dir_parsed[:date]}
		return sorted
	end

=begin
	Input: dir name
	Output: parsed the backup directory checkpoint file and return the config as a hash
=end
	def parse_checkpoints_file(dir)
		path="#{@backup_dir}/#{dir}/#{@checkpoint_file_name}"
		file = File.open(path, "rb")
		contents = file.read
		entries=contents.split("\n")
		config={}
		entries.each do |entry|
			key=entry.split("=")[0].delete(' ')
			value=entry.split("=")[1].delete(' ')
			config[key]=value
		end
		return config
	end

=begin
	Input:
	Output performs an incremental backup
=end
	def perform_incremental_backup()
		#if no full backups found create a new one
		if get_last_full_backup()==nil and get_last_incremental_backup()==nil
			@logger.info("No existing full or incremental backups found, performing a full backup to be used as base")
			cmd="innobackupex --user=#{@user} --password=#{@password} #{@backup_dir}"
			#@logger.info(cmd) - commented to hide password from logs
		else
			incremental_basedir="#{@backup_dir}#{get_last_backup()[:dirname]}/"
			cmd="innobackupex --incremental --user=#{@user} --password=#{@password} #{@backup_dir} --incremental-basedir=#{incremental_basedir}"
			@logger.info("Creating incremental backup")
		end
		system(cmd)
		
		#refresh backups list
		@backups=get_parsed_backup_dirs()
		archive_and_upload_to_s3()
	end

=begin
	Input:
	Output: restores incremental backup
=end	
	def restore_incremental_backups()
		last_full_backup=get_last_full_backup()
		if last_full_backup==nil
			raise "no full backup found"
		end
		
		#apply logs back starting from the base backup going forward to the latest and then most recent incremental backup
		basedir="#{@backup_dir}#{last_full_backup[:dirname]}"
		cmd="innobackupex --apply-log --redo-only #{basedir}"
    @logger.info("Base full backup found, applying logs on base backup")
    @logger.info(cmd)
		system(cmd)
		
		#apply incremental backups logs on base backup
		incremental_backups=get_incremental_backups()
		incremental_backups=incremental_backups.sort_by {|backup| backup[:date]}
		@logger.info("applying incremental backup logs to base backup")
		incremental_backups.each do |backup|
			incremental_dir="#{@backup_dir}#{backup[:dirname]}"
			cmd="innobackupex --apply-log --redo-only #{basedir} --incremental-dir=#{incremental_dir}"
    	@logger.info(cmd)
			system(cmd)
		end
		
		#applying all the logs on base backup
		@logger.info("applying logs on base backup")
		cmd="innobackupex --apply-log #{basedir}"
		@logger.info(cmd)
		system(cmd)
		
		copy_files_back(basedir)
		 	
	end

=begin
	Input: path to a restored base backup directory
	Output: copy files back to the data dir
=end	
	def copy_files_back(basedir=nil)

		if basedir==nil
			@logger.info("Trying to locate a prepated backup to restore")
			last_full_backup=get_last_prepared_backup()
			basedir="#{@backup_dir}#{last_full_backup[:dirname]}"
		end

    if Dir["#{@data_dir}*"].empty?
			@logger.info("Copying base backup back to data dir")
			cmd="innobackupex --copy-back #{basedir}"
			@logger.info(cmd)
			system(cmd)
			@logger.info("Setting data dir permissions")
			cmd="chown -R mysql:mysql #{@data_dir}"
			system(cmd)
    else
      @logger.error("data dir: #{@data_dir}\n must be empty to copy back the restored backup.\nClean it up and then run the copy_files_back method")
    end
	end

=begin
	Input:
	Output: archives the last backup and uploads it to s3
=end
	def archive_and_upload_to_s3()
    @backups.each do |backup|
			#zipping backups
			backup_path="#{@backup_dir}#{backup[:dirname]}"
			backup_archived_path="#{backup_path}.tgz"
			backup_encrypted_path="#{backup_archived_path}.enc"
			if !File.exists?(backup_archived_path)
      	cmd="tar -czvf #{backup_archived_path} #{backup_path}"
				@logger.info(cmd)
      	system(cmd)
			end
			#Encrypting backups
			#### Place holder for when the backups can be properly encrypted
			#uploading to s3
			cmd="s3cmd put #{backup_archived_path} #{@s3_bucket_path} --config=#{@s3cmd_config_path}"
			@logger.info(cmd)
			system(cmd)
    end

	end

=begin
	Input: rotation_size- number of backups to leave on disk, e.g. only the last #{rotation_size} number of backups will remain on disk
	output: rotates the backups
=end
	def rotate_backups(rotation_size=@rotation_size)
		sorted_backups=@backups.sort_by {|backup| backup[:date]}
		puts "These are the sorted backups: #{sorted_backups}"
		if sorted_backups.length>rotation_size
			remove_size=sorted_backups.length-rotation_size
			sorted_backups[0..(remove_size-1)].each do |backup|
				backup_path="#{@backup_dir}#{backup[:dirname]}"
				backup_archived_path="#{backup_path}.tgz"
				@logger.info("rotating #{backup_path}")
				cmd="rm -rf #{backup_path}"
				system(cmd)
				@logger.info("rotating #{backup_archived_path}")
        cmd="rm -rf #{backup_archived_path}"
        system(cmd)				
			end
		end
		
	end

	def get_full_backups()
		@backups.select {|dir| dir[:config]["backup_type"]=="full-backuped"}
	end

	def get_prepared_backups()
		@backups.select {|dir| dir[:config]["backup_type"]=="full-prepared"}
	end

	def get_last_prepared_backup()
    backups=get_prepared_backups()
    sorted=backups.sort_by {|backup| backup[:date]}
    return sorted.last
	end

	def get_incremental_backups()	
    @backups.select {|dir| dir[:config]["backup_type"]=="incremental"}		
	end

	def get_last_incremental_backup()
		backups=get_incremental_backups()
		sorted=backups.sort_by {|backup| backup[:date]}
		return sorted.last	
	end

  def get_last_full_backup()
    backups=get_full_backups()
    sorted=backups.sort_by {|backup| backup[:date]}
    return sorted.last
  end

	def get_last_backup()
    sorted=@backups.sort_by {|backup| backup[:date]}
    return sorted.last
	end

end # class DbBackup


