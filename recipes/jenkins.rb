##JENKINS AGENT##

include_recipe 'jenkins::master' #do I include all the recipes on the cookbook and is that right syntax?

include_recipe 'agent' #ros buildfarm agent recipe

file '/var/jenkins/casc_configs/jenkins.yaml' do
end

jenkins::jenkins_user 'admin' do
  public_keys node['jenkins']['admin']['key']
end

timezone 'PST'

package 'nginx'
service 'nginx' do
  action [ :enable, :start]
end
template 'path/to/some/file' do
end

package 'python3-yaml'

package 'docker'

jenkins_private_key_credentials 'idk' do
  id 'agent'
  description 'a slave machine'
  private_key node['jenkins']['slave']['key']
end

jenkins_password_credentials 'idk' do
  id node['jenkins']['admin']['username']
  description 'credentials for jenkins?'
  password node['jenkins']['admin']['password']
end
