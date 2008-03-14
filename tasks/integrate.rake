require 'find'

INTEGRATION_TASKS = %w( 
    svn:status:check
    log:clear
    tmp:clear
    backup:local
    svn:update
    db:migrate
    test:units
    test:functionals
    test:integration
    spec:lib
    spec:models
    spec:helpers
    spec:controllers
    spec:views
    test:rcov:units
    test:rcov:units:verify
    test:rcov:functionals
    test:rcov:functionals:verify
    spec:rcov
    spec:rcov:verify
    test:plugins:selected
    spec:plugins:selected
    test:selenium:server:start
    test_acceptance
    test:selenium:server:stop
    svn:commit            
)


# Extract project name.
def project_name
  File.expand_path(RAILS_ROOT).split("/").last
end

# Run coverage test to check project coverage.
def rcov_verify
  sh "ruby #{File.expand_path(File.dirname(__FILE__) + '/../test/coverage_test.rb')}" 
end

# Stop mongrel server.
def stop_mongrel
    sh "mongrel_rails stop" if FileTest.exists?('log/mongrel.pid') 
end

# Print message with separator.
def p80(message)
  puts "-"*80
  puts message if message
  yield if block_given?
end

# Extract environment parameters
def environment_parameters(key)
  return ENV[key].split(/\s*\,\s*/) if ENV[key]
  []
end

# Check if need to skip task.
def skip_task?(task)
  environment_parameters('SKIP_TASKS').include?(task)  
end

# Remove old backups
def remove_old_backups(backup_dir)
  backups_to_keep = ENV['NUMBER_OF_BACKUPS_TO_KEEP'] || 30
  backups = []
  Find.find(backup_dir) { |file_name| backups << file_name if !File.directory?(file_name) && file_name =~ /.*\.tar.gz$/ }
  backups.sort!
  (backups - backups.last(backups_to_keep - 1)).each do |file_name|
    puts "Removing #{file_name}..."
    FileUtils.rm(file_name)
  end
end

namespace :backup do
  desc 'Creates a backup of the project in the local disk.'
  task :local do
    backup_dir = '../backup-' + project_name
    sh "mkdir #{backup_dir}" if !FileTest.exists?(backup_dir)
    remove_old_backups(backup_dir)
    sh "tar cfz #{backup_dir}/#{project_name}-#{Time.now.strftime('%Y%m%d-%H%M%S')}.tar.gz ../#{project_name}"
  end
end

namespace :svn do
  namespace :status do
    desc 'Check if project can be committed to the repository.'
    task :check do
      files_out_of_sync = `svn status | grep -e '[?|!]'`
      if files_out_of_sync.size > 0
        puts "Files out of sync:"
        files_out_of_sync.each { |filename| puts filename }
        puts 
        exit
      end
    end
  end

  desc 'Update files from repository.'
  task :update do
    sh "svn update"
  end
  
  desc 'Commit project.'
  task :commit do
    sh "svn commit vendor/plugins/*"
    sh "svn commit"
  end
end

namespace :test do
  namespace :plugins do
    desc 'Run tests for each plugin defined in PLUGINS_TO_TEST'
    task :selected do
      environment_parameters('PLUGINS_TO_TEST').each do |name|
        if File.exist?("#{RAILS_ROOT}/vendor/plugins/#{name}")
          puts "Executing tests for plugin: #{name}"
          puts `rake test:plugins PLUGIN=#{name}`
        end
      end if ENV['PLUGINS_TO_TEST']
    end
  end
  
  namespace :rcov do
    namespace :units do
      desc 'Check unit tests coverage.'
      task :verify do
        rcov_verify
      end
    end

    namespace :functionals do
      desc 'Check functional tests coverage.'
      task :verify do
        rcov_verify
      end
    end
  end
  
  desc 'Start Mongrel, run Selenium tests and stop Mongrel.'
  task :selenium => ["test:selenium:server:start", :test_acceptance, "test:selenium:server:stop"]
  
  namespace :selenium do
    namespace :server do
      desc 'Start Mongrel on port 4000.'
      task :start do
        stop_mongrel
        rails_env = ENV['RAILS_ENV'] || 'test'
        port = ENV['SELENIUM_PORT'] || '4000'
        sh "mongrel_rails start -d -e #{rails_env} -p #{port} && sleep 2s" 
      end

      desc 'Stop Mongrel.'
      task :stop do
        stop_mongrel
      end
    end
  end
  
  desc 'Run test coverage.'
  task :rcov => ["test:rcov:units", "test:rcov:units:verify", "test:rcov:functionals", "test:rcov:functionals:verify"]
end

namespace :spec do
  namespace :plugins do
    desc 'Run specs for each plugin defined in PLUGINS_TO_SPEC'
    task :selected do
      environment_parameters('PLUGINS_TO_SPEC').each do |name|
        if File.exist?("#{RAILS_ROOT}/vendor/plugins/#{name}")
          puts "Executing specs for plugin: #{name}"
          puts `rake spec:plugins PLUGIN=#{name}`
        end
      end if ENV['PLUGINS_TO_SPEC']
    end
  end

  namespace :rcov do
    desc 'Check specs coverage.'
    task :verify do
      rcov_verify
    end
  end
end

desc 'Integrate new code to repository'
task :integrate do
  INTEGRATION_TASKS.each do |subtask|
    if Rake::Task.task_defined?("#{subtask}:before") && !skip_task?(subtask)
      p80("Executing #{subtask}:before...") { Rake::Task["#{subtask}:before"].invoke }
    end

    if skip_task?(subtask)
      p80 "Skipping #{subtask}..."
    else
      p80("Executing #{subtask}...") { Rake::Task[subtask].invoke }
    end

    if Rake::Task.task_defined?("#{subtask}:after") && !skip_task?(subtask)
      p80("Executing #{subtask}:after...") { Rake::Task["#{subtask}:after"].invoke }
    end
  end
end
