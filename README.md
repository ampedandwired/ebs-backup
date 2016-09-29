Automatic EBS Snapshots
=======================

This service automatically creates regular snapshots of EBS volumes based on a schedule specified by a tag on the volume.
It also purges snapshots based on a specified retention period, again specified by a tag on the volume.

It's currently distributed as a Docker container, but it could be distributed as a gem as well in the future.

# Running
## Tag Your Volumes
Use the following tags on your volumes to configure backups:
- `backup.enabled` - If "true" backups will be made. If not present or any other value, they will not.
- `backup.frequency_hours` - Number of hours between backups. Default is 24.
- `backup.retention_hours` - Number of hours that backups are retained. Default is 168 (7 days).

Once volumes are backed up, a `backup.last` tag is added indicating the time (seconds since the epoch) that the volume was last backed up.
This tag is used when determining when to next back up this volume.
Snapshots are tagged with `backup.purge` indicating the time (in seconds since the epoch) that the snapshot will be purged.
Snapshots are also given a "Name" tag to indicate the volume that they came from.

# Run the Docker Container
The following environment variables are required:
- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY

These should be AWS credentials with the following permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:CreateSnapshot",
        "ec2:CreateTags",
        "ec2:DescribeSnapshots",
        "ec2:DescribeVolumes"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
```

The following environment variables are optional:
- AWS_REGION - Region to make backups in. Required if you don't specify EBS_BACKUP_REGIONS.
- EBS_BACKUP_REGIONS - Comma separated list of AWS regions to make backups in. Required if you don't specify AWS_REGION.
- EBS_BACKUP_INTERVAL_SECS - Seconds between checking for new backups. If omitted, container will be run in "once only" mode, useful if you prefer to schedule via cron.
- EBS_BACKUP_DRY_RUN - If set to "true" changes will be logged only and not applied


# Developing
Suggestions and pull requests welcome at the [GitHub repo](https://github.com/ampedandwired/ebs-backup).

To run locally in Docker, set the environment variables listed above and run:
```shell
$ docker-compose up
```

Or without docker (local Ruby 2.x installation required):
```shell
$ bundle install
$ bundle exec lib/backup.rb
```
