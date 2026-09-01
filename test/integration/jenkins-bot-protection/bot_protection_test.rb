# Verifies bot protection nginx configuration when node['jenkins']['bot_protection']
# is enabled. Tests verify that config files are deployed with correct permissions
# and that nginx configuration includes the bot protection actions.

jenkins_site = '/etc/nginx/sites-enabled/jenkins'
bot_protection_dir = '/etc/nginx/conf.d/bot-protection'

describe service 'nginx' do
  it { should be_running }
end

describe directory bot_protection_dir do
  it { should exist }
  its('mode') { should cmp '0750' }
  its('owner') { should eq 'root' }
  its('group') { should eq 'www-data' }
end

%w(10-bot-detection.conf 15-bot-protection-maps.conf 20-bot-maps.conf bot-actions.conf).each do |config_file|
  describe file "#{bot_protection_dir}/#{config_file}" do
    it { should exist }
    its('mode') { should cmp '0640' }
    its('owner') { should eq 'root' }
    its('group') { should eq 'www-data' }
  end
end

describe file jenkins_site do
  it { should exist }

  # Bot protection include directive should be present
  its('content') { should match(%r{include conf\.d/bot-protection/bot-actions\.conf;}) }
end

describe command 'nginx -t' do
  its('exit_status') { should eq 0 }
end
