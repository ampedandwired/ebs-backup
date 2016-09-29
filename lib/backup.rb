#!/usr/bin/env ruby
require "logger"
require "aws-sdk"

LOGGER = Logger.new(STDOUT)

class EbsBackup
  BACKUP_ENABLED_TAG = "backup.enabled"
  BACKUP_FREQUENCY_HOURS_TAG = "backup.frequency_hours"
  BACKUP_RETENTION_HOURS_TAG = "backup.retention_hours"
  BACKUP_LAST_TAG = "backup.last"
  BACKUP_PURGE_TAG = "backup.purge"

  BACKUP_FREQUENCY_HOURS_DEFAULT = 24
  BACKUP_RETENTION_HOURS_DEFAULT = 7 * 24


  def initialize(region: nil, dry_run: false)
    @region = region
    @dry_run = dry_run
    if region
      ec2_client = Aws::EC2::Client.new(region: region)
    else
      ec2_client = Aws::EC2::Client.new
    end
    @ec2 = Aws::EC2::Resource.new(client: ec2_client)
    @now = Time.now.to_i
  end

  def backup_and_purge
    LOGGER.info("Backing up volumes and purging snapshots in region #{@region || 'default'}")
    LOGGER.info("** Dry run specified, no changes will be applied") if @dry_run
    backup
    purge
  end

  def backup
    volumes_due_for_backup.each do |v|
      LOGGER.info("Backing up volume #{v.id}")
      if !@dry_run
        snapshot = @ec2.create_snapshot(volume_id: v.id)
        LOGGER.info("Created snapshot #{snapshot.id} for volume #{v.id}")
        @ec2.create_tags(resources: [snapshot.id], tags: snapshot_tags(v))
        @ec2.create_tags(resources: [v.id], tags: [{key: BACKUP_LAST_TAG, value: @now.to_s}])
      end
    end
  end

  def purge
    snapshots_due_for_purge.each do |s|
      LOGGER.info("Purging snapshot #{s.id}")
      if !@dry_run
        s.delete
      end
    end
  end


  private

  def volumes_due_for_backup
    volumes_enabled_for_backup.select do |v|
      secs_since_last_backup = @now - last_backup_time(v)
      backup_frequency_secs = backup_frequency_hours(v) * 60 * 60
      secs_since_last_backup >= backup_frequency_secs
    end
  end

  def volumes_enabled_for_backup
    @ec2.volumes(filters: [
      { name: "tag:#{BACKUP_ENABLED_TAG}", values: ["true"] }
    ])
  end

  def snapshots_due_for_purge
    snapshots_enabled_for_purge.select do |s|
      purge_time = get_tag_value(s, BACKUP_PURGE_TAG).to_i
      @now >= purge_time
    end
  end

  def snapshots_enabled_for_purge
    @ec2.snapshots(filters: [
      { name: "tag-key", values: [BACKUP_PURGE_TAG] }
    ])
  end

  def snapshot_tags(volume)
    name = get_tag_value(volume, "Name", volume.id) + "-#{@now}"
    purge_time = @now + (backup_retention_hours(volume) * 60 * 60)
    [
      { key: BACKUP_PURGE_TAG, value: purge_time.to_s },
      { key: "Name", value: name }
    ]
  end

  def backup_frequency_hours(volume)
    get_tag_value(volume, BACKUP_FREQUENCY_HOURS_TAG, BACKUP_FREQUENCY_HOURS_DEFAULT).to_i
  end

  def backup_retention_hours(volume)
    get_tag_value(volume, BACKUP_RETENTION_HOURS_TAG, BACKUP_RETENTION_HOURS_DEFAULT).to_i
  end

  def last_backup_time(volume)
    get_tag_value(volume, BACKUP_LAST_TAG, 0).to_i
  end

  def get_tag_value(resource, tag_name, default=nil)
    tag = resource.tags.find { |tag| tag.key == tag_name }
    tag ? tag.value : default
  end
end



class EbsBackupManager
  def initialize(regions: nil, interval_secs: nil, dry_run: false)
    @regions = regions
    @interval_secs = interval_secs
    @dry_run = dry_run
  end

  def run
    if @interval_secs
      LOGGER.info("EBS backup monitor started")
      while true
        begin
          do_backup
        rescue => error
          LOGGER.error(error)
        end
        sleep @interval_secs
      end
      LOGGER.info("EBS backup monitor started exited")
    else
      do_backup
    end
  end


  private

  def do_backup
    if @regions
      @regions.each do |region|
        EbsBackup.new(region: region, dry_run: @dry_run).backup_and_purge
      end
    else
      EbsBackup.new(dry_run: @dry_run).backup_and_purge
    end
  end
end


if __FILE__ == $0
  regions = ENV["EBS_BACKUP_REGIONS"]
  regions = regions && !regions.empty? ? regions.split(",") : nil
  interval_secs = Integer(ENV["EBS_BACKUP_INTERVAL_SECS"]) rescue nil
  dry_run = ENV["EBS_BACKUP_DRY_RUN"] == "true"

  EbsBackupManager.new(regions: regions, interval_secs: interval_secs, dry_run: dry_run).run
end
