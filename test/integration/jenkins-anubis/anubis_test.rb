# Verifies the Anubis nginx configuration rendered by
# templates/nginx/jenkins-webproxy.ssl.conf.erb when node['jenkins']['anubis']
# is enabled. The suite runs with letsencrypt_enabled so that the SSL template
# (the only one carrying the Anubis configuration) is the one installed.

jenkins_site = '/etc/nginx/sites-enabled/jenkins'

# Endpoints which are expected to be challenged by Anubis. The keys are used
# for the test descriptions, the values are the location matchers as rendered
# into the nginx configuration.
anubis_locations = {
  'Anubis static assets' => 'location ^~ /.within.website/',
  'securityRealm' => 'location ~* /securityRealm(/|$)',
  'testReport' => 'location ~* /testReport(/|$)',
  'build console output' => 'location ~* /(console(Text|Full)?|logText/progressive(Text|Html))(/|$)',
}

describe service 'nginx' do
  it { should be_running }
end

describe file jenkins_site do
  it { should exist }

  # The Anubis upstream is served by the anubis@jenkins systemd unit over a
  # unix socket and falls back to Jenkins directly if Anubis is unavailable.
  its('content') { should match(/upstream anubis \{/) }
  its('content') { should match(%r{server unix:/run/anubis/jenkins/instance\.sock fail_timeout=0;}) }
  its('content') { should match(/server 127\.0\.0\.1:8080 backup;/) }

  anubis_locations.each do |name, location|
    it "proxies #{name} to the anubis upstream" do
      block = subject.content[/#{Regexp.escape(location)}.*?\n  \}/m]
      expect(block).not_to be_nil, "no #{location.inspect} block in #{jenkins_site}"
      expect(block).to match(%r{proxy_pass http://anubis;})
      expect(block).to match(/proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;/)
    end
  end

  # Everything which is not explicitly handed to Anubis must still be proxied
  # straight to Jenkins.
  its('content') { should match(%r[location / \{[^}]*proxy_pass http://jenkins;]m) }
end

describe command 'nginx -t' do
  its('exit_status') { should eq 0 }
end
