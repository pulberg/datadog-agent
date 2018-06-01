#!/usr/bin/env ruby

require 'aws-sdk'
require 'trollop'

opts = Trollop::options do
  opt :repo_type, "Type of repo to invalidate ('apt' or 'yum')",  :type => :string, :default => nil
  opt :env, "Environment of the repo ('staging' or 'prod')", :type => :string, :default => nil
  opt :pattern_regex, "Regex defining whitelist of objects to invalidate",  :type => :string, :default => ''
  opt :pattern_substring, "Substring defining whitelist of objects to invalidate (only objects matching the substring will be selected for invalidation)",  :type => :string, :default => ''
  opt :invalidate_versioned, "Don't filter out versioned objects from invalidation (versioned == with one or more digits in the filename)"
  opt :dry_run, "Stop script before creating the invalidation"
  opt :raw_cloudfront_path, "Don't query S3, create cloudfront invalidation directly against this path", :type => :string, :default => nil
end

# Repo holds the info of a repo: s3 bucket and CloudFront distribution ID
class Repo < Struct.new(:s3_bucket, :distribution_id)
end

repos = {
  'staging' => {
    'apt' => Repo.new('apt.datad0g.com', 'E18ZGDURBK5K6X'),
    'yum' => Repo.new('yum.datad0g.com', 'E17ZLUWTA3BBMD')
  },
  'prod' => {
    'apt' => Repo.new('apt.datadoghq.com', 'E3Q5GQK7JXVKE'),
    'yum' => Repo.new('yum.datadoghq.com', 'E1KM31Z2LAGIKZ')
  }
}

Trollop::die :repo_type, "You must specify a repo-type of 'apt' or 'yum'" unless %w{apt yum}.include?(opts[:repo_type])
Trollop::die :env, "You must specify an env of 'prod' or 'staging'" unless %w{prod staging}.include?(opts[:env])

repo = repos[opts[:env]][opts[:repo_type]]

objects = []

if opts[:raw_cloudfront_path].nil?
  ## List all objects from S3 bucket and optionally filter out versioned ones
  Aws.config.update(region: 'us-east-1')
  s3 = Aws::S3::Resource.new

  s3.bucket(repo.s3_bucket).objects.each do |obj|
    if opts[:invalidate_versioned] || obj.key.split('/').last !~ /[0-9]/
      objects.push('/' + obj.key)
    end
  end

  unless opts[:invalidate_versioned]
    puts "Found the following unversioned objects:"
    puts objects
  end

  ## Filter out objects based on the selected patterns
  if !opts[:pattern_regex].empty?
    objects.select! do |obj_name|
      obj_name =~ Regexp.new(opts[:pattern_regex])
    end
  end

  if !opts[:pattern_substring].empty?
    objects.select! do |obj_name|
      obj_name.include?(opts[:pattern_substring])
    end
  end

  if objects.empty?
    fail "No object matching the conditions has been found on the S3 bucket '#{repo.s3_bucket}'"
  end
else
  objects.push(opts[:raw_cloudfront_path])
end

## Run invalidation
puts "Invalidating the following #{objects.length} objects:"
puts objects

if opts[:dry_run]
  puts "Dry run: no invalidation created, exiting"
  exit
end

# We assume that we're running from a staging `ott` node
if opts[:env] == 'prod'
  puts "Assuming prod role to invalidate prod CloudFront distributions"
  role_credentials = Aws::AssumeRoleCredentials.new(
    client: Aws::STS::Client.new(region: 'us-east-1'),
    role_arn: "arn:aws:iam::727006795293:role/build-stable-cloudfront-invalidation",
    role_session_name: "gitlab-cloudfront-invalidate-script"
  )
  cloudfront = Aws::CloudFront::Client.new(
    region: 'us-east-1',
    credentials: role_credentials
  )
else
  cloudfront = Aws::CloudFront::Client.new(
    region: 'us-east-1'
  )
end

# Generate a caller_reference, which has to be unique for what this invalidation does.
# It's a CloudFront mechanism to ensure that we don't accidentally trigger multiple
# identical invalidations in a very short period of time
caller_reference = "invalidate.rb:#{Time.now.getutc.to_s}:#{objects.first}"

resp = cloudfront.create_invalidation({
  distribution_id: repo.distribution_id,
  invalidation_batch: {
    paths: {
      quantity: objects.length,
      items: objects,
    },
    caller_reference: caller_reference,
  },
})

puts "Successfully created invalidation '#{resp.location}'"
