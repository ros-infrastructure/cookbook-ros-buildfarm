package 'postfix'
package 'opendkim'
package 'opendkim-tools'

mail_name = node['ros_buildfarm']['jenkins']['server_name']
file '/etc/mailname' do
  content mail_name
end
template '/etc/postfix/main.cf' do
  source 'postfix/main.cf.erb'
  variables Hash[
    hostname: mail_name
  ]
end

dkim_config = data_bag_item('ros_buildfarm_dkim_configuration', node.chef_environment)

directory "/etc/opendkim/keys/#{mail_name}" do
  recursive true
end
dkim_config['keys'].each do |name, data|
  file "/etc/opendkim/keys/#{mail_name}/#{name}.private" do
    content data['private']
    mode '0600'
  end
  file "/etc/opendkim/keys/#{mail_name}/#{name}.txt" do
    content data['txt']
    mode '0600'
  end
end

trusted_hosts = dkim_config['trusted_hosts']
unless trusted_hosts.include? mail_name
  trusted_hosts << mail_name
end
file '/etc/opendkim/TrustedHosts' do
  content trusted_hosts.join("\n")
  mode '0644'
end

template '/etc/opendkim/KeyTable' do
  source 'opendkim/keytable.erb'
  variables Hash[
    keys: dkim_config['keys'],
    mail_name: mail_name,
  ]
  mode '0644'
end

signing_table_content = dkim_config['signing_entries'].map do |address, domainkey|
  "#{address} #{domainkey}"
end.join("\n")
file '/etc/opendkim/SigningTable' do
  content signing_table_content
  mode '0644'
end
