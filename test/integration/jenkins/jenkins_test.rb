describe service 'jenkins' do
  it { should be_running }
end

describe service 'nginx' do
  it { should be_running }
end

# Anubis is opt-in via node['jenkins']['anubis'], see the jenkins-anubis suite
# for the enabled case. Match on the directives rather than the word 'anubis'
# because the SSL template carries the Anubis comments unconditionally.
describe file '/etc/nginx/sites-enabled/jenkins' do
  its('content') { should_not match(/upstream anubis \{/) }
  its('content') { should_not match(%r{proxy_pass http://anubis;}) }
end
