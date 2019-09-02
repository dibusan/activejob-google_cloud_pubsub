require 'bundler/setup'

require 'activejob-google_cloud_pubsub'
require 'timeout'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  config.expect_with :rspec do |rspec|
    rspec.syntax = :expect
  end

  config.around :each, use_pubsub_emulator: true do |example|
    run_pubsub_emulator do |host|
      pubsub = Google::Cloud::Pubsub.new(emulator_host: host, project_id: 'activejob-test')

      orig, ActiveJob::Base.queue_adapter = ActiveJob::Base.queue_adapter, ActiveJob::GoogleCloudPubsub::Adapter.new(pubsub: pubsub)

      begin
        @pubsub_emulator_host = host

        example.run
      ensure
        ActiveJob::Base.queue_adapter = orig
      end
    end
  end

  private

  def run_pubsub_emulator(&block)
    pipe = IO.popen("#{gcloud_path} beta emulators pubsub start", err: %i(child out), pgroup: true)

    begin
      Timeout.timeout 10 do
        pipe.each do |line|
          break if line.include?('Server started, listening on')

          raise line if line.include?('Exception in thread')
        end
      end

      host = `#{gcloud_path} beta emulators pubsub env-init`.match(/^export PUBSUB_EMULATOR_HOST=(\S+)$/).captures.first

      block.call host
    ensure
      begin
        Process.kill :TERM, -Process.getpgid(pipe.pid)
        Process.wait pipe.pid
      rescue Errno::ESRCH, Errno::ECHILD
        # already terminated
      end
    end
  end

  def gcloud_path
    @gcloud_path ||=
      begin
        bin_path = File.join('google-cloud-sdk', 'bin')
        Dir.exist?(bin_path) ? File.join(bin_path, 'gcloud') : 'gcloud'
      end
  end
end
