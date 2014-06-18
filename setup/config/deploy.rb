require 'json'
require 'stringio'
require 'securerandom'
require 'shellwords'
require 'net/http'
require 'net/https'
require_relative '../../lib/config'
require_relative '../../lib/version'

fatal_and_abort "Please set the CONFIG_FILE environment variable" if !ENV['CONFIG_FILE']
CONFIG = JSON.parse(File.read(ENV['CONFIG_FILE']))

check_config_requirements(CONFIG)
Flippo.set_config_defaults(CONFIG)


task :install_flippo_manifest => :install_essentials do
  name    = CONFIG['name']
  app_dir = CONFIG['app_dir']

  config = StringIO.new
  config.puts JSON.dump(CONFIG)
  config.rewind

  on roles(:app) do
    upload! config, "#{app_dir}/flippo-setup.json"
    execute "chown root: #{app_dir}/flippo-setup.json && " +
      "chmod 600 #{app_dir}/flippo-setup.json"
    execute "mkdir -p /etc/flippo/apps && " +
      "cd /etc/flippo/apps && " +
      "rm -f #{name} && " +
      "ln -s #{app_dir} #{name}"
  end

  on roles(:app, :db) do
    execute "mkdir -p /etc/flippo/setup && " +
      "cd /etc/flippo/setup && " +
      "date +%s > last_run_time && " +
      "echo #{Flippo::VERSION_STRING} > last_run_version"
  end
end

task :restart_services => :install_essentials do
  on roles(:app) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      raise "TODO"
    when :debian
      case CONFIG['web_server_type']
      when 'nginx'
        if test("[[ -e /var/run/flippo/restart_web_server ]]")
          execute "rm -f /var/run/flippo/restart_web_server"
          if test("[[ -e /etc/init.d/nginx ]]")
            execute "/etc/init.d/nginx restart"
          elsif test("[[ -e /etc/service/nginx ]]")
            execute "sv restart /etc/service/nginx"
          end
        end
      when 'apache'
        execute(
          "if [[ -e /var/run/flippo/restart_web_server ]]; then " +
            "rm -f /var/run/flippo/restart_web_server && service apache2 restart; " +
          "fi")
      else
        abort "Unsupported web server. Flippo supports 'nginx' and 'apache'."
      end
    else
      raise "Bug"
    end
  end
end

desc "Setup the server environment"
task :setup do
  invoke :autodetect_os
  invoke :install_essentials
  invoke :install_language_runtime
  invoke :install_passenger
  invoke :install_web_server
  invoke :create_app_user
  invoke :create_app_dir
  invoke :install_dbms
  setup_database(CONFIG['database_type'], CONFIG['database_name'],
    CONFIG['database_user'])
  create_app_database_config(CONFIG['app_dir'], CONFIG['user'],
    CONFIG['database_type'], CONFIG['database_name'],
    CONFIG['database_user'])
  invoke :install_flippo_manifest
  invoke :restart_services
end
