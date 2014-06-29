set :linked_files, %w{config/database.yml config/secrets.yml}
set :linked_dirs, %w{log tmp vendor/bundle public/system}
set :bundle_roles, :app
set :bundle_flags, "--deployment"

namespace :deploy do
  # Override migrate task from capistrano-rails.
  # We add the ability to run db:schema:load instead of db:migrate.
  # We also don't run the task if ActiveRecord is disabled in the app.
  Rake::Task["deploy:migrate"].clear_actions
  task :migrate => [:set_rails_env] do
    on primary fetch(:migration_role) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          output = capture(:rake, "-T")
          if fetch(:schema_load)
            if output =~ / db:schema:load /
              execute :rake, "db:schema:load"
            end
          else
            if output =~ / db:migrate /
              execute :rake, "db:migrate"
            end
          end
        end
      end
    end
  end

  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      execute :touch, release_path.join('tmp/restart.txt')
    end
  end

  after :publishing, :restart

  after :restart, :clear_cache do
    on roles(:web), in: :groups, limit: 3, wait: 10 do
      within release_path do
        execute :rake, 'tmp:clear'
      end
    end
  end


  ###### Progress reporting hooks ######
  
  before :starting, :report_progress_starting do
    notice "Running sanity checks..."
    report_progress(2, TOTAL_STEPS)
  end

  before :updating, :report_progress_updating do
    notice "Copying files for new release..."
    report_progress(3, TOTAL_STEPS)
  end

  before '^bundler:install', :report_progress_bundle_install do
    notice "Installing gem bundle..."
    report_progress(4, TOTAL_STEPS)
  end

  before :compile_assets, :report_progress_compile_assets do
    notice "Compiling assets..."
    report_progress(5, TOTAL_STEPS)
  end

  before :normalize_assets, :report_progress_normalize_assets do
    notice "Normalizing assets..."
    report_progress(6, TOTAL_STEPS)
  end

  before :migrate, :report_progress_migrate do
    notice "Running database migrations..."
    report_progress(7, TOTAL_STEPS)
  end

  before :reverting, :report_progress_reverting do
    notice "Reverting to previous release..."
    report_progress((TOTAL_STEPS - 1), TOTAL_STEPS)
  end

  before :finishing, :report_progress_finishing do
    notice "Finalizing release..."
    report_progress((TOTAL_STEPS - 1), TOTAL_STEPS)
  end

  after :finished, :report_progress_finished do
    notice "Finished!"
    report_progress(TOTAL_STEPS, TOTAL_STEPS)
  end
end
