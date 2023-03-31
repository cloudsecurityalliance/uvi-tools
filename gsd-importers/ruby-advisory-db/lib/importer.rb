# Debugging tools
require 'byebug'
require 'diffy'

require_relative 'advisory'
require_relative 'database'
require 'bundler/audit/database'

puts "Checking if RubySec Database exists..."

if Bundler::Audit::Database.exists?
  puts "Exists, updating to latest..."
  Bundler::Audit::Database.update!
else
  puts "Does not exist, downloading..."
  Bundler::Audit::Database.download
end

puts "Syncing GSD Database (this may take a while)..."
gsd_database = GSD::Database.new(work_branch: 'automated/ruby-advisory-db')
gsd_database.sync!

count = 0
MAX_FILES_PER_COMMIT = 500
NAMESPACE = 'github.com/rubysec/ruby-advisory-db'

puts "Parsing advisories..."

rubysec_database = Bundler::Audit::Database.new
rubysec_database.send(:each_advisory_path) do |path|
  advisory = GSD::RubySecImporter::Advisory.new(yaml_file: path)

  if advisory.invalid?
    puts "Invalid entry, skipping"
    next
  end

  gsd_file_path = File.join(gsd_database.repo_path, advisory.gsd_file_path)

  puts "Checking #{advisory.gsd_id}"

  gsd_database.modify(gsd_file_path) do |gsd_entry|
    gsd_entry['namespaces'] = {} if gsd_entry['namespaces'].nil?
    gsd_entry['namespaces'][NAMESPACE] = advisory.to_h.compact

    gsd_entry['gsd'] = {} if gsd_entry['gsd'].nil?
    gsd_entry['gsd']['osvSchema'] = advisory.to_osv if gsd_entry['gsd']['osvSchema'].nil?
  end

  count += 1
  break if (count >= MAX_FILES_PER_COMMIT)
end

puts "Saving changes to branch"
gsd_database.save!

puts "Pushing to fork under #{gsd_database.work_branch}"
gsd_database.push!

puts "Done!"